import CoreGraphics
import SwiftUI

struct AppWindowPreviewPanelView: View {
    let appName: String
    let previews: [AppWindowPreviewItem]
    let onHoverChanged: (Bool) -> Void
    let onSelectWindow: (CGWindowID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if previews.isEmpty {
                Text("暂无可预览窗口")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: BarLayoutConstants.previewCardSpacing) {
                    ForEach(previews) { preview in
                        WindowPreviewCardView(
                            preview: preview,
                            onSelectWindow: onSelectWindow
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(BarLayoutConstants.previewPanelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
        )
        .onHover(perform: onHoverChanged)
    }
}

private struct WindowPreviewCardView: View {
    let preview: AppWindowPreviewItem
    let onSelectWindow: (CGWindowID) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onSelectWindow(preview.windowID)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(decorative: preview.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(
                        width: BarLayoutConstants.previewCardWidth - 18,
                        height: BarLayoutConstants.previewCardImageHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
            }
            .padding(9)
            .frame(width: BarLayoutConstants.previewCardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.34 : 0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.72 : 0.4), lineWidth: 1)
                    )
            )
            .scaleEffect(isHovering ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
