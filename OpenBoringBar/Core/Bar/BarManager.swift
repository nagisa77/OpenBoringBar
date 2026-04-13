import AppKit
import Combine

final class BarManager: ObservableObject {
    @Published private(set) var connectedDisplays: [NSScreen]
    @Published private(set) var mockRunningApps: [String]

    private var displayObserver: NSObjectProtocol?

    init() {
        connectedDisplays = NSScreen.screens
        mockRunningApps = ["Finder", "Safari", "Xcode", "Terminal", "Music"]

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.connectedDisplays = NSScreen.screens
        }
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
    }

    func activate(appName: String) {
        guard let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
            return
        }

        runningApp.activate(options: [.activateAllWindows])
    }
}
