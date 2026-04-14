import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

protocol WindowPreviewProviding {
    func fetchWindowPreviews(
        for processID: pid_t,
        displayID: CGDirectDisplayID
    ) -> [AppWindowPreviewItem]

    func activateWindow(
        windowID: CGWindowID,
        processID: pid_t
    ) -> Bool
}

final class WindowPreviewProvider: WindowPreviewProviding {
    func fetchWindowPreviews(
        for processID: pid_t,
        displayID: CGDirectDisplayID
    ) -> [AppWindowPreviewItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let displayBounds = CGDisplayBounds(displayID)
        let appName = NSRunningApplication(processIdentifier: processID)?.localizedName ?? "Window"
        var rawPreviews: [RawWindowPreview] = []

        for windowInfo in windowList {
            guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(ownerPIDNumber.int32Value) == processID,
                  let windowIDNumber = windowInfo[kCGWindowNumber as String] as? NSNumber else {
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
                  !windowBounds.isEmpty,
                  displayBounds.intersects(windowBounds) else {
                continue
            }

            let windowID = CGWindowID(windowIDNumber.uint32Value)
            guard let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) else {
                continue
            }

            let windowTitle = (windowInfo[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rawPreviews.append(
                RawWindowPreview(
                    windowID: windowID,
                    title: windowTitle,
                    frame: windowBounds,
                    image: image
                )
            )
        }

        rawPreviews.sort { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }

            if lhs.frame.minY != rhs.frame.minY {
                return lhs.frame.minY > rhs.frame.minY
            }

            return lhs.windowID < rhs.windowID
        }

        return rawPreviews.enumerated().map { index, preview in
            let resolvedTitle: String
            if let title = preview.title, !title.isEmpty {
                resolvedTitle = title
            } else {
                resolvedTitle = "\(appName) \(index + 1)"
            }

            return AppWindowPreviewItem(
                windowID: preview.windowID,
                title: resolvedTitle,
                image: preview.image
            )
        }
    }

    func activateWindow(
        windowID: CGWindowID,
        processID: pid_t
    ) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: processID),
              !app.isTerminated else {
            return false
        }

        let requestAccepted: Bool
        if #available(macOS 14.0, *) {
            NSApp.activate()
            NSApp.yieldActivation(to: app)
            requestAccepted = app.activate(from: .current, options: [.activateAllWindows])
        } else {
            NSApp.activate(ignoringOtherApps: true)
            requestAccepted = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard AXIsProcessTrusted() else {
            return requestAccepted
        }

        let appElement = AXUIElementCreateApplication(processID)
        guard let windows = AXElementInspector.windows(from: appElement),
              !windows.isEmpty else {
            return requestAccepted
        }

        let descriptor = activationDescriptor(
            for: windowID,
            processID: processID
        )
        guard let targetWindow = bestMatchingWindow(
            from: windows,
            descriptor: descriptor
        ) else {
            return requestAccepted
        }

        _ = AXUIElementSetAttributeValue(
            targetWindow,
            AXAttributeName.minimized,
            kCFBooleanFalse
        )

        let raiseResult = AXUIElementPerformAction(
            targetWindow,
            kAXRaiseAction as CFString
        )
        let focusResult = AXUIElementSetAttributeValue(
            appElement,
            AXAttributeName.focusedWindow,
            targetWindow
        )

        return requestAccepted || raiseResult == .success || focusResult == .success
    }

    private func activationDescriptor(
        for windowID: CGWindowID,
        processID: pid_t
    ) -> WindowActivationDescriptor? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let ownerPIDNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(ownerPIDNumber.int32Value) == processID,
                  let windowIDNumber = windowInfo[kCGWindowNumber as String] as? NSNumber,
                  CGWindowID(windowIDNumber.uint32Value) == windowID else {
                continue
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDictionary),
                  !frame.isEmpty else {
                continue
            }

            let title = (windowInfo[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WindowActivationDescriptor(
                title: title,
                frame: frame
            )
        }

        return nil
    }

    private func bestMatchingWindow(
        from windows: [AXUIElement],
        descriptor: WindowActivationDescriptor?
    ) -> AXUIElement? {
        guard let descriptor else {
            return windows.first(where: { !AXElementInspector.isWindowMinimized($0) }) ?? windows.first
        }

        var bestMatch: (window: AXUIElement, score: CGFloat)?

        for window in windows {
            guard let frame = AXElementInspector.frame(of: window) else {
                continue
            }

            let title = AXElementInspector.stringAttributeValue(
                of: AXAttributeName.title,
                from: window
            )?.trimmingCharacters(in: .whitespacesAndNewlines)

            var score = frameDistance(from: frame, to: descriptor.frame)

            if let descriptorTitle = descriptor.title,
               !descriptorTitle.isEmpty {
                if title == descriptorTitle {
                    score -= 8_000
                } else if title?.localizedCaseInsensitiveContains(descriptorTitle) == true {
                    score -= 4_000
                }
            }

            if AXElementInspector.isWindowMinimized(window) {
                score += 12_000
            }

            if let currentBest = bestMatch {
                if score < currentBest.score {
                    bestMatch = (window, score)
                }
            } else {
                bestMatch = (window, score)
            }
        }

        return bestMatch?.window
            ?? windows.first(where: { !AXElementInspector.isWindowMinimized($0) })
            ?? windows.first
    }

    private func frameDistance(from lhs: CGRect, to rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX)
            + abs(lhs.midY - rhs.midY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}

private struct RawWindowPreview {
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let image: CGImage
}

private struct WindowActivationDescriptor {
    let title: String?
    let frame: CGRect
}
