import AppKit
import Foundation

@MainActor
final class AppRuntimeCoordinator: ObservableObject {
    @Published private(set) var barManager: BarManager?

    private let eventBus: AppEventBus
    private var displayPanelController: DisplayPanelController?
    private var activeWindowBottomGuardManager: ActiveWindowBottomGuardManager?

    init(eventBus: AppEventBus = DefaultAppEventBus()) {
        self.eventBus = eventBus
    }

    func startBarManagerIfNeeded() {
        guard barManager == nil else {
            return
        }

        barManager = BarManager(eventBus: eventBus)
    }

    func startPanelsIfNeeded() {
        guard let barManager else {
            return
        }

        if displayPanelController == nil {
            let controller = DisplayPanelController(barManager: barManager)
            controller.start()
            displayPanelController = controller

            closeHostWindowsKeepingPanels()
        }

        startActiveWindowBottomGuardIfNeeded()
    }

    func stopPanelsAndReset() {
        displayPanelController?.stop()
        displayPanelController = nil
        activeWindowBottomGuardManager = nil
        barManager = nil
    }

    private func closeHostWindowsKeepingPanels() {
        DispatchQueue.main.async {
            for window in NSApp.windows where !(window is DisplayPanelWindow) {
                window.orderOut(nil)
                window.close()
            }
        }
    }

    private func startActiveWindowBottomGuardIfNeeded() {
        guard activeWindowBottomGuardManager == nil else {
            return
        }

        activeWindowBottomGuardManager = ActiveWindowBottomGuardManager(eventBus: eventBus)
    }
}
