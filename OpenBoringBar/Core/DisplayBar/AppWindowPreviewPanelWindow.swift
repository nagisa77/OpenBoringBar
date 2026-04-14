import AppKit

final class AppWindowPreviewPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
