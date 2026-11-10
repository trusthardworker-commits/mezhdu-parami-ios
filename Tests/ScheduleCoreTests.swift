import XCTest
@testable import ScheduleCore

final class ScheduleCoreTests: XCTestCase {
    func testWidgetLinkPreservesCyrillicGroupAndRejectsOtherRoutes() throws {
        let url = try XCTUnwrap(ScheduleLink.url(group: "23ПИжб"))
        XCTAssertEqual(ScheduleLink.group(from: url), "23ПИжб")
        XCTAssertNil(ScheduleLink.group(from: URL(string: "https://example.com/schedule?group=23")!))
        XCTAssertNil(ScheduleLink.group(from: URL(string: "fiteuschedule://other?group=23")!))
        XCTAssertNil(ScheduleLink.group(from: ScheduleLink.url(group: nil)!))
    }
    private func database() throws -> ScheduleDatabase {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../ScheduleApp/Resources/schedule.json").standardizedFileURL
        return try JSONDecoder().decode(ScheduleDatabase.self, from: Data(contentsOf: url))
    }
    private func engine(_ zone: String = "Asia/Kamchatka") throws -> ScheduleEngine {
        ScheduleEngine(database: try database(), timeZone: TimeZone(identifier: zone)!)
    }
    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testEveningAndMidnightKeepSameTargetDay() throws {
        let e = try engine()
        XCTAssertEqual(e.dateKey(e.displayDate(at: instant("2026-11-10T19:59:59+12:00"))), "2026-11-10")
        for timestamp in ["2026-11-10T20:00:00+12:00", "2026-11-10T23:59:59+12:00",
                          "2026-11-11T00:00:00+12:00", "2026-11-11T19:59:59+12:00"] {
            XCTAssertEqual(e.dateKey(e.displayDate(at: instant(timestamp))), "2026-11-11")
        }
        XCTAssertEqual(e.dateKey(e.displayDate(at: instant("2026-11-11T20:00:00+12:00"))), "2026-11-12")
    }

    func testSundayEveningUsesNextWeeksParity() throws {
        let e = try engine()
        let before = e.day(for: e.displayDate(at: instant("2026-11-15T19:59:59+12:00")), groupName: "23ПИжб")
        let after = e.day(for: e.displayDate(at: instant("2026-11-15T20:00:00+12:00")), groupName: "23ПИжб")
        XCTAssertEqual(before.week, .upper)
        XCTAssertTrue(before.lessons.isEmpty)
        XCTAssertEqual(after.week, .lower)
        XCTAssertEqual(after.lessons.map(\.period), [3, 4])
        XCTAssertEqual(after.lessons.last?.title, "ЭПОРПО")
    }

    func testActualGroupBothWeekVariants() throws {
        let e = try engine()
        let upper = e.day(for: instant("2026-11-09T12:00:00+12:00"), groupName: " 23 пиЖб ")
        XCTAssertEqual(upper.lessons.map(\.period), [2, 3])
        XCTAssertTrue(upper.lessons.first!.details.contains("пр."))
        let lower = e.day(for: instant("2026-11-16T12:00:00+12:00"), groupName: "23ПИжб")
        XCTAssertEqual(lower.lessons.map(\.period), [3, 4])
        XCTAssertTrue(lower.lessons.last!.details.contains("лк."))
        XCTAssertTrue(e.day(for: instant("2026-11-10T12:00:00+12:00"), groupName: "23ПИжб").lessons.isEmpty)
        XCTAssertEqual(e.day(for: instant("2026-11-17T12:00:00+12:00"), groupName: "23ПИжб").lessons.map(\.period), [2, 3, 4])
    }

    func testStartDateAndExcludedDates() throws {
        let e = try engine()
        XCTAssertFalse(e.day(for: instant("2026-11-18T12:00:00+12:00"), groupName: "23ПИжб").lessons.contains { $0.period == 3 })
        XCTAssertTrue(e.day(for: instant("2026-11-25T12:00:00+12:00"), groupName: "23ПИжб").lessons.contains { $0.period == 3 })
        XCTAssertEqual(e.day(for: instant("2026-11-09T12:00:00+12:00"), groupName: "25ПИжб").lessons.map(\.period), [5])
        XCTAssertFalse(e.day(for: instant("2026-12-04T12:00:00+12:00"), groupName: "24ПИжб").lessons.contains { $0.period == 4 })
    }

    func testSpecificDatesOverrideHalfCellParityAndRegularRow() throws {
        let e = try engine()
        let day = e.day(for: instant("2026-11-16T12:00:00+12:00"), groupName: "25ИТб")
        XCTAssertEqual(day.lessons.filter { $0.period == 2 }.map(\.title), ["ЗИ"])
        XCTAssertEqual(e.day(for: instant("2026-11-14T12:00:00+12:00"), groupName: "26УСб").lessons.map(\.period), [1, 2, 3])
        XCTAssertEqual(e.day(for: instant("2026-11-21T12:00:00+12:00"), groupName: "26УСб").lessons.map(\.period), [3])
    }

    func testUnknownAndExpiredAreNotFreeDays() throws {
        let e = try engine()
        XCTAssertEqual(e.day(for: instant("2026-11-11T12:00:00+12:00"), groupName: "99нет").availability, .chooseGroup)
        XCTAssertEqual(e.day(for: instant("2027-01-11T12:00:00+12:00"), groupName: "23ПИжб").availability, .noSchedule)
        XCTAssertEqual(e.day(for: instant("2027-09-06T12:00:00+12:00"), groupName: "23ПИжб").availability, .noCalendar)
        XCTAssertEqual(e.day(for: instant("2026-12-23T12:00:00+12:00"), groupName: "23УСб").availability, .noSchedule)
    }

    func testTimelineAllFutureEntriesAtTwentyAndDST() throws {
        for zone in ["Asia/Kamchatka", "Europe/Berlin", "America/New_York"] {
            let e = try engine(zone)
            let now = instant("2026-10-24T10:00:00Z")
            let dates = e.timelineDates(after: now)
            XCTAssertEqual(dates.count, 15)
            XCTAssertEqual(dates.first, now)
            for (previous, next) in zip(dates, dates.dropFirst()) {
                XCTAssertGreaterThan(next, previous)
                XCTAssertEqual(e.calendar.component(.hour, from: next), 20)
                XCTAssertEqual(e.calendar.component(.minute, from: next), 0)
            }
        }
    }

    func testLocalZoneChangesTargetDate() throws {
        let now = instant("2026-11-10T08:00:00Z")
        let kamchatka = try engine()
        let moscow = try engine("Europe/Moscow")
        XCTAssertEqual(kamchatka.dateKey(kamchatka.displayDate(at: now)), "2026-11-11")
        XCTAssertEqual(moscow.dateKey(moscow.displayDate(at: now)), "2026-11-10")
    }

    func testCalendarYearBoundaryAndAllGroups() throws {
        let e = try engine()
        XCTAssertEqual(e.database.groups.count, 21)
        XCTAssertEqual(e.database.weeks.count, 53)
        XCTAssertEqual(e.day(for: instant("2027-01-01T12:00:00+12:00"), groupName: "23ПИжб").week, .lower)
        XCTAssertEqual(e.dateKey(e.displayDate(at: instant("2026-12-31T20:00:00+12:00"))), "2027-01-01")
        for group in e.database.groups { XCTAssertFalse(group.lessons.isEmpty) }
    }
}
