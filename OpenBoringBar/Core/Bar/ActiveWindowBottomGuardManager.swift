import AppKit
import ApplicationServices
import OSLog

final class ActiveWindowBottomGuardManager {
    private enum AccessibilityAttribute {
        static let focusedWindow = "AXFocusedWindow" as CFString
        static let position = "AXPosition" as CFString
        static let size = "AXSize" as CFString
        static let minimized = "AXMinimized" as CFString
        static let fullScreen = "AXFullScreen" as CFString
    }

    private struct ActiveProcessSnapshot: Equatable {
        let processID: pid_t
        let windowFrame: CGRect
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openboringbar.app",
        category: "ActiveWindowBottomGuard"
    )

    private var refreshTimer: Timer?
    private var lastSnapshot: ActiveProcessSnapshot?

    init() {
        log("init")
        startTimer()
        adjustActiveWindowIfNeeded()
    }

    deinit {
        log("deinit")
        refreshTimer?.invalidate()
    }

    private func startTimer() {
        let timer = Timer(
            timeInterval: BarLayoutConstants.activeWindowCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.log("timer tick")
            self?.adjustActiveWindowIfNeeded()
        }

        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        log("timer started (interval: \(BarLayoutConstants.activeWindowCheckInterval)s)")
    }

    private func adjustActiveWindowIfNeeded() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            log("skip: no frontmost application")
            lastSnapshot = nil
            return
        }

        let processID = frontmostApp.processIdentifier
        guard processID != ProcessInfo.processInfo.processIdentifier,
              frontmostApp.activationPolicy == .regular else {
            log("skip: unsupported frontmost app pid=\(processID), policy=\(frontmostApp.activationPolicy.rawValue)")
            lastSnapshot = nil
            return
        }

        let appElement = AXUIElementCreateApplication(processID)
        guard let focusedWindow = focusedWindow(from: appElement) else {
            log("skip: cannot resolve focused window for pid=\(processID)")
            return
        }

        if isWindowMinimized(focusedWindow) {
            log("skip: window minimized for pid=\(processID)")
            return
        }

        if isWindowFullScreen(focusedWindow) {
            log("skip: window fullscreen for pid=\(processID)")
            return
        }

        guard let windowFrame = frame(of: focusedWindow) else {
            log("skip: cannot read window frame for pid=\(processID)")
            return
        }

        guard let screen = screen(for: windowFrame) else {
            log("skip: cannot match screen for frame=\(windowFrame.debugDescription)")
            return
        }

        let requiredBottomY = screen.frame.maxY - BarLayoutConstants.panelHeight
        let currentSnapshot = ActiveProcessSnapshot(processID: processID, windowFrame: windowFrame)
        log("check1: pid=\(processID), windowMaxY=\(windowFrame.maxY), requiredMaxY=\(requiredBottomY), screenMaxY=\(screen.frame.maxY)")

        guard windowFrame.maxY > requiredBottomY else {
            log("no-op: window already above panel for pid=\(processID)")
            if currentSnapshot != lastSnapshot {
                lastSnapshot = currentSnapshot
            }
            return
        }

        var adjustedFrame = windowFrame
        let offset = adjustedFrame.origin.y - (requiredBottomY - adjustedFrame.height)
        log("offset=\(offset)")

        adjustedFrame.origin.y = requiredBottomY - adjustedFrame.height
        adjustedFrame.size.height = adjustedFrame.height - offset
      
        log("move: pid=\(processID), fromY=\(windowFrame.minY), toY=\(adjustedFrame.minY)")
        if setFrame(adjustedFrame, for: focusedWindow) {
            log("move success: pid=\(processID)")
            lastSnapshot = ActiveProcessSnapshot(processID: processID, windowFrame: adjustedFrame)
        } else {
            log("move failed: pid=\(processID)")
        }
    }

    private func focusedWindow(from appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            AccessibilityAttribute.focusedWindow,
            &value
        )

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            log("AXFocusedWindow read failed, result=\(result.rawValue)")
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttributeValue(of: AccessibilityAttribute.position, from: window),
              let size = sizeAttributeValue(of: AccessibilityAttribute.size, from: window) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            log("AXValueCreate(CGPoint) failed")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            window,
            AccessibilityAttribute.position,
            positionValue
        )
        if result != .success {
            log("AXPosition write failed, result=\(result.rawValue)")
        }
        return result == .success
    }

    private func screen(for windowFrame: CGRect) -> NSScreen? {
        var bestScreen: NSScreen?
        var maxIntersectionArea: CGFloat = 0

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(windowFrame)
            guard !intersection.isNull, !intersection.isEmpty else {
                continue
            }

            let area = intersection.width * intersection.height
            if area > maxIntersectionArea {
                maxIntersectionArea = area
                bestScreen = screen
            }
        }

        return bestScreen
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        boolAttributeValue(of: AccessibilityAttribute.minimized, from: window) ?? false
    }

    private func isWindowFullScreen(_ window: AXUIElement) -> Bool {
        boolAttributeValue(of: AccessibilityAttribute.fullScreen, from: window) ?? false
    }

    private func pointAttributeValue(of attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            log("AX point read failed, attribute=\(attribute), result=\(result.rawValue)")
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttributeValue(of attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            log("AX size read failed, attribute=\(attribute), result=\(result.rawValue)")
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func boolAttributeValue(of attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success,
              let number = value as? NSNumber else {
            log("AX bool read failed, attribute=\(attribute), result=\(result.rawValue)")
            return nil
        }

        return number.boolValue
    }

    private func log(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
#if DEBUG
        print("[ActiveWindowBottomGuard] \(message)")
#endif
    }
}
