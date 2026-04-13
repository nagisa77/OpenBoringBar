import AppKit
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
    @Published private(set) var displayStates: [DisplayState]

    private var displayObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol]
    private var refreshTimer: Timer?

    init() {
        displayStates = []
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

        _ = app.unhide()

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
            self.refreshDisplayStates()
        }
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

            let apps = appsByDisplay[displayID, default: []].map { snapshot in
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

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

private struct AppSnapshot {
    let processID: pid_t
    let name: String
}
