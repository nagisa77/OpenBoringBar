import CoreGraphics

struct AppWindowPreviewItem: Identifiable {
    let windowID: CGWindowID
    let title: String
    let image: CGImage

    var id: CGWindowID { windowID }
}
