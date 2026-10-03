import Charts
import CoreData
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

private enum PatternDetail: String, Identifiable {
    case overview
    case places
    case foods
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .places: return "Eating places"
        case .foods: return "Foods noted"
        case .people: return "People"
        }
    }
}

struct PatternsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.foodAccentColor) private var accentColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)]
    ) private var entries: FetchedResults<FoodEntry>

    @State private var range: PatternRange = .week
    @State private var isBackfillingPlaces = false
    @State private var backfillMessage: String?
    @State private var selectedDetail: PatternDetail?
    @State private var calendar = Calendar.current
    @StateObject private var contactPhotos = ContactsSearchModel(includesImages: true)

    private var selectedEntries: [FoodEntry] {
        guard range.rawValue > 0,
              let start = Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date()))
        else { return Array(entries) }
        return entries.filter { $0.wrappedDate >= start }
    }

    private var overnightEstimates: [OvernightFastEstimate] {
        let estimates = OvernightFasting.estimates(from: Array(entries), calendar: calendar)
        guard range.rawValue > 0,
              let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1),
                                        to: calendar.startOfDay(for: Date())) else { return estimates }
        // Select by the first meal's day, retaining the previous day's last
        // meal even when it falls outside the selected reporting range.
        return estimates.filter { $0.endDate >= start }
    }

    private var daysRepresented: Int {
        Set(selectedEntries.map { Calendar.current.startOfDay(for: $0.wrappedDate) }).count
    }

    private var individualFoodCounts: [(String, Int)] {
        frequency(of: selectedEntries.flatMap { entry in
            entry.wrappedFood
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
        })
    }

    private var peopleCounts: [(String, Int)] {
        frequency(of: selectedEntries.flatMap(\.companionNames))
    }

    private var currentStreak: Int {
        FoodLogStatistics.currentStreak(entryDates: entries.map(\.wrappedDate))
    }

    private var dailyCounts: [(Date, Int)] {
        Dictionary(
            grouping: selectedEntries,
            by: { Calendar.current.startOfDay(for: $0.wrappedDate) }
        )
        .map { ($0.key, $0.value.count) }
        .sorted { $0.0 > $1.0 }
    }

    private var mappedPlaces: [EatingPlacePoint] {
        var points: [String: EatingPlacePoint] = [:]

        for entry in selectedEntries {
            guard let coordinates = entry.placeCoordinates else { continue }
            let displayName = PlaceFormatting.conciseName(
                place: entry.wrappedPlace,
                city: entry.wrappedPlaceCity
            )
            guard !displayName.isEmpty else { continue }

            let key = "\(displayName.lowercased())|\(coordinates.latitude)|\(coordinates.longitude)"
            if var point = points[key] {
                point.count += 1
                points[key] = point
            } else {
                points[key] = EatingPlacePoint(
                    id: key,
                    displayName: displayName,
                    latitude: coordinates.latitude,
                    longitude: coordinates.longitude,
                    count: 1
                )
            }
        }

        return points.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var entriesWithoutCoordinates: [FoodEntry] {
        entries.filter {
            !$0.wrappedPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPlaceCoordinates
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                rangePicker
                overnightPatternsCard
                eatingPlacesCard
                summaryCards

                if !individualFoodCounts.isEmpty {
                    frequencyCard(title: "FOODS NOTED", icon: "fork.knife", items: individualFoodCounts)
                }
                if !peopleCounts.isEmpty {
                    peopleCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
        .navigationTitle("Patterns")
        .foodCompactPageTitle()
        .toolbar(.visible, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            calendar = .current
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { calendar = .current }
        }
        .onAppear(perform: contactPhotos.loadIfAuthorized)
        .sheet(item: $selectedDetail, content: detailSheet)
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            rangePickerControl.pickerStyle(.menu)
        } else {
            rangePickerControl.pickerStyle(.segmented)
        }
    }

    private var rangePickerControl: some View {
        Picker("Range", selection: $range) {
            ForEach(PatternRange.allCases, id: \.rawValue) { option in
                Text(option.label).tag(option)
            }
        }
    }

    private var overnightPatternsCard: some View {
        let estimates = overnightEstimates
        return VStack(alignment: .leading, spacing: 12) {
            Label("FASTS", systemImage: "hourglass")
                .sectionLabel()
            if let summary = OvernightFasting.summary(of: estimates), let latest = estimates.first {
                HStack(alignment: .top, spacing: 16) {
                    overnightMetric("Average gap", duration: summary.averageDuration)
                    overnightMetric("Latest gap", duration: latest.duration)
                }
                Text("Range: \(FastTimeText.duration(summary.shortestDuration)) – \(FastTimeText.duration(summary.longestDuration))")
                    .font(.system(.subheadline, design: .rounded))
                Text("\(summary.count) \(summary.count == 1 ? "fast" : "fasts")")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FoodTheme.secondaryText)
            } else {
                Text("Log meals on consecutive days to see fasting times.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
        }
        .foregroundStyle(FoodTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foodPanel(cornerRadius: 20)
        .accessibilityIdentifier("overnight-patterns")
    }

    private func overnightMetric(_ title: String, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FastTimeText.duration(duration))
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(FoodTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCards: some View {
        Button {
            selectedDetail = .overview
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        overviewMetric(value: selectedEntries.count, label: "Entries", symbol: "square.and.pencil")
                        overviewMetric(value: daysRepresented, label: "Days", symbol: "calendar")
                        overviewMetric(value: peopleCounts.count, label: "People", symbol: "person.2.fill")
                        overviewMetric(value: currentStreak, label: "Streak", symbol: "flame.fill")
                    }
                } else {
                    HStack(spacing: 0) {
                        overviewMetric(value: selectedEntries.count, label: "Entries", symbol: "square.and.pencil")
                        Divider().frame(height: 54)
                        overviewMetric(value: daysRepresented, label: "Days", symbol: "calendar")
                        Divider().frame(height: 54)
                        overviewMetric(value: peopleCounts.count, label: "People", symbol: "person.2.fill")
                        Divider().frame(height: 54)
                        overviewMetric(value: currentStreak, label: "Streak", symbol: "flame.fill")
                    }
                }
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foodPanel(cornerRadius: 20)
        .accessibilityLabel("Overview")
        .accessibilityHint("Shows daily activity and summary details")
    }

    private func overviewMetric(value: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Label("\(value)", systemImage: symbol)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(accentColor)
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(FoodTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var eatingPlacesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("EATING PLACES", systemImage: "map.fill")
                    .sectionLabel()
                Spacer()
                if !mappedPlaces.isEmpty {
                    Text("\(mappedPlaces.count) \(mappedPlaces.count == 1 ? "place" : "places")")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FoodTheme.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FoodTheme.secondaryText)
            }

            if mappedPlaces.isEmpty {
                placesEmptyState
            } else {
                EatingPlacesMap(points: mappedPlaces)
                    .allowsHitTesting(false)
            }
        }
        .padding(17)
        .contentShape(Rectangle())
        .onTapGesture { selectedDetail = .places }
        .foodPanel(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Eating places")
        .accessibilityHint("Shows a larger map and all eating places")
    }

    @MainActor
    private func backfillOlderPlaces() async {
        guard !isBackfillingPlaces else { return }
        isBackfillingPlaces = true
        backfillMessage = nil

        let candidates = entriesWithoutCoordinates
        var resolvedByQuery: [String: LocationSelection] = [:]
        var unresolvedQueries = Set<String>()
        var updatedCount = 0

        for entry in candidates {
            let query = entry.wrappedPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = query.lowercased()
            let selection: LocationSelection?

            if let cached = resolvedByQuery[key] {
                selection = cached
            } else if unresolvedQueries.contains(key) {
                selection = nil
            } else {
                selection = await PlaceCoordinateBackfill.resolve(query)
                if let selection {
                    resolvedByQuery[key] = selection
                } else {
                    unresolvedQueries.insert(key)
                }
            }

            guard let selection else { continue }
            entry.placeCity = selection.city
            entry.placeLatitude = selection.latitude
            entry.placeLongitude = selection.longitude
            entry.hasPlaceCoordinates = true
            updatedCount += 1
        }

        do {
            if context.hasChanges { try context.save() }
            let skippedCount = candidates.count - updatedCount
            if updatedCount == 0 {
                backfillMessage = "No exact place matches were found. Your entries were left unchanged."
            } else if skippedCount > 0 {
                backfillMessage = "Located \(updatedCount) older \(updatedCount == 1 ? "entry" : "entries"). Left \(skippedCount) ambiguous \(skippedCount == 1 ? "place" : "places") unchanged."
            } else {
                backfillMessage = "Located \(updatedCount) older \(updatedCount == 1 ? "entry" : "entries")."
            }
        } catch {
            context.rollback()
            backfillMessage = "The older places could not be saved."
        }

        isBackfillingPlaces = false
    }

    private var peopleCard: some View {
        Button {
            selectedDetail = .people
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("PEOPLE", systemImage: "person.2.fill")
                        .sectionLabel()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FoodTheme.secondaryText)
                }

                ForEach(Array(peopleCounts.prefix(5)), id: \.0) { item in
                    HStack(spacing: 12) {
                        ContactAvatar(
                            name: item.0,
                            photoData: contactPhotos.photoData(for: item.0)
                        )

                        Text(item.0)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.1)")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                }
            }
            .padding(17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foodPanel(cornerRadius: 20)
        .accessibilityLabel("People")
        .accessibilityHint("Shows every person and their entry count")
    }

    private func frequencyCard(title: String, icon: String, items: [(String, Int)]) -> some View {
        Button {
            selectedDetail = .foods
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(title, systemImage: icon)
                        .sectionLabel()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FoodTheme.secondaryText)
                }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foodPanel(cornerRadius: 20)
        .accessibilityLabel("Foods noted")
        .accessibilityHint("Shows all foods noted in this range")
    }

    private var placesEmptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 28))
                .foregroundStyle(FoodTheme.secondaryText)
            Text(entriesWithoutCoordinates.isEmpty
                 ? "Places selected from MapKit will appear here."
                 : "Older places can be located for this map.")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(FoodTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }

    private func detailSheet(_ detail: PatternDetail) -> some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    detailRangeLabel
                    detailContent(detail)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(FoodTheme.background)
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selectedDetail = nil }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var detailRangeLabel: some View {
        Text(range.label.uppercased())
            .sectionLabel()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailContent(_ detail: PatternDetail) -> some View {
        switch detail {
        case .overview:
            overviewDetail
        case .places:
            placesDetail
        case .foods:
            rankedDetail(items: individualFoodCounts, showsAvatars: false)
        case .people:
            peopleDetail
        }
    }

    private var overviewDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                expandedMetric(value: selectedEntries.count, label: "Entries", symbol: "square.and.pencil")
                expandedMetric(value: daysRepresented, label: "Days", symbol: "calendar")
                expandedMetric(value: peopleCounts.count, label: "People", symbol: "person.2.fill")
                expandedMetric(value: currentStreak, label: "Current streak", symbol: "flame.fill")
            }

            if !dailyCounts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("DAYS WITH ENTRIES").sectionLabel()
                    ForEach(dailyCounts, id: \.0) { day, count in
                        HStack(spacing: 12) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(width: 82, alignment: .leading)
                            PatternCountBar(category: day.formatted(date: .abbreviated, time: .omitted),
                                            count: count, maximum: dailyCounts.map(\.1).max() ?? 1)
                            Text("\(count)")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(FoodTheme.secondaryText)
                                .frame(minWidth: 20, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(count) \(count == 1 ? "entry" : "entries")")
                    }
                }
                .padding(17)
                .foodPanel(cornerRadius: 20)
            }

            Text("A streak counts consecutive days with at least one entry. Today is optional until the day ends.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(FoodTheme.secondaryText)
                .padding(.horizontal, 4)
        }
    }

    private func expandedMetric(value: Int, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(accentColor)
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(FoodTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .foodPanel(cornerRadius: 20)
    }

    private var placesDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mappedPlaces.isEmpty {
                placesEmptyState
                    .padding(17)
                    .foodPanel(cornerRadius: 20)
            } else {
                EatingPlacesMap(points: mappedPlaces, height: 360)
                    .padding(12)
                    .foodPanel(cornerRadius: 20)

                VStack(alignment: .leading, spacing: 14) {
                    Text("PLACES").sectionLabel()
                    ForEach(mappedPlaces) { point in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(accentColor)
                            Text(point.displayName)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(point.count)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(FoodTheme.secondaryText)
                        }
                    }
                }
                .padding(17)
                .foodPanel(cornerRadius: 20)
            }

            if !entriesWithoutCoordinates.isEmpty {
                Button {
                    Task { await backfillOlderPlaces() }
                } label: {
                    HStack {
                        Label("Locate older places", systemImage: "location.magnifyingglass")
                        Spacer()
                        if isBackfillingPlaces {
                            ProgressView()
                        } else {
                            Text("\(entriesWithoutCoordinates.count)")
                                .foregroundStyle(FoodTheme.secondaryText)
                        }
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isBackfillingPlaces)
            }

            if let backfillMessage {
                Text(backfillMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
        }
    }

    private var peopleDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            rankedDetail(items: peopleCounts, showsAvatars: true)

            if contactPhotos.canRequestAccess {
                Button {
                    contactPhotos.setEnabled(true, query: "")
                } label: {
                    Label("Show contact photos", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if contactPhotos.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading contact photos")
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(FoodTheme.secondaryText)
            } else if let message = contactPhotos.message {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
        }
    }

    private func rankedDetail(items: [(String, Int)], showsAvatars: Bool) -> some View {
        let maximum = max(items.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 12) {
                    if showsAvatars {
                        ContactAvatar(name: item.0, photoData: contactPhotos.photoData(for: item.0))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.0)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                            Spacer()
                            Text("\(item.1)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(FoodTheme.secondaryText)
                        }
                        PatternCountBar(category: item.0, count: item.1, maximum: maximum)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.0)
                .accessibilityValue("Count: \(item.1)")
            }
        }
        .padding(17)
        .foodPanel(cornerRadius: 20)
    }

    private func frequency(of values: [String]) -> [(String, Int)] {
        FoodLogStatistics.frequencies(values).map { ($0.name, $0.count) }
    }
}

