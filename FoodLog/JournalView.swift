import CoreData
import SwiftUI
import UIKit

struct JournalView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)],
        animation: .default
    ) private var entries: FetchedResults<FoodEntry>

    let openBrowse: () -> Void
    @State private var selectedEntry: FoodEntry?
    @State private var entryToDelete: FoodEntry?

    private var thisWeek: [FoodEntry] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else {
            return Array(entries)
        }
        return entries.filter { interval.contains($0.wrappedDate) }
    }

    private var recentGroups: [EntryDayGroup] {
        Array(groupEntriesByDay(Array(entries)).prefix(7))
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
                header
                weeklySummary

                if entries.isEmpty {
                    emptyState
                } else {
                    HStack {
                        Text("RECENT")
                            .sectionLabel()
                        Spacer()
                        Button("View all", action: openBrowse)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(FoodTheme.secondaryText)
                    }

                    ForEach(recentGroups) { group in
                        daySection(group)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
        .fullScreenCover(item: $selectedEntry) { entry in
            FoodEntryEditor(entry: entry)
        }
        .alert("Delete this entry?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let entryToDelete {
                    context.delete(entryToDelete)
                    try? context.save()
                }
                self.entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This only removes the record from your food log.")
        }
    }

    private var header: some View {
        Text("Food log")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundColor(FoodTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK")
                        .sectionLabel()
                    Text("\(thisWeek.count)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(FoodTheme.ink)
                }
                Spacer()
                Text(thisWeek.count == 1 ? "entry logged" : "entries logged")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundColor(FoodTheme.secondaryText)
                    .padding(.bottom, 8)
            }

            if mealCounts.isEmpty {
                Text("Your meal categories will appear here.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mealCounts, id: \.0) { item in
                            let meal = item.0
                            let count = item.1
                            HStack(spacing: 6) {
                                Text(FoodTheme.emoji(for: meal))
                                Text(meal)
                                Text("\(count)")
                                    .foregroundColor(FoodTheme.color(for: meal))
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
        .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(FoodTheme.outline, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🍜")
                .font(.system(size: 44))
            Text("No entries yet")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(FoodTheme.ink)
            Text("Tap + to add your first entry.")
                .font(.system(.body, design: .rounded))
                .foregroundColor(FoodTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
    }

    private func daySection(_ group: EntryDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle(group.date))
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
                            Button(role: .destructive) { entryToDelete = entry } label: {
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

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return FoodLogFormatters.dayHeading.string(from: date)
    }
}

struct EntryRow: View {
    let entry: FoodEntry
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
                Text(FoodTheme.emoji(for: entry.wrappedMealType))
                    .font(.system(size: 22))
                    .frame(width: 42, height: 42)
                    .background(
                        FoodTheme.color(for: entry.wrappedMealType).opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.wrappedFood)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(FoodTheme.ink)
                    .lineLimit(2)

                HStack(spacing: 7) {
                    Text(FoodLogFormatters.time.string(from: entry.wrappedDate))
                    if showMealLabels {
                        Text("•")
                        Text(entry.wrappedMealType)
                    }
                    if !entry.wrappedPlace.isEmpty {
                        Text("•")
                        Label(entry.wrappedPlace, systemImage: "mappin")
                            .lineLimit(1)
                    }
                }
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(FoodTheme.secondaryText)
            }

            Spacer(minLength: 8)

            if !entry.wrappedPeople.isEmpty {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FoodTheme.secondaryText)
                    .accessibilityLabel("With \(entry.wrappedPeople)")
            }
        }
        .padding(12)
    }
}

extension View {
    func sectionLabel() -> some View {
        font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(FoodTheme.secondaryText)
    }
}
