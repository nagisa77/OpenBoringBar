import SwiftUI

struct AppWindowPreviewPanelView: View {
    let appName: String
    let previews: [AppWindowPreviewItem]
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))

                Text(appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }

            if previews.isEmpty {
                Text("暂无可预览窗口")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: BarLayoutConstants.previewCardSpacing) {
                    ForEach(previews) { preview in
                        WindowPreviewCardView(preview: preview)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(BarLayoutConstants.previewPanelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
        )
        .onHover(perform: onHoverChanged)
    }
}

private struct WindowPreviewCardView: View {
    let preview: AppWindowPreviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
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
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .padding(9)
        .frame(width: BarLayoutConstants.previewCardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
