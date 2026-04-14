import Foundation

struct LaunchableApplicationItem: Identifiable, Hashable {
    let bundleURL: URL
    let name: String

    var id: String { bundleURL.path }
}
