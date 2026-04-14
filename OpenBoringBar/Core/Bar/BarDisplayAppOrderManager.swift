import ApplicationServices

/// Keeps each display's app order stable after startup so UI updates only perform minimal movement.
final class BarDisplayAppOrderManager {
    private var orderByDisplay: [CGDirectDisplayID: [pid_t]] = [:]

    func syncActiveDisplays(_ activeDisplayIDs: Set<CGDirectDisplayID>) {
        orderByDisplay = orderByDisplay.filter { activeDisplayIDs.contains($0.key) }
    }

    func applyStableOrder(
        for displayID: CGDirectDisplayID,
        snapshots: [BarAppSnapshot]
    ) -> [BarAppSnapshot] {
        guard !snapshots.isEmpty else {
            return []
        }

        let visibleByPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.processID, $0) })
        let visiblePIDs = snapshots.map(\.processID)

        if orderByDisplay[displayID] == nil {
            orderByDisplay[displayID] = visiblePIDs
            return snapshots
        }

        var storedOrder = orderByDisplay[displayID] ?? []
        let visiblePIDSet = Set(visiblePIDs)
        var orderedVisiblePIDs = storedOrder.filter(visiblePIDSet.contains)

        let storedPIDSet = Set(storedOrder)
        let newPIDs = visiblePIDs.filter { !storedPIDSet.contains($0) }
        orderedVisiblePIDs.append(contentsOf: newPIDs)

        if !newPIDs.isEmpty {
            storedOrder.append(contentsOf: newPIDs)
            orderByDisplay[displayID] = storedOrder
        }

        return orderedVisiblePIDs.compactMap { visibleByPID[$0] }
    }
}
