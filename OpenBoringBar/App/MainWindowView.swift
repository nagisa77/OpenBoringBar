import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var barManager: BarManager

    private let columns = [GridItem(.adaptive(minimum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(barManager.displayStates.enumerated()), id: \.element.id) { index, display in
                        DisplayCard(
                            index: index + 1,
                            screenFrame: display.frame,
                            apps: display.apps,
                            onSwitch: barManager.activate(processID:)
                        )
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenBoringBar")
                .font(.system(size: 36, weight: .bold))

            Text("v1.0: 每个显示器底部展示 panel，支持快速切换窗口。")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Text("当前检测到 \(barManager.displayStates.count) 个显示器")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct DisplayCard: View {
    let index: Int
    let screenFrame: CGRect
    let apps: [RunningAppItem]
    let onSwitch: (pid_t) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Display \(index)")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(Int(screenFrame.width)) x \(Int(screenFrame.height))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            displayPreview
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var displayPreview: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.87, green: 0.91, blue: 0.94),
                            Color(red: 0.79, green: 0.86, blue: 0.83)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )

            DisplayBottomPanel(apps: apps, onSwitch: onSwitch)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct DisplayBottomPanel: View {
    let apps: [RunningAppItem]
    let onSwitch: (pid_t) -> Void

    var body: some View {
        Group {
            if apps.isEmpty {
                Text("该显示器暂无可见窗口")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(apps, id: \.self) { app in
                            DisplayAppPill(app: app, onSwitch: onSwitch)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct DisplayAppPill: View {
    let app: RunningAppItem
    let onSwitch: (pid_t) -> Void

    var body: some View {
        Button(action: { onSwitch(app.processID) }) {
            HStack(spacing: 8) {
                RunningAppIcon(processID: app.processID)

                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minWidth: 130, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        app.isFrontmost
                            ? Color.white.opacity(0.72)
                            : Color.white.opacity(0.34)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        app.isFrontmost
                            ? Color.accentColor.opacity(0.45)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RunningAppIcon: View {
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
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
    }
}
