import CoreData
import SwiftUI
import UIKit

struct BrowseView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)],
        animation: .default
    ) private var entries: FetchedResults<FoodEntry>

    @State private var query = ""
    @State private var mealFilter = "All"
    @State private var selectedEntry: FoodEntry?

    private var filteredEntries: [FoodEntry] {
        entries.filter { entry in
            let matchesMeal = mealFilter == "All" || entry.wrappedMealType == mealFilter
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = trimmed.isEmpty
                || entry.wrappedFood.localizedCaseInsensitiveContains(trimmed)
                || entry.wrappedPlace.localizedCaseInsensitiveContains(trimmed)
                || entry.wrappedPeople.localizedCaseInsensitiveContains(trimmed)
                || entry.wrappedNote.localizedCaseInsensitiveContains(trimmed)
            return matchesMeal && matchesQuery
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(FoodTheme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(FoodTheme.secondaryText)
                TextField("Food, place, person, or note", text: $query)
                    .font(.system(.body, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(FoodTheme.secondaryText)
                    }
                }
            }
            .padding(13)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["All"] + FoodEntryEditor.mealTypes, id: \.self) { meal in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { mealFilter = meal }
                        } label: {
                            Text(meal)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(mealFilter == meal ? FoodTheme.onInk : FoodTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    mealFilter == meal ? FoodTheme.ink : FoodTheme.surface,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34, weight: .medium))
                    Text(entries.isEmpty ? "No entries yet" : "Nothing found")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
                .foregroundColor(FoodTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 15) {
                        ForEach(groupEntriesByDay(filteredEntries)) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(FoodLogFormatters.dayHeading.string(from: group.date))
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.secondaryText)

                                VStack(spacing: 0) {
                                    ForEach(Array(group.entries.enumerated()), id: \.element.objectID) { index, entry in
                                        EntryRow(entry: entry)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedEntry = entry }
                                            .contextMenu {
                                                Button { selectedEntry = entry } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    context.delete(entry)
                                                    try? context.save()
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        if index < group.entries.count - 1 {
                                            Divider().padding(.leading, 55)
                                        }
                                    }
                                }
                                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(FoodTheme.background)
        .fullScreenCover(item: $selectedEntry) { entry in
            FoodEntryEditor(entry: entry)
        }
    }
}

private enum PatternRange: Int, CaseIterable {
    case week = 7
    case month = 30
    case all = 0

    var label: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .all: return "All"
        }
    }
}

