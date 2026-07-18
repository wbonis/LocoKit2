//
//  TimelineProcessor+OrphanAdoption.swift
//  LocoKit2
//
//  Created by Claude on 2026-03-25
//

import Foundation
import GRDB

@TimelineActor
extension TimelineProcessor {

    /// Adopt orphaned samples (timelineItemId = NULL) into existing timeline items
    /// whose date range spans the sample's date, then create individual items for
    /// any remaining orphans that don't fit an existing item.
    public static func adoptOrphanedSamples(dryRun: Bool = false) async throws {
        // quick check: any non-disabled orphans to process?
        let orphanCount = try await Database.pool.read { db in
            try LocomotionSample
                .filter(LocomotionSample.Columns.timelineItemId == nil)
                .filter(LocomotionSample.Columns.disabled == false)
                .fetchCount(db)
        }
        guard orphanCount > 0 else { return }

        Log.info("Found \(orphanCount) orphaned samples (excluding disabled)", subsystem: .timeline)

        // count how many can be adopted into existing items (type-matched)
        let adoptableCount = try await Database.pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM LocomotionSample
                WHERE timelineItemId IS NULL
                AND disabled = 0
                AND EXISTS (
                    SELECT 1 FROM TimelineItemBase
                    WHERE deleted = 0
                    AND disabled = 0
                    AND startDate <= LocomotionSample.date
                    AND endDate >= LocomotionSample.date
                    AND isVisit = CASE LocomotionSample.movingState
                        WHEN 0 THEN 1
                        ELSE 0
                    END
                )
                """) ?? 0
        }
        let unadoptableCount = orphanCount - adoptableCount
        Log.info("Orphan breakdown: \(adoptableCount) adoptable, \(unadoptableCount) need new items", subsystem: .timeline)

        if dryRun {
            Log.info("Dry run — no changes made", subsystem: .timeline)
            return
        }

        // Step 1: SQL-level adoption into existing items.
        // mapmyway: only adopt into an item whose isVisit matches the sample's
        // movingState. Blind date-range adoption poured stationary orphans into
        // a spanning Trip (18 Jul eternal-trip: 117 orphans → mega-trip, visit
        // never formed, canStartSleeping stuck false).
        if adoptableCount > 0 {
            let adopted = try await Database.pool.write { db -> Int in
                try db.execute(sql: """
                    UPDATE LocomotionSample
                    SET timelineItemId = (
                        SELECT id FROM TimelineItemBase
                        WHERE deleted = 0
                        AND disabled = LocomotionSample.disabled
                        AND startDate <= LocomotionSample.date
                        AND endDate >= LocomotionSample.date
                        AND isVisit = CASE LocomotionSample.movingState
                            WHEN 0 THEN 1
                            ELSE 0
                        END
                        LIMIT 1
                    )
                    WHERE timelineItemId IS NULL
                    AND EXISTS (
                        SELECT 1 FROM TimelineItemBase
                        WHERE deleted = 0
                        AND disabled = LocomotionSample.disabled
                        AND startDate <= LocomotionSample.date
                        AND endDate >= LocomotionSample.date
                        AND isVisit = CASE LocomotionSample.movingState
                            WHEN 0 THEN 1
                            ELSE 0
                        END
                    )
                    """)
                return db.changesCount
            }
            Log.info("Adopted \(adopted) orphaned samples into existing items", subsystem: .timeline)
        }

        // Step 2: Create individual items for remaining non-disabled orphans
        let remainingOrphans = try await Database.pool.read { db in
            try LocomotionSample
                .filter(LocomotionSample.Columns.timelineItemId == nil)
                .filter(LocomotionSample.Columns.disabled == false)
                .order(LocomotionSample.Columns.date)
                .fetchAll(db)
        }

        if !remainingOrphans.isEmpty {
            Log.info("Creating items for \(remainingOrphans.count) remaining orphaned samples", subsystem: .timeline)

            for sample in remainingOrphans {
                let isVisit = sample.movingState == .stationary
                try await Database.pool.write { db in
                    _ = try TimelineItem.createItem(from: [sample], isVisit: isVisit, disabled: sample.disabled, db: db)
                }
            }
        }

        let created = remainingOrphans.count
        Log.info("Orphan adoption complete: \(adoptableCount) adopted, \(created) new items created", subsystem: .timeline)
    }
}
