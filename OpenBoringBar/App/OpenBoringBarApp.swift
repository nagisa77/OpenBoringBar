import SwiftUI

@main
struct OpenBoringBarApp: App {
    @StateObject private var barManager = BarManager()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(barManager)
                .frame(minWidth: 960, minHeight: 560)
        }
    }
}
