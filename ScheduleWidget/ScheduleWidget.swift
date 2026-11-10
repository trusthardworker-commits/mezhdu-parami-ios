import SwiftUI
import WidgetKit
import AppIntents

struct GroupOption: AppEntity {
    let id: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Группа"
    static var defaultQuery = GroupQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct GroupQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GroupOption] {
        try ScheduleDatabase.load().groups.filter { identifiers.contains($0.id) }.map { GroupOption(id: $0.id) }
    }
    func suggestedEntities() async throws -> [GroupOption] {
        try ScheduleDatabase.load().groups.map { GroupOption(id: $0.id) }
    }
    func entities(matching string: String) async throws -> [GroupOption] {
        let query = ScheduleDatabase.normalize(string)
        return try ScheduleDatabase.load().groups
            .filter { ScheduleDatabase.normalize($0.id).contains(query) }.map { GroupOption(id: $0.id) }
    }
}

struct ChooseGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Группа"
    static var description = IntentDescription("Выберите группу для этого виджета.")
    @Parameter(title: "Группа") var group: GroupOption?
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let day: ScheduleDay
}

struct ScheduleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry { entry(at: Date(), preview: true) }
    func snapshot(for configuration: ChooseGroupIntent, in context: Context) async -> ScheduleEntry {
        entry(at: Date(), group: configuration.group?.id, preview: context.isPreview)
    }
    func timeline(for configuration: ChooseGroupIntent, in context: Context) async -> Timeline<ScheduleEntry> {
        let now = Date()
        guard let database = try? ScheduleDatabase.load() else {
            return Timeline(entries: [entry(at: now)], policy: .after(now.addingTimeInterval(3600)))
        }
        let engine = ScheduleEngine(database: database)
        let group = configuration.group?.id ?? ""
        let entries = engine.timelineDates(after: now).map { instant in
            ScheduleEntry(date: instant, day: engine.day(for: engine.displayDate(at: instant), groupName: group))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
    private func entry(at now: Date, group: String? = nil, preview: Bool = false) -> ScheduleEntry {
        guard let database = try? ScheduleDatabase.load() else {
            return ScheduleEntry(date: now, day: ScheduleDay(date: now, group: nil, week: nil, lessons: [], availability: .loadError))
        }
        let engine = ScheduleEngine(database: database)
        // The gallery uses a real loaded date rather than invented example classes.
        let date = preview ? engine.calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))! : engine.displayDate(at: now)
        return ScheduleEntry(date: now, day: engine.day(for: date, groupName: preview ? "23ПИжб" : (group ?? "")))
    }
}

struct ScheduleWidgetView: View {
    let entry: ScheduleEntry
    @Environment(\.widgetFamily) private var family
    private let lime = Color(red: 0.82, green: 0.94, blue: 0.55)
    private var limit: Int { family == .systemLarge ? 6 : family == .systemMedium ? 3 : 2 }
    private var compact: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack {
                Text(entry.day.group?.id ?? "МЕЖДУ ПАРАМИ").font(.caption.weight(.bold)).tracking(0.8)
                Spacer(minLength: 2)
                if let week = entry.day.week {
                    Label(compact ? "" : (week == .upper ? "Верхняя" : "Нижняя"), systemImage: week.symbol)
                        .font(.caption2.weight(.semibold)).foregroundStyle(lime)
                        .accessibilityLabel(week.title)
                }
            }
            Text(RussianDate.string(entry.day.date, format: compact ? "EE, d MMM" : "EEEE, d MMMM"))
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            if entry.day.lessons.isEmpty {
                Spacer(minLength: 0)
                Label(entry.day.availability == .chooseGroup ? "Удерживайте виджет → Изменить виджет → Группа" : entry.day.availability.message,
                      systemImage: entry.day.availability == .ready ? "cup.and.saucer" : "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(lime)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.day.lessons.prefix(limit)) { lesson in
                    HStack(alignment: .top, spacing: 9) {
                        Text(lesson.period == 0 ? "•" : "\(lesson.period)")
                            .font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(lime).frame(width: 13)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lesson.title).font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if family == .systemLarge {
                                Text(lesson.details).font(.system(size: 10)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                            }
                        }
                        if family == .systemMedium, let room = lesson.room {
                            Spacer(minLength: 2)
                            Text(room).font(.system(size: 10)).foregroundStyle(lime).lineLimit(1)
                        }
                    }
                    if family == .systemLarge && lesson.id != entry.day.lessons.prefix(limit).last?.id {
                        Divider().overlay(.white.opacity(0.15))
                    }
                }
                if entry.day.lessons.count > limit {
                    Text("Ещё занятий: \(entry.day.lessons.count - limit)").font(.caption2).foregroundStyle(lime)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                if entry.day.group?.warning != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Уточните срок PDF")
                } else {
                    Image(systemName: "moon")
                    Text("Смена дня в 20:00")
                }
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(lime.opacity(0.8)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .containerBackground(Color(red: 0.10, green: 0.17, blue: 0.16), for: .widget)
        .widgetURL(ScheduleLink.url(group: entry.day.group?.id))
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

@main
struct FITeUScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedPreferences.widgetKind, intent: ChooseGroupIntent.self, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("Между парами")
        .description("Твоя группа, нужная неделя. Следующий день — с 20:00.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
