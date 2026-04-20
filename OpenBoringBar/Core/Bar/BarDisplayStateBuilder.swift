import AppKit
import ApplicationServices

final class BarDisplayStateBuilder {
    private let appOrderManager: BarDisplayAppOrderManager

    init(appOrderManager: BarDisplayAppOrderManager = BarDisplayAppOrderManager()) {
        self.appOrderManager = appOrderManager
    }

    func buildDisplayStates(
        notificationBadgeCountByProcessID: [pid_t: Int] = [:]
    ) -> [DisplayState] {
        let screens = NSScreen.screens
        let displayIDs = screens.compactMap(\.displayID)
        appOrderManager.syncActiveDisplays(Set(displayIDs))

        let displayBoundsByID = Dictionary(
            uniqueKeysWithValues: displayIDs.map { ($0, CGDisplayBounds($0)) }
        )
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var appsByDisplay: [CGDirectDisplayID: [BarAppSnapshot]] = [:]
        var seenByDisplay: [CGDirectDisplayID: Set<pid_t>] = [:]
        for displayID in displayIDs {
            appsByDisplay[displayID] = []
            seenByDisplay[displayID] = []
        }

        var frontmostDisplayID: CGDirectDisplayID?
        appendVisibleLayerZeroApps(
            appsByDisplay: &appsByDisplay,
            seenByDisplay: &seenByDisplay,
            displayIDs: displayIDs,
            displayBoundsByID: displayBoundsByID,
            frontmostPID: frontmostPID,
            frontmostDisplayID: &frontmostDisplayID
        )
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
            guard let displayID = screen.displayID else {
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
                    isFrontmost: snapshot.processID == frontmostPID && displayID == frontmostDisplayID,
                    notificationBadgeCount: max(
                        0,
                        notificationBadgeCountByProcessID[snapshot.processID] ?? 0
                    )
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

        return nextDisplayStates
    }

    private func appendVisibleLayerZeroApps(
        appsByDisplay: inout [CGDirectDisplayID: [BarAppSnapshot]],
        seenByDisplay: inout [CGDirectDisplayID: Set<pid_t>],
        displayIDs: [CGDirectDisplayID],
        displayBoundsByID: [CGDirectDisplayID: CGRect],
        frontmostPID: pid_t?,
        frontmostDisplayID: inout CGDirectDisplayID?
    ) {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }

        for windowInfo in windowList {
            guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }
            let processID = pid_t(ownerPIDNumber.int32Value)

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
                  !windowBounds.isEmpty,
                  let runningApplication = NSRunningApplication(processIdentifier: processID),
                  runningApplication.activationPolicy == .regular else {
                continue
            }

            let appName = runningApplication.localizedName
                ?? (windowInfo[kCGWindowOwnerName as String] as? String)
                ?? "Unknown App"
            let windowTitle = trimmedWindowTitle(
                from: windowInfo[kCGWindowName as String] as? String
            )
            let displayName = windowTitle ?? appName

            for displayID in displayIDs {
                guard let displayBounds = displayBoundsByID[displayID],
                      displayBounds.intersects(windowBounds) else {
                    continue
                }

                if seenByDisplay[displayID, default: []].insert(processID).inserted {
                    appsByDisplay[displayID, default: []].append(
                        BarAppSnapshot(processID: processID, name: displayName)
                    )
                } else if let windowTitle,
                          var snapshots = appsByDisplay[displayID],
                          let snapshotIndex = snapshots.firstIndex(where: { $0.processID == processID }),
                          snapshots[snapshotIndex].name == appName {
                    snapshots[snapshotIndex] = BarAppSnapshot(processID: processID, name: windowTitle)
                    appsByDisplay[displayID] = snapshots
                }

                if processID == frontmostPID, frontmostDisplayID == nil {
                    frontmostDisplayID = displayID
                }
            }
        }
    }

    private func appendMinimizedApps(
        appsByDisplay: inout [CGDirectDisplayID: [BarAppSnapshot]],
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
            guard let windows = AXElementInspector.windows(from: appElement),
                  !windows.isEmpty else {
                continue
            }

            let appName = app.localizedName ?? "Unknown App"
            for window in windows {
                guard AXElementInspector.isWindowMinimized(window),
                      let windowFrame = AXElementInspector.frame(of: window),
                      !windowFrame.isEmpty else {
                    continue
                }

                let windowTitle = trimmedWindowTitle(
                    from: AXElementInspector.stringAttributeValue(
                        of: AXAttributeName.title,
                        from: window
                    )
                )
                let displayName = windowTitle ?? appName

                for displayID in displayIDs {
                    guard let displayBounds = displayBoundsByID[displayID],
                          displayBounds.intersects(windowFrame) else {
                        continue
                    }

                    if seenByDisplay[displayID, default: []].insert(processID).inserted {
                        appsByDisplay[displayID, default: []].append(
                            BarAppSnapshot(processID: processID, name: displayName)
                        )
                    }
                }
            }
        }
    }

    private func trimmedWindowTitle(from title: String?) -> String? {
        guard let title else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
