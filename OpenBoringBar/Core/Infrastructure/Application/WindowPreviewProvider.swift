import AppKit
import CoreGraphics
import Foundation

protocol WindowPreviewProviding {
    func fetchWindowPreviews(
        for processID: pid_t,
        displayID: CGDirectDisplayID
    ) -> [AppWindowPreviewItem]
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
}

private struct RawWindowPreview {
    let windowID: CGWindowID
    let title: String?
    let frame: CGRect
    let image: CGImage
}
