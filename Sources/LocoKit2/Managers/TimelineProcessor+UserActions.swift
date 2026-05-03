//
//  TimelineProcessor+UserActions.swift
//  LocoKit2
//
//  User-driven editing operations for the timeline. Exposes the bits of
//  Merge / disabled / bogus handling that hosting apps need to build an
//  edit UI without reaching into internal types.
//

import Foundation
import GRDB

@TimelineActor
extension TimelineProcessor {

    public enum MergeDirection: Sendable {
        case previous
        case next
    }

    /// Marks an item as bogus and hides it from the timeline.
    ///
    /// Sets every sample's `confirmedActivityType = .bogus` so the item is
    /// excluded from CoreML training, then sets `disabled = 1` on the base
    /// so timeline queries (which filter `disabled = 0`) skip it. The data
    /// stays in the DB for forensic recovery.
    public static func markBogus(itemId: String) async throws {
        guard var item = try await TimelineItem.fetchItem(itemId: itemId, includeSamples: true) else {
            return
        }

        try await Database.pool.write { [item] db in
            if let samples = item.samples {
                for var sample in samples where sample.confirmedActivityType != .bogus {
                    try sample.updateChanges(db) {
                        $0.confirmedActivityType = .bogus
                    }
                }
            }
            var base = item.base
            try base.updateChanges(db) {
                $0.disabled = true
            }
        }

        // Clear chain links so neighbours can heal across this item next pass.
        try? await Database.pool.write { db in
            try db.execute(
                sql: """
                    UPDATE TimelineItemBase
                       SET previousItemId = NULL, nextItemId = NULL
                     WHERE id = ?
                    """,
                arguments: [itemId]
            )
        }

        // Force the now-orphaned neighbours to re-heal across the bogus item.
        await item.fetchSamples(forceFetch: false)
    }

    /// Merges an item with a chain-adjacent neighbour. The focused item is the
    /// `deadman` (it disappears); the neighbour becomes the `keeper`. Returns
    /// the merge result so callers can refresh state or detect the survivor.
    @discardableResult
    public static func mergeWithNeighbor(
        itemId: String,
        direction: MergeDirection
    ) async throws -> MergeResult? {
        guard let list = await TimelineLinkedList(fromItemId: itemId) else {
            return nil
        }

        var focused: TimelineItem?
        for await item in list {
            if item.id == itemId { focused = item; break }
        }
        guard let focused else { return nil }

        let neighbour: TimelineItem?
        switch direction {
        case .previous: neighbour = await focused.previousItem(in: list)
        case .next:     neighbour = await focused.nextItem(in: list)
        }
        guard let neighbour else { return nil }

        let merge = await Merge(keeper: neighbour, deadman: focused, in: list)
        return await merge.doIt()
    }
}
