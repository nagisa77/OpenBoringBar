import AppKit
import ApplicationServices
import Combine

final class BarManager: ObservableObject {
    @Published private(set) var displayStates: [DisplayState]
    @Published private(set) var launchableApplications: [LaunchableApplicationItem]

    private let eventBus: AppEventBus
    private let installedApplicationProvider: InstalledApplicationProviding
    private let windowPreviewProvider: WindowPreviewProviding
    private let displayStateBuilder: BarDisplayStateBuilder
    private let accessibilityObserverManager: BarAccessibilityObserverManager

    private var displayObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol]
    private var pendingRefreshWorkItem: DispatchWorkItem?

    private let refreshDebounceInterval: TimeInterval = 0.10

    init(
        eventBus: AppEventBus,
        installedApplicationProvider: InstalledApplicationProviding = InstalledApplicationProvider(),
        windowPreviewProvider: WindowPreviewProviding = WindowPreviewProvider(),
        displayStateBuilder: BarDisplayStateBuilder = BarDisplayStateBuilder(),
        accessibilityObserverManager: BarAccessibilityObserverManager = BarAccessibilityObserverManager()
    ) {
        self.displayStates = []
        self.launchableApplications = []
        self.eventBus = eventBus
        self.installedApplicationProvider = installedApplicationProvider
        self.windowPreviewProvider = windowPreviewProvider
        self.displayStateBuilder = displayStateBuilder
        self.accessibilityObserverManager = accessibilityObserverManager
        self.workspaceObservers = []

        self.accessibilityObserverManager.onObservedChange = { [weak self] in
            self?.scheduleDisplayRefresh()
        }

        configureDisplayObserver()
        configureWorkspaceObservers()
        self.accessibilityObserverManager.installObserversForRunningApps()

        refreshDisplayStates()
        refreshLaunchableApplications()
    }

    deinit {
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        accessibilityObserverManager.teardownAllObservers()

        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }

        teardownWorkspaceObservers()
    }

    func activate(processID: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: processID),
              !app.isTerminated else {
            return
        }

        let previousFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

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
            let currentFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if previousFrontmostPID != processID, currentFrontmostPID == processID {
                self.eventBus.post(.capsuleAppSwitchConfirmed(processID: processID))
            }
            self.refreshDisplayStates()
        }
    }

    func openApplication(bundleURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, _ in
            self?.refreshDisplayStates()
        }
    }

    func activateWindow(
        processID: pid_t,
        windowID: CGWindowID
    ) {
        let previousFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let didActivateSpecificWindow = windowPreviewProvider.activateWindow(
            windowID: windowID,
            processID: processID
        )

        guard didActivateSpecificWindow else {
            activate(processID: processID)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else {
                return
            }

            let currentFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if previousFrontmostPID != processID, currentFrontmostPID == processID {
                self.eventBus.post(.capsuleAppSwitchConfirmed(processID: processID))
            }
            self.refreshDisplayStates()
        }
    }

    func windowPreviews(
        for processID: pid_t,
        on displayID: CGDirectDisplayID
    ) -> [AppWindowPreviewItem] {
        windowPreviewProvider.fetchWindowPreviews(
            for: processID,
            displayID: displayID
        )
    }

    private func configureDisplayObserver() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDisplayRefresh()
        }
    }

    private func configureWorkspaceObservers() {
        workspaceObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleDisplayRefresh()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] notification in
                guard let self else {
                    return
                }

                if let app = self.runningApplication(from: notification) {
                    self.accessibilityObserverManager.installObserverIfNeeded(for: app)
                }
                self.scheduleDisplayRefresh()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] notification in
                guard let self else {
                    return
                }

                if let app = self.runningApplication(from: notification) {
                    self.accessibilityObserverManager.removeObserver(for: app.processIdentifier)
                }
                self.scheduleDisplayRefresh()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didHideApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleDisplayRefresh()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.didUnhideApplicationNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleDisplayRefresh()
            },
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleDisplayRefresh()
            }
        ]
    }

    private func teardownWorkspaceObservers() {
        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func scheduleDisplayRefresh() {
        pendingRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingRefreshWorkItem = nil
            self.refreshDisplayStates()
        }

        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDebounceInterval, execute: workItem)
    }

    private func runningApplication(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func minimizeFocusedWindow(of processID: pid_t) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let appElement = AXUIElementCreateApplication(processID)
        guard let focusedWindow = AXElementInspector.focusedWindow(from: appElement) else {
            return false
        }

        let minimizeResult = AXUIElementSetAttributeValue(
            focusedWindow,
            AXAttributeName.minimized,
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
        displayStates = displayStateBuilder.buildDisplayStates()
    }

    private func refreshLaunchableApplications() {
        launchableApplications = installedApplicationProvider.fetchInstalledApplications()
    }

    private func restoreFirstMinimizedWindowIfNoVisibleWindow(of processID: pid_t) -> Bool {
        guard AXIsProcessTrusted(),
              !hasVisibleLayerZeroWindow(of: processID),
              let window = firstMinimizedWindow(of: processID) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            window,
            AXAttributeName.minimized,
            kCFBooleanFalse
        )
        return result == .success
    }

    private func firstMinimizedWindow(of processID: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processID)
        guard let windows = AXElementInspector.windows(from: appElement) else {
            return nil
        }

        return windows.first(where: AXElementInspector.isWindowMinimized)
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

            if let layerNumber = windowInfo[kCGWindowLayer as String] as? NSNumber,
               layerNumber.intValue != 0 {
                continue
            }

            if let alphaNumber = windowInfo[kCGWindowAlpha as String] as? NSNumber,
               alphaNumber.doubleValue <= 0 {
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
}
