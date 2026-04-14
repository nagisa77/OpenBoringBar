import AppKit
import ApplicationServices
import Combine
import OSLog

final class ActiveWindowBottomGuardManager {
    private struct ActiveProcessSnapshot: Equatable {
        let processID: pid_t
        let windowFrame: CGRect
    }

    private struct ScreenMatch {
        let displayID: CGDirectDisplayID
        let displayBounds: CGRect
    }

    private struct PendingResizeRequest {
        let frame: CGRect
        let window: AXUIElement
        let processID: pid_t
        let source: String
    }

    private enum ResizeRequestResult {
        case performed(success: Bool)
        case queued
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openboringbar.app",
        category: "ActiveWindowBottomGuard"
    )

    private static let observerCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else {
            return
        }

        let manager = Unmanaged<ActiveWindowBottomGuardManager>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        manager.handleAccessibilityNotification(
            element: element,
            notification: notification as String
        )
    }

    private var lastSnapshot: ActiveProcessSnapshot?
    private var observerByPID: [pid_t: AXObserver] = [:]
    private var appElementByPID: [pid_t: AXUIElement] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var eventCancellable: AnyCancellable?
    private let resizeThrottleInterval: TimeInterval = 1
    private var lastResizeExecutionUptime: TimeInterval = -.infinity
    private var pendingResizeRequest: PendingResizeRequest?
    private var pendingResizeWorkItem: DispatchWorkItem?
    private var delayedCapsuleSwitchAdjustWorkItem: DispatchWorkItem?
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

    init(eventBus: AppEventBus) {
        log("init")
        configureWorkspaceObservers()
        configureEventSubscriptions(eventBus: eventBus)
        installObserversForRunningApps()
        adjustAllWindowsAtLaunchIfNeeded()
        adjustActiveWindowIfNeeded()
    }

    deinit {
        delayedCapsuleSwitchAdjustWorkItem?.cancel()
        delayedCapsuleSwitchAdjustWorkItem = nil
        pendingResizeWorkItem?.cancel()
        pendingResizeWorkItem = nil
        pendingResizeRequest = nil
        eventCancellable?.cancel()
        eventCancellable = nil
        teardownWorkspaceObservers()
        teardownAllAXObservers()
        log("deinit")
    }

    private func configureEventSubscriptions(eventBus: AppEventBus) {
        eventCancellable = eventBus.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else {
                    return
                }

                switch event {
                case .capsuleAppSwitchConfirmed(let processID):
                    self.scheduleDelayedAdjustAfterConfirmedSwitch(expectedProcessID: processID)
                }
            }
    }

    private func adjustActiveWindowIfNeeded(source: String = "active") {
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
        guard let focusedWindow = AXElementInspector.focusedWindow(from: appElement) else {
            log("skip: cannot resolve focused window for pid=\(processID)")
            return
        }

        _ = adjustWindowIfNeeded(focusedWindow, processID: processID, source: source)
    }

    private func scheduleDelayedAdjustAfterConfirmedSwitch(expectedProcessID: pid_t) {
        delayedCapsuleSwitchAdjustWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.delayedCapsuleSwitchAdjustWorkItem = nil

            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedProcessID else {
                self.log("[capsuleSwitchDelayed] skip: frontmost changed before delayed adjust, expected pid=\(expectedProcessID)")
                return
            }

            self.adjustActiveWindowIfNeeded(source: "capsuleSwitchDelayed")
        }

        delayedCapsuleSwitchAdjustWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func configureWorkspaceObservers() {
        workspaceObservers = [
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let app = self.runningApplication(from: notification) else {
                    return
                }

                self.installObserverIfNeeded(for: app)
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let app = self.runningApplication(from: notification) else {
                    return
                }

                self.installObserverIfNeeded(for: app)
                self.adjustActiveWindowIfNeeded()
            },
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let app = self.runningApplication(from: notification) else {
                    return
                }

                self.removeObserver(for: app.processIdentifier)
            }
        ]
    }

    private func teardownWorkspaceObservers() {
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func installObserversForRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            installObserverIfNeeded(for: app)
        }
    }

    private func installObserverIfNeeded(for app: NSRunningApplication) {
        let processID = app.processIdentifier
        guard processID != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated,
              app.activationPolicy == .regular else {
            return
        }

        guard observerByPID[processID] == nil else {
            return
        }

        var observer: AXObserver?
        let createResult = AXObserverCreate(
            processID,
            Self.observerCallback,
            &observer
        )

        guard createResult == .success, let observer else {
            log("AXObserverCreate failed, pid=\(processID), result=\(createResult.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(processID)
        observerByPID[processID] = observer
        appElementByPID[processID] = appElement

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        registerAppLevelNotifications(
            observer: observer,
            appElement: appElement,
            processID: processID
        )
        registerWindowLevelNotifications(processID: processID)
        log("observer installed, pid=\(processID)")
    }

    private func removeObserver(for processID: pid_t) {
        guard let observer = observerByPID.removeValue(forKey: processID) else {
            appElementByPID.removeValue(forKey: processID)
            return
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        appElementByPID.removeValue(forKey: processID)
        log("observer removed, pid=\(processID)")
    }

    private func teardownAllAXObservers() {
        let processIDs = Array(observerByPID.keys)
        for processID in processIDs {
            removeObserver(for: processID)
        }
    }

    private func registerAppLevelNotifications(
        observer: AXObserver,
        appElement: AXUIElement,
        processID: pid_t
    ) {
        registerNotification(
            AXNotificationName.focusedWindowChanged,
            observer: observer,
            element: appElement,
            processID: processID
        )
        registerNotification(
            AXNotificationName.mainWindowChanged,
            observer: observer,
            element: appElement,
            processID: processID
        )
        registerNotification(
            AXNotificationName.windowCreated,
            observer: observer,
            element: appElement,
            processID: processID
        )
    }

    private func registerWindowLevelNotifications(processID: pid_t) {
        guard let appElement = appElementByPID[processID],
              let observer = observerByPID[processID],
              let windows = AXElementInspector.windows(from: appElement) else {
            return
        }

        for window in windows {
            registerNotification(
                AXNotificationName.moved,
                observer: observer,
                element: window,
                processID: processID
            )
            registerNotification(
                AXNotificationName.resized,
                observer: observer,
                element: window,
                processID: processID
            )
            registerNotification(
                AXNotificationName.uiElementDestroyed,
                observer: observer,
                element: window,
                processID: processID
            )
        }
    }

    private func registerNotification(
        _ notification: String,
        observer: AXObserver,
        element: AXUIElement,
        processID: pid_t
    ) {
        let result = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if result == .success || result == .notificationAlreadyRegistered {
            return
        }

        log("AXObserverAddNotification failed, pid=\(processID), notification=\(notification), result=\(result.rawValue)")
    }

    private func handleAccessibilityNotification(
        element: AXUIElement,
        notification: String
    ) {
        guard let processID = processID(of: element) else {
            log("event ignored: cannot resolve pid, notification=\(notification)")
            return
        }

        switch notification {
        case AXNotificationName.windowCreated:
            registerWindowLevelNotifications(processID: processID)
            if let appElement = appElementByPID[processID],
               let focusedWindow = AXElementInspector.focusedWindow(from: appElement) {
                _ = adjustWindowIfNeeded(
                    focusedWindow,
                    processID: processID,
                    source: "event:\(notification)"
                )
            }

        case AXNotificationName.focusedWindowChanged,
             AXNotificationName.mainWindowChanged:
            registerWindowLevelNotifications(processID: processID)
            if let appElement = appElementByPID[processID],
               let focusedWindow = AXElementInspector.focusedWindow(from: appElement) {
                _ = adjustWindowIfNeeded(
                    focusedWindow,
                    processID: processID,
                    source: "event:\(notification)"
                )
            }

        case AXNotificationName.moved,
             AXNotificationName.resized:
            _ = adjustWindowIfNeeded(
                element,
                processID: processID,
                source: "event:\(notification)"
            )

        case AXNotificationName.uiElementDestroyed:
            break

        default:
            log("event ignored: notification=\(notification), pid=\(processID)")
        }
    }

    private func runningApplication(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        let result = AXUIElementGetPid(element, &processID)
        guard result == .success else {
            return nil
        }
        return processID
    }

    private func adjustAllWindowsAtLaunchIfNeeded() {
        guard AXIsProcessTrusted() else {
            log("startup bulk adjust skipped: AX not trusted")
            return
        }

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated &&
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }

        log("startup bulk adjust begin: appCount=\(runningApps.count)")

        var totalWindowCount = 0
        var totalAdjustedCount = 0

        for app in runningApps {
            let processID = app.processIdentifier
            let appElement = AXUIElementCreateApplication(processID)
            guard let windows = AXElementInspector.windows(from: appElement) else {
                continue
            }

            totalWindowCount += windows.count
            for window in windows {
                if adjustWindowIfNeeded(window, processID: processID, source: "startup") {
                    totalAdjustedCount += 1
                }
            }
        }

        log("startup bulk adjust done: windowCount=\(totalWindowCount), adjustedCount=\(totalAdjustedCount)")
    }

    @discardableResult
    private func adjustWindowIfNeeded(_ window: AXUIElement, processID: pid_t, source: String) -> Bool {
        if AXElementInspector.isWindowMinimized(window) {
            log("[\(source)] skip: window minimized for pid=\(processID)")
            return false
        }

        if AXElementInspector.isWindowFullScreen(window) {
            log("[\(source)] skip: window fullscreen for pid=\(processID)")
            return false
        }

        guard let windowFrame = AXElementInspector.frame(of: window) else {
            log("[\(source)] skip: cannot read window frame for pid=\(processID)")
            return false
        }

        guard let screenMatch = screenMatch(for: windowFrame) else {
            log("[\(source)] skip: cannot match screen for frame=\(windowFrame.debugDescription)")
            return false
        }

        let requiredBottomY = screenMatch.displayBounds.maxY - BarLayoutConstants.panelHeight
        let currentSnapshot = ActiveProcessSnapshot(processID: processID, windowFrame: windowFrame)
        log("[\(source)] check: pid=\(processID), displayID=\(screenMatch.displayID), windowMaxY=\(windowFrame.maxY), requiredMaxY=\(requiredBottomY), screenMaxY=\(screenMatch.displayBounds.maxY)")

        guard windowFrame.maxY > requiredBottomY else {
            log("[\(source)] no-op: window already above panel for pid=\(processID)")
            if currentSnapshot != lastSnapshot {
                lastSnapshot = currentSnapshot
            }
            return false
        }

        let targetHeight = max(1, requiredBottomY - windowFrame.origin.y)
        var adjustedFrame = windowFrame
        adjustedFrame.size.height = targetHeight

        log("[\(source)] resize: pid=\(processID), topY=\(windowFrame.origin.y), bottomFrom=\(windowFrame.maxY), bottomTo=\(adjustedFrame.maxY), heightFrom=\(windowFrame.height), heightTo=\(adjustedFrame.height)")
        switch resizeKeepingTop(
            adjustedFrame,
            for: window,
            processID: processID,
            source: source
        ) {
        case .performed(let success):
            if success {
                log("[\(source)] resize success: pid=\(processID)")
                lastSnapshot = ActiveProcessSnapshot(processID: processID, windowFrame: adjustedFrame)
                return true
            }

            log("[\(source)] resize failed: pid=\(processID)")
            return false

        case .queued:
            log("[\(source)] resize throttled: trailing queued for pid=\(processID)")
            return false
        }
    }

    private func resizeKeepingTop(
        _ frame: CGRect,
        for window: AXUIElement,
        processID: pid_t,
        source: String
    ) -> ResizeRequestResult {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let elapsed = nowUptime - lastResizeExecutionUptime

        if elapsed < resizeThrottleInterval {
            let remaining = max(0, resizeThrottleInterval - elapsed)
            scheduleTrailingResize(
                frame: frame,
                for: window,
                processID: processID,
                source: source,
                delay: remaining
            )
            return .queued
        }

        let success = performResizeKeepingTop(frame, for: window)
        lastResizeExecutionUptime = nowUptime
        return .performed(success: success)
    }

    private func scheduleTrailingResize(
        frame: CGRect,
        for window: AXUIElement,
        processID: pid_t,
        source: String,
        delay: TimeInterval
    ) {
        pendingResizeRequest = PendingResizeRequest(
            frame: frame,
            window: window,
            processID: processID,
            source: source
        )

        if pendingResizeWorkItem != nil {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingResizeWorkItem = nil

            guard let request = self.pendingResizeRequest else {
                return
            }
            self.pendingResizeRequest = nil

            let success = self.performResizeKeepingTop(request.frame, for: request.window)
            self.lastResizeExecutionUptime = ProcessInfo.processInfo.systemUptime

            if success {
                self.log("[\(request.source):trailing] resize success: pid=\(request.processID)")
                self.lastSnapshot = ActiveProcessSnapshot(
                    processID: request.processID,
                    windowFrame: request.frame
                )
            } else {
                self.log("[\(request.source):trailing] resize failed: pid=\(request.processID)")
            }
        }

        pendingResizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performResizeKeepingTop(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            log("AXValueCreate(CGSize) failed")
            return false
        }

        let sizeResult = AXUIElementSetAttributeValue(
            window,
            AXAttributeName.size,
            sizeValue
        )
        if sizeResult != .success {
            log("AXSize write failed, result=\(sizeResult.rawValue)")
            return false
        }

        // Force-restore top-left anchor to avoid visual upward translation.
        var position = frame.origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            log("AXValueCreate(CGPoint) failed after size update")
            return true
        }

        let positionResult = AXUIElementSetAttributeValue(
            window,
            AXAttributeName.position,
            positionValue
        )
        if positionResult != .success {
            log("AXPosition restore failed, result=\(positionResult.rawValue)")
        }

        return true
    }

    private func screenMatch(for windowFrame: CGRect) -> ScreenMatch? {
        var bestMatch: ScreenMatch?
        var maxIntersectionArea: CGFloat = 0

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else {
                continue
            }

            let displayBounds = CGDisplayBounds(displayID)
            let intersection = displayBounds.intersection(windowFrame)
            guard !intersection.isNull, !intersection.isEmpty else {
                continue
            }

            let area = intersection.width * intersection.height
            if area > maxIntersectionArea {
                maxIntersectionArea = area
                bestMatch = ScreenMatch(
                    displayID: displayID,
                    displayBounds: displayBounds
                )
            }
        }

        if let bestMatch {
            return bestMatch
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        var nearestMatch: ScreenMatch?
        var minDistanceSquared = CGFloat.greatestFiniteMagnitude

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else {
                continue
            }

            let displayBounds = CGDisplayBounds(displayID)
            let distanceSquared = squaredDistance(from: center, to: displayBounds)
            if distanceSquared < minDistanceSquared {
                minDistanceSquared = distanceSquared
                nearestMatch = ScreenMatch(
                    displayID: displayID,
                    displayBounds: displayBounds
                )
            }
        }

        if let nearestMatch {
            log("fallback: matched nearest screen displayID=\(nearestMatch.displayID), frame=\(windowFrame.debugDescription), distanceSquared=\(minDistanceSquared)")
        }

        return nearestMatch
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }

    private func log(_ message: String) {
        Self.logger.debug("\(message, privacy: .public)")
    }
}
