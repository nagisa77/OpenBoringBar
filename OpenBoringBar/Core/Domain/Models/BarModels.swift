import CoreGraphics

struct RunningAppItem: Identifiable, Hashable {
    let processID: pid_t
    let name: String
    let isFrontmost: Bool

    var id: pid_t { processID }
}

struct DisplayState: Identifiable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let apps: [RunningAppItem]
}
