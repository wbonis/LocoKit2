//
//  TimelineRecorder.swift
//
//
//  Created by Matt Greenfield on 11/3/24.
//

import Foundation
import CoreLocation
import GRDB

@TimelineActor
public enum TimelineRecorder {

    public static func startup() {
        Database.pool.add(transactionObserver: TimelineObserver.highlander)
        Database.pool.add(transactionObserver: TimelineItemObserver.highlander)
    }

    public static func startRecording() async throws {
        if await ImportState.hasPartialImport {
            Log.info("TimelineRecorder.startRecording() blocked by partial import", subsystem: .timeline)
            throw ImportExportError.partialImportInProgress
        }
        startWatchingLoco()
        await loco.startRecording()
        await startFallbackSampleTimer()
    }

    public static func stopRecording() async {
        await loco.stopRecording()
        await stopFallbackSampleTimer()
    }

    public static var isRecording: Bool {
        get async {
            return await loco.recordingState != .off
        }
    }

    // MARK: - Drift Profile Context

    public struct DriftContext: Sendable {
        public let itemId: String
        public let placeId: String
        public let centroid: CLLocation
        public let profile: DriftProfile
    }

    private static var _cachedDriftContext: DriftContext?

    /// Returns the drift profile context applicable to the given location, if any.
    ///
    /// Primary path: current item is a Visit with a place → that place's profile.
    ///
    /// Extended trust window: if the current item has no place-based context (e.g. a Trip after
    /// drift escaped the Visit), falls back to the previously cached profile as long as the
    /// location is still within `maxObservedDrift` of the cached centroid. The profile's own
    /// learned scope defines its scope of concern — beyond that distance we have no basis for
    /// defending, and the cache expires.
    ///
    /// Caches the primary context by itemId; rebuild only happens on item transitions. The
    /// fallback path does a cheap distance check per call but no DB work.
    public static func currentDriftContext(for location: CLLocation) -> DriftContext? {
        guard let itemId = currentItemId else {
            _cachedDriftContext = nil
            return nil
        }

        // cache hit — same item AND same place context
        if let cached = _cachedDriftContext,
           cached.itemId == itemId,
           cached.placeId == currentPlaceId {
            return cached
        }

        // item changed — try to build fresh context from current item's place
        if let item = currentItem(includeSamples: false, includePlaces: true),
           let place = item.place,
           let placeId = item.visit?.placeId {

            let context: DriftContext? = try? Database.pool.read { db in
                guard let profile = try DriftProfile
                    .filter(DriftProfile.Columns.placeId == placeId)
                    .fetchOne(db) else { return nil }

                let centroid = CLLocation(latitude: place.latitude, longitude: place.longitude)
                return DriftContext(itemId: itemId, placeId: placeId, centroid: centroid, profile: profile)
            }

            if let context {
                _cachedDriftContext = context
                return context
            }
        }

        // current item has no place-based context — check extended trust window from previous cache
        if let cached = _cachedDriftContext {
            let distance = location.distance(from: cached.centroid)
            if distance < cached.profile.maxObservedDrift {
                return cached  // still within profile's scope of concern
            }
            // crossed profile's scope — expire
            _cachedDriftContext = nil
        }

        return nil
    }

    // MARK: -

    public static private(set) var currentItemId: String? {
        didSet {
            Task { await loco.appGroup?.save() }
        }
    }

    /// The placeId of the current item's visit. Refreshed lazily as a side effect of
    /// `currentItem(includePlaces: true)` calls — may be briefly stale between a place
    /// reassignment and the next refresh. Sufficient for drift-cache validation;
    /// not for real-time place state.
    public static private(set) var currentPlaceId: String?

    public static func currentItem(includeSamples: Bool = false, includePlaces: Bool = false) -> TimelineItem? {
        do {
            let item = try Database.pool.read { db in
                let request = TimelineItem
                    .itemBaseRequest(includeSamples: includeSamples, includePlaces: includePlaces)
                    .filter { $0.deleted == false && $0.disabled == false }
                    .order(\.endDate.desc)
                return try request.asRequest(of: TimelineItem.self).fetchOne(db)
            }

            // update currentItemId if changed
            if let item, item.id != currentItemId {
                self.currentItemId = item.id
            }

            // refresh currentPlaceId if visit data was loaded
            if includePlaces {
                self.currentPlaceId = item?.visit?.placeId
            }

            return item

        } catch {
            Log.error(error, subsystem: .database)
        }

        return nil
    }

