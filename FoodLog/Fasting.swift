import CoreData
import SwiftUI
import UIKit

struct OvernightMeal {
    let date: Date
    let mealType: String
}

struct OvernightFastEstimate: Identifiable, Equatable {
    let day: Date
    let startDate: Date
    let endDate: Date
    var id: Date { day }
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}

struct OvernightFastSummary {
    let count: Int
    let averageDuration: TimeInterval
    let shortestDuration: TimeInterval
    let longestDuration: TimeInterval
}

struct FastingCalendarMonth {
    let start: Date
    let cells: [Date?]

    init(containing date: Date, calendar: Calendar) {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        self.start = start
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start) ?? 1..<2
        var cells = Array<Date?>(repeating: nil, count: offset)
        for day in days {
            cells.append(calendar.date(byAdding: .day, value: day - days.lowerBound, to: start)
                .map { calendar.startOfDay(for: $0) })
        }
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7))
        self.cells = cells
    }

    // A fixed scale keeps a duration's shade consistent across months.
    static func intensity(for duration: TimeInterval) -> Double {
        guard duration.isFinite else { return 0 }
        return min(1, max(0, duration / (36 * 3_600)))
    }

    static func opacity(for duration: TimeInterval) -> Double {
        0.08 + 0.92 * intensity(for: duration)
    }

    static func usesLightText(accent: [Double], surface: [Double], opacity: Double) -> Bool {
        let channels = zip(accent, surface).map { foreground, background in
            let channel = foreground * opacity + background * (1 - opacity)
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        guard channels.count == 3 else { return false }
        let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        return luminance < 0.179
    }
}

enum FastingGoalPreference {
    static let hoursKey = "fastingGoalHours"
    static let enabledKey = "showFastingGoal"
    static let defaultHours = 14.0

    static func isMet(by duration: TimeInterval, hours: Double, enabled: Bool) -> Bool {
        enabled && hours.isFinite && hours > 0 && duration.isFinite && duration >= hours * 3_600
    }
}

enum OvernightFasting {
    static func summary(of estimates: [OvernightFastEstimate]) -> OvernightFastSummary? {
        let durations = estimates.map(\.duration)
        guard let shortest = durations.min(), let longest = durations.max() else { return nil }
        return OvernightFastSummary(count: durations.count,
                                    averageDuration: durations.reduce(0, +) / Double(durations.count),
                                    shortestDuration: shortest, longestDuration: longest)
    }

    static func estimates(from meals: [OvernightMeal], calendar: Calendar = .current) -> [OvernightFastEstimate] {
        let mealsByDay = Dictionary(grouping: meals.filter { $0.mealType != "Drink" }) {
            calendar.startOfDay(for: $0.date)
        }
        return mealsByDay.compactMap { day, meals in
            guard let previousDate = calendar.date(byAdding: .day, value: -1, to: day),
                  let start = mealsByDay[calendar.startOfDay(for: previousDate)]?.map(\.date).max(),
                  let end = meals.map(\.date).min(), end > start else { return nil }
            return OvernightFastEstimate(day: day, startDate: start, endDate: end)
        }
        .sorted { $0.endDate > $1.endDate }
    }

    static func estimates(from entries: [FoodEntry], calendar: Calendar = .current) -> [OvernightFastEstimate] {
        estimates(from: entries.compactMap { entry in
            entry.date.map { OvernightMeal(date: $0, mealType: entry.wrappedMealType) }
        }, calendar: calendar)
    }
}

struct OvernightFastCard: View {
    let estimate: OvernightFastEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .accessibilityHidden(true)
                Text(FastTimeText.duration(estimate.duration))
                    .accessibilityIdentifier("overnight-duration")
            }
            .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("Last meal: \(estimate.startDate.formatted(date: .abbreviated, time: .shortened))")
            Text("First meal: \(estimate.endDate.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(FoodTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foodPanel(cornerRadius: 18)
    }
}

private struct FastingMonthCalendar: View {
    @Environment(\.foodAccentColor) private var accentColor
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(FastingGoalPreference.hoursKey) private var goalHours = FastingGoalPreference.defaultHours
    @AppStorage(FastingGoalPreference.enabledKey) private var goalEnabled = true
    let estimates: [OvernightFastEstimate]
    let calendar: Calendar
    @Binding var displayedMonth: Date
    @Binding var selectedEstimate: OvernightFastEstimate?

