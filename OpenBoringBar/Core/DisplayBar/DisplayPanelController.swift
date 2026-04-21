import AppKit
import Combine
import SwiftUI

final class DisplayPanelController {
    private static let autoCollapseDefaultsKey = "OpenBoringBar.autoCollapseEnabled"

    private let barManager: BarManager
    private let eventBus: AppEventBus
    private var panelStateCancellable: AnyCancellable?
    private var windowsByDisplayID: [CGDirectDisplayID: DisplayPanelWindow] = [:]
    private var previewContextsByDisplayID: [CGDirectDisplayID: DisplayPreviewContext] = [:]
    private var panelHeightByDisplayID: [CGDirectDisplayID: CGFloat] = [:]
    private var isBarHoveringByDisplayID: [CGDirectDisplayID: Bool] = [:]
    private var isCollapsedByDisplayID: [CGDirectDisplayID: Bool] = [:]
    private var collapseHideWorkItemByDisplayID: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var pointerPollTimer: Timer?
    private var isAutoCollapseEnabled: Bool

    init(barManager: BarManager, eventBus: AppEventBus) {
        self.barManager = barManager
        self.eventBus = eventBus
        self.isAutoCollapseEnabled = UserDefaults.standard.bool(
            forKey: Self.autoCollapseDefaultsKey
        )
    }

    deinit {
        stopPointerPolling()
        for displayID in Array(collapseHideWorkItemByDisplayID.keys) {
            cancelCollapseHideWorkItem(for: displayID)
        }
    }

    func start() {
        guard panelStateCancellable == nil else {
            return
        }

        if isAutoCollapseEnabled {
            startPointerPollingIfNeeded()
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
        stopPointerPolling()

        for displayID in windowsByDisplayID.keys {
            cancelCollapseHideWorkItem(for: displayID)
            postDisplayHeight(0, for: displayID, force: true)
        }

        for panel in windowsByDisplayID.values {
            panel.orderOut(nil)
            panel.close()
        }
        windowsByDisplayID.removeAll()
        panelHeightByDisplayID.removeAll()
        isBarHoveringByDisplayID.removeAll()
        isCollapsedByDisplayID.removeAll()

        for displayID in Array(previewContextsByDisplayID.keys) {
            closePreviewContext(for: displayID)
        }
    }

    private func syncPanels(
        with states: [DisplayState],
        launchableApplications: [LaunchableApplicationItem]
    ) {
        let activeDisplayIDs = Set(states.map(\.id))

        for (displayID, panel) in Array(windowsByDisplayID) where !activeDisplayIDs.contains(displayID) {
            cancelCollapseHideWorkItem(for: displayID)
            panel.orderOut(nil)
            panel.close()
            windowsByDisplayID.removeValue(forKey: displayID)
            isBarHoveringByDisplayID.removeValue(forKey: displayID)
            isCollapsedByDisplayID.removeValue(forKey: displayID)
            postDisplayHeight(0, for: displayID, force: true)
            panelHeightByDisplayID.removeValue(forKey: displayID)
        }

        for displayID in Array(previewContextsByDisplayID.keys) where !activeDisplayIDs.contains(displayID) {
            closePreviewContext(for: displayID)
        }

        for state in states {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == state.id }) else {
                continue
            }

            let isNewPanel = windowsByDisplayID[state.id] == nil
            let panel = panelForDisplay(state.id)
            updateContent(
                of: panel,
                displayID: state.id,
                with: state.apps,
                launchableApplications: launchableApplications
            )
            updatePanelPresentation(
                of: panel,
                displayID: state.id,
                in: screen,
                animated: !isNewPanel
            )

            if let context = previewContextsByDisplayID[state.id],
               let hoveredPID = context.hoverTarget?.processID,
               !state.apps.contains(where: { $0.processID == hoveredPID }) {
                context.hoverTarget = nil
                if !context.isPointerInsidePreview {
                    schedulePreviewHide(for: state.id, context: context)
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
            styleMask: [.borderless],
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
            .fullScreenAuxiliary
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
        refreshAutoCollapsePresentation(animated: true)
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
                isAutoCollapseEnabled: isAutoCollapseEnabled,
                onSwitch: barManager.activate(processID:),
                onOpenApplication: barManager.openApplication(bundleURL:),
                onAppHoverChanged: { [weak self] processID, frameInScreen in
                    self?.handleAppHoverChanged(
                        displayID: displayID,
                        processID: processID,
                        pillFrameInScreen: frameInScreen
                    )
                },
                onBarHoverChanged: { [weak self] isHovering in
                    self?.handleBarHoverChanged(
                        displayID: displayID,
                        isHovering: isHovering
                    )
                },
                onAutoCollapseToggled: { [weak self] isEnabled in
                    self?.handleAutoCollapseToggled(isEnabled: isEnabled)
                },
                onRequestQuit: handleQuitRequested
            )
        )

        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
    }

