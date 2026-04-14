import AppKit
import SwiftUI

struct DisplayBottomBarView: View {
    let apps: [RunningAppItem]
    let launchableApplications: [LaunchableApplicationItem]
    let onSwitch: (pid_t) -> Void
    let onOpenApplication: (URL) -> Void
    let onAppHoverChanged: (pid_t?, CGRect?) -> Void

    @State private var isApplicationLauncherPresented = false

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

                if apps.isEmpty {
                    Text("该显示器暂无可见窗口")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 10)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(apps, id: \.self) { app in
                                DisplayBarAppPill(
                                    app: app,
                                    onSwitch: onSwitch,
                                    onHoverChanged: onAppHoverChanged
                                )
                            }
                        }
                        .padding(.trailing, 10)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var applicationLauncherButton: some View {
        Button {
            isApplicationLauncherPresented.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(
                width: BarLayoutConstants.launcherButtonSize,
                height: BarLayoutConstants.launcherButtonSize
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
            .background(
                DisplayBarPillHoverTrackingArea { isHovering, frameInScreen in
                    if isHovering {
                        onHoverChanged(app.processID, frameInScreen)
                    } else {
                        onHoverChanged(nil, nil)
                    }
                }
            )
        }
        .buttonStyle(.plain)
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
