import Foundation

enum WeekKind: String, Codable {
    case upper, lower, both
    var title: String {
        switch self {
        case .upper: return "Верхняя неделя"
        case .lower: return "Нижняя неделя"
        case .both: return "Каждую неделю"
        }
    }
    var symbol: String { self == .lower ? "arrow.down" : "arrow.up" }
}

struct AcademicWeek: Codable {
    let start: String
    let end: String
    let kind: WeekKind
}

struct Lesson: Codable, Identifiable {
    let id: String
    let weekday: Int
    let period: Int
    let week: WeekKind
    let title: String
    let details: String
    var startsOn: String? = nil
    var endsOn: String? = nil
    var onlyDates: [String]? = nil
    var excludedDates: [String]? = nil

    var periodTitle: String { period == 0 ? "Весь день" : "\(period) пара" }
    var room: String? {
        let pattern = #"АК-\d{3}|\d-\d{3}|УК-2\s*СЗ|ФОК|дистанционно"#
        guard let range = details.range(of: pattern, options: .regularExpression) else { return nil }
        return String(details[range])
    }

    func occurs(on key: String, weekday day: Int, week kind: WeekKind) -> Bool {
        guard weekday == day else { return false }
        if let startsOn, key < startsOn { return false }
        if let endsOn, key > endsOn { return false }
        if excludedDates?.contains(key) == true { return false }
        // Explicit dates in a half-cell may cross week parity (e.g. 09.11 and 16.11).
        // They represent a dated exception, taking precedence over the repeating row.
        if let onlyDates { return onlyDates.contains(key) }
        return week == .both || week == kind
    }
}

struct StudentGroup: Codable, Identifiable {
    let id: String
    let sourcePage: Int
    let validFrom: String
    let validThrough: String
    let warning: String?
    let lessons: [Lesson]
}

struct ScheduleDatabase: Codable {
    let schemaVersion: Int
    let title: String
    let importedOn: String
    let sourceSchedule: String
    let sourceWeeks: String
    let weeks: [AcademicWeek]
    let groups: [StudentGroup]

    static func load(bundle: Bundle = .main) throws -> ScheduleDatabase {
        guard let url = bundle.url(forResource: "schedule", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let database = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard database.schemaVersion == 1, !database.groups.isEmpty else {
            throw CocoaError(.coderReadCorrupt)
        }
        return database
    }

    func group(named name: String) -> StudentGroup? {
        groups.first { Self.normalize($0.id) == Self.normalize(name) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    }
}

enum DayAvailability: Equatable {
    case ready, chooseGroup, noCalendar, noSchedule, loadError
    var message: String {
        switch self {
        case .ready: return "Пар нет по расписанию"
        case .chooseGroup: return "Выберите свою группу"
        case .noCalendar: return "На эту дату нет календаря недель"
        case .noSchedule: return "На эту дату расписание не загружено"
        case .loadError: return "Не удалось прочитать расписание"
        }
    }
}

struct ScheduleDay {
    let date: Date
    let group: StudentGroup?
    let week: WeekKind?
    let lessons: [Lesson]
    let availability: DayAvailability
}

struct ScheduleEngine {
    let database: ScheduleDatabase
    var calendar: Calendar

    init(database: ScheduleDatabase, timeZone: TimeZone = .autoupdatingCurrent) {
        self.database = database
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    func dateKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func displayDate(at now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.component(.hour, from: now) >= 20
            ? calendar.date(byAdding: .day, value: 1, to: today)!
            : today
    }

    func nextSwitch(after now: Date) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 20, minute: 0, second: 0),
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first)!
    }

    /// Precomputed entries change the display without requiring a network or app launch.
    func timelineDates(after now: Date, days: Int = 14) -> [Date] {
        var dates = [now]
        var boundary = nextSwitch(after: now)
        for _ in 0..<max(0, days) {
            dates.append(boundary)
            boundary = calendar.date(byAdding: .day, value: 1, to: boundary)!
        }
        return dates
    }

    func day(for date: Date, groupName: String) -> ScheduleDay {
        let key = dateKey(date)
        let week = database.weeks.first { $0.start <= key && key <= $0.end }?.kind
        let group = database.group(named: groupName)
        let status: DayAvailability
        if group == nil { status = .chooseGroup }
        else if week == nil { status = .noCalendar }
        else if key < group!.validFrom || key > group!.validThrough { status = .noSchedule }
        else { status = .ready }
        var lessons: [Lesson] = []
        if status == .ready, let group, let week {
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
            let matching = group.lessons.filter { $0.occurs(on: key, weekday: weekday, week: week) }
            let exceptions = Set(matching.filter { $0.onlyDates != nil }.map(\.period))
            lessons = matching.filter { $0.onlyDates != nil || !exceptions.contains($0.period) }
                .sorted { $0.period == $1.period ? $0.id < $1.id : $0.period < $1.period }
        }
        return ScheduleDay(date: calendar.startOfDay(for: date), group: group, week: week,
                           lessons: lessons, availability: status)
    }
}

enum SharedPreferences {
    static let groupKey = "selectedGroup"
    static let widgetKind = "FITeUScheduleWidget"
    // App-only preferences. Widget choices are stored by WidgetKit in its intent.
    static var defaults: UserDefaults { .standard }
    static var selectedGroup: String { defaults.string(forKey: groupKey) ?? "" }
}

enum ScheduleLink {
    static func url(group: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "fiteuschedule"
        components.host = "schedule"
        if let group { components.queryItems = [URLQueryItem(name: "group", value: group)] }
        return components.url
    }
    static func group(from url: URL) -> String? {
        guard url.scheme == "fiteuschedule", url.host == "schedule" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "group" })?.value
    }
}

enum RussianDate {
    static func string(_ date: Date, format: String = "EEEE, d MMMM", timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
