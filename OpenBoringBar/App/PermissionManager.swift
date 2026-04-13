import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var setupCompleted = false

    private let setupRequiredAtLaunch: Bool

    var allGranted: Bool {
        accessibilityGranted && screenRecordingGranted
    }

    var shouldPresentSetup: Bool {
//        !allGranted || (setupRequiredAtLaunch && !setupCompleted)
      return false
    }

    init() {
        let initialAccessibilityGranted = AXIsProcessTrusted()
        let initialScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        let requiresSetup = !(initialAccessibilityGranted && initialScreenRecordingGranted)

        accessibilityGranted = initialAccessibilityGranted
        screenRecordingGranted = initialScreenRecordingGranted
        setupRequiredAtLaunch = requiresSetup
        setupCompleted = !requiresSetup
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        scheduleRefresh()
    }

    func requestScreenRecordingAccess() {
        _ = CGRequestScreenCaptureAccess()
        scheduleRefresh()
    }

    func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSettings(anchor: "Privacy_ScreenCapture")
    }

    func completeSetupIfPossible() {
        refreshPermissions()
        guard allGranted else {
            return
        }

        setupCompleted = true
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshPermissions()
        }
    }

    private func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