    private func handleBarHoverChanged(
        displayID: CGDirectDisplayID,
        isHovering: Bool
    ) {
        isBarHoveringByDisplayID[displayID] = isHovering
        guard isAutoCollapseEnabled else {
            return
        }

        refreshAutoCollapsePresentation(animated: true)
    }

    private func handleAutoCollapseToggled(isEnabled: Bool) {
        guard isAutoCollapseEnabled != isEnabled else {
            return
        }

        isAutoCollapseEnabled = isEnabled
        UserDefaults.standard.set(
            isEnabled,
            forKey: Self.autoCollapseDefaultsKey
        )
        if isEnabled {
            startPointerPollingIfNeeded()
        } else {
            stopPointerPolling()
        }

        syncPanels(
            with: barManager.displayStates,
            launchableApplications: barManager.launchableApplications
        )
        refreshAutoCollapsePresentation(animated: true)
    }

    private func startPointerPollingIfNeeded() {
        guard pointerPollTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: BarLayoutConstants.autoCollapsePointerPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refreshAutoCollapsePresentation(animated: true)
        }
        pointerPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPointerPolling() {
        pointerPollTimer?.invalidate()
        pointerPollTimer = nil
    }

    private func refreshAutoCollapsePresentation(animated: Bool) {
        guard isAutoCollapseEnabled, !windowsByDisplayID.isEmpty else {
            return
        }

        for (displayID, panel) in windowsByDisplayID {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                continue
            }

            updatePanelPresentation(
                of: panel,
                displayID: displayID,
                in: screen,
                animated: animated
            )
        }
    }

    private func updatePanelPresentation(
        of panel: DisplayPanelWindow,
        displayID: CGDirectDisplayID,
        in screen: NSScreen,
        animated: Bool
    ) {
        let shouldCollapse = shouldCollapsePanel(displayID: displayID, in: screen)
        let wasCollapsed = isCollapsedByDisplayID[displayID] ?? false
        isCollapsedByDisplayID[displayID] = shouldCollapse

        let expandedFrame = expandedFrame(in: screen)
        let collapsedFrame = collapsedFrame(in: screen)

        if shouldCollapse {
            panel.setFrame(collapsedFrame, display: true, animate: animated && !wasCollapsed)
            postDisplayHeight(0, for: displayID)

            let hideAction = { [weak self, weak panel] in
                guard let self, let panel else {
                    return
                }
                self.collapseHideWorkItemByDisplayID[displayID] = nil
                guard self.isCollapsedByDisplayID[displayID] == true else {
                    return
                }
                panel.orderOut(nil)
            }

            cancelCollapseHideWorkItem(for: displayID)
            if animated && !wasCollapsed {
                let workItem = DispatchWorkItem(block: hideAction)
                collapseHideWorkItemByDisplayID[displayID] = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + BarLayoutConstants.panelCollapseAnimationDuration,
                    execute: workItem
                )
            } else {
                hideAction()
            }
            return
        }

        cancelCollapseHideWorkItem(for: displayID)
        if !panel.isVisible {
            panel.setFrame(collapsedFrame, display: true)
        }
        panel.orderFrontRegardless()
        if panel.frame != expandedFrame {
            panel.setFrame(expandedFrame, display: true, animate: animated)
        }
        postDisplayHeight(expandedFrame.height, for: displayID)
    }

    private func shouldCollapsePanel(
        displayID: CGDirectDisplayID,
        in screen: NSScreen
    ) -> Bool {
        guard isAutoCollapseEnabled else {
            return false
        }

        if isBarHoveringByDisplayID[displayID] == true {
            return false
        }

        if shouldKeepExpandedForPreview(displayID: displayID) {
            return false
        }

        return !isPointerNearBottom(of: screen)
    }

    private func shouldKeepExpandedForPreview(displayID: CGDirectDisplayID) -> Bool {
        guard let context = previewContextsByDisplayID[displayID] else {
            return false
        }

        return context.panel.isVisible
            || context.hoverTarget != nil
            || context.isPointerInsidePreview
    }

    private func isPointerNearBottom(of screen: NSScreen) -> Bool {
        let pointerLocation = NSEvent.mouseLocation
        guard screen.frame.contains(pointerLocation) else {
            return false
        }

        return pointerLocation.y <=
            (screen.frame.minY + BarLayoutConstants.autoCollapseBottomRevealHotZoneHeight)
    }

    private func expandedFrame(in screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: BarLayoutConstants.panelHeight
        )
    }

    private func collapsedFrame(in screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: 0
        )
    }

    private func cancelCollapseHideWorkItem(for displayID: CGDirectDisplayID) {
        collapseHideWorkItemByDisplayID[displayID]?.cancel()
        collapseHideWorkItemByDisplayID[displayID] = nil
    }

    private func postDisplayHeight(
        _ height: CGFloat,
        for displayID: CGDirectDisplayID,
        force: Bool = false
    ) {
        let normalizedHeight = max(0, height)

        if !force,
           let previousHeight = panelHeightByDisplayID[displayID],
           abs(previousHeight - normalizedHeight) < 0.5 {
            return
        }

        panelHeightByDisplayID[displayID] = normalizedHeight
        eventBus.post(
            .barDisplayHeightChanged(
                displayID: displayID,
                height: normalizedHeight
            )
        )
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
                schedulePreviewHide(for: displayID, context: context)
            }
            refreshAutoCollapsePresentation(animated: true)
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
        refreshAutoCollapsePresentation(animated: true)
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
            refreshAutoCollapsePresentation(animated: true)
            return
        }

        if context.hoverTarget == nil {
            schedulePreviewHide(for: displayID, context: context)
        }
        refreshAutoCollapsePresentation(animated: true)
    }

    private func handlePreviewWindowSelection(
        displayID: CGDirectDisplayID,
        processID: pid_t,
        windowID: CGWindowID
    ) {
        guard previewContextsByDisplayID[displayID] != nil else {
            return
        }

        barManager.activateWindow(
            processID: processID,
            windowID: windowID
        )
    }

    private func handleQuitRequested() {
        NSApp.terminate(nil)
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

        let appName = NSRunningApplication(processIdentifier: hoverTarget.processID)?.localizedName
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
            processID: hoverTarget.processID,
            appName: appName,
            previews: previews
        )

        if context.panel.frame != frame {
            context.panel.setFrame(frame, display: true, animate: context.panel.isVisible)
        }

        context.panel.orderFrontRegardless()
        refreshAutoCollapsePresentation(animated: true)
    }

    private func schedulePreviewHide(
        for displayID: CGDirectDisplayID,
        context: DisplayPreviewContext
    ) {
        context.showWorkItem?.cancel()
        context.showWorkItem = nil
        context.hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak context] in
            guard let self, let context else {
                return
            }

            context.hideWorkItem = nil

            guard context.hoverTarget == nil,
                  !context.isPointerInsidePreview else {
                return
            }

            context.panel.orderOut(nil)
            self.refreshAutoCollapsePresentation(animated: true)
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
        processID: pid_t,
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
                },
                onSelectWindow: { [weak self] windowID in
                    self?.handlePreviewWindowSelection(
                        displayID: displayID,
                        processID: processID,
                        windowID: windowID
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