/// A historical count, not task progress. Labels and counts remain outside the
/// chart for long names and Dynamic Type; each surrounding row is one complete
/// accessibility element, so VoiceOver doesn't announce the value twice.
private struct PatternCountBar: View {
    @Environment(\.foodAccentColor) private var accentColor
    let category: String
    let count: Int
    let maximum: Int

    var body: some View {
        Chart {
            BarMark(x: .value("Count", count), y: .value("Category", category))
                .foregroundStyle(accentColor)
                .cornerRadius(3)
        }
        .chartXScale(domain: 0...max(1, maximum))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct ContactAvatar: View {
    @Environment(\.foodAccentColor) private var accentColor
    let name: String
    let photoData: Data?

    private var initials: String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(accentColor.opacity(0.18))
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(FoodTheme.outline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct EatingPlacePoint: Identifiable {
    let id: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    var count: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct EatingPlacesMap: View {
    @Environment(\.foodAccentColor) private var accentColor
    let points: [EatingPlacePoint]
    let height: CGFloat

    @State private var region: MKCoordinateRegion
    @State private var selectedPointID: String?

    init(points: [EatingPlacePoint], height: CGFloat = 205) {
        self.points = points
        self.height = height
        _region = State(initialValue: Self.region(containing: points))
        _selectedPointID = State(initialValue: points.first?.id)
    }

    private var selectedPoint: EatingPlacePoint? {
        points.first { $0.id == selectedPointID } ?? points.first
    }

    var body: some View {
        VStack(spacing: 10) {
            Map(
                coordinateRegion: $region,
                interactionModes: [.pan, .zoom],
                annotationItems: points
            ) { point in
                MapAnnotation(coordinate: point.coordinate) {
                    Button {
                        selectedPointID = point.id
                    } label: {
                        Image(systemName: selectedPointID == point.id ? "mappin.circle.fill" : "mappin.circle")
                            .font(.system(size: selectedPointID == point.id ? 27 : 23, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(point.displayName)
                    .accessibilityValue("\(point.count) \(point.count == 1 ? "entry" : "entries")")
                    .accessibilityIdentifier("eating-place-map-pin")
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let selectedPoint {
                HStack(spacing: 9) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(accentColor)
                    Text(selectedPoint.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("\(selectedPoint.count)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(FoodTheme.secondaryText)
                }
            }
        }
        .onChange(of: points.map(\.id)) { _ in
            region = Self.region(containing: points)
            if !points.contains(where: { $0.id == selectedPointID }) {
                selectedPointID = points.first?.id
            }
        }
    }

    private static func region(containing points: [EatingPlacePoint]) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100)
            )
        }

        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let minimumLongitude = longitudes.min() ?? first.longitude
        let maximumLongitude = longitudes.max() ?? first.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(max((maximumLatitude - minimumLatitude) * 1.7, 0.025), 120),
                longitudeDelta: min(max((maximumLongitude - minimumLongitude) * 1.7, 0.025), 120)
            )
        )
    }
}

private enum PlaceCoordinateBackfill {
    static func resolve(_ query: String) async -> LocationSelection? {
        guard !query.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        return await withCheckedContinuation { continuation in
            MKLocalSearch(request: request).start { response, error in
                guard error == nil, let item = response?.mapItems.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let city = PlaceFormatting.city(from: item.placemark)
                let placeName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let placeName,
                      !placeName.isEmpty,
                      PlaceFormatting.isConfidentBackfillMatch(query: query, resultName: placeName)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let displayName = PlaceFormatting.conciseName(
                    place: placeName,
                    city: city
                )
                continuation.resume(returning: LocationSelection(
                    displayName: displayName,
                    fullAddress: PlaceFormatting.fullAddress(placeName: placeName, placemark: item.placemark),
                    city: city,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                ))
            }
        }
    }
}

struct FoodLogSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)])
    private var entries: FetchedResults<FoodEntry>

    @AppStorage("foodLogAppearance") private var appearance = 0
    @AppStorage(FoodAccentOption.settingKey) private var accentValue = FoodAccentOption.teal.rawValue
    @AppStorage("showMealLabels") private var showMealLabels = true
    @AppStorage(BiometricAuthentication.settingKey) private var biometricLockEnabled = false
    @AppStorage(AppRelockDelay.settingKey) private var relockDelaySeconds = 0
    @AppStorage(FastingGoalPreference.hoursKey) private var fastingGoalHours = FastingGoalPreference.defaultHours
    @AppStorage(FastingGoalPreference.enabledKey) private var fastingGoalEnabled = true
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var showingFileImporter = false
    @State private var importPreview: FoodLogCSVImportPreview?
    @State private var importMessage: String?
    @State private var confirmErase = false
    @State private var biometricAvailability = BiometricAuthentication.availability()

    var body: some View {
        settingsContent
    }

    private var settingsContent: some View {
        Form {
            Section {
                appearancePicker
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings-appearance")
                accentPicker
            } header: {
                Text("Appearance").foregroundStyle(FoodTheme.secondaryText)
            }

            Section {
                Toggle("Show meal labels in journal", isOn: $showMealLabels)
                    .accessibilityIdentifier("settings-meal-labels")
                NavigationLink("Default meal times") {
                    MealDefaultTimesSettingsView()
                }
                .accessibilityIdentifier("settings-meal-times")
                NavigationLink("Notifications") {
                    FoodReminderSettingsView()
                }
                .accessibilityIdentifier("settings-notifications")
            } header: {
                Text("Meals").foregroundStyle(FoodTheme.secondaryText)
            }

            Section {
                Toggle("Show goal in calendar", isOn: $fastingGoalEnabled)
                    .accessibilityIdentifier("fasting-goal-enabled")
                if fastingGoalEnabled {
                    Stepper(value: $fastingGoalHours, in: 1...36, step: 0.5) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Fasting goal")
                            Text(FastTimeText.compactDuration(fastingGoalHours * 3_600))
                                .font(.footnote)
                                .foregroundStyle(FoodTheme.secondaryText)
                        }
                    }
                    .accessibilityIdentifier("fasting-goal-hours")
                    .accessibilityValue(FastTimeText.duration(fastingGoalHours * 3_600))
                }
            } header: {
                Text("Fasting").foregroundStyle(FoodTheme.secondaryText)
            }

            Section {
                Toggle(isOn: $biometricLockEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App lock")
                        Text(biometricAvailability.isAvailable
                             ? "Require \(biometricAvailability.name) when opening Savour"
                             : "Face ID or Touch ID is unavailable")
                            .font(.footnote)
                            .foregroundStyle(FoodTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!biometricAvailability.isAvailable && !biometricLockEnabled)
                .accessibilityIdentifier("settings-app-lock")

                Picker("Relock", selection: $relockDelaySeconds) {
                    ForEach(AppRelockDelay.allCases) { delay in
                        Text(delay.title).tag(delay.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("relock-delay")
            } header: {
                Text("Privacy").foregroundStyle(FoodTheme.secondaryText)
            } footer: {
                Text("Savour stays hidden in the background. A new launch always requires authentication when app lock is enabled.")
                    .foregroundStyle(FoodTheme.secondaryText)
            }

            Section {
                Button(action: exportCSV) {
                    HStack {
                        Text("Export CSV")
                        Spacer()
                        Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settings-export-csv")

                Button("Import CSV") { showingFileImporter = true }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("settings-import-csv")

#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-test-csv-fixture") {
                    Button("Preview CSV fixture", action: previewCSVFixture)
                }
#endif

                Button("Erase all entries", role: .destructive) { confirmErase = true }
                    .disabled(entries.isEmpty)
                    .accessibilityIdentifier("settings-erase-entries")
            } header: {
                Text("Your data").foregroundStyle(FoodTheme.secondaryText)
            }

            Section {
                Text("Adapted from [Dime](https://github.com/rafsoh/dimeApp)'s open-source SwiftUI code and interaction ideas under GPLv3.")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dime-source-link")
            } header: {
                Text("About").foregroundStyle(FoodTheme.secondaryText)
            } footer: {
                VStack(spacing: 8) {
                    Text("Built with ❤️ by Viraat")
                        .accessibilityIdentifier("settings-credit")
                    Text("Savour \(appVersion) (Build \(appBuild))")
                        .accessibilityIdentifier("settings-version")
                }
                .foregroundStyle(FoodTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
        }
        .formStyle(.grouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(FoodTheme.background)
        .navigationTitle("Settings")
        .foodCompactPageTitle()
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            biometricAvailability = BiometricAuthentication.availability()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case let .success(url):
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let csv = try String(contentsOf: url, encoding: .utf8)
                    importPreview = try FoodLogCSVImporter.preview(
                        csv,
                        fileName: url.lastPathComponent,
                        existingEntries: Array(entries)
                    )
                } catch {
                    importMessage = "Could not preview the CSV: \(error.localizedDescription)"
                }
            case let .failure(error):
                importMessage = "Could not open the CSV: \(error.localizedDescription)"
            }
        }
        .sheet(item: $importPreview) { preview in
            FoodLogCSVImportPreviewView(preview: preview) {
                let importedCount = try FoodLogCSVImporter.commit(preview, to: context)
                importPreview = nil
                importMessage = "Imported \(importedCount) \(importedCount == 1 ? "entry" : "entries")."
            }
        }
        .alert("CSV import", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("Erase every entry?", isPresented: $confirmErase) {
            Button("Erase all", role: .destructive, action: eraseAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes food entries but keeps fasting records and their times. Export first if you want a food-entry backup.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var appearancePicker: some View {
        Picker("Appearance", selection: $appearance) {
            Text("System").tag(0)
            Text("Light").tag(1)
            Text("Dark").tag(2)
        }
    }

    private var accentPicker: some View {
        Picker("Accent color", selection: $accentValue) {
            ForEach(FoodAccentOption.allCases) { option in
                HStack(spacing: 12) {
                    Circle()
                        .fill(option.color)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(option.name)
                }
                .tag(option.rawValue)
                .accessibilityLabel(option.name)
            }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("settings-accent-color")
    }

    private func exportCSV() {
        exportURL = CSVExporter.makeFile(from: Array(entries))
        showingShareSheet = exportURL != nil
    }

#if DEBUG
    private func previewCSVFixture() {
        guard let existing = entries.first else { return }
        let duplicate = CSVExporter.row(for: existing)
        var imported = duplicate
        imported[0] = "Imported CSV fixture"
        imported[9] = "A note, with \"quotes\"\nand a new line"
        imported[10] = UUID().uuidString
        var invalid = imported
        invalid[1] = "invalid-date"
        let csv = FoodLogCSVDocument.encodeExtended(dataRows: [duplicate, imported, invalid])
        importPreview = try? FoodLogCSVImporter.preview(
            csv, fileName: "fixture.csv", existingEntries: Array(entries)
        )
    }
#endif

    private func eraseAll() {
        do {
            for entry in Array(entries) {
                try FastingStore.detachEntry(entry, in: context)
                context.delete(entry)
            }
            try context.save()
        } catch {
            context.rollback()
            importMessage = error.localizedDescription
        }
    }
}

struct FoodReminderSettingsView: View {
    @StateObject private var reminder = FoodDailyReminder.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: Binding(
                    get: { reminder.isEnabled },
                    set: { enabled in Task { await reminder.setEnabled(enabled) } }
                ))
                .disabled(reminder.isUpdating)
                .accessibilityIdentifier("notifications-enabled")
            }
            Section {
                ForEach(reminder.times.indices, id: \.self) { index in
                    DatePicker("Reminder \(index + 1)", selection: Binding(
                        get: { date(minutes: reminder.times.indices.contains(index) ? reminder.times[index] : 480) },
                        set: { date in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            Task { await reminder.setMinutes((components.hour ?? 8) * 60 + (components.minute ?? 0), at: index) }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .disabled(reminder.isUpdating)
                    .deleteDisabled(reminder.times.count == 1 || reminder.isUpdating)
                    .accessibilityIdentifier("notifications-time-\(index + 1)")
                }
                .onDelete { offsets in Task { await reminder.removeReminders(at: offsets) } }
                if reminder.times.count < FoodReminderSchedule.maximumCount {
                    Button {
                        Task { await reminder.addReminder() }
                    } label: { Label("Add reminder", systemImage: "plus") }
                    .disabled(reminder.isUpdating)
                    .accessibilityIdentifier("notifications-add-reminder")
                }
            }

            Section {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("notifications-open-settings")
            } footer: {
                if reminder.permission == .denied {
                    Text("Notifications are disabled for Savour in iOS Settings.")
                        .foregroundStyle(FoodTheme.secondaryText)
                }
            }
            if let message = reminder.errorMessage {
                Section {
                    Text(message).foregroundStyle(FoodTheme.secondaryText)
                        .accessibilityIdentifier("notifications-error")
                }
            }
        }
        .formStyle(.grouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(FoodTheme.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminder.refresh() }
    }

    private func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}

private struct MealDefaultTimesSettingsView: View {
    @State private var defaultMealTimes = Dictionary(
        uniqueKeysWithValues: MealDefaultTimes.mealTypes.map { ($0, MealDefaultTimes.date(for: $0)) }
    )

    var body: some View {
        Form {
            Section {
                ForEach(MealDefaultTimes.mealTypes, id: \.self) { meal in
                    DatePicker(
                        meal,
                        selection: defaultTimeBinding(for: meal),
                        displayedComponents: .hourAndMinute
                    )
                    .font(.system(.body, design: .rounded).weight(.medium))
                }
            } footer: {
                Text("Applied when you switch to a different meal type.")
            }
        }
        .navigationTitle("Default meal times")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func defaultTimeBinding(for mealType: String) -> Binding<Date> {
        Binding(
            get: { defaultMealTimes[mealType] ?? MealDefaultTimes.date(for: mealType) },
            set: { newTime in
                defaultMealTimes[mealType] = newTime
                MealDefaultTimes.set(newTime, for: mealType)
            }
        )
    }
}

enum CSVExporter {
    static func makeFile(from entries: [FoodEntry]) -> URL? {
        let rows = entries.map(row(for:))
        let csv = FoodLogCSVDocument.encodeExtended(dataRows: rows)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Savour.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func row(for entry: FoodEntry) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"
        let names = entry.companionNames
        let peopleJSON = (try? JSONEncoder().encode(names)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return [
            entry.wrappedFood,
            dateFormatter.string(from: entry.wrappedDate),
            timeFormatter.string(from: entry.wrappedDate),
            entry.wrappedMealType,
            entry.wrappedPlace,
            entry.wrappedPlaceCity,
            entry.hasPlaceCoordinates ? String(entry.placeLatitude) : "",
            entry.hasPlaceCoordinates ? String(entry.placeLongitude) : "",
            entry.companionDisplayText,
            entry.wrappedNote,
            entry.id?.uuidString ?? "",
            peopleJSON,
            String(entry.wrappedDate.timeIntervalSince1970)
        ]
    }

}

private struct FoodLogCSVImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    let preview: FoodLogCSVImportPreview
    let onImport: () throws -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(preview.importableCount) to import · \(preview.duplicateCount) duplicates · \(preview.issues.count) errors")
                    Text("Review \(preview.fileName) before adding entries to your journal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if preview.isLegacyFormat {
                        Text("Older CSV files store people as one text field. Names containing commas may be split into separate people.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !preview.issues.isEmpty {
                    Section("Validation errors · skipped") {
                        ForEach(preview.issues) { issue in
                            Text(issue.message)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !preview.rows.isEmpty {
                    Section("Entries") {
                        ForEach(preview.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.food).font(.headline)
                                    Spacer()
                                    if row.isDuplicate {
                                        Text("Duplicate").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Row \(row.rowNumber) · \(row.dateText) · \(row.meal)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !row.place.isEmpty { Text("Place: \(row.place)") }
                                if !row.people.isEmpty { Text("People: \(row.people)") }
                                if !row.note.isEmpty { Text("Note: \(row.note)") }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section {
                    Text("CSV exports do not contain photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(preview.importableCount)") {
                        do { try onImport() }
                        catch { errorMessage = error.localizedDescription }
                    }
                        .disabled(preview.importableCount == 0)
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
