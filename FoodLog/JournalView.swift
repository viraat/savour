import CoreData
import SwiftUI
import UIKit

struct JournalView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)],
        animation: .default
    ) private var entries: FetchedResults<FoodEntry>

    @State private var selectedEntry: FoodEntry?
    @State private var entryToDelete: FoodEntry?
    @State private var query = ""
    @State private var showingSearch = false
    @FocusState private var searchFocused: Bool
    @State private var mealFilter = "All"
    @State private var fastingMessage: String?
    @State private var calendar = Calendar.current

    private var thisWeek: [FoodEntry] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return Array(entries)
        }
        return entries.filter { interval.contains($0.wrappedDate) }
    }

    private var filteredEntries: [FoodEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let matchesMeal = mealFilter == "All" || entry.wrappedMealType == mealFilter
            let matchesQuery = trimmedQuery.isEmpty
                || entry.wrappedFood.localizedCaseInsensitiveContains(trimmedQuery)
                || entry.wrappedPlace.localizedCaseInsensitiveContains(trimmedQuery)
                || entry.companionNames.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
                || entry.wrappedNote.localizedCaseInsensitiveContains(trimmedQuery)
            return matchesMeal && matchesQuery
        }
    }

    private var isFiltering: Bool {
        mealFilter != "All" || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mealCounts: [(String, Int)] {
        let counts = Dictionary(grouping: thisWeek, by: \.wrappedMealType).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !isFiltering {
                    weeklySummary
                }

                if entries.isEmpty {
                    emptyState
                } else if filteredEntries.isEmpty {
                    noResultsState
                } else {
                    HStack {
                        Text(isFiltering ? "RESULTS" : "JOURNAL")
                            .sectionLabel()
                        Spacer()
                        if isFiltering {
                            Text("\(filteredEntries.count)")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(FoodTheme.secondaryText)
                        }
                    }

                    ForEach(groupEntriesByDay(filteredEntries)) { group in
                        daySection(group)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
        .navigationTitle("Food log")
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            calendar = .current
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { calendar = .current }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                FoodPageHeader("Food log", identifier: "journal-title") { headerActions }
                    .background(FoodTheme.background)
                if showingSearch { searchBar }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            FoodEntryEditor(entry: entry)
                .presentationDragIndicator(.visible)
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let entryToDelete {
                    do {
                        try FastingStore.detachEntry(entryToDelete, in: context)
                        context.delete(entryToDelete)
                        try context.save()
                    } catch {
                        context.rollback()
                        fastingMessage = error.localizedDescription
                    }
                }
                self.entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This only removes the record from your food log.")
        }
        .alert("Entry could not be deleted", isPresented: Binding(
            get: { fastingMessage != nil }, set: { if !$0 { fastingMessage = nil } }
        )) { Button("OK") { fastingMessage = nil } } message: { Text(fastingMessage ?? "") }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                showingSearch = true
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 24, height: 24)
            }
            .foodSecondaryActionStyle()
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Search entries")
            .accessibilityIdentifier("journal-search-button")
            mealFilterMenu
        }
        .font(.system(.body).weight(.semibold))
        .fixedSize()
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FoodTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("Search entries", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .onAppear { searchFocused = true }
                .accessibilityIdentifier("journal-search-field")
            Button {
                searchFocused = false
                query = ""
                showingSearch = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close search")
        }
        .font(.system(.body, design: .rounded))
        .foregroundStyle(FoodTheme.ink)
        .padding(.leading, 12)
        .foodGlass(cornerRadius: 22, interactive: true)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("THIS WEEK")
                    .sectionLabel()
                Text("\(thisWeek.count) \(thisWeek.count == 1 ? "entry" : "entries") logged")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(FoodTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("THIS WEEK")
                            .sectionLabel()
                        Text("\(thisWeek.count)")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(FoodTheme.ink)
                    }
                    Spacer()
                    Text(thisWeek.count == 1 ? "entry logged" : "entries logged")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundColor(FoodTheme.secondaryText)
                        .padding(.bottom, 8)
                }
            }

            if mealCounts.isEmpty {
                Text("Your meal categories will appear here.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(FoodTheme.ink)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mealCounts, id: \.0) { item in
                            let meal = item.0
                            let count = item.1
                            HStack(spacing: 6) {
                                Image(systemName: FoodTheme.symbol(for: meal))
                                Text(meal)
                                Text("\(count)")
                                    .foregroundColor(FoodTheme.ink)
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(FoodTheme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(18)
        .foodPanel(cornerRadius: 22)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 44, weight: .regular))
                .accessibilityHidden(true)
            Text("No entries yet")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(FoodTheme.ink)
            Text("Tap + to begin.")
                .font(.system(.body, design: .rounded))
                .foregroundColor(FoodTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
    }

    private var noResultsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .accessibilityHidden(true)
            Text("Nothing found")
                .font(.system(.title3, design: .rounded).weight(.bold))
        }
        .foregroundColor(FoodTheme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var mealFilterMenu: some View {
        Menu {
            Picker("Meal type", selection: $mealFilter) {
                ForEach(["All"] + FoodEntryEditor.mealTypes, id: \.self) { meal in
                    Text(meal).tag(meal)
                }
            }
        } label: {
            Image(systemName: mealFilter == "All"
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .frame(width: 24, height: 24)
        }
        .foodSecondaryActionStyle()
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Filter by meal type")
        .accessibilityValue(mealFilter)
    }

    private func daySection(_ group: EntryDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle(group.date))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.objectID) { index, entry in
                    Button { selectedEntry = entry } label: {
                        EntryRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this entry for editing")
                    .contextMenu {
                        Button { selectedEntry = entry } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { entryToDelete = entry } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if index < group.entries.count - 1 {
                        Divider().padding(.leading, 55)
                    }
                }
            }
            .foodPanel(cornerRadius: 18)
        }
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return FoodLogFormatters.dayHeading.string(from: date)
    }
}

struct EntryRow: View {
    @ObservedObject var entry: FoodEntry
    @AppStorage("showMealLabels") private var showMealLabels = true

    var body: some View {
        HStack(spacing: 12) {
            if let photoData = entry.photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityLabel("Photo of \(entry.wrappedFood)")
            } else {
                Image(systemName: FoodTheme.symbol(for: entry.wrappedMealType))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FoodTheme.color(for: entry.wrappedMealType))
                    .frame(width: 42, height: 42)
                    .background(
                        FoodTheme.color(for: entry.wrappedMealType).opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.wrappedFood)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(FoodTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(FoodLogFormatters.time.string(from: entry.wrappedDate))
                        if showMealLabels {
                            Text("•")
                            Text(entry.wrappedMealType)
                        }
                    }
                    if !entry.wrappedPlace.isEmpty {
                        Label(entry.wrappedPlace, systemImage: "mappin")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(FoodTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if !entry.companionNames.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FoodTheme.secondaryText)
                    .accessibilityLabel("With \(entry.companionDisplayText)")
            }
        }
        .padding(12)
    }
}

extension View {
    func sectionLabel() -> some View {
        font(.system(.caption, design: .rounded).weight(.bold))
            .tracking(0.8)
            .foregroundColor(FoodTheme.ink)
    }
}