    public static private(set) var latestSampleId: String?

    public static func latestSample() -> LocomotionSample? {
        guard let latestSampleId else { return nil }
        return try? Database.pool.read {
            try LocomotionSample.fetchOne($0, id: latestSampleId)
        }
    }

    // MARK: - Private

    private static let loco = LocomotionManager.highlander

    private static var watchingLoco = false

    private static func startWatchingLoco() {
        if watchingLoco { return }
        watchingLoco = true
        
        print("startWatchingLoco()")

        updateCurrentItemId()

        Task {
            for await _ in loco.locationUpdates() {
                await recordSample()
            }
        }

        Task {
            for await newState in loco.stateUpdates() {
                await recordingStateChanged(newState)
            }
        }
    }

    public static func updateCurrentItemId() {
        currentItemId = try? Database.pool.read {
            try TimelineItemBase
                .filter(TimelineItemBase.Columns.deleted == false && TimelineItemBase.Columns.disabled == false)
                .order(TimelineItemBase.Columns.endDate.desc)
                .selectPrimaryKey()
                .fetchOne($0)
        }
    }

    private static var previousRecordingState: RecordingState?
    private static var recordingEnded: Date?

    // MARK: -

    private static func recordingStateChanged(_ recordingState: RecordingState) async {
        // we're only here for changes
        if recordingState == previousRecordingState {
            return
        }

        // keep track of sleep start
        if recordingState == .recording {
            recordingEnded = nil
        } else if previousRecordingState == .recording {
            recordingEnded = .now
        }

        // fire up the processor on transition to sleep
        if previousRecordingState == .recording, recordingState == .sleeping {
            print("recordingStateChanged() .recording -> .sleeping")

            // no fallback samples while sleeping
            await stopFallbackSampleTimer()

            // force a sample at state transition, to ensure currentVisit is a keeper
            // (transition to sleep only requires up-to-now duration, and distance filtered
            // location updates mean actual dateRange may not reflect that, preventing
            // merges with previous items at same location)
            await recordSample()

            if let currentItemId {
                Task { await TimelineProcessor.processFrom(itemId: currentItemId) }
            }
        }

        // restart fallback timer when returning to active recording
        if recordingState == .recording, previousRecordingState != .recording {
            await startFallbackSampleTimer()
        }

        previousRecordingState = recordingState

        switch recordingState {
        case .sleeping, .recording:
            await updateSleepCycleDuration(recordingState)
            break
        default:
            break
        }
    }

    private static func updateSleepCycleDuration(_ recordingState: RecordingState) async {
        // ensure sleep cycles are short for when sleeping next starts
        if recordingState == .recording {
            await loco.setSleepCycleDuration(6)
            return
        }

        guard let currentItem = currentItem(includePlaces: true),
              let place = currentItem.place,
              let dateRange = currentItem.dateRange else {
            await updateSleepCycleDurationFallback()
            return
        }

        // Calculate combined probability
        let visitDuration = -dateRange.start.timeIntervalSinceNow
        guard let probability = place.leavingProbabilityFor(duration: visitDuration) else {
            await updateSleepCycleDurationFallback()
            return
        }

        // Map probability to duration (6-60 seconds)
        let shortCycleThreshold = 0.1 // probability threshold for 6s sleep cycles

        switch probability {
        case shortCycleThreshold...1.0:  // high probability
            await loco.setSleepCycleDuration(6)

        case 0.01..<shortCycleThreshold: // common probability range
            let normalised = (probability - 0.01) / (shortCycleThreshold - 0.01)
            // Use cube root (0.33) for aggressive curve towards shorter cycles
            let curved = pow(normalised, 0.33)
            let duration = 60 - (curved * 54)
            await loco.setSleepCycleDuration(duration)

        default:         // Very low probability (<1%)
            await loco.setSleepCycleDuration(60)
        }
    }