struct PatternsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)]
    ) private var entries: FetchedResults<FoodEntry>

    @State private var range: PatternRange = .week

    private var selectedEntries: [FoodEntry] {
        guard range.rawValue > 0,
              let start = Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date()))
        else { return Array(entries) }
        return entries.filter { $0.wrappedDate >= start }
    }

    private var daysRepresented: Int {
        Set(selectedEntries.map { Calendar.current.startOfDay(for: $0.wrappedDate) }).count
    }

    private var categoryCounts: [(String, Int)] {
        Dictionary(grouping: selectedEntries, by: \.wrappedMealType)
            .mapValues(\.count)
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }

    private var placeCounts: [(String, Int)] {
        frequency(of: selectedEntries.map(\.wrappedPlace).filter { !$0.isEmpty })
    }

    private var peopleCounts: [(String, Int)] {
        frequency(of: selectedEntries.map(\.wrappedPeople).filter { !$0.isEmpty })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Patterns")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(FoodTheme.ink)

                rangePicker
                summaryCards
                categoryBreakdown

                if !placeCounts.isEmpty {
                    frequencyCard(title: "PLACES", icon: "mappin.and.ellipse", items: placeCounts)
                }
                if !peopleCounts.isEmpty {
                    frequencyCard(title: "PEOPLE", icon: "person.2.fill", items: peopleCounts)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
    }

    private var rangePicker: some View {
        HStack(spacing: 5) {
            ForEach(PatternRange.allCases, id: \.rawValue) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { range = option }
                } label: {
                    Text(option.label)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(range == option ? FoodTheme.ink : FoodTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(range == option ? FoodTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(4)
        .background(FoodTheme.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            summaryCard(value: selectedEntries.count, label: "entries")
            summaryCard(value: daysRepresented, label: daysRepresented == 1 ? "day" : "days")
        }
    }

    private func summaryCard(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(FoodTheme.ink)
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(FoodTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MEAL CATEGORIES")
                .sectionLabel()

            if categoryCounts.isEmpty {
                Text("Log a meal to see its category here.")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
                    .padding(.vertical, 10)
            } else {
                let maximum = max(categoryCounts.first?.1 ?? 1, 1)
                ForEach(categoryCounts, id: \.0) { item in
                    VStack(spacing: 7) {
                        HStack {
                            Text("\(FoodTheme.emoji(for: item.0))  \(item.0)")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(item.1)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundColor(FoodTheme.color(for: item.0))
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(FoodTheme.field)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(FoodTheme.color(for: item.0))
                                        .frame(width: proxy.size.width * CGFloat(item.1) / CGFloat(maximum))
                                }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(17)
        .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func frequencyCard(title: String, icon: String, items: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon)
                .sectionLabel()
            ForEach(Array(items.prefix(5)), id: \.0) { item in
                HStack {
                    Text(item.0)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.1)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundColor(FoodTheme.secondaryText)
                }
            }
        }
        .padding(17)
        .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func frequency(of values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }
}

struct FoodLogSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)])
    private var entries: FetchedResults<FoodEntry>

    @AppStorage("foodLogAppearance") private var appearance = 0
    @AppStorage("showMealLabels") private var showMealLabels = true
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var confirmErase = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(FoodTheme.ink)

                settingsSection("APPEARANCE") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)

                    Divider()

                    Toggle("Show meal labels in journal", isOn: $showMealLabels)
                        .font(.system(.body, design: .rounded).weight(.medium))
                }

                settingsSection("YOUR DATA") {
                    Button(action: exportCSV) {
                        settingsRow(icon: "square.and.arrow.up", title: "Export CSV", detail: "\(entries.count) entries")
                    }
                    .disabled(entries.isEmpty)

                    Divider()

                    Button { confirmErase = true } label: {
                        settingsRow(icon: "trash", title: "Erase all entries", detail: nil, destructive: true)
                    }
                    .disabled(entries.isEmpty)
                }

                settingsSection("ABOUT") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FoodLog 1.0")
                            .font(.system(.body, design: .rounded).weight(.bold))
                        Text("Adapted from Dime's open-source SwiftUI code and interaction ideas under GPLv3.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(FoodTheme.secondaryText)
                        Link("View Dime on GitHub", destination: URL(string: "https://github.com/rafsoh/dimeApp")!)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
        .alert("Erase every entry?", isPresented: $confirmErase) {
            Button("Erase all", role: .destructive, action: eraseAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Export first if you want a backup. This cannot be undone.")
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            VStack(spacing: 12) { content() }
                .padding(16)
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func settingsRow(icon: String, title: String, detail: String?, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(FoodTheme.secondaryText)
        }
        .foregroundColor(destructive ? .red : FoodTheme.ink)
    }

    private func exportCSV() {
        exportURL = CSVExporter.makeFile(from: Array(entries))
        showingShareSheet = exportURL != nil
    }

    private func eraseAll() {
        entries.forEach { context.delete($0) }
        try? context.save()
    }
}

private enum CSVExporter {
    static func makeFile(from entries: [FoodEntry]) -> URL? {
        var csv = "food,date,time,meal,place,people,note\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for entry in entries {
            let fields = [
                entry.wrappedFood,
                dateFormatter.string(from: entry.wrappedDate),
                timeFormatter.string(from: entry.wrappedDate),
                entry.wrappedMealType,
                entry.wrappedPlace,
                entry.wrappedPeople,
                entry.wrappedNote
            ].map(escape)
            csv += fields.joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FoodLog.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
