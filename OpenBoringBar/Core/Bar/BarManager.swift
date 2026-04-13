import AppKit
import ApplicationServices
import Combine

struct RunningAppItem: Identifiable, Hashable {
    let processID: pid_t
    let name: String
    let isFrontmost: Bool

    var id: pid_t { processID }
}

struct DisplayState: Identifiable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let apps: [RunningAppItem]
}

final class BarManager: ObservableObject {
    private enum AccessibilityAttribute {
        static let focusedWindow = "AXFocusedWindow" as CFString
        static let windows = "AXWindows" as CFString
        static let title = "AXTitle" as CFString
        static let position = "AXPosition" as CFString
        static let size = "AXSize" as CFString
        static let minimized = "AXMinimized" as CFString
    }

    @Published private(set) var displayStates: [DisplayState]

    private let appOrderManager: AppOrderManager
    private var displayObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol]
    private var refreshTimer: Timer?

    init() {
        displayStates = []
        appOrderManager = AppOrderManager()
        workspaceObservers = []

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayStates()
        }

        workspaceObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDisplayStates()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDisplayStates()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDisplayStates()
            }
        ]

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshDisplayStates()
        }

        refreshDisplayStates()
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        refreshTimer?.invalidate()
    }

    func activate(processID: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: processID),
              !app.isTerminated else {
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
           minimizeFocusedWindow(of: processID) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshDisplayStates()
            }
            return
        }

        _ = app.unhide()
        _ = restoreFirstMinimizedWindowIfNoVisibleWindow(of: processID)

        let requestAccepted: Bool
        if #available(macOS 14.0, *) {
            // Clicks on our non-activating panel do not always make this app active.
            // Become active first, then cooperatively yield to the target app.
            NSApp.activate()
            NSApp.yieldActivation(to: app)
            requestAccepted = app.activate(from: .current, options: [.activateAllWindows])
        } else {
            NSApp.activate(ignoringOtherApps: true)
            requestAccepted = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        if !requestAccepted {
            reopen(app)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else {
                return
            }

            if !app.isActive {
                self.reopen(app)
            }

            _ = self.restoreFirstMinimizedWindowIfNoVisibleWindow(of: processID)
            self.refreshDisplayStates()
        }
    }

    private func minimizeFocusedWindow(of processID: pid_t) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let appElement = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            AccessibilityAttribute.focusedWindow,
            &value
        )

        guard focusedWindowResult == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedWindow = unsafeBitCast(value, to: AXUIElement.self)
        let minimizeResult = AXUIElementSetAttributeValue(
            focusedWindow,
            AccessibilityAttribute.minimized,
            kCFBooleanTrue
        )
        return minimizeResult == .success
    }

    private func reopen(_ app: NSRunningApplication) {
        guard let bundleURL = app.bundleURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, _ in
            self?.refreshDisplayStates()
        }
    }


    private func refreshDisplayStates() {
        let screens = NSScreen.screens
        let displayIDs = screens.compactMap(displayID(for:))
        appOrderManager.syncActiveDisplays(Set(displayIDs))
        let displayBoundsByID = Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, CGDisplayBounds($0)) })
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var appsByDisplay: [CGDirectDisplayID: [AppSnapshot]] = [:]
        var seenByDisplay: [CGDirectDisplayID: Set<pid_t>] = [:]
        for displayID in displayIDs {
            appsByDisplay[displayID] = []
            seenByDisplay[displayID] = []
        }

        var frontmostDisplayID: CGDirectDisplayID?

        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for windowInfo in windowList {
                guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber else {
                    continue
                }
                let processID = pid_t(ownerPIDNumber.int32Value)

                if let layerNumber = windowInfo[kCGWindowLayer as String] as? NSNumber, layerNumber.intValue != 0 {
                    continue
                }

                if let alphaNumber = windowInfo[kCGWindowAlpha as String] as? NSNumber, alphaNumber.doubleValue <= 0 {
                    continue
                }

                guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                      let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                      !windowBounds.isEmpty,
                      let runningApplication = NSRunningApplication(processIdentifier: processID),
                      runningApplication.activationPolicy == .regular else {
                    continue
                }

                let appName = runningApplication.localizedName
                    ?? (windowInfo[kCGWindowOwnerName as String] as? String)
                    ?? "Unknown App"
                let windowTitle = (windowInfo[kCGWindowName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = (windowTitle?.isEmpty == false) ? windowTitle! : appName

                for displayID in displayIDs {
                    guard let displayBounds = displayBoundsByID[displayID], displayBounds.intersects(windowBounds) else {
                        continue
                    }

                    if seenByDisplay[displayID, default: []].insert(processID).inserted {
                        appsByDisplay[displayID, default: []].append(AppSnapshot(processID: processID, name: displayName))
                    } else if let windowTitle,
                              !windowTitle.isEmpty,
                              var snapshots = appsByDisplay[displayID],
                              let snapshotIndex = snapshots.firstIndex(where: { $0.processID == processID }),
                              snapshots[snapshotIndex].name == appName {
                        snapshots[snapshotIndex] = AppSnapshot(processID: processID, name: windowTitle)
                        appsByDisplay[displayID] = snapshots
                    }

                    if processID == frontmostPID, frontmostDisplayID == nil {
                        frontmostDisplayID = displayID
                    }
                }
            }
        }

        appendMinimizedApps(
            appsByDisplay: &appsByDisplay,
            seenByDisplay: &seenByDisplay,
            displayIDs: displayIDs,
            displayBoundsByID: displayBoundsByID
        )

        if frontmostDisplayID == nil, let frontmostPID {
            frontmostDisplayID = displayIDs.first { displayID in
                appsByDisplay[displayID, default: []].contains(where: { $0.processID == frontmostPID })
            }
        }

        var nextDisplayStates: [DisplayState] = []
        for screen in screens {
            guard let displayID = displayID(for: screen) else {
                continue
            }

            let orderedSnapshots = appOrderManager.applyStableOrder(
                for: displayID,
                snapshots: appsByDisplay[displayID, default: []]
            )

            let apps = orderedSnapshots.map { snapshot in
                RunningAppItem(
                    processID: snapshot.processID,
                    name: snapshot.name,
                    isFrontmost: snapshot.processID == frontmostPID && displayID == frontmostDisplayID
                )
            }

            nextDisplayStates.append(
                DisplayState(
                    id: displayID,
                    frame: screen.frame,
                    apps: apps
                )
            )
        }

        displayStates = nextDisplayStates
    }

    private func appendMinimizedApps(
        appsByDisplay: inout [CGDirectDisplayID: [AppSnapshot]],
        seenByDisplay: inout [CGDirectDisplayID: Set<pid_t>],
        displayIDs: [CGDirectDisplayID],
        displayBoundsByID: [CGDirectDisplayID: CGRect]
    ) {
        guard AXIsProcessTrusted() else {
            return
        }

        for app in NSWorkspace.shared.runningApplications {
            let processID = app.processIdentifier
            guard !app.isTerminated,
                  app.activationPolicy == .regular else {
                continue
            }

            let appElement = AXUIElementCreateApplication(processID)
            guard let windows = windows(from: appElement),
                  !windows.isEmpty else {
                continue
            }

            let appName = app.localizedName ?? "Unknown App"
            for window in windows {
                guard isWindowMinimized(window),
                      let windowFrame = frame(of: window),
                      !windowFrame.isEmpty else {
                    continue
                }

                let windowTitle = stringAttributeValue(of: AccessibilityAttribute.title, from: window)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = (windowTitle?.isEmpty == false) ? windowTitle! : appName

                for displayID in displayIDs {
                    guard let displayBounds = displayBoundsByID[displayID],
                          displayBounds.intersects(windowFrame) else {
                        continue
                    }

                    if seenByDisplay[displayID, default: []].insert(processID).inserted {
                        appsByDisplay[displayID, default: []].append(
                            AppSnapshot(processID: processID, name: displayName)
                        )
                    }
                }
            }
        }
    }

    private func restoreFirstMinimizedWindowIfNoVisibleWindow(of processID: pid_t) -> Bool {
        guard AXIsProcessTrusted(),
              !hasVisibleLayerZeroWindow(of: processID),
              let window = firstMinimizedWindow(of: processID) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            window,
            AccessibilityAttribute.minimized,
            kCFBooleanFalse
        )
        return result == .success
    }

    private func firstMinimizedWindow(of processID: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processID)
        guard let windows = windows(from: appElement) else {
            return nil
        }
        return windows.first(where: isWindowMinimized)
    }

    private func hasVisibleLayerZeroWindow(of processID: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for windowInfo in windowList {
            guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(ownerPIDNumber.int32Value) == processID else {
                continue
            }

            if let layerNumber = windowInfo[kCGWindowLayer as String] as? NSNumber, layerNumber.intValue != 0 {
                continue
            }

            if let alphaNumber = windowInfo[kCGWindowAlpha as String] as? NSNumber, alphaNumber.doubleValue <= 0 {
                continue
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let windowBounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  !windowBounds.isEmpty else {
                continue
            }

            return true
        }

        return false
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func windows(from appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            AccessibilityAttribute.windows,
            &value
        )

        guard result == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }

        let array = unsafeBitCast(value, to: NSArray.self)
        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(item as CFTypeRef, to: AXUIElement.self)
        }
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttributeValue(of: AccessibilityAttribute.position, from: window),
              let size = sizeAttributeValue(of: AccessibilityAttribute.size, from: window) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        boolAttributeValue(of: AccessibilityAttribute.minimized, from: window) ?? false
    }

    private func pointAttributeValue(of attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
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
            return nil
        }
        return number.boolValue
    }

    private func stringAttributeValue(of attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)

        guard result == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }
}