    private static func updateSleepCycleDurationFallback() async {
        guard let recordingEnded else {
            await loco.setSleepCycleDuration(6)
            return
        }

        // scale sleep cycles based on time at unknown place:
        // - first 2 minutes: 6 seconds (quick wake detection)
        // - 2-60 minutes: scale from 6 to 30 seconds
        // - after 60 minutes: cap at 30 seconds (matches Arc Timeline)
        let sleepMinutes = recordingEnded.age / 60
        if sleepMinutes < 2 {
            await loco.setSleepCycleDuration(6)
        } else if sleepMinutes <= 60 {
            let duration = 6 + ((sleepMinutes - 2) / 58 * (30 - 6))
            await loco.setSleepCycleDuration(duration)
        } else {
            await loco.setSleepCycleDuration(30)
        }
    }

    static var canStartSleeping: Bool {
        get async {
            guard let currentItem = currentItem() else {
                return false
            }
            guard currentItem.isVisit else {
                return false
            }
            guard let dateRange = currentItem.dateRange else {
                return false
            }
            // use age instead of duration, because distanceFilter delays new samples when stationary
            return dateRange.start.age >= TimelineItemVisit.minimumKeeperDuration
        }
    }

    // MARK: - Sample recording

    private static var lastRecordSampleCall: Date?

    // mapmyway: opt-in classify-at-record (see setClassifiesSamplesOnRecord below)
    private static var classifiesSamplesOnRecord = false

    /// Opt-in: classify each sample at record time, so `classifiedActivityType`
    /// persists inside the sample's single insert commit instead of via a later
    /// per-sample re-save from the classification chain. Halves steady-state WAL
    /// commits while recording. The consuming app enables this together with
    /// `ActivityClassifier.setAllowsBackgroundClassification(true)` so background
    /// recordings classify too. Default off = upstream write behavior.
    public static func setClassifiesSamplesOnRecord(_ enabled: Bool) {
        classifiesSamplesOnRecord = enabled
    }

    private static func recordSample() async {
        guard await isRecording else { return }

        // minimum 1 second between samples plz
        if let lastRecordSampleCall, lastRecordSampleCall.age < 1 { return }
        lastRecordSampleCall = .now

        var sample = await loco.createASample()

        // mapmyway: decide the sample's timeline item BEFORE the insert.
        // Attach path: sample carries timelineItemId into a single insert commit
        // (LocomotionSample_AFTER_INSERT_timelineItemId_SET bumps the item).
        // New-item path: item + visit/trip + sample in ONE transaction — never
        // insert an orphan first (field bug 18 Jul: 117 stationary orphans,
        // visit never formed, trip ran 32h because canStartSleeping needs a visit).
        let destination = await destination(for: sample)

        // mapmyway: classify BEFORE the insert (opt-in) so the classified type
        // rides the sample's insert commit. Returns nil in background unless
        // the app opted in — then the later pass fills it exactly as before.
        var preClassified = false
        if classifiesSamplesOnRecord,
           let results = await sample.classifierResults,
           let bestMatch = results.bestMatch {
            sample.classifiedActivityType = bestMatch.activityType
            preClassified = true
        }

        do {
            switch destination {
            case .attach(let itemId):
                sample.timelineItemId = itemId
                let toInsert = sample
                try await Database.pool.write { db in
                    var s = toInsert
                    try s.insert(db)
                }
                SampleWriteStats.recordInsert(preClassified: preClassified)

            case .newItem(let previousItemId):
                do {
                    let newItemId = try await persistNewItem(sample: sample, previousItemId: previousItemId)
                    currentItemId = newItemId
                    SampleWriteStats.recordInsert(preClassified: preClassified)
                } catch {
                    // Boundary failed (e.g. no usable coordinate for a visit).
                    // Prefer attaching to the previous item over leaving an orphan
                    // that adoptOrphanedSamples would later merge into a spanning trip.
                    Log.error(error, subsystem: .database)
                    if let previousItemId {
                        sample.timelineItemId = previousItemId
                        let toInsert = sample
                        try await Database.pool.write { db in
                            var s = toInsert
                            try s.insert(db)
                        }
                        SampleWriteStats.recordInsert(preClassified: preClassified)
                    } else {
                        throw error
                    }
                }
            }

            await startFallbackSampleTimer()

        } catch {
            Log.error(error, subsystem: .database)
        }

        latestSampleId = sample.id
    }

