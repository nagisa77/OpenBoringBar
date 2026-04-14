import Foundation

protocol InstalledApplicationProviding {
    func fetchInstalledApplications() -> [LaunchableApplicationItem]
}

final class InstalledApplicationProvider: InstalledApplicationProviding {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fetchInstalledApplications() -> [LaunchableApplicationItem] {
        var applications: [LaunchableApplicationItem] = []
        var seenPaths = Set<String>()

        for rootDirectory in searchDirectories where fileManager.fileExists(atPath: rootDirectory.path) {
            guard let enumerator = fileManager.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let candidateURL as URL in enumerator {
                guard candidateURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }
                enumerator.skipDescendants()

                let normalizedPath = candidateURL.standardizedFileURL.path
                guard seenPaths.insert(normalizedPath).inserted else {
                    continue
                }

                applications.append(
                    LaunchableApplicationItem(
                        bundleURL: candidateURL,
                        name: applicationName(for: candidateURL)
                    )
                )
            }
        }

        applications.sort { lhs, rhs in
            let byName = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if byName == .orderedSame {
                return lhs.bundleURL.path.localizedCaseInsensitiveCompare(rhs.bundleURL.path) == .orderedAscending
            }
            return byName == .orderedAscending
        }

        return applications
    }

    private var searchDirectories: [URL] {
        let standardDirectories =
            fileManager.urls(for: .applicationDirectory, in: .systemDomainMask) +
            fileManager.urls(for: .applicationDirectory, in: .localDomainMask) +
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)

        let extraDirectories = [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true)
        ]

        var uniqueDirectories: [URL] = []
        var seenPaths = Set<String>()

        for directory in standardDirectories + extraDirectories {
            let normalizedPath = directory.standardizedFileURL.path
            if seenPaths.insert(normalizedPath).inserted {
                uniqueDirectories.append(directory)
            }
        }

        return uniqueDirectories
    }

    private func applicationName(for bundleURL: URL) -> String {
        guard let bundle = Bundle(url: bundleURL) else {
            return bundleURL.deletingPathExtension().lastPathComponent
        }

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return bundleURL.deletingPathExtension().lastPathComponent
    }
}
