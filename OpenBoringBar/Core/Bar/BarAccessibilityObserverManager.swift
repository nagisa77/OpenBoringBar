import AppKit
import ApplicationServices

final class BarAccessibilityObserverManager {
    var onObservedChange: (() -> Void)?

    private static let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else {
            return
        }

        let manager = Unmanaged<BarAccessibilityObserverManager>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        manager.handleAccessibilityNotification(
            element: element,
            notification: notification as String
        )
    }

    private var observerByPID: [pid_t: AXObserver] = [:]
    private var appElementByPID: [pid_t: AXUIElement] = [:]

    func installObserversForRunningApps() {
        guard AXIsProcessTrusted() else {
            return
        }

        for app in NSWorkspace.shared.runningApplications {
            installObserverIfNeeded(for: app)
        }
    }

    func installObserverIfNeeded(for app: NSRunningApplication) {
        guard AXIsProcessTrusted() else {
            return
        }

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
            Self.axObserverCallback,
            &observer
        )

        guard createResult == .success, let observer else {
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
            appElement: appElement
        )
        registerWindowLevelNotifications(processID: processID)
    }

    func removeObserver(for processID: pid_t) {
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
    }

    func teardownAllObservers() {
        let processIDs = Array(observerByPID.keys)
        for processID in processIDs {
            removeObserver(for: processID)
        }
    }

    private func registerAppLevelNotifications(
        observer: AXObserver,
        appElement: AXUIElement
    ) {
        registerNotification(
            AXNotificationName.focusedWindowChanged,
            observer: observer,
            element: appElement
        )
        registerNotification(
            AXNotificationName.mainWindowChanged,
            observer: observer,
            element: appElement
        )
        registerNotification(
            AXNotificationName.windowCreated,
            observer: observer,
            element: appElement
        )
        registerNotification(
            AXNotificationName.applicationHidden,
            observer: observer,
            element: appElement
        )
        registerNotification(
            AXNotificationName.applicationShown,
            observer: observer,
            element: appElement
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
                element: window
            )
            registerNotification(
                AXNotificationName.resized,
                observer: observer,
                element: window
            )
            registerNotification(
                AXNotificationName.titleChanged,
                observer: observer,
                element: window
            )
            registerNotification(
                AXNotificationName.windowMiniaturized,
                observer: observer,
                element: window
            )
            registerNotification(
                AXNotificationName.windowDeminiaturized,
                observer: observer,
                element: window
            )
            registerNotification(
                AXNotificationName.uiElementDestroyed,
                observer: observer,
                element: window
            )
        }
    }

    private func registerNotification(
        _ notification: String,
        observer: AXObserver,
        element: AXUIElement
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
    }

    private func handleAccessibilityNotification(
        element: AXUIElement,
        notification: String
    ) {
        guard let processID = processID(of: element) else {
            return
        }

        switch notification {
        case AXNotificationName.windowCreated,
             AXNotificationName.focusedWindowChanged,
             AXNotificationName.mainWindowChanged:
            registerWindowLevelNotifications(processID: processID)
            onObservedChange?()

        case AXNotificationName.moved,
             AXNotificationName.resized,
             AXNotificationName.titleChanged,
             AXNotificationName.windowMiniaturized,
             AXNotificationName.windowDeminiaturized,
             AXNotificationName.applicationHidden,
             AXNotificationName.applicationShown,
             AXNotificationName.uiElementDestroyed:
            onObservedChange?()

        default:
            break
        }
    }

    private func processID(of element: AXUIElement) -> pid_t? {
        var processID: pid_t = 0
        let result = AXUIElementGetPid(element, &processID)
        guard result == .success else {
            return nil
        }
        return processID
    }
}
