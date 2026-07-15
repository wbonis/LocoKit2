//
//  SampleWriteStats.swift
//  LocoKit2
//
//  Created by Wim Bonis on 2026-07-15.
//

import Foundation
import Synchronization

/// Commit-rate telemetry for the sample recording path.
///
/// Counts sample inserts (one WAL commit each), inserts that carried a
/// classification (classify-at-record, see
/// `TimelineRecorder.setClassifiesSamplesOnRecord(_:)`), and post-insert
/// classification re-saves (the second write per sample this telemetry exists
/// to measure away). A summary is logged every `logInterval` inserts so field
/// log pulls can compare write rates before/after enabling classify-at-record.
///
/// The consuming app can also read `snapshot()` for debug UI.
public enum SampleWriteStats {

    public struct Snapshot: Sendable {
        public let inserts: Int
        public let preClassifiedInserts: Int
        public let reSavedSamples: Int
    }

    private struct State {
        var inserts = 0
        var preClassifiedInserts = 0
        var reSavedSamples = 0
    }

    private static let logInterval = 100

    private static let state = Mutex(State())

    static func recordInsert(preClassified: Bool) {
        let logDue: Bool = state.withLock {
            $0.inserts += 1
            if preClassified { $0.preClassifiedInserts += 1 }
            return $0.inserts % logInterval == 0
        }
        if logDue { logSummary() }
    }

    static func recordReSave() {
        state.withLock { $0.reSavedSamples += 1 }
    }

    public static func snapshot() -> Snapshot {
        return state.withLock {
            Snapshot(
                inserts: $0.inserts,
                preClassifiedInserts: $0.preClassifiedInserts,
                reSavedSamples: $0.reSavedSamples
            )
        }
    }

    private static func logSummary() {
        let snapshot = snapshot()
        Log.info(
            "Sample write stats: inserts=\(snapshot.inserts) " +
            "preClassified=\(snapshot.preClassifiedInserts) " +
            "reSaves=\(snapshot.reSavedSamples)",
            subsystem: .database
        )
    }

}
