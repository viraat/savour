import CoreData
import MapKit
import SwiftUI
import UIKit

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
    @Environment(\.managedObjectContext) private var context
    @Environment(\.foodAccentColor) private var accentColor
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)]
    ) private var entries: FetchedResults<FoodEntry>

    @State private var range: PatternRange = .week
    @State private var isBackfillingPlaces = false
    @State private var backfillMessage: String?
    @StateObject private var contactPhotos = ContactsSearchModel(includesImages: true)

    private var selectedEntries: [FoodEntry] {
        guard range.rawValue > 0,
              let start = Calendar.current.date(byAdding: .day, value: -(range.rawValue - 1), to: Calendar.current.startOfDay(for: Date()))
        else { return Array(entries) }
        return entries.filter { $0.wrappedDate >= start }
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
        let calendar = Calendar.current
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.wrappedDate) })
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        var day: Date
        if loggedDays.contains(today) {
            day = today
        } else if let yesterday, loggedDays.contains(yesterday) {
            day = yesterday
        } else {
            return 0
        }

        var count = 0
        while loggedDays.contains(day) {
            count += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return count
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
            .padding(.bottom, 110)
        }
        .background(FoodTheme.background)
        .navigationTitle("Patterns")
        .onAppear(perform: contactPhotos.loadIfAuthorized)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(PatternRange.allCases, id: \.rawValue) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryCards: some View {
        HStack(spacing: 0) {
            overviewMetric(
                value: selectedEntries.count,
                label: "Entries",
                symbol: "square.and.pencil"
            )

            Divider().frame(height: 54)

            overviewMetric(
                value: daysRepresented,
                label: "Days",
                symbol: "calendar"
            )

            Divider().frame(height: 54)

            overviewMetric(
                value: peopleCounts.count,
                label: "People",
                symbol: "person.2.fill"
            )

            Divider().frame(height: 54)

            overviewMetric(
                value: currentStreak,
                label: "Streak",
                symbol: "flame.fill"
            )
        }
        .padding(.vertical, 16)
        .foodPanel(cornerRadius: 20)
    }

    private func overviewMetric(value: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Label("\(value)", systemImage: symbol)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(accentColor)
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(FoodTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
            }

            if mappedPlaces.isEmpty {
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
            } else {
                EatingPlacesMap(points: mappedPlaces)
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
        .padding(17)
        .foodPanel(cornerRadius: 20)
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
            entry.place = selection.displayName
            entry.placeCity = selection.city
            entry.placeLatitude = selection.latitude
            entry.placeLongitude = selection.longitude
            entry.hasPlaceCoordinates = true
            updatedCount += 1
        }

        do {
            if context.hasChanges { try context.save() }
            backfillMessage = updatedCount == 0
                ? "No matching places were found."
                : "Located \(updatedCount) older \(updatedCount == 1 ? "entry" : "entries")."
        } catch {
            context.rollback()
            backfillMessage = "The older places could not be saved."
        }

        isBackfillingPlaces = false
    }

    private var peopleCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("PEOPLE", systemImage: "person.2.fill")
                .sectionLabel()

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
        .padding(17)
        .foodPanel(cornerRadius: 20)
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
        .foodPanel(cornerRadius: 20)
    }

    private func frequency(of values: [String]) -> [(String, Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            let current = counts[key] ?? (trimmed, 0)
            counts[key] = (current.name, current.count + 1)
        }
        return counts.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .map { ($0.name, $0.count) }
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

    @State private var region: MKCoordinateRegion
    @State private var selectedPointID: String?

    init(points: [EatingPlacePoint]) {
        self.points = points
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(point.displayName)
                    .accessibilityValue("\(point.count) \(point.count == 1 ? "entry" : "entries")")
                }
            }
            .frame(height: 205)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let selectedPoint {
                HStack(spacing: 9) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(accentColor)
                    Text(selectedPoint.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(2)
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
                let displayName = PlaceFormatting.conciseName(
                    place: placeName?.isEmpty == false ? placeName! : query,
                    city: city
                )
                continuation.resume(returning: LocationSelection(
                    displayName: displayName,
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
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    @State private var confirmErase = false
    @State private var biometricAvailability = BiometricAuthentication.availability()

    var body: some View {
        settingsContent
    }

    private var settingsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection("APPEARANCE") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)

                    Divider()

                    accentPicker

                    Divider()

                    Toggle("Show meal labels in journal", isOn: $showMealLabels)
                        .font(.system(.body, design: .rounded).weight(.medium))
                }

                settingsSection("MEALS") {
                    NavigationLink {
                        MealDefaultTimesSettingsView()
                    } label: {
                        settingsRow(
                            icon: "clock",
                            title: "Default meal times",
                            detail: nil
                        )
                    }
                }

                settingsSection("PRIVACY") {
                    Toggle(isOn: $biometricLockEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("App lock")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text(biometricAvailability.isAvailable
                                 ? "Require \(biometricAvailability.name) when opening FoodLog"
                                 : "Face ID or Touch ID is unavailable")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(FoodTheme.secondaryText)
                        }
                    }
                    .disabled(!biometricAvailability.isAvailable && !biometricLockEnabled)
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
                        Text("FoodLog \(appVersion)")
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
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(FoodTheme.background)
        .navigationTitle("Settings")
        .onAppear {
            biometricAvailability = BiometricAuthentication.availability()
        }
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent color")
                .font(.system(.body, design: .rounded).weight(.medium))

            HStack(spacing: 8) {
                ForEach(FoodAccentOption.allCases) { option in
                    Button {
                        accentValue = option.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 34, height: 34)

                                if accentValue == option.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        accentValue == option.rawValue ? FoodTheme.ink : .clear,
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            }

                            Text(option.name)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(FoodTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityValue(accentValue == option.rawValue ? "Selected" : "")
                }
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            VStack(spacing: 12) { content() }
                .padding(16)
                .foodPanel(cornerRadius: 18)
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

private enum CSVExporter {
    static func makeFile(from entries: [FoodEntry]) -> URL? {
        var csv = "food,date,time,meal,place,city,latitude,longitude,people,note\n"
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
                entry.wrappedPlaceCity,
                entry.hasPlaceCoordinates ? String(entry.placeLatitude) : "",
                entry.hasPlaceCoordinates ? String(entry.placeLongitude) : "",
                entry.companionDisplayText,
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
