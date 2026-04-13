import AppKit
import Combine
import SwiftUI

@main
struct OpenBoringBarApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @State private var barManager: BarManager?
    @State private var displayPanelController: DisplayPanelController?
    @State private var activeWindowBottomGuardManager: ActiveWindowBottomGuardManager?
    private let setupMinHeight: CGFloat = 760
    private let runtimeMinHeight: CGFloat = 540

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.shouldPresentSetup {
                    PermissionSetupView()
                        .environmentObject(permissionManager)
                } else if let barManager {
                    PanelBootstrapView()
                        .task {
                            startPanelsIfNeeded(with: barManager)
                        }
                } else {
                    ProgressView("Starting boringBar...")
                        .task {
                            startBarManagerIfNeeded()
                        }
                }
            }
            .onChange(of: permissionManager.shouldPresentSetup) { _, shouldPresent in
                if shouldPresent {
                    stopPanelsAndReset()
                } else {
                    startBarManagerIfNeeded()
                }
            }
            .frame(minWidth: 920, minHeight: permissionManager.shouldPresentSetup ? setupMinHeight : runtimeMinHeight)
        }
    }

    private func startBarManagerIfNeeded() {
        if barManager == nil {
            barManager = BarManager()
        }
    }

    private func startPanelsIfNeeded(with manager: BarManager) {
        if displayPanelController == nil {
            let controller = DisplayPanelController(barManager: manager)
            controller.start()
            displayPanelController = controller

            closeHostWindowsKeepingPanels()
        }

        startActiveWindowBottomGuardIfNeeded()
    }

    private func stopPanelsAndReset() {
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
        if activeWindowBottomGuardManager == nil {
            activeWindowBottomGuardManager = ActiveWindowBottomGuardManager()
        }
    }
}

private struct PanelBootstrapView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}

private final class DisplayPanelController {
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

private final class DisplayPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DisplayBottomBarView: View {
    let apps: [RunningAppItem]
    let onSwitch: (pid_t) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )

            if apps.isEmpty {
                Text("该显示器暂无可见窗口")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(apps, id: \.self) { app in
                            DisplayBarAppPill(
                                app: app,
                                onSwitch: onSwitch
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DisplayBarAppPill: View {
    private static let appNameMaxWidth: CGFloat = 140

    @Environment(\.colorScheme) private var colorScheme

    let app: RunningAppItem
    let onSwitch: (pid_t) -> Void

    var body: some View {
        Button(action: { onSwitch(app.processID) }) {
            HStack(spacing: 8) {
                DisplayBarAppIcon(processID: app.processID)

                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.appNameMaxWidth, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var titleColor: Color {
        if app.isFrontmost {
            return colorScheme == .dark ? .white : Color.black.opacity(0.9)
        }

        return .primary
    }

    private var backgroundColor: Color {
        if app.isFrontmost {
            return colorScheme == .dark
                ? Color.white.opacity(0.24)
                : Color.white.opacity(0.72)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.white.opacity(0.34)
    }

    private var borderColor: Color {
        if app.isFrontmost {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.60 : 0.42)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.08)
    }
}

private struct DisplayBarAppIcon: View {
    let processID: pid_t

    private var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: processID)?.icon
    }

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
