import AppKit
import SwiftUI

struct ApplicationLauncherPopoverView: View {
    let applications: [LaunchableApplicationItem]
    let onSelect: (LaunchableApplicationItem) -> Void

    @State private var query = ""

    private var filteredApplications: [LaunchableApplicationItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return applications
        }

        return applications.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmed)
                || item.bundleURL.lastPathComponent.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Applications")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredApplications.isEmpty {
                        Text("No matching applications")
                            .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(filteredApplications) { app in
                            Button {
                                onSelect(app)
                            } label: {
                                ApplicationLauncherRow(app: app)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search applications...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(
            width: BarLayoutConstants.launcherPopoverWidth,
            height: BarLayoutConstants.launcherPopoverHeight
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct ApplicationLauncherRow: View {
    let app: LaunchableApplicationItem

    private var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text(app.name)
                .font(.system(size: BarLayoutConstants.launcherBaseFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
