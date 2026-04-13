import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var barManager: BarManager

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16)]

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

            Text("v1.0: 每个显示器底部都有 bar，展示运行应用并支持切换。")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Display \(index)")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(Int(screenFrame.width)) x \(Int(screenFrame.height))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(apps, id: \.self) { app in
                    Button(action: { onSwitch(app.processID) }) {
                        Text(app.name)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        app.isFrontmost
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.white.opacity(0.9)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if apps.isEmpty {
                Text("该显示器暂无可见应用窗口")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
