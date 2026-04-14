import SwiftUI

@main
struct OpenBoringBarApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var runtimeCoordinator = AppRuntimeCoordinator()

    private let setupMinHeight: CGFloat = 590
    private let runtimeMinHeight: CGFloat = 540

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.shouldPresentSetup {
                    PermissionSetupView()
                        .environmentObject(permissionManager)
                } else if runtimeCoordinator.barManager != nil {
                    PanelBootstrapView()
                        .task {
                            runtimeCoordinator.startPanelsIfNeeded()
                        }
                } else {
                    ProgressView("Starting boringBar...")
                        .task {
                            runtimeCoordinator.startBarManagerIfNeeded()
                        }
                }
            }
            .onChange(of: permissionManager.shouldPresentSetup) { _, shouldPresent in
                if shouldPresent {
                    runtimeCoordinator.stopPanelsAndReset()
                } else {
                    runtimeCoordinator.startBarManagerIfNeeded()
                }
            }
            .frame(minWidth: 920, minHeight: permissionManager.shouldPresentSetup ? setupMinHeight : runtimeMinHeight)
        }
    }
}

private struct PanelBootstrapView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}
