//
//  Database.swift
//  LocoKit2
//
//  Created by Matt Greenfield on 11/3/24.
//

import Foundation
import GRDB

public final class Database: @unchecked Sendable {

    public static let highlander = Database()

    public var appGroup: AppGroup? 

    // MARK: - Pool

    public static var pool: DatabasePool { return highlander.pool }
    
    public static var legacyPool: DatabasePool? { return highlander.legacyPool }

    public private(set) lazy var pool: DatabasePool = {
        let dbUrl: URL
        if let appGroup, appGroup.localDatabaseOnly {
            dbUrl = appContainerDbUrl
        } else {
            dbUrl = appGroupDbUrl ?? appContainerDbUrl
        }
        return try! DatabasePool(path: dbUrl.path, configuration: makeConfig(dbPath: dbUrl.path))
    }()

    public private(set) lazy var legacyPool: DatabasePool? = {
        guard let dbUrl = appGroupLegacyDbUrl else { return nil }
        return try! DatabasePool(path: dbUrl.path, configuration: makeConfig(dbPath: dbUrl.path))
    }()

    /// Close and nil the legacy pool ahead of legacy database deletion (BIG-321).
    /// The nil assignment marks the lazy var initialised, so later accesses return
    /// nil instead of lazily recreating the pool (GRDB creates a missing db file
    /// on pool init, which would resurrect an empty LocoKit.sqlite post-deletion).
    public func closeLegacyPool() {
        try? legacyPool?.close()
        legacyPool = nil
    }

    private func makeConfig(dbPath: String) -> Configuration {
        var config = Configuration()
        config.busyMode = .timeout(30)
        config.maximumReaderCount = 12
        config.observesSuspensionNotifications = true
        config.prepareDatabase { db in
            if !db.configuration.readonly {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: dbPath)
            }
        }

//        config.prepareDatabase { db in
//            db.trace { event in
//                print("SQL: \(event.expandedDescription)")
//            }
//        }

        return config
    }

    // MARK: - Migrations

    public lazy var migrator = {
        var migrator = DatabaseMigrator()
        return migrator
    }()

    public func runMigrations() {
        let pending = pendingMigrations()
        if !pending.isEmpty {
            Log.info("Running \(pending.count) migrations: \(pending.joined(separator: ", "))", subsystem: .database)
        }
        let start = Date()
        do {
            try migrator.migrate(pool)
        } catch {
            Log.error(error, subsystem: .database)
        }
        // Bulk imports drop the sample R-tree insert trigger; if the app
        // was killed mid-import the schema would stay without it. Cheap
        // existence check, backfill + recreate only when needed.
        do {
            try pool.write { try Database.ensureSampleRTreeIntegrity($0) }
        } catch {
            Log.error(error, subsystem: .database)
        }
        if !pending.isEmpty {
            Log.info("Migrations completed in \(String(format: "%.1f", -start.timeIntervalSinceNow))s", subsystem: .database)
        }
    }

    public func doMigrations() {
        addMigrations()
        runMigrations()
    }

    public var havePendingMigrations: Bool {
        !pendingMigrations().isEmpty
    }

    private func pendingMigrations() -> [String] {
        do {
            let registered = migrator.migrations
            let done = try pool.read { try migrator.appliedMigrations($0) }
            return registered.filter { !done.contains($0) }
        } catch {
            return []
        }
    }

    public func eraseTheDb() {
        Log.info("ERASING THE DATABASE", subsystem: .database)
        do {
            try Database.pool.erase()
            migrator = DatabaseMigrator()
        } catch {
            Log.error(error, subsystem: .database)
        }
    }

    // MARK: -

    /// Registers the schema migrations into `migrator` WITHOUT running them.
    /// Public so a read-only viewer (App-Group multi-app split) can populate
    /// the migrator and then use `havePendingMigrations` / `appliedMigrations`
    /// for the ADR-0004 schema-version guard, without ever migrating.
    /// WARNING: do not also call `doMigrations()` in the same process — that
    /// would register the same migration identifiers twice and trap.
    public func addMigrations() {
        addInitialSchema(to: &migrator)
        addLastSavedTriggers(to: &migrator)
        addEdgeTriggers(to: &migrator)
        addSampleTriggers(to: &migrator)
        addRTreeTriggers(to: &migrator)
        // mapmyway: upstream leaves delayed migrations for the consuming app to
        // register (Arc does). MapMyWay never did, so existing DBs missed every
        // post-creation schema change — BIG-455's locality/countryCode columns
        // made TimelineItemVisit inserts fail forever (the eternal-trip bug,
        // 2026-07-18). Registering here covers doMigrations() and the reader
        // guard's pending-migrations check in one place.
        addDelayedMigrations(to: &migrator)
    }

    // MARK: - URLs

    private lazy var appContainerDbDir: URL = {
        return try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }()

    public var appGroupDbDir: URL? {
        guard let suiteName = appGroup?.suiteName else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    // MARK: -

    private lazy var appContainerDbUrl: URL = {
        return appContainerDbDir.appendingPathComponent("LocoKit2.sqlite")
    }()

    private var appGroupDbUrl: URL? {
        return appGroupDbDir?.appendingPathComponent("LocoKit2.sqlite")
    }

    private var appGroupLegacyDbUrl: URL? {
        return appGroupDbDir?.appendingPathComponent("LocoKit.sqlite")
    }

}