    private var month: FastingCalendarMonth {
        FastingCalendarMonth(containing: displayedMonth, calendar: calendar)
    }

    private var estimatesByDay: [Date: OvernightFastEstimate] {
        Dictionary(estimates.map { (calendar.startOfDay(for: $0.endDate), $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        return formatter.string(from: month.start)
    }

    private func shade(_ intensity: Double) -> Color {
        accentColor.opacity(0.08 + 0.92 * intensity)
    }

    private func textColor(for opacity: Double) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        func channels(_ color: UIColor) -> [Double] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [Double(red), Double(green), Double(blue)]
        }
        let light = FastingCalendarMonth.usesLightText(accent: channels(UIColor(accentColor)),
                                                      surface: channels(.secondarySystemGroupedBackground),
                                                      opacity: opacity)
        return light ? .white : .black
    }

    private func moveMonth(by offset: Int) {
        if let date = calendar.date(byAdding: .month, value: offset, to: month.start) {
            displayedMonth = date
        }
    }

    var body: some View {
        let month = month
        let estimatesByDay = estimatesByDay
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Text(monthTitle)
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Button { moveMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    let index = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.shortStandaloneWeekdaySymbols[index])
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(FoodTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(calendar.standaloneWeekdaySymbols[index])
                }
                ForEach(month.cells.indices, id: \.self) { index in
                    if let day = month.cells[index] {
                        dayCell(day, estimate: estimatesByDay[day])
                    } else {
                        Color.clear.frame(minHeight: 44).accessibilityHidden(true)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    durationLegend
                    Spacer(minLength: 0)
                    if goalEnabled { goalLegend }
                }
                VStack(alignment: .leading, spacing: 8) {
                    durationLegend
                    if goalEnabled { goalLegend }
                }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(FoodTheme.secondaryText)
        }
        .foregroundStyle(FoodTheme.ink)
        .padding(16)
        .foodPanel(cornerRadius: 24)
        .accessibilityIdentifier("fasting-month-calendar")
    }

    private var durationLegend: some View {
        HStack(spacing: 4) {
            Text("Shorter")
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(shade(Double(index) / 4))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            Text("Longer")
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More opaque dates indicate longer fasts")
    }

    private var goalLegend: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(FoodTheme.fastGoalBorder, lineWidth: 2)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(">\(FastTimeText.compactDuration(goalHours * 3_600)) goal")
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A silver border marks fasts of at least \(FastTimeText.compactDuration(goalHours * 3_600))")
    }

    private func dayCell(_ day: Date, estimate: OvernightFastEstimate?) -> some View {
        let opacity = estimate.map { FastingCalendarMonth.opacity(for: $0.duration) } ?? 0
        let meetsGoal = estimate.map {
            FastingGoalPreference.isMet(by: $0.duration, hours: goalHours, enabled: goalEnabled)
        } ?? false
        let foreground = estimate == nil ? FoodTheme.ink : textColor(for: opacity)
        return Button {
            selectedEstimate = estimate
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if estimate != nil {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accentColor.opacity(opacity))
                    }
                }
                .overlay {
                    if meetsGoal {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(FoodTheme.fastGoalBorder, lineWidth: 2)
                    }
                    if calendar.isDateInToday(day) {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(foreground, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .padding(meetsGoal ? 4 : 0)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(estimate == nil)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(estimate.map {
            FastTimeText.duration($0.duration) + (meetsGoal ? ", Goal met" : "")
        } ?? "No fast")
        .accessibilityHint(estimate == nil ? "" : "Shows meal times")
    }
}

enum FastingError: LocalizedError, Equatable {
    case datesOutOfOrder
    case overlapsExisting
    case missingStart

    var errorDescription: String? {
        switch self {
        case .datesOutOfOrder: return "The end time must be after the start time."
        case .overlapsExisting: return "These times overlap another fast. Adjust the times or edit that record."
        case .missingStart: return "Choose a start time."
        }
    }
}

enum FastingStore {
    static func sessions(in context: NSManagedObjectContext) throws -> [FastSession] {
        let request: NSFetchRequest<FastSession> = FastSession.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        return try context.fetch(request)
    }

    static func active(in context: NSManagedObjectContext) throws -> FastSession? {
        try sessions(in: context).first { $0.endDate == nil }
    }

    static func validate(
        start: Date,
        end: Date?,
        excluding excluded: FastSession? = nil,
        in context: NSManagedObjectContext
    ) throws {
        if let end, end <= start { throw FastingError.datesOutOfOrder }
        for session in try sessions(in: context) where session != excluded {
            guard let otherStart = session.startDate else { continue }
            if start < (session.endDate ?? .distantFuture) && otherStart < (end ?? .distantFuture) {
                throw FastingError.overlapsExisting
            }
        }
    }

    @discardableResult
    static func create(
        start: Date,
        end: Date? = nil,
        target: TimeInterval? = nil,
        startEntryID: UUID? = nil,
        endEntryID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> FastSession {
        try validate(start: start, end: end, in: context)
        let session = FastSession(context: context)
        session.id = UUID()
        session.createdAt = Date()
        session.startDate = start
        session.endDate = end
        session.startEntryID = startEntryID
        session.endEntryID = end == nil ? nil : endEntryID
        session.targetSeconds = target.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        return session
    }

    static func update(
        _ session: FastSession,
        start: Date,
        end: Date?,
        target: TimeInterval?,
        startEntryID: UUID?,
        endEntryID: UUID?,
        in context: NSManagedObjectContext
    ) throws {
        try validate(start: start, end: end, excluding: session, in: context)
        session.startDate = start
        session.endDate = end
        session.startEntryID = startEntryID
        session.endEntryID = end == nil ? nil : endEntryID
        session.targetSeconds = target.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    static func end(_ session: FastSession, at date: Date, with entryID: UUID? = nil) throws {
        guard let start = session.startDate else { throw FastingError.missingStart }
        guard date > start else { throw FastingError.datesOutOfOrder }
        session.endDate = date
        session.endEntryID = entryID
    }

    // Linked dates follow the food entry when possible. If moving the entry would
    // invalidate a session, retain the recorded times and detach only that link.
    static func entryDateChanged(_ entry: FoodEntry, in context: NSManagedObjectContext) throws {
        guard let id = entry.id, let date = entry.date else { return }
        for session in try sessions(in: context) {
            if session.startEntryID == id {
                do {
                    try validate(start: date, end: session.endDate, excluding: session, in: context)
                    session.startDate = date
                } catch {
                    session.startEntryID = nil
                }
            }
            if session.endEntryID == id, let start = session.startDate {
                do {
                    try validate(start: start, end: date, excluding: session, in: context)
                    session.endDate = date
                } catch {
                    session.endEntryID = nil
                }
            }
        }
    }

    static func detachEntry(_ entry: FoodEntry, in context: NSManagedObjectContext) throws {
        guard let id = entry.id else { return }
        for session in try sessions(in: context) {
            if session.startEntryID == id { session.startEntryID = nil }
            if session.endEntryID == id { session.endEntryID = nil }
        }
    }
}

extension FastSession {
    var targetSeconds: TimeInterval? {
        get { (value(forKey: "targetDuration") as? NSNumber)?.doubleValue }
        set { setValue(newValue.map(NSNumber.init(value:)), forKey: "targetDuration") }
    }

    var duration: TimeInterval? {
        guard let startDate, let endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }
}

enum FastTargetPreference {
    static let key = "defaultFastTargetHours"
    static func seconds(for hours: Double) -> TimeInterval? {
        hours > 0 && hours.isFinite ? hours * 3_600 : nil
    }
}

enum FastTimeText {
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

enum FastingHistory {
    static let pageSize = 30

    static func nextLimit(current: Int, total: Int) -> Int {
        min(max(0, total), max(0, current) + pageSize)
    }
}

private struct FastHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let date: String
    let duration: TimeInterval
    let detail: String
    var isSummary = false

    private var durationText: String {
        FastTimeText.compactDuration(duration)
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            Text(date).frame(width: 64, alignment: .leading)
            Text(durationText).frame(width: 76, alignment: .leading)
            Spacer(minLength: 0)
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(FoodTheme.secondaryText)
                .fixedSize()
        }
    }

    private var expandedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date)
                Spacer()
                Text(durationText)
            }
            Text(detail)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(FoodTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                expandedRow
            } else {
                ViewThatFits(in: .horizontal) {
                    compactRow
                    expandedRow
                }
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(isSummary ? .bold : .medium))
        .foregroundStyle(FoodTheme.ink)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct FastSessionsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)])
    private var sessions: FetchedResults<FastSession>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var entries: FetchedResults<FoodEntry>
    @State private var editingSession: FastSession?
    @State private var deletingSession: FastSession?
    @State private var message: String?
    @State private var calendar = Calendar.current
    @State private var displayedMonth = Date()
    @State private var selectedEstimate: OvernightFastEstimate?
    @State private var historyLimit = FastingHistory.pageSize

    private var estimates: [OvernightFastEstimate] {
        OvernightFasting.estimates(from: Array(entries), calendar: calendar)
    }

    private var visibleEstimates: [OvernightFastEstimate] {
        Array(estimates.prefix(historyLimit))
    }

    var body: some View {
        List {
            FastingMonthCalendar(estimates: estimates, calendar: calendar,
                                 displayedMonth: $displayedMonth, selectedEstimate: $selectedEstimate)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 12, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if estimates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hourglass").font(.largeTitle)
                    Text("No fasting times yet").font(.headline)
                    Text("Log meals on consecutive days to see your fasting times.").font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(FoodTheme.secondaryText)
            }
            Section {
                if let summary = OvernightFasting.summary(of: visibleEstimates) {
                    FastHistoryRow(date: "Avg", duration: summary.averageDuration,
                                   detail: "\(summary.count) \(summary.count == 1 ? "fast" : "fasts")", isSummary: true)
                        .padding(.vertical, 3)
                        .background(FoodTheme.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(FoodTheme.ink.opacity(0.2), lineWidth: 1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Average fast, \(FastTimeText.duration(summary.averageDuration)), \(summary.count) fasts")
                        .accessibilityIdentifier("fasting-history-average")
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(visibleEstimates) { estimate in
                    Button { selectedEstimate = estimate } label: {
                        FastHistoryRow(date: estimate.endDate.formatted(.dateTime.month(.abbreviated).day()),
                                       duration: estimate.duration,
                                       detail: "\(estimate.startDate.formatted(date: .omitted, time: .shortened)) → \(estimate.endDate.formatted(date: .omitted, time: .shortened))")
                    }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(estimate.endDate.formatted(date: .complete, time: .omitted)), \(FastTimeText.duration(estimate.duration)), last meal \(estimate.startDate.formatted(date: .abbreviated, time: .shortened)), first meal \(estimate.endDate.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityHint("Shows meal times")
                        .accessibilityIdentifier("fasting-history-\(estimate.day.timeIntervalSince1970)")
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if historyLimit < estimates.count {
                    Button("View more") {
                        historyLimit = FastingHistory.nextLimit(current: historyLimit, total: estimates.count)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Shows up to 30 more fasts")
                    .accessibilityIdentifier("fasting-history-more")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } footer: {
                Text("Calculated between meals on consecutive days. Drinks are excluded.")
            }
            if !sessions.isEmpty {
                Section("Previously saved fasting records") {
                    ForEach(sessions, id: \.objectID) { session in
                        Button { editingSession = session } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.startDate?.formatted(date: .abbreviated, time: .shortened) ?? "Start time unavailable")
                                    .font(.headline)
                                Text(session.endDate.map { "Ended \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No end recorded")
                                    .font(.subheadline)
                                if let duration = session.duration {
                                    Text(FastTimeText.duration(duration)).font(.subheadline)
                                }
                            }
                            .foregroundStyle(FoodTheme.ink)
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingSession = session }
                            Button("Delete", systemImage: "trash", role: .destructive) { deletingSession = session }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(FoodTheme.background)
        .navigationTitle("Fasts")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            FoodPageHeader("Fasts", identifier: "fasts-title")
                .background(FoodTheme.background)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            calendar = .current
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { calendar = .current }
        }
        .sheet(item: $editingSession) { FastSessionEditor(session: $0) }
        .sheet(item: $selectedEstimate) { estimate in
            NavigationStack {
                ScrollView {
                    OvernightFastCard(estimate: estimate).padding()
                }
                .background(FoodTheme.background)
                .navigationTitle(estimate.endDate.formatted(date: .abbreviated, time: .omitted))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selectedEstimate = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Delete this fast?", isPresented: Binding(
            get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let deletingSession {
                    context.delete(deletingSession)
                    do { try context.save() } catch { context.rollback(); message = error.localizedDescription }
                }
                deletingSession = nil
            }
            Button("Cancel", role: .cancel) { deletingSession = nil }
        } message: { Text("This removes only the fasting record.") }
        .alert("Fast could not be deleted", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}

struct FastSessionEditor: View {
    private enum DateField: String, Identifiable {
        case start, end
        var id: String { rawValue }
        var title: String { self == .start ? "Start time" : "End time" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var entries: FetchedResults<FoodEntry>
    @AppStorage(FastTargetPreference.key) private var defaultTargetHours = 0.0

    let session: FastSession?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEnd: Bool
    @State private var startEntryID: UUID?
    @State private var endEntryID: UUID?
    @State private var targetHours: Double
    @State private var customTarget = ""
    @State private var message: String?
    @State private var editingDateField: DateField?

    init(session: FastSession?) {
        self.session = session
        _startDate = State(initialValue: session?.startDate ?? Date().addingTimeInterval(-12 * 3_600))
        _endDate = State(initialValue: session?.endDate ?? Date())
        _hasEnd = State(initialValue: session == nil || session?.endDate != nil)
        _startEntryID = State(initialValue: session?.startEntryID)
        _endEntryID = State(initialValue: session?.endEntryID)
        _targetHours = State(initialValue: (session?.targetSeconds ?? 0) / 3_600)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start") {
                    entryPicker("Food entry", selection: Binding(
                        get: { startEntryID },
                        set: { id in
                            if let entry = entries.first(where: { $0.id == id }), id != nil {
                                startDate = entry.wrappedDate
                            }
                            startEntryID = id
                        }
                    ))
                    dateRow("Start time", date: startDate, identifier: "fast-start-time") {
                        editingDateField = .start
                    }
                }
                Section("End") {
                    Toggle("Has end time", isOn: $hasEnd)
                    if hasEnd {
                        entryPicker("Food entry", selection: Binding(
                            get: { endEntryID },
                            set: { id in
                                if let entry = entries.first(where: { $0.id == id }), id != nil {
                                    endDate = entry.wrappedDate
                                }
                                endEntryID = id
                            }
                        ))
                        dateRow("End time", date: endDate, identifier: "fast-end-time") {
                            editingDateField = .end
                        }
                    }
                }
                Section("Optional target") {
                    Picker("Target", selection: $targetHours) {
                        Text("None").tag(0.0)
                        Text("12 hours").tag(12.0)
                        Text("14 hours").tag(14.0)
                        Text("16 hours").tag(16.0)
                        if targetHours > 0 && ![12.0, 14.0, 16.0].contains(targetHours) {
                            Text("\(targetHours.formatted()) hours").tag(targetHours)
                        }
                    }
                    HStack {
                        TextField("Custom hours", text: $customTarget)
                            .keyboardType(.decimalPad)
                        Button("Use") {
                            if let hours = Double(customTarget), hours > 0, hours.isFinite { targetHours = hours }
                        }
                    }
                }
            }
            .navigationTitle(session == nil ? "Add fast" : "Edit fast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .onAppear {
            if session == nil { targetHours = defaultTargetHours }
        }
        .sheet(item: $editingDateField) { field in
            FoodLogDateTimeSheet(
                title: field.title,
                date: field == .start ? startDate : endDate
            ) { selectedDate in
                if field == .start {
                    startDate = selectedDate
                    startEntryID = nil
                } else {
                    endDate = selectedDate
                    endEntryID = nil
                }
            }
        }
        .alert("Fast could not be saved", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }

    private func entryPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Manual time").tag(Optional<UUID>.none)
            ForEach(entries.filter { $0.id != nil }, id: \.objectID) { entry in
                Text("\(entry.wrappedFood) · \(entry.wrappedDate.formatted(date: .abbreviated, time: .shortened))")
                    .tag(entry.id)
            }
        }
    }

    private func dateRow(_ title: String, date: Date, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(FoodTheme.secondaryText)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
            .foregroundStyle(FoodTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func save() {
        do {
            let end = hasEnd ? endDate : nil
            let target = FastTargetPreference.seconds(for: targetHours)
            if let session {
                try FastingStore.update(session, start: startDate, end: end, target: target,
                                        startEntryID: startEntryID, endEntryID: hasEnd ? endEntryID : nil, in: context)
            } else {
                try FastingStore.create(start: startDate, end: end, target: target,
                                        startEntryID: startEntryID, endEntryID: hasEnd ? endEntryID : nil, in: context)
            }
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            message = error.localizedDescription
        }
    }
}