    private enum SampleDestination {
        case attach(itemId: String)
        case newItem(previousItemId: String?)
    }

    private static func destination(for sample: LocomotionSample) async -> SampleDestination {

        /** first timeline item **/
        guard let workingItem = currentItem() else {
            return .newItem(previousItemId: nil)
        }

        let previouslyMoving = !workingItem.isVisit
        let currentlyMoving = sample.movingState != .stationary

        // only create new items during full recording. during .wakeup we're still in the
        // sleep mode paradigm — samples attach to the current visit, no item boundaries.
        let isFullRecording = await loco.recordingState == .recording

        /** stationary -> moving || moving -> stationary (only during recording) **/
        if isFullRecording, currentlyMoving != previouslyMoving {
            return .newItem(previousItemId: workingItem.id)
        }

        /** same state, or wakeup — attach sample to current item **/
        return .attach(itemId: workingItem.id)
    }

    private enum PersistNewItemError: Error {
        case cannotCreateVisitWithoutCoordinate
    }

    /// Persists a new timeline item and its seed sample in one WAL transaction.
    /// Throws if the item detail row cannot be formed (so the caller can fall back).
    private static func persistNewItem(sample: LocomotionSample, previousItemId: String?) async throws -> String {
        var newItem = TimelineItemBase(from: sample)
        newItem.previousItemId = previousItemId

        let newVisit: TimelineItemVisit?
        let newTrip: TimelineItemTrip?

        if newItem.isVisit {
            if let visit = TimelineItemVisit(itemId: newItem.id, samples: [sample]) {
                newVisit = visit
            } else if let lat = sample.latitude, let lon = sample.longitude {
                // mapmyway: weightedCenter can fail on edge samples; still open
                // the visit so sleep can eventually anchor (canStartSleeping).
                newVisit = TimelineItemVisit(
                    itemId: newItem.id,
                    latitude: lat,
                    longitude: lon,
                    radiusMean: TimelineItemVisit.minRadius,
                    radiusSD: 0
                )
                Log.info("Visit created via coordinate fallback (weightedCenter nil)", subsystem: .timeline)
            } else {
                throw PersistNewItemError.cannotCreateVisitWithoutCoordinate
            }
            newTrip = nil
        } else {
            newTrip = TimelineItemTrip(itemId: newItem.id, samples: [sample])
            newVisit = nil
        }

        var sampleToInsert = sample
        sampleToInsert.timelineItemId = newItem.id

        let item = newItem
        let visit = newVisit
        let trip = newTrip
        let seed = sampleToInsert

        try await Database.pool.write { db in
            var mutableItem = item
            try mutableItem.insert(db)
            try visit?.insert(db)
            try trip?.insert(db)
            var mutableSample = seed
            try mutableSample.insert(db)
        }

        return item.id
    }

    // MARK: - Fallback sample recording

    @MainActor
    private static let fallbackSampleDuration: TimeInterval = 10

    @MainActor
    private static var fallbackSampleTimer: Timer?

    @MainActor
    private static func startFallbackSampleTimer() {
        fallbackSampleTimer?.invalidate()
        fallbackSampleTimer = Timer.scheduledTimer(withTimeInterval: fallbackSampleDuration, repeats: false) { _ in
            Task {
                // don't do anything if we're not actively recording
                guard await Self.loco.recordingState == .recording else { return }

                // only record if we haven't had a sample in a while
                if let latestSample = await Self.latestSample(),
                   await latestSample.date.age > Self.loco.fallbackUpdateDuration {
                    await Self.recordSample()
                }
                await Self.startFallbackSampleTimer()
            }
        }
    }

    @MainActor
    private static func stopFallbackSampleTimer() {
        fallbackSampleTimer?.invalidate()
        fallbackSampleTimer = nil
    }

}
