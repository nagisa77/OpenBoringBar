import AppKit
import SwiftUI

private enum DisplayBottomBarAnimation {
    static let contentSwap = Animation.easeInOut(duration: 0.2)
    static let appListMutation = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let appStateChange = Animation.easeInOut(duration: 0.16)
    static let pillHover = Animation.easeOut(duration: 0.12)
    static let launcherToggle = Animation.spring(response: 0.24, dampingFraction: 0.8)
}

struct DisplayBottomBarView: View {
    let apps: [RunningAppItem]
    let launchableApplications: [LaunchableApplicationItem]
    let isAutoCollapseEnabled: Bool
    let onSwitch: (pid_t) -> Void
    let onOpenApplication: (URL) -> Void
    let onAppHoverChanged: (pid_t?, CGRect?) -> Void
    let onBarHoverChanged: (Bool) -> Void
    let onAutoCollapseToggled: (Bool) -> Void
    let onRequestQuit: () -> Void

    @State private var isApplicationLauncherPresented = false

    private var appLayoutAnimationKeys: [String] {
        apps.map { "\($0.processID)-\($0.name)" }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )

            HStack(spacing: 8) {
                applicationLauncherButton

                Divider()
                    .padding(.vertical, 9)

                Group {
                    if apps.isEmpty {
                        Text("该显示器暂无可见窗口")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 10)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                )
                            )
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(apps) { app in
                                    DisplayBarAppPill(
                                        app: app,
                                        onSwitch: onSwitch,
                                        onHoverChanged: onAppHoverChanged
                                    )
                                    .transition(
                                        .asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                                            removal: .opacity
                                        )
                                    )
                                }
                            }
                            .padding(.trailing, 10)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            )
                        )
                    }
                }
            }
            .padding(.leading, 8)
            .animation(
                DisplayBottomBarAnimation.contentSwap,
                value: apps.isEmpty
            )
            .animation(
                DisplayBottomBarAnimation.appListMutation,
                value: appLayoutAnimationKeys
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover(perform: onBarHoverChanged)
        .contextMenu {
            Button(action: onRequestQuit) {
                Label("Quit", systemImage: "xmark.circle")
            }

            Toggle(
                "Auto-collapse",
                isOn: Binding(
                    get: { isAutoCollapseEnabled },
                    set: onAutoCollapseToggled
                )
            )
        }
    }

    private var applicationLauncherButton: some View {
        Button {
            withAnimation(DisplayBottomBarAnimation.launcherToggle) {
                isApplicationLauncherPresented.toggle()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        Color.white.opacity(
                            isApplicationLauncherPresented ? 0.2 : 0.12
                        )
                    )

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(
                        .degrees(isApplicationLauncherPresented ? 8 : 0)
                    )
                    .scaleEffect(isApplicationLauncherPresented ? 0.94 : 1)
            }
            .frame(
                width: BarLayoutConstants.launcherButtonSize,
                height: BarLayoutConstants.launcherButtonSize
            )
            .animation(
                DisplayBottomBarAnimation.launcherToggle,
                value: isApplicationLauncherPresented
            )
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isApplicationLauncherPresented,
            attachmentAnchor: .point(.topLeading),
            arrowEdge: .bottom
        ) {
            ApplicationLauncherPopoverView(applications: launchableApplications) { app in
                isApplicationLauncherPresented = false
                onOpenApplication(app.bundleURL)
            }
            .padding(8)
        }
    }
}

private struct DisplayBarAppPill: View {
    private static let appNameMaxWidth: CGFloat = 140

    let app: RunningAppItem
    let onSwitch: (pid_t) -> Void
    let onHoverChanged: (pid_t?, CGRect?) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: { onSwitch(app.processID) }) {
            HStack(spacing: 8) {
                DisplayBarAppIcon(processID: app.processID)

                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(app.isFrontmost ? Color.black : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.appNameMaxWidth, alignment: .leading)
                    .contentTransition(.opacity)

                if app.notificationBadgeCount > 0 {
                    DisplayBarAppNotificationBadge(
                        count: app.notificationBadgeCount
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        app.isFrontmost
                            ? Color.white.opacity(0.72)
                            : Color.white.opacity(0.1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        app.isFrontmost
                            ? Color.accentColor.opacity(0.42)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1)
            .shadow(
                color: Color.black.opacity(isHovering ? 0.2 : 0),
                radius: isHovering ? 9 : 0,
                x: 0,
                y: 4
            )
            .background(
                DisplayBarPillHoverTrackingArea { hovering, frameInScreen in
                    withAnimation(DisplayBottomBarAnimation.pillHover) {
                        isHovering = hovering
                    }

                    if hovering {
                        onHoverChanged(app.processID, frameInScreen)
                    } else {
                        onHoverChanged(nil, nil)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .animation(
            DisplayBottomBarAnimation.appStateChange,
            value: app.isFrontmost
        )
        .animation(
            DisplayBottomBarAnimation.appStateChange,
            value: app.notificationBadgeCount
        )
        .animation(
            DisplayBottomBarAnimation.appListMutation,
            value: app.name
        )
    }
}

private struct DisplayBarAppNotificationBadge: View {
    private static let minimumWidth: CGFloat = 18
    private static let horizontalPadding: CGFloat = 6
    private static let verticalPadding: CGFloat = 2
    private static let maxDisplayedCount = 99

    let count: Int

    private var text: String {
        if count > Self.maxDisplayedCount {
            return "\(Self.maxDisplayedCount)+"
        }
        return String(count)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(minWidth: Self.minimumWidth)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.92))
            )
    }
}

private struct DisplayBarAppIcon: View {
    let processID: pid_t

    private var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: processID)?.icon
    }

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

private struct DisplayBarPillHoverTrackingArea: NSViewRepresentable {
    let onHoverChanged: (Bool, CGRect) -> Void

    func makeNSView(context: Context) -> DisplayBarPillHoverTrackingNSView {
        let view = DisplayBarPillHoverTrackingNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: DisplayBarPillHoverTrackingNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }
}

private final class DisplayBarPillHoverTrackingNSView: NSView {
    var onHoverChanged: ((Bool, CGRect) -> Void)?

    private var trackingAreaRef: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        notifyHoverChanged(isHovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        notifyHoverChanged(isHovering: false)
    }

    private func notifyHoverChanged(isHovering: Bool) {
        guard let window else {
            return
        }

        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        onHoverChanged?(isHovering, frameInScreen)
    }
}
