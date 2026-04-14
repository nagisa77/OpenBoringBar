import AppKit
import Combine
import SwiftUI

final class DisplayPanelController {
    private let barManager: BarManager
    private var panelStateCancellable: AnyCancellable?
    private var windowsByDisplayID: [CGDirectDisplayID: DisplayPanelWindow] = [:]
    private var previewContextsByDisplayID: [CGDirectDisplayID: DisplayPreviewContext] = [:]
    private var appNamesByDisplayID: [CGDirectDisplayID: [pid_t: String]] = [:]

    init(barManager: BarManager) {
        self.barManager = barManager
    }

    func start() {
        guard panelStateCancellable == nil else {
            return
        }

        panelStateCancellable = Publishers.CombineLatest(
            barManager.$displayStates,
            barManager.$launchableApplications
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] states, launchableApplications in
                self?.syncPanels(with: states, launchableApplications: launchableApplications)
            }

        syncPanels(
            with: barManager.displayStates,
            launchableApplications: barManager.launchableApplications
        )
    }

    func stop() {
        panelStateCancellable?.cancel()
        panelStateCancellable = nil

        for panel in windowsByDisplayID.values {
            panel.orderOut(nil)
            panel.close()
        }
        windowsByDisplayID.removeAll()

        for displayID in Array(previewContextsByDisplayID.keys) {
            closePreviewContext(for: displayID)
        }

        appNamesByDisplayID.removeAll()
    }

    private func syncPanels(
        with states: [DisplayState],
        launchableApplications: [LaunchableApplicationItem]
    ) {
        let activeDisplayIDs = Set(states.map(\.id))

        for (displayID, panel) in Array(windowsByDisplayID) where !activeDisplayIDs.contains(displayID) {
            panel.orderOut(nil)
            panel.close()
            windowsByDisplayID.removeValue(forKey: displayID)
        }

        for displayID in Array(previewContextsByDisplayID.keys) where !activeDisplayIDs.contains(displayID) {
            closePreviewContext(for: displayID)
        }

        appNamesByDisplayID = appNamesByDisplayID.filter { activeDisplayIDs.contains($0.key) }

        for state in states {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == state.id }) else {
                continue
            }

            appNamesByDisplayID[state.id] = Dictionary(
                uniqueKeysWithValues: state.apps.map { ($0.processID, $0.name) }
            )

            let panel = panelForDisplay(state.id)
            updateFrame(of: panel, in: screen)
            updateContent(
                of: panel,
                displayID: state.id,
                with: state.apps,
                launchableApplications: launchableApplications
            )
            panel.orderFrontRegardless()

            if let context = previewContextsByDisplayID[state.id],
               let hoveredPID = context.hoverTarget?.processID,
               !state.apps.contains(where: { $0.processID == hoveredPID }) {
                context.hoverTarget = nil
                if !context.isPointerInsidePreview {
                    schedulePreviewHide(for: context)
                }
            }
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

    private func previewContext(for displayID: CGDirectDisplayID) -> DisplayPreviewContext {
        if let existing = previewContextsByDisplayID[displayID] {
            return existing
        }

        let panel = AppWindowPreviewPanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
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

        let context = DisplayPreviewContext(panel: panel)
        previewContextsByDisplayID[displayID] = context
        return context
    }

    private func closePreviewContext(for displayID: CGDirectDisplayID) {
        guard let context = previewContextsByDisplayID.removeValue(forKey: displayID) else {
            return
        }

        context.invalidate()
        context.panel.orderOut(nil)
        context.panel.close()
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

    private func updateContent(
        of panel: DisplayPanelWindow,
        displayID: CGDirectDisplayID,
        with apps: [RunningAppItem],
        launchableApplications: [LaunchableApplicationItem]
    ) {
        let content = AnyView(
            DisplayBottomBarView(
                apps: apps,
                launchableApplications: launchableApplications,
                onSwitch: barManager.activate(processID:),
                onOpenApplication: barManager.openApplication(bundleURL:),
                onAppHoverChanged: { [weak self] processID, frameInScreen in
                    self?.handleAppHoverChanged(
                        displayID: displayID,
                        processID: processID,
                        pillFrameInScreen: frameInScreen
                    )
                }
            )
        )

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
    }

    private func handleAppHoverChanged(
        displayID: CGDirectDisplayID,
        processID: pid_t?,
        pillFrameInScreen: CGRect?
    ) {
        let context = previewContext(for: displayID)

        guard let processID, let pillFrameInScreen else {
            context.hoverTarget = nil
            if !context.isPointerInsidePreview {
                schedulePreviewHide(for: context)
            }
            return
        }

        context.hoverTarget = HoverPreviewTarget(
            processID: processID,
            pillFrameInScreen: pillFrameInScreen
        )

        context.hideWorkItem?.cancel()
        context.hideWorkItem = nil

        if context.panel.isVisible {
            showPreview(for: displayID, context: context)
        } else {
            schedulePreviewShow(for: displayID, context: context)
        }
    }

    private func handlePreviewHoverChanged(
        displayID: CGDirectDisplayID,
        isHovering: Bool
    ) {
        guard let context = previewContextsByDisplayID[displayID] else {
            return
        }

        context.isPointerInsidePreview = isHovering

        if isHovering {
            context.hideWorkItem?.cancel()
            context.hideWorkItem = nil
            return
        }

        if context.hoverTarget == nil {
            schedulePreviewHide(for: context)
        }
    }

    private func schedulePreviewShow(
        for displayID: CGDirectDisplayID,
        context: DisplayPreviewContext
    ) {
        context.showWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak context] in
            guard let self, let context else {
                return
            }

            self.showPreview(for: displayID, context: context)
        }

        context.showWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + BarLayoutConstants.previewPanelShowDelay,
            execute: workItem
        )
    }

    private func showPreview(
        for displayID: CGDirectDisplayID,
        context: DisplayPreviewContext
    ) {
        context.showWorkItem = nil

        guard let hoverTarget = context.hoverTarget,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return
        }

        let previews = barManager.windowPreviews(
            for: hoverTarget.processID,
            on: displayID
        )

        let appName = appNamesByDisplayID[displayID]?[hoverTarget.processID]
            ?? NSRunningApplication(processIdentifier: hoverTarget.processID)?.localizedName
            ?? "Application"

        let desiredWidth = previewPanelWidth(forWindowCount: previews.count)
        let frame = previewFrame(
            around: hoverTarget.pillFrameInScreen,
            desiredWidth: desiredWidth,
            screenFrame: screen.frame
        )

        updatePreviewPanelContent(
            of: context.panel,
            displayID: displayID,
            appName: appName,
            previews: previews
        )

        if context.panel.frame != frame {
            context.panel.setFrame(frame, display: true, animate: context.panel.isVisible)
        }

        context.panel.orderFrontRegardless()
    }

    private func schedulePreviewHide(for context: DisplayPreviewContext) {
        context.showWorkItem?.cancel()
        context.showWorkItem = nil
        context.hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak context] in
            guard let context else {
                return
            }

            context.hideWorkItem = nil

            guard context.hoverTarget == nil,
                  !context.isPointerInsidePreview else {
                return
            }

            context.panel.orderOut(nil)
        }

        context.hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + BarLayoutConstants.previewPanelHideDelay,
            execute: workItem
        )
    }

    private func updatePreviewPanelContent(
        of panel: AppWindowPreviewPanelWindow,
        displayID: CGDirectDisplayID,
        appName: String,
        previews: [AppWindowPreviewItem]
    ) {
        let content = AnyView(
            AppWindowPreviewPanelView(
                appName: appName,
                previews: previews,
                onHoverChanged: { [weak self] isHovering in
                    self?.handlePreviewHoverChanged(
                        displayID: displayID,
                        isHovering: isHovering
                    )
                }
            )
        )

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
    }

    private func previewPanelWidth(forWindowCount windowCount: Int) -> CGFloat {
        guard windowCount > 0 else {
            return BarLayoutConstants.previewPanelFallbackWidth
        }

        let cardsWidth = CGFloat(windowCount) * BarLayoutConstants.previewCardWidth
        let spacing = CGFloat(max(0, windowCount - 1)) * BarLayoutConstants.previewCardSpacing
        return (BarLayoutConstants.previewPanelPadding * 2) + cardsWidth + spacing
    }

    private func previewFrame(
        around pillFrameInScreen: CGRect,
        desiredWidth: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let maxWidth = max(
            BarLayoutConstants.previewPanelFallbackWidth,
            screenFrame.width - (BarLayoutConstants.previewPanelHorizontalInset * 2)
        )
        let width = min(desiredWidth, maxWidth)
        let height = BarLayoutConstants.previewPanelHeight

        let minX = screenFrame.minX + BarLayoutConstants.previewPanelHorizontalInset
        let maxX = screenFrame.maxX - width - BarLayoutConstants.previewPanelHorizontalInset
        let preferredX = pillFrameInScreen.midX - (width / 2)
        let x = min(max(preferredX, minX), maxX)

        let minY = screenFrame.minY + BarLayoutConstants.previewPanelVerticalGap
        let maxY = screenFrame.maxY - height - BarLayoutConstants.previewPanelVerticalGap
        let preferredY = pillFrameInScreen.maxY + BarLayoutConstants.previewPanelVerticalGap
        let y = min(max(preferredY, minY), maxY)

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct HoverPreviewTarget {
    let processID: pid_t
    let pillFrameInScreen: CGRect
}

private final class DisplayPreviewContext {
    let panel: AppWindowPreviewPanelWindow
    var hoverTarget: HoverPreviewTarget?
    var isPointerInsidePreview = false
    var showWorkItem: DispatchWorkItem?
    var hideWorkItem: DispatchWorkItem?

    init(panel: AppWindowPreviewPanelWindow) {
        self.panel = panel
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        showWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hoverTarget = nil
        isPointerInsidePreview = false
    }
}

final class DisplayPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
