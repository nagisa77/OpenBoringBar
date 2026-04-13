import SwiftUI

@main
struct OpenBoringBarApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @State private var barManager: BarManager?

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.shouldPresentSetup {
                    PermissionSetupView()
                        .environmentObject(permissionManager)
                } else if let barManager {
                    MainWindowView()
                        .environmentObject(barManager)
                } else {
                    ProgressView("Starting boringBar...")
                        .task {
                            if barManager == nil {
                                barManager = BarManager()
                            }
                        }
                }
            }
            .onChange(of: permissionManager.shouldPresentSetup) { _, shouldPresent in
                if shouldPresent {
                    barManager = nil
                }
            }
            .frame(minWidth: 960, minHeight: 560)
        }
    }
}
