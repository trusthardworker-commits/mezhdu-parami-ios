import SwiftUI
import WidgetKit
import PDFKit
import Combine
import UIKit

@main
struct FITeUScheduleApp: App {
    var body: some Scene { WindowGroup { ScheduleRootView() } }
}

private enum Palette {
    static let ink = Color(red: 0.10, green: 0.17, blue: 0.16)
    static let green = Color(red: 0.16, green: 0.38, blue: 0.29)
    static let paper = Color(red: 0.95, green: 0.95, blue: 0.91)
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.55)
}

struct ScheduleRootView: View {
    @AppStorage(SharedPreferences.groupKey, store: SharedPreferences.defaults) private var groupName = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var database: ScheduleDatabase?
    @State private var failed = false
    @State private var now = Date()
    @State private var selectedDate: Date?
    @State private var showGroups = false
    @State private var showInfo = false
    @State private var document: SourceDocument?
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let database {
                    if database.group(named: groupName) == nil {
                        GroupPicker(database: database) { choose($0) }
                    } else {
                        schedule(database)
                    }
                } else if failed {
                    ContentUnavailableView("Расписание не открылось", systemImage: "doc.badge.ellipsis",
                                           description: Text("Не удалось прочитать встроенные данные. Попробуйте переустановить приложение."))
                } else { ProgressView("Открываем расписание") }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Palette.green)
        .task {
            do { database = try ScheduleDatabase.load() } catch { failed = true }
        }
        .onReceive(timer) { value in now = value }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                WidgetCenter.shared.reloadTimelines(ofKind: SharedPreferences.widgetKind)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: SharedPreferences.widgetKind)
        }
        .onOpenURL { url in
            guard url.scheme == "fiteuschedule" else { return }
            if let name = ScheduleLink.group(from: url), let group = database?.group(named: name) {
                groupName = group.id
            }
            now = Date()
            selectedDate = nil
        }
        .sheet(isPresented: $showGroups) {
            if let database {
                NavigationStack {
                    GroupPicker(database: database) { choose($0); showGroups = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { showGroups = false } } }
                }
            }
        }
        .sheet(isPresented: $showInfo) { information }
        .sheet(item: $document) { source in
            NavigationStack {
                PDFSourceView(name: source.name, page: source.page)
                    .navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { document = nil } } }
            }
        }
    }

    private func choose(_ group: StudentGroup) {
        groupName = group.id
        selectedDate = nil
        WidgetCenter.shared.reloadTimelines(ofKind: SharedPreferences.widgetKind)
    }

    private func schedule(_ database: ScheduleDatabase) -> some View {
        let engine = ScheduleEngine(database: database)
        let widgetDay = engine.day(for: engine.displayDate(at: now), groupName: groupName)
        let day = engine.day(for: selectedDate ?? widgetDay.date, groupName: groupName)
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("МЕЖДУ ПАРАМИ").font(.caption2.weight(.heavy)).tracking(2.2).foregroundStyle(Palette.green)
                        Text("Твоё расписание").font(.system(.title, design: .rounded, weight: .bold))
                    }
                    Spacer()
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle").font(.title2).padding(8)
                    }.accessibilityLabel("О приложении и виджете")
                }
                HStack {
                    Button { showGroups = true } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "person.2.fill")
                            Text(groupName).fontWeight(.bold)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.white, in: Capsule())
                    }.accessibilityLabel("Выбрать группу. Сейчас \(groupName)")
                    Spacer()
                    Text("ФИТЭУ\nОсень 2026").font(.caption).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("ПРЕВЬЮ ВИДЖЕТА", systemImage: "square.grid.2x2.fill").font(.caption2.weight(.bold)).tracking(1)
                        Spacer()
                        Text("20:00 → 20:00").font(.caption.monospacedDigit())
                    }.foregroundStyle(Palette.lime)
                    Text(RussianDate.string(widgetDay.date)).font(.system(.title2, design: .rounded, weight: .bold))
                    if let week = widgetDay.week {
                        Label(week.title, systemImage: week.symbol).font(.subheadline).foregroundStyle(Palette.lime)
                    }
                    if widgetDay.lessons.isEmpty {
                        Text(widgetDay.availability.message).font(.subheadline).padding(.vertical, 6)
                    } else {
                        ForEach(widgetDay.lessons.prefix(3)) { lesson in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(lesson.period == 0 ? "•" : "\(lesson.period)").font(.headline.monospacedDigit()).foregroundStyle(Palette.lime).frame(width: 20)
                                Text(lesson.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            }
                        }
                        if widgetDay.lessons.count > 3 { Text("Ещё занятий: \(widgetDay.lessons.count - 3)").font(.caption).foregroundStyle(Palette.lime) }
                    }
                    Divider().overlay(.white.opacity(0.18))
                    Text("Следующая смена — \(RussianDate.string(engine.nextSwitch(after: now), format: "d MMM, HH:mm"))")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                    Text("На экране «Домой» выберите \(groupName) через «Изменить виджет».")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                .padding(22).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 28))

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("По дням").font(.title2.bold())
                        Spacer()
                        if selectedDate != nil { Button("К виджету") { selectedDate = nil }.font(.subheadline) }
                        DatePicker("Выбрать дату", selection: Binding(get: { day.date }, set: { selectedDate = $0 }), displayedComponents: .date)
                            .labelsHidden().fixedSize()
                    }
                    weekStrip(engine: engine, selected: day.date)
                    HStack {
                        Text(RussianDate.string(day.date, format: "d MMMM, EEEE")).font(.headline)
                        Spacer()
                        if let week = day.week {
                            Label(week == .upper ? "Верхняя" : "Нижняя", systemImage: week.symbol)
                                .font(.caption.weight(.semibold)).foregroundStyle(Palette.green)
                        }
                    }
                    if let warning = day.group?.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if day.lessons.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: day.availability == .ready ? "cup.and.saucer" : "calendar.badge.exclamationmark")
                                .font(.largeTitle).foregroundStyle(Palette.green)
                            Text(day.availability.message).font(.headline).multilineTextAlignment(.center)
                            Text(day.availability == .ready ? "Этот день свободен в загруженной таблице." : "Откройте исходный PDF, чтобы проверить период действия.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(30).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        ForEach(day.lessons) { lesson in
                            HStack(alignment: .top, spacing: 16) {
                                VStack(spacing: 2) {
                                    Text(lesson.period == 0 ? "•" : "\(lesson.period)").font(.system(.title2, design: .rounded, weight: .bold))
                                    Text(lesson.period == 0 ? "день" : "пара").font(.caption2)
                                }.foregroundStyle(Palette.green).frame(width: 38).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(lesson.title).font(.headline)
                                    Text(lesson.details).font(.subheadline).foregroundStyle(.secondary)
                                    if lesson.onlyDates == nil {
                                        Text(lesson.week.title).font(.caption2.weight(.medium)).foregroundStyle(Palette.green)
                                    } else {
                                        Text("Занятие на конкретную дату").font(.caption2).foregroundStyle(Palette.green)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Номера пар — из PDF. Общее время звонков в документе не указано.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { document = SourceDocument(name: "timetable", title: "Исходное расписание", page: (day.group?.sourcePage ?? 1) - 1) } label: {
                        Label("Проверить исходное расписание", systemImage: "doc.text.magnifyingglass")
                    }.font(.subheadline)
                    Button { document = SourceDocument(name: "academic-weeks", title: "Календарь недель", page: 0) } label: {
                        Label("Календарь верхних и нижних недель", systemImage: "calendar")
                    }.font(.subheadline)
                }
            }.padding(22)
        }.background(Palette.paper).foregroundStyle(Palette.ink)
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .preferredColorScheme(.light)
    }

    private func weekStrip(engine: ScheduleEngine, selected: Date) -> some View {
        let offset = (engine.calendar.component(.weekday, from: selected) + 5) % 7
        let monday = engine.calendar.date(byAdding: .day, value: -offset, to: selected)!
        return HStack(spacing: 5) {
            ForEach(0..<7) { index in
                let date = engine.calendar.date(byAdding: .day, value: index, to: monday)!
                let active = engine.calendar.isDate(date, inSameDayAs: selected)
                Button { selectedDate = date } label: {
                    VStack(spacing: 9) {
                        Text(RussianDate.string(date, format: "EE")).font(.caption)
                        Text(RussianDate.string(date, format: "d")).font(.headline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(active ? Palette.green : .white, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(active ? .white : Palette.ink)
                }.accessibilityLabel(RussianDate.string(date))
                    .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
    }

    private var information: some View {
        NavigationStack {
            List {
                Section("Виджет на главном экране") {
                    Text("1. Откройте приложение хотя бы один раз.\n2. Удерживайте свободное место на экране iPhone.\n3. Добавьте виджет «Между парами».\n4. Удерживайте добавленный виджет → «Изменить виджет» → «Группа».\n5. Выберите свою группу из списка.")
                    Text("Группа в приложении и в каждом виджете выбирается отдельно. Можно поставить несколько виджетов для разных групп. Нажатие на виджет открывает его группу в приложении.")
                    Text("Большой виджет показывает весь день, средний — до трёх занятий, маленький — до двух. Если пары не поместились, виден их остаток. Нажмите на виджет, чтобы открыть приложение.")
                }
                Section("Смена дня в 20:00") {
                    Text("С 20:00 показывается завтрашняя дата. В полночь расписание остаётся тем же и меняется только следующим вечером. Используется местный часовой пояс iPhone.")
                    Text("Верхняя или нижняя неделя определяется для отображаемой даты, включая переход с воскресенья на понедельник. Даты смены подготовлены заранее; фактическое обновление экрана планирует iOS.")
                    Text("После изменения часового пояса откройте приложение, чтобы сразу перепланировать виджет.")
                }
                Section("Данные") {
                    Text("21 группа · загружено 10 ноября 2026. Приложение работает без интернета. Расписание перенесено из предоставленных сканов; сокращения сохранены. Сверяйте важные занятия с оригиналом.")
                    Text("Период расписания ограничен осенним семестром. Календарь недель сам по себе не означает, что осенние занятия продолжаются весной. Отмены, праздники и изменения, которых нет в PDF, автоматически не добавляются.")
                    Text("У 24ГУб и 23Мб дата окончания в заголовке указана с 2025 годом. Их шаблон показан с предупреждением до 29.12.2026 — технической границы осеннего набора, а не подтверждённого срока этих групп.")
                }
            }
            .navigationTitle("Как это работает")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showInfo = false } } }
        }
    }
}

struct GroupPicker: View {
    let database: ScheduleDatabase
    let select: (StudentGroup) -> Void
    @State private var search = ""
    private var matches: [StudentGroup] {
        let query = ScheduleDatabase.normalize(search)
        return database.groups.filter { query.isEmpty || ScheduleDatabase.normalize($0.id).contains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 42)).foregroundStyle(Palette.green)
                Text("Своя группа.\nВесь день под рукой.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Выбери группу для приложения. На экране «Домой» группу можно выбрать через «Изменить виджет».").foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 32)
            TextField("Например, 23ПИжб", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 24)
                .accessibilityLabel("Поиск группы")
            if matches.isEmpty {
                ContentUnavailableView("Группа не найдена", systemImage: "magnifyingglass",
                                       description: Text("Введите обозначение кириллицей. Доступны все 21 группа из загруженного PDF."))
            } else {
                List(matches) { group in
                    Button { select(group) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.id).font(.headline).foregroundStyle(Palette.ink)
                                Text("ФИТЭУ · осень 2026").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Palette.green)
                        }.padding(.vertical, 7)
                    }
                }.scrollContentBackground(.hidden)
            }
        }.background(Palette.paper).preferredColorScheme(.light)
    }
}

struct SourceDocument: Identifiable {
    var id: String { name }
    let name: String
    let title: String
    let page: Int
}

struct PDFSourceView: UIViewRepresentable {
    let name: String
    let page: Int
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        if let url = Bundle.main.url(forResource: name, withExtension: "pdf") {
            view.document = PDFDocument(url: url)
            if let target = view.document?.page(at: page) { view.go(to: target) }
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
