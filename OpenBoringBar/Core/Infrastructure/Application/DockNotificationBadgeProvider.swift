import AppKit
import ApplicationServices
import Foundation

protocol DockNotificationBadgeProviding: AnyObject {
    var onBadgeStateChanged: (() -> Void)? { get set }

    func startObserving()
    func stopObserving()
    func fetchBadgeCountByProcessID() -> [pid_t: Int]
}

final class DockNotificationBadgeProvider: DockNotificationBadgeProviding {
    private static let dockBundleIdentifier = "com.apple.dock"
    private static let applicationDockItemSubrole = "AXApplicationDockItem"

    private static let dockElementNotifications = [
        AXNotificationName.childrenChanged,
        AXNotificationName.valueChanged,
        AXNotificationName.titleChanged
    ]

    private static let dockItemNotifications = [
        AXNotificationName.valueChanged,
        AXNotificationName.titleChanged,
        AXNotificationName.childrenChanged,
        AXNotificationName.uiElementDestroyed
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
    }

    func stopObserving() {
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

    private func ensureObservationIfNeeded() {
        if dockObserver == nil || dockElement == nil {
            startObserving()
        }
    }

    private func handleAccessibilityNotification(
        element: AXUIElement,
        notification: String
    ) {
        if notification == AXNotificationName.childrenChanged,
           let dockElement,
           CFEqual(element, dockElement) {
            reloadDockItemObservers()
        }

        if notification == AXNotificationName.uiElementDestroyed,
           observedDockItemElements.contains(where: { CFEqual($0, element) }) {
            reloadDockItemObservers()
        }

        onBadgeStateChanged?()
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
}
