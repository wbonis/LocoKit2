//
//  Database+RTreeTriggers.swift
//  LocoKit2
//
//  Created by Matt Greenfield on 7/4/25.
//

import GRDB

extension Database {
    func addRTreeTriggers(to migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Initial RTree triggers") { db in

            // MARK: - Place RTree Triggers

            /** maintain PlaceRTree when Place coordinates change */

            try db.execute(sql: """
                CREATE TRIGGER Place_AFTER_INSERT
                AFTER INSERT ON Place
                BEGIN
                    INSERT INTO PlaceRTree (latMin, latMax, lonMin, lonMax)
                    VALUES (NEW.latitude, NEW.latitude, NEW.longitude, NEW.longitude);
                    
                    UPDATE Place 
                    SET rtreeId = last_insert_rowid()
                    WHERE id = NEW.id;
                END;
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER Place_AFTER_UPDATE_coordinates
                AFTER UPDATE OF latitude, longitude ON Place
                WHEN OLD.latitude != NEW.latitude OR OLD.longitude != NEW.longitude OR NEW.rtreeId IS NULL
                BEGIN
                    UPDATE PlaceRTree 
                    SET latMin = NEW.latitude, latMax = NEW.latitude, 
                        lonMin = NEW.longitude, lonMax = NEW.longitude
                    WHERE id = NEW.rtreeId;
                    
                    INSERT INTO PlaceRTree (latMin, latMax, lonMin, lonMax)
                    SELECT NEW.latitude, NEW.latitude, NEW.longitude, NEW.longitude
                    WHERE NEW.rtreeId IS NULL;
                    
                    UPDATE Place 
                    SET rtreeId = last_insert_rowid()
                    WHERE id = NEW.id AND NEW.rtreeId IS NULL;
                END;
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER Place_AFTER_DELETE
                AFTER DELETE ON Place
                WHEN OLD.rtreeId IS NOT NULL
                BEGIN
                    DELETE FROM PlaceRTree 
                    WHERE id = OLD.rtreeId;
                END;
                """)
            
            try Database.createSampleRTreeTriggers(db)
        }
    }

    /// Recreates the sample R-tree insert trigger and bulk-backfills any
    /// samples inserted while it was missing. Safety net for databases
    /// touched by builds that dropped the trigger during bulk imports —
    /// an app kill mid-import left the schema without it. Cheap no-op
    /// when the trigger is present.
    static func ensureSampleRTreeIntegrity(_ db: GRDB.Database) throws {
        let triggerExists = try Bool.fetchOne(db, sql: """
            SELECT EXISTS(
                SELECT 1 FROM sqlite_master
                WHERE type = 'trigger' AND name = 'LocomotionSample_AFTER_INSERT_coordinates'
            )
            """) ?? false
        if triggerExists { return }

        Log.info("Sample R-tree insert trigger missing - backfilling and recreating", subsystem: .database)

        let base = try Int64.fetchOne(db, sql: "SELECT IFNULL(MAX(id), 0) FROM SampleRTree") ?? 0
        try db.execute(sql: """
            INSERT INTO SampleRTree (id, latMin, latMax, lonMin, lonMax)
            SELECT rowid + ?, latitude, latitude, longitude, longitude
            FROM LocomotionSample
            WHERE rtreeId IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL
            """, arguments: [base])
        try db.execute(sql: """
            UPDATE LocomotionSample SET rtreeId = rowid + ?
            WHERE rtreeId IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL
            """, arguments: [base])

        try db.execute(sql: "DROP TRIGGER IF EXISTS LocomotionSample_AFTER_DELETE_rtreeId")
        try createSampleRTreeTriggers(db)
    }

    static func createSampleRTreeTriggers(_ db: GRDB.Database) throws {
        try db.execute(sql: """
            CREATE TRIGGER LocomotionSample_AFTER_INSERT_coordinates
            AFTER INSERT ON LocomotionSample
            WHEN NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL
            BEGIN
                INSERT INTO SampleRTree (latMin, latMax, lonMin, lonMax)
                VALUES (NEW.latitude, NEW.latitude, NEW.longitude, NEW.longitude);

                UPDATE LocomotionSample
                SET rtreeId = last_insert_rowid()
                WHERE id = NEW.id;
            END;
            """)

        try db.execute(sql: """
            CREATE TRIGGER LocomotionSample_AFTER_DELETE_rtreeId
            AFTER DELETE ON LocomotionSample
            WHEN OLD.rtreeId IS NOT NULL
            BEGIN
                DELETE FROM SampleRTree
                WHERE id = OLD.rtreeId;
            END;
            """)
    }
}
