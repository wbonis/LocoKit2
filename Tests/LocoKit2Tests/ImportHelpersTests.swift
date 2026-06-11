//
//  ImportHelpersTests.swift
//  LocoKit2
//

import Testing
import Foundation
@testable import LocoKit2

struct ImportHelpersTests {

    @Test func dayKeyFormatsCurrentTimezoneDay() throws {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 20
        comps.hour = 12
        let date = try #require(Calendar.current.date(from: comps))

        #expect(ImportHelpers.dayKey(for: date) == "2026-04-20")
    }

    @Test func dayKeyPadsSingleDigitComponents() throws {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 5
        comps.hour = 12
        let date = try #require(Calendar.current.date(from: comps))

        #expect(ImportHelpers.dayKey(for: date) == "2026-01-05")
    }

    @Test func dayKeyRespectsLocalMidnightBoundary() throws {
        // one second before local midnight stays on the earlier day
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 10
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        let beforeMidnight = try #require(Calendar.current.date(from: comps))

        #expect(ImportHelpers.dayKey(for: beforeMidnight) == "2026-06-10")
        #expect(ImportHelpers.dayKey(for: beforeMidnight.addingTimeInterval(1)) == "2026-06-11")
    }
}
