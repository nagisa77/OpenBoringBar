import SwiftUI

struct PermissionSetupView: View {
    @EnvironmentObject private var permissionManager: PermissionManager

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                header
                requiredIntro
                permissionCard
                notesSection
                footer
            }
            .multilineTextAlignment(.leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            permissionManager.refreshPermissions()
        }
        .onReceive(refreshTimer) { _ in
            permissionManager.refreshPermissions()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .quaternaryLabelColor))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Access for boringBar")
                    .font(.system(size: 22, weight: .bold))

                Text("Set up permissions before the app can start.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requiredIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("REQUIRED")

            Text("boringBar needs both permissions before it can start.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PermissionRow(
                iconName: "figure.stand",
                title: "Accessibility",
                description: "Needed to observe windows and respond to focus changes.",
                pathText: "System Settings > Privacy & Security > Accessibility",
                granted: permissionManager.accessibilityGranted,
                primaryTitle: permissionManager.accessibilityGranted ? "Check Again" : "Request Access",
                primaryAction: {
                    if permissionManager.accessibilityGranted {
                        permissionManager.refreshPermissions()
                    } else {
                        permissionManager.requestAccessibilityAccess()
                    }
                },
                secondaryTitle: "Open Settings",
                secondaryAction: permissionManager.openAccessibilitySettings
            )

            Divider()
                .padding(.leading, 60)

            PermissionRow(
                iconName: "display",
                title: "Screen Recording",
                description: "Needed to display window titles and thumbnails.",
                pathText: "System Settings > Privacy & Security > Screen Recording",
                granted: permissionManager.screenRecordingGranted,
                primaryTitle: permissionManager.screenRecordingGranted ? "Check Again" : "Request Access",
                primaryAction: {
                    if permissionManager.screenRecordingGranted {
                        permissionManager.refreshPermissions()
                    } else {
                        permissionManager.requestScreenRecordingAccess()
                    }
                },
                secondaryTitle: "Open Settings",
                secondaryAction: permissionManager.openScreenRecordingSettings
            )
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOTES")

            Text("If Screen Recording was just granted, macOS may require a restart.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("1. Click Request Access for each missing permission.")
                Text("2. If needed, use Open Settings to grant it manually.")
                Text("3. Click Continue once both rows show Granted.")
                Text("4. Accessibility entry must match bundle ID: \(Bundle.main.bundleIdentifier ?? "(unknown)")")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(
                permissionManager.allGranted ? "Permissions granted. Continue to launch." : "Grant both permissions to continue",
                systemImage: permissionManager.allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(permissionManager.allGranted ? Color.green : Color.orange)

            Spacer()

            Button("quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(SetupButtonStyle(isPrimary: false))

            Button("continue") {
                permissionManager.completeSetupIfPossible()
            }
            .buttonStyle(SetupButtonStyle(isPrimary: true))
            .disabled(!permissionManager.allGranted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

private struct PermissionRow: View {
    let iconName: String
    let title: String
    let description: String
    let pathText: String
    let granted: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))

                    PermissionBadge(granted: granted)
                }

                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(pathText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 10) {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(SetupButtonStyle(isPrimary: true))

                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(SetupButtonStyle(isPrimary: false))
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionBadge: View {
    let granted: Bool

    var body: some View {
        Text(granted ? "Granted" : "Required")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(granted ? Color.green : Color.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((granted ? Color.green : Color.orange).opacity(0.14))
            )
    }
}

private struct SetupButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private var foregroundColor: Color {
        guard isPrimary else {
            return .primary
        }

        return colorScheme == .dark ? Color.black : Color.white
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPrimary {
            if colorScheme == .dark {
                return isPressed ? Color.white.opacity(0.3) : Color.white.opacity(0.22)
            }

            return isPressed ? Color.black.opacity(0.6) : Color.black.opacity(0.45)
        }

        if colorScheme == .dark {
            return isPressed ? Color.white.opacity(0.24) : Color.white.opacity(0.14)
        }

        return isPressed ? Color.black.opacity(0.12) : Color.black.opacity(0.08)
    }
}
