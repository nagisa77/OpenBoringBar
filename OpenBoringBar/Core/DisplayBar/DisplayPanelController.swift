import AppKit
import Combine
import SwiftUI

final class DisplayPanelController {
    private let barManager: BarManager
    private var displayStateCancellable: AnyCancellable?
    private var windowsByDisplayID: [CGDirectDisplayID: DisplayPanelWindow] = [:]

    init(barManager: BarManager) {
        self.barManager = barManager
    }

    func start() {
        guard displayStateCancellable == nil else {
            return
        }

        displayStateCancellable = barManager.$displayStates
            .receive(on: RunLoop.main)
            .sink { [weak self] states in
                self?.syncPanels(with: states)
            }

        syncPanels(with: barManager.displayStates)
    }

    func stop() {
        displayStateCancellable?.cancel()
        displayStateCancellable = nil

        for panel in windowsByDisplayID.values {
            panel.orderOut(nil)
            panel.close()
        }
        windowsByDisplayID.removeAll()
    }

    private func syncPanels(with states: [DisplayState]) {
        let activeDisplayIDs = Set(states.map(\.id))

        for (displayID, panel) in windowsByDisplayID where !activeDisplayIDs.contains(displayID) {
            panel.orderOut(nil)
            panel.close()
            windowsByDisplayID.removeValue(forKey: displayID)
        }

        for state in states {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == state.id }) else {
                continue
            }

            let panel = panelForDisplay(state.id)
            updateFrame(of: panel, in: screen)
            updateContent(of: panel, with: state.apps)
            panel.orderFrontRegardless()
        }
    }

    private func panelForDisplay(_ displayID: CGDirectDisplayID) -> DisplayPanelWindow {
        if let existing = windowsByDisplayID[displayID] {
            return existing
        }

        let panel = DisplayPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        windowsByDisplayID[displayID] = panel
        return panel
    }

    private func updateFrame(of panel: DisplayPanelWindow, in screen: NSScreen) {
        let width = screen.frame.width
        let x = screen.frame.minX
        let y = screen.frame.minY
        let frame = CGRect(x: x, y: y, width: width, height: BarLayoutConstants.panelHeight)

        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func updateContent(of panel: DisplayPanelWindow, with apps: [RunningAppItem]) {
        let content = AnyView(
            DisplayBottomBarView(
                apps: apps,
                onSwitch: barManager.activate(processID:)
            )
        )

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
    }
}

final class DisplayPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
