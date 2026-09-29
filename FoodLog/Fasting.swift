import CoreData
import SwiftUI

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
}

struct FastJournalCard: View {
    @ObservedObject var session: FastSession
    @Environment(\.managedObjectContext) private var context
    @State private var message: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 10) {
                Label("Current fast", systemImage: "clock")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(FoodTheme.ink)
                if let start = session.startDate {
                    Text(FastTimeText.duration(timeline.date.timeIntervalSince(start)))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(FoodTheme.ink)
                        .accessibilityIdentifier("fast-elapsed")
                    Text("Started \(start.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(FoodTheme.secondaryText)
                    if let target = session.targetSeconds, target > 0 {
                        ProgressView(value: min(max(timeline.date.timeIntervalSince(start) / target, 0), 1))
                            .accessibilityLabel("Target progress")
                        Text("Optional target: \(FastTimeText.duration(target))")
                            .font(.subheadline)
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                }
                Button("End fast") {
                    do {
                        try FastingStore.end(session, at: Date())
                        try context.save()
                    } catch {
                        context.rollback()
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("end-fast")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .foodPanel(cornerRadius: 18)
        }
        .alert("Fast could not be updated", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}

struct FastSessionsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)])
    private var sessions: FetchedResults<FastSession>
    @State private var editingSession: FastSession?
    @State private var adding = false
    @State private var deletingSession: FastSession?
    @State private var message: String?

    var body: some View {
        List {
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.largeTitle)
                    Text("No fasts recorded").font(.headline)
                    Text("Add one whenever you want to keep a record.").font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(FoodTheme.secondaryText)
            }
            ForEach(sessions, id: \.objectID) { session in
                Button { editingSession = session } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.startDate?.formatted(date: .abbreviated, time: .shortened) ?? "Start time unavailable")
                            .font(.headline)
                        Text(session.endDate.map { "Ended \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Active")
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
        .navigationTitle("Fasts")
        .toolbar { Button("Add", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { FastSessionEditor(session: nil) }
        .sheet(item: $editingSession) { FastSessionEditor(session: $0) }
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

struct FastTargetSettingsView: View {
    @AppStorage(FastTargetPreference.key) private var hours = 0.0
    @State private var customHours = ""

    var body: some View {
        Form {
            Section {
                Picker("Default target", selection: $hours) {
                    Text("No target").tag(0.0)
                    Text("12 hours").tag(12.0)
                    Text("14 hours").tag(14.0)
                    Text("16 hours").tag(16.0)
                    if hours > 0 && ![12.0, 14.0, 16.0].contains(hours) {
                        Text("\(hours.formatted()) hours").tag(hours)
                    }
                }
                HStack {
                    TextField("Custom hours", text: $customHours).keyboardType(.decimalPad)
                    Button("Use") {
                        if let value = Double(customHours), value > 0, value.isFinite { hours = value }
                    }
                }
            } footer: {
                Text("A target is optional and can be changed for each fast.")
            }
        }
        .navigationTitle("Fasting target")
    }
}