private struct AppSnapshot {
    let processID: pid_t
    let name: String
}

/// Keeps each display's app order stable after startup so UI updates only perform minimal movement.
private final class AppOrderManager {
    private var orderByDisplay: [CGDirectDisplayID: [pid_t]] = [:]

    func syncActiveDisplays(_ activeDisplayIDs: Set<CGDirectDisplayID>) {
        orderByDisplay = orderByDisplay.filter { activeDisplayIDs.contains($0.key) }
    }

    func applyStableOrder(for displayID: CGDirectDisplayID, snapshots: [AppSnapshot]) -> [AppSnapshot] {
        if snapshots.isEmpty {
            return []
        }

        let visibleByPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.processID, $0) })
        let visiblePIDs = snapshots.map(\.processID)

        if orderByDisplay[displayID] == nil {
            orderByDisplay[displayID] = visiblePIDs
            return snapshots
        }

        var storedOrder = orderByDisplay[displayID] ?? []
        let visiblePIDSet = Set(visiblePIDs)
        var orderedVisiblePIDs = storedOrder.filter(visiblePIDSet.contains)

        let storedPIDSet = Set(storedOrder)
        let newPIDs = visiblePIDs.filter { !storedPIDSet.contains($0) }
        orderedVisiblePIDs.append(contentsOf: newPIDs)

        if !newPIDs.isEmpty {
            storedOrder.append(contentsOf: newPIDs)
            orderByDisplay[displayID] = storedOrder
        }

        return orderedVisiblePIDs.compactMap { visibleByPID[$0] }
    }
}
