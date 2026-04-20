import AppKit
import ApplicationServices
import Foundation
import OSLog

protocol DockNotificationBadgeProviding: AnyObject {
    var onBadgeStateChanged: (() -> Void)? { get set }

    func startObserving()
    func stopObserving()
    func fetchBadgeCountByProcessID() -> [pid_t: Int]
}

final class DockNotificationBadgeProvider: DockNotificationBadgeProviding {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openboringbar.app",
        category: "DockNotificationBadgeProvider"
    )

    private static let dockBundleIdentifier = "com.apple.dock"
    private static let applicationDockItemSubrole = kAXApplicationDockItemSubrole as String
    // Dock sometimes emits this undocumented notification in practice.
    private static let undocumentedChildrenChangedNotification = "AXChildrenChanged"

    private static let dockElementNotifications = [
        AXNotificationName.valueChanged,
        AXNotificationName.titleChanged,
        AXNotificationName.layoutChanged,
        AXNotificationName.selectedChildrenChanged,
        AXNotificationName.created,
        undocumentedChildrenChangedNotification
    ]

    private static let dockItemNotifications = [
        AXNotificationName.valueChanged,
        AXNotificationName.titleChanged,
        AXNotificationName.layoutChanged,
        AXNotificationName.created,
        AXNotificationName.uiElementDestroyed,
        undocumentedChildrenChangedNotification
    ]

    private static let observerCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else {
            return
        }

        let provider = Unmanaged<DockNotificationBadgeProvider>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        provider.handleAccessibilityNotification(
            element: element,
            notification: notification as String
        )
    }

    var onBadgeStateChanged: (() -> Void)?

    private var dockObserver: AXObserver?
    private var dockElement: AXUIElement?
    private var observedDockItemElements: [AXUIElement] = []
    private var dockProcessID: pid_t?

    private var latestBadgeSnapshot: [pid_t: Int] = [:]

    private var watchdogWorkItem: DispatchWorkItem?
    private var watchdogCurrentInterval: TimeInterval
    private var watchdogActiveUntil: Date?

    private let watchdogMinimumInterval: TimeInterval = 2
    private let watchdogMaximumInterval: TimeInterval = 5
    private let watchdogBackoffStep: TimeInterval = 1
    private let watchdogActivityWindow: TimeInterval = 30

    init() {
        watchdogCurrentInterval = watchdogMinimumInterval
    }

    deinit {
        stopObserving()
    }

    func startObserving() {
        guard AXIsProcessTrusted(),
              let dockApplication = NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.dockBundleIdentifier
              ).first else {
            return
        }

        let processID = dockApplication.processIdentifier
        if processID == dockProcessID,
           dockObserver != nil,
           dockElement != nil {
            return
        }

        stopObserving()

        var observer: AXObserver?
        let createResult = AXObserverCreate(
            processID,
            Self.observerCallback,
            &observer
        )

        guard createResult == .success,
              let observer else {
            Self.logger.debug(
                "AXObserverCreate failed for Dock. result=\(createResult.rawValue, privacy: .public)"
            )
            return
        }

        let dockElement = AXUIElementCreateApplication(processID)

        self.dockObserver = observer
        self.dockElement = dockElement
        self.dockProcessID = processID

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        registerNotifications(
            Self.dockElementNotifications,
            observer: observer,
            element: dockElement
        )

        reloadDockItemObservers()

        let snapshot = collectBadgeCountByProcessID()
        latestBadgeSnapshot = snapshot
        updateWatchdogState(afterReading: snapshot, extendActivityWindow: !snapshot.isEmpty)
    }

    func stopObserving() {
        stopWatchdog(resetActivityWindow: true)
        latestBadgeSnapshot = [:]

        guard let observer = dockObserver else {
            dockElement = nil
            observedDockItemElements.removeAll()
            dockProcessID = nil
            return
        }

        unregisterObservedDockItemNotifications(observer: observer)

        if let dockElement {
            unregisterNotifications(
                Self.dockElementNotifications,
                observer: observer,
                element: dockElement
            )
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        dockObserver = nil
        dockElement = nil
        observedDockItemElements.removeAll()
        dockProcessID = nil
    }

    func fetchBadgeCountByProcessID() -> [pid_t: Int] {
        ensureObservationIfNeeded()

        let snapshot = collectBadgeCountByProcessID()
        latestBadgeSnapshot = snapshot
        updateWatchdogState(afterReading: snapshot, extendActivityWindow: !snapshot.isEmpty)
        return snapshot
    }

    private func ensureObservationIfNeeded() {
        if dockObserver == nil || dockElement == nil {
            startObserving()
        }
    }

    private func handleAccessibilityNotification(
        element: AXUIElement,
        notification: String
    ) {
        if shouldReloadDockItemObservers(element: element, notification: notification) {
            reloadDockItemObservers()
        }

        recordWatchdogActivity()
        onBadgeStateChanged?()
    }

    private func shouldReloadDockItemObservers(
        element: AXUIElement,
        notification: String
    ) -> Bool {
        if notification == AXNotificationName.uiElementDestroyed,
           observedDockItemElements.contains(where: { CFEqual($0, element) }) {
            return true
        }

        guard let dockElement,
              CFEqual(element, dockElement) else {
            return false
        }

        switch notification {
        case AXNotificationName.selectedChildrenChanged,
             AXNotificationName.layoutChanged,
             AXNotificationName.created,
             Self.undocumentedChildrenChangedNotification:
            return true

        default:
            return false
        }
    }

    private func reloadDockItemObservers() {
        guard let observer = dockObserver,
              let dockElement else {
            return
        }

        unregisterObservedDockItemNotifications(observer: observer)

        let dockItems = applicationDockItems(startingAt: dockElement)
        for dockItem in dockItems {
            registerNotifications(
                Self.dockItemNotifications,
                observer: observer,
                element: dockItem
            )
        }

        observedDockItemElements = dockItems
    }

    private func unregisterObservedDockItemNotifications(observer: AXObserver) {
        for dockItem in observedDockItemElements {
            unregisterNotifications(
                Self.dockItemNotifications,
                observer: observer,
                element: dockItem
            )
        }

        observedDockItemElements.removeAll()
    }

    private func registerNotifications(
        _ notifications: [String],
        observer: AXObserver,
        element: AXUIElement
    ) {
        for notification in notifications {
            let result = AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )

            if result == .success || result == .notificationAlreadyRegistered {
                continue
            }

            Self.logger.debug(
                "AXObserverAddNotification failed. notification=\(notification, privacy: .public) result=\(result.rawValue, privacy: .public)"
            )
        }
    }

    private func unregisterNotifications(
        _ notifications: [String],
        observer: AXObserver,
        element: AXUIElement
    ) {
        for notification in notifications {
            AXObserverRemoveNotification(
                observer,
                element,
                notification as CFString
            )
        }
    }

    private func collectBadgeCountByProcessID() -> [pid_t: Int] {
        guard AXIsProcessTrusted(),
              let dockElement else {
            return [:]
        }

        let dockItems = applicationDockItems(startingAt: dockElement)
        guard !dockItems.isEmpty else {
            return [:]
        }

        var badgeCountByBundleIdentifier: [String: Int] = [:]
        for dockItem in dockItems {
            guard let bundleIdentifier = bundleIdentifier(from: dockItem),
                  let badgeCount = badgeCount(from: dockItem),
                  badgeCount > 0 else {
                continue
            }

            let existingCount = badgeCountByBundleIdentifier[bundleIdentifier] ?? 0
            badgeCountByBundleIdentifier[bundleIdentifier] = max(existingCount, badgeCount)
        }

        guard !badgeCountByBundleIdentifier.isEmpty else {
            return [:]
        }

        var badgeCountByProcessID: [pid_t: Int] = [:]
        for application in NSWorkspace.shared.runningApplications {
            guard !application.isTerminated,
                  application.activationPolicy == .regular,
                  let bundleIdentifier = application.bundleIdentifier,
                  let badgeCount = badgeCountByBundleIdentifier[bundleIdentifier] else {
                continue
            }

            badgeCountByProcessID[application.processIdentifier] = badgeCount
        }

        return badgeCountByProcessID
    }

    private func applicationDockItems(startingAt element: AXUIElement) -> [AXUIElement] {
        collectApplicationDockItems(from: element, depth: 0)
    }

    private func collectApplicationDockItems(
        from element: AXUIElement,
        depth: Int
    ) -> [AXUIElement] {
        guard depth <= 6 else {
            return []
        }

        var items: [AXUIElement] = []

        if AXElementInspector.stringAttributeValue(of: AXAttributeName.subrole, from: element) == Self.applicationDockItemSubrole {
            items.append(element)
        }

        guard let children = AXElementInspector.children(from: element),
              !children.isEmpty else {
            return items
        }

        for child in children {
            items.append(contentsOf: collectApplicationDockItems(from: child, depth: depth + 1))
        }

        return items
    }

    private func bundleIdentifier(from dockItem: AXUIElement) -> String? {
        guard let url = AXElementInspector.urlAttributeValue(
            of: AXAttributeName.url,
            from: dockItem
        ) else {
            return nil
        }

        return Bundle(url: url)?.bundleIdentifier
    }

    private func badgeCount(from dockItem: AXUIElement) -> Int? {
        if let statusLabel = AXElementInspector.stringAttributeValue(
            of: AXAttributeName.statusLabel,
            from: dockItem
        ),
           let parsed = parseBadgeCount(from: statusLabel) {
            return parsed
        }

        for child in collectDescendants(from: dockItem, depth: 0, maxDepth: 2) {
            guard let statusLabel = AXElementInspector.stringAttributeValue(
                of: AXAttributeName.statusLabel,
                from: child
            ),
            let parsed = parseBadgeCount(from: statusLabel) else {
                continue
            }

            return parsed
        }

        return nil
    }

    private func collectDescendants(
        from element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> [AXUIElement] {
        guard depth < maxDepth,
              let children = AXElementInspector.children(from: element),
              !children.isEmpty else {
            return []
        }

        var descendants: [AXUIElement] = children
        for child in children {
            descendants.append(
                contentsOf: collectDescendants(
                    from: child,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
            )
        }

        return descendants
    }

    private func parseBadgeCount(from label: String) -> Int? {
        let digitScalars = label.unicodeScalars.filter {
            CharacterSet.decimalDigits.contains($0)
        }

        guard !digitScalars.isEmpty,
              let value = Int(String(String.UnicodeScalarView(digitScalars))),
              value > 0 else {
            return nil
        }

        return value
    }

    private func recordWatchdogActivity() {
        watchdogActiveUntil = Date().addingTimeInterval(watchdogActivityWindow)
        watchdogCurrentInterval = watchdogMinimumInterval
        scheduleWatchdogTickIfNeeded()
    }

    private func updateWatchdogState(
        afterReading snapshot: [pid_t: Int],
        extendActivityWindow: Bool
    ) {
        if extendActivityWindow {
            watchdogActiveUntil = Date().addingTimeInterval(watchdogActivityWindow)
        }

        guard shouldKeepWatchdogRunning(with: snapshot) else {
            stopWatchdog(resetActivityWindow: false)
            return
        }

        scheduleWatchdogTickIfNeeded()
    }

    private func shouldKeepWatchdogRunning(with snapshot: [pid_t: Int]) -> Bool {
        if !snapshot.isEmpty {
            return true
        }

        guard let watchdogActiveUntil else {
            return false
        }

        return Date() < watchdogActiveUntil
    }

    private func scheduleWatchdogTickIfNeeded() {
        guard watchdogWorkItem == nil else {
            return
        }

        let interval = min(
            max(watchdogCurrentInterval, watchdogMinimumInterval),
            watchdogMaximumInterval
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.watchdogWorkItem = nil
            self.runWatchdogTick()
        }

        watchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func runWatchdogTick() {
        let snapshot = collectBadgeCountByProcessID()
        let didChange = snapshot != latestBadgeSnapshot
        latestBadgeSnapshot = snapshot

        if didChange {
            onBadgeStateChanged?()
            watchdogCurrentInterval = watchdogMinimumInterval
            watchdogActiveUntil = Date().addingTimeInterval(watchdogActivityWindow)
        } else {
            watchdogCurrentInterval = min(
                watchdogCurrentInterval + watchdogBackoffStep,
                watchdogMaximumInterval
            )
        }

        if !snapshot.isEmpty {
            watchdogActiveUntil = Date().addingTimeInterval(watchdogActivityWindow)
        }

        guard shouldKeepWatchdogRunning(with: snapshot) else {
            stopWatchdog(resetActivityWindow: false)
            return
        }

        scheduleWatchdogTickIfNeeded()
    }

    private func stopWatchdog(resetActivityWindow: Bool) {
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        watchdogCurrentInterval = watchdogMinimumInterval

        if resetActivityWindow {
            watchdogActiveUntil = nil
        }
    }
}
