import CoreData
import PhotosUI
import SwiftUI
import UIKit

private struct ReusablePlace: Identifiable {
    let place: String
    let city: String
    let latitude: Double
    let longitude: Double
    let hasCoordinates: Bool
    var count: Int

    var id: String { place.lowercased() }
}

private struct FrequentCompanionGroup: Identifiable {
    let people: [String]
    var count: Int

    var id: String { people.map { $0.lowercased() }.sorted().joined(separator: "|") }
}

struct FoodEntryEditor: View {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack", "Drink", "Other"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.createdAt, ascending: false)]
    ) private var previousEntries: FetchedResults<FoodEntry>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)])
    private var fasts: FetchedResults<FastSession>
    @AppStorage(FastTargetPreference.key) private var defaultFastTargetHours = 0.0

    let entry: FoodEntry?

    @State private var food: String
    @State private var date: Date
    @State private var mealType: String
    @State private var place: String
    @State private var placeCity: String
    @State private var placeLatitude: Double
    @State private var placeLongitude: Double
    @State private var hasPlaceCoordinates: Bool
    @State private var selectedPlaceLabel: String?
    @State private var selectedPlaceSavedName: String?
    @State private var selectedCompanions: [String]
    @State private var companionQuery = ""
    @State private var note: String
    @State private var photoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isLoadingPhoto = false
    @State private var photoMessage: String?
    @State private var confirmDelete = false
    @State private var detailsExpanded: Bool
    @State private var showingDateTimeSheet = false
    @State private var startFastAfterMeal = false
    @State private var askAboutActiveFast = false
    @State private var fastingMessage: String?
    @StateObject private var locationSearch = LocationSearchModel()
    @StateObject private var contactsSearch = ContactsSearchModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case food, place, companion, note
    }

    init(entry: FoodEntry?) {
        self.entry = entry
        let initialDate = entry?.wrappedDate ?? Date()
        _food = State(initialValue: entry?.wrappedFood ?? "")
        _date = State(initialValue: initialDate)
        _mealType = State(initialValue: entry?.wrappedMealType ?? MealTypeSuggestion.suggested(for: initialDate))
        _place = State(initialValue: entry?.wrappedPlace ?? "")
        _placeCity = State(initialValue: entry?.wrappedPlaceCity ?? "")
        _placeLatitude = State(initialValue: entry?.placeLatitude ?? 0)
        _placeLongitude = State(initialValue: entry?.placeLongitude ?? 0)
        _hasPlaceCoordinates = State(initialValue: entry?.hasPlaceCoordinates ?? false)
        _selectedPlaceLabel = State(initialValue: entry?.hasPlaceCoordinates == true ? entry?.wrappedPlace : nil)
        _selectedPlaceSavedName = State(initialValue: entry?.hasPlaceCoordinates == true ? entry?.wrappedPlace : nil)
        _selectedCompanions = State(initialValue: entry?.companionNames ?? [])
        _note = State(initialValue: entry?.wrappedNote ?? "")
        _photoData = State(initialValue: entry?.photoData)
        _detailsExpanded = State(initialValue: Self.hasDetails(entry))
    }

    private var canSave: Bool {
        !food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestions: [String] {
        FoodSuggestionEngine.suggestions(
            from: previousEntries.compactMap { previousEntry in
                guard previousEntry.objectID != entry?.objectID else { return nil }
                return FoodSuggestionSource(
                    mealType: previousEntry.wrappedMealType,
                    food: previousEntry.wrappedFood,
                    date: previousEntry.wrappedDate
                )
            },
            mealType: mealType,
            currentFood: food
        )
    }

    private var frequentPeople: [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for previousEntry in previousEntries {
            for name in previousEntry.companionNames {
                let key = name.lowercased()
                let current = counts[key] ?? (name, 0)
                counts[key] = (current.name, current.count + 1)
            }
        }

        let selected = Set(selectedCompanions.map { $0.lowercased() })
        return counts.values
            .filter { !selected.contains($0.name.lowercased()) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(6)
            .map(\.name)
    }

    private var contactSuggestions: [String] {
        let selected = Set(selectedCompanions.map { $0.lowercased() })
        return contactsSearch.suggestions.filter { !selected.contains($0.lowercased()) }
    }

    private var frequentCompanionGroups: [FrequentCompanionGroup] {
        var groups: [String: FrequentCompanionGroup] = [:]

        for previousEntry in previousEntries {
            let people = previousEntry.companionNames
            guard people.count >= 2 else { continue }
            let key = people.map { $0.lowercased() }.sorted().joined(separator: "|")
            if var group = groups[key] {
                group.count += 1
                groups[key] = group
            } else {
                groups[key] = FrequentCompanionGroup(people: people, count: 1)
            }
        }

        let selected = Set(selectedCompanions.map { $0.lowercased() })
        return groups.values
            .filter { group in
                group.count >= 2 && group.people.contains { !selected.contains($0.lowercased()) }
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.id < $1.id
            }
            .prefix(4)
            .map { $0 }
    }

    private var frequentPlaces: [ReusablePlace] {
        var places: [String: ReusablePlace] = [:]

        for previousEntry in previousEntries {
            let name = previousEntry.wrappedPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()

            if var existing = places[key] {
                existing.count += 1
                if !existing.hasCoordinates, previousEntry.hasPlaceCoordinates {
                    existing = ReusablePlace(
                        place: existing.place,
                        city: previousEntry.wrappedPlaceCity,
                        latitude: previousEntry.placeLatitude,
                        longitude: previousEntry.placeLongitude,
                        hasCoordinates: true,
                        count: existing.count
                    )
                }
                places[key] = existing
            } else {
                places[key] = ReusablePlace(
                    place: name,
                    city: previousEntry.wrappedPlaceCity,
                    latitude: previousEntry.placeLatitude,
                    longitude: previousEntry.placeLongitude,
                    hasCoordinates: previousEntry.hasPlaceCoordinates,
                    count: 1
                )
            }
        }

        return places.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.place.localizedCaseInsensitiveCompare($1.place) == .orderedAscending
            }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    whatSection
                    mealAndTimeSection
                    optionalDetails
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 28)
            }
            .background(FoodTheme.background)
            .navigationTitle(entry == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if entry != nil {
                    ToolbarItem(placement: .secondaryAction) {
                        Menu {
                            Button("Delete entry", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Entry actions")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(entry == nil ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .background(FoodTheme.background.ignoresSafeArea())
        .onAppear {
            if entry == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focusedField = .food
                }
            }
        }
        .onChange(of: locationSearch.resolvedSelection) { selection in
            guard let selection else { return }
            applyLocationSelection(selection)
            focusedField = nil
        }
        .onDisappear { locationSearch.stop() }
        .sheet(isPresented: $showingDateTimeSheet) {
            FoodLogDateTimeSheet(title: "Date & time", date: date) { date = $0 }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(isPresented: $showingCamera) { image in
                photoData = PhotoProcessor.prepare(image)
                photoMessage = photoData == nil ? "The photo could not be processed." : nil
            }
            .ignoresSafeArea()
        }
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: deleteEntry)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog("End the current fast with this entry?", isPresented: $askAboutActiveFast) {
            Button("End fast with this entry") { commitSave(endCurrentFast: true) }
            Button("Keep fast active") { commitSave(endCurrentFast: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The entry will be saved either way. Drinks are not handled differently.")
        }
        .alert("Could not save", isPresented: Binding(
            get: { fastingMessage != nil }, set: { if !$0 { fastingMessage = nil } }
        )) { Button("OK") { fastingMessage = nil } } message: { Text(fastingMessage ?? "") }
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What did you eat?")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.secondaryText)

            TextField("e.g. dosa and chutney", text: $food, axis: .vertical)
                .accessibilityIdentifier("food-description")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.ink)
                .lineLimit(2 ... 5)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .food)
                .padding(20)
                .frame(minHeight: 116, alignment: .topLeading)
                .foodPanel(cornerRadius: 22)

            if !suggestions.isEmpty && focusedField == .food {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                applyFoodSuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .foodGlass(cornerRadius: 10, interactive: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func applyFoodSuggestion(_ suggestion: String) {
        food = FoodSuggestionEngine.replacingCurrentSegment(in: food, with: suggestion)
        focusedField = .food
    }

    private var mealAndTimeSection: some View {
        VStack(spacing: 0) {
            whenRow
            Divider().padding(.leading, 16)
            mealMenu
        }
        .foodPanel(cornerRadius: 18)
    }

    private var whenRow: some View {
        Button {
            focusedField = nil
            showingDateTimeSheet = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Date & time")
                        .foregroundStyle(FoodTheme.ink)
                    Text("\(FoodLogFormatters.shortDate.string(from: date)) · \(FoodLogFormatters.time.string(from: date))")
                        .foregroundStyle(FoodTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date and time")
        .accessibilityValue("\(FoodLogFormatters.shortDate.string(from: date)), \(FoodLogFormatters.time.string(from: date))")
    }

    private var mealMenu: some View {
        Menu {
            ForEach(Self.mealTypes, id: \.self) { type in
                Button {
                    switchMealType(to: type)
                } label: {
                    if type == mealType {
                        Label(type, systemImage: "checkmark")
                    } else {
                        Label(type, systemImage: FoodTheme.symbol(for: type))
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text("Meal type")
                    .foregroundStyle(FoodTheme.ink)
                Spacer(minLength: 8)
                Image(systemName: FoodTheme.symbol(for: mealType))
                    .foregroundStyle(FoodTheme.color(for: mealType))
                Text(mealType)
                    .foregroundStyle(FoodTheme.secondaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(FoodTheme.secondaryText)
            }
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Meal type")
        .accessibilityValue(mealType)
    }

    private func switchMealType(to newMealType: String) {
        guard newMealType != mealType else { return }
        mealType = newMealType
        date = MealDefaultTimes.applyingDefault(for: newMealType, to: date)
    }

    private var optionalDetails: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                locationField
                contactsField

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                        .foregroundColor(FoodTheme.secondaryText)
                        .frame(width: 24)
                        .padding(.top, 3)
                    TextField("Anything you want to remember", text: $note, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .focused($focusedField, equals: .note)
                }
                .font(.system(.body, design: .rounded))
                .padding(14)
                .foodPanel(cornerRadius: 14)

                photoSection

                if let entry, fasts.contains(where: { $0.startEntryID == entry.id }) {
                    Label("A fast starts with this entry. Edit it in Fasts.", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(FoodTheme.secondaryText)
                } else {
                    Toggle("Start a fast after this meal", isOn: $startFastAfterMeal)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .accessibilityIdentifier("start-fast-after-meal")
                }
            }
            .padding(.top, 14)
        } label: {
            Text("Add details")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.secondaryText)
        }
        .tint(FoodTheme.secondaryText)
        .padding(16)
        .foodPanel(cornerRadius: 18)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Entry photo")
            }

            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        focusedField = nil
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PhotoActionButtonStyle())
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(photoData == nil ? "Photos" : "Replace", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PhotoActionButtonStyle())
                .onChange(of: selectedPhotoItem) { item in
                    guard let item else { return }
                    isLoadingPhoto = true
                    photoMessage = nil
                    Task {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data),
                                  let prepared = PhotoProcessor.prepare(image)
                            else {
                                photoMessage = "The selected photo could not be loaded."
                                isLoadingPhoto = false
                                return
                            }
                            photoData = prepared
                        } catch {
                            photoMessage = "The selected photo could not be loaded."
                        }
                        isLoadingPhoto = false
                    }
                }

                if photoData != nil {
                    Button(role: .destructive) {
                        photoData = nil
                        selectedPhotoItem = nil
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PhotoActionButtonStyle())
                    .accessibilityLabel("Remove photo")
                }
            }

            if isLoadingPhoto {
                ProgressView("Loading photo…")
                    .font(.system(.caption, design: .rounded))
            } else if let photoMessage {
                Text(photoMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
            }
        }
    }

    private var contactsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(FoodTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a companion")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(FoodTheme.secondaryText)
                    TextField("Name", text: $companionQuery)
                        .font(.system(.body, design: .rounded))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .companion)
                        .onChange(of: companionQuery) { contactsSearch.updateQuery($0) }
                        .onSubmit(addTypedCompanion)
                }

                Button {
                    contactsSearch.setEnabled(true, query: companionQuery)
                } label: {
                    Group {
                        if contactsSearch.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: contactsSearch.isEnabled ? "person.crop.circle.fill" : "person.crop.circle")
                        }
                    }
                    .foregroundColor(contactsSearch.isEnabled ? FoodTheme.onInk : FoodTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(contactsSearch.isEnabled ? FoodTheme.ink : FoodTheme.field, in: Circle())
                }
                .disabled(contactsSearch.isEnabled || contactsSearch.isLoading)
                .accessibilityLabel(contactsSearch.isEnabled ? "Contact suggestions enabled" : "Enable contact suggestions")
                .accessibilityAddTraits(contactsSearch.isEnabled ? .isSelected : [])
            }
            .padding(14)
            .foodPanel(cornerRadius: 14)

            if !selectedCompanions.isEmpty || !frequentPeople.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedCompanions, id: \.self) { name in
                            companionChip(name, isSelected: true)
                        }

                        ForEach(frequentPeople, id: \.self) { name in
                            companionChip(name, isSelected: false)
                        }
                    }
                }
            }

            if !frequentCompanionGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentCompanionGroups) { group in
                            Button {
                                group.people.forEach(addCompanion)
                            } label: {
                                Label(group.people.joined(separator: " + "), systemImage: "person.2.fill")
                                    .lineLimit(1)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(FoodTheme.field, in: Capsule())
                            }
                            .accessibilityHint("Adds each person")
                        }
                    }
                }
            }

            if !companionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addTypedCompanion) {
                    Label("Add \(companionQuery.trimmingCharacters(in: .whitespacesAndNewlines))", systemImage: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(FoodTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(FoodTheme.field, in: Capsule())
                }
            }

            if contactsSearch.isEnabled && focusedField == .companion && !contactSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(contactSuggestions.enumerated()), id: \.offset) { index, name in
                        Button {
                            addCompanion(name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .foregroundColor(FoodTheme.secondaryText)
                                    .frame(width: 20)
                                Text(name)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        if index < contactSuggestions.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .foodPanel(cornerRadius: 14)
            }

            if let message = contactsSearch.message {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
                    .padding(.horizontal, 4)
            }

        }
    }

    private func companionChip(_ name: String, isSelected: Bool) -> some View {
        Button {
            if isSelected {
                removeCompanion(name)
            } else {
                addCompanion(name)
            }
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(isSelected ? FoodTheme.onInk : FoodTheme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(isSelected ? FoodTheme.ink : FoodTheme.field, in: Capsule())
        }
        .accessibilityLabel(isSelected ? "\(name), selected" : name)
        .accessibilityHint(isSelected ? "Removes companion" : "Adds companion")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func addTypedCompanion() {
        addCompanion(companionQuery)
    }

    private func addCompanion(_ name: String) {
        let normalized = CompanionNames.normalized([name])
        guard let name = normalized.first,
              !selectedCompanions.contains(where: {
                  $0.caseInsensitiveCompare(name) == .orderedSame
              })
        else {
            companionQuery = ""
            contactsSearch.updateQuery("")
            return
        }

        selectedCompanions.append(name)
        companionQuery = ""
        contactsSearch.updateQuery("")
        focusedField = .companion
    }

    private func removeCompanion(_ name: String) {
        selectedCompanions.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(FoodTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Where?")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(FoodTheme.secondaryText)
                    TextField("Home, restaurant, office…", text: $place)
                        .font(.system(.body, design: .rounded))
                        .focused($focusedField, equals: .place)
                        .onChange(of: place) { updatedPlace in
                            locationSearch.updateQuery(updatedPlace)
                            guard selectedPlaceLabel?.caseInsensitiveCompare(updatedPlace) != .orderedSame else {
                                return
                            }
                            clearPlaceMetadata()
                        }
                }

                Button {
                    let enabled = !locationSearch.isEnabled
                    locationSearch.setEnabled(enabled, query: place)
                    if enabled {
                        focusedField = .place
                        locationSearch.requestNearbyRegion()
                    }
                } label: {
                    Group {
                        if locationSearch.isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .foregroundColor(locationSearch.isEnabled ? FoodTheme.onInk : FoodTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(locationSearch.isEnabled ? FoodTheme.ink : FoodTheme.field, in: Circle())
                }
                .accessibilityLabel(locationSearch.isEnabled ? "Disable location suggestions" : "Enable location suggestions")
                .accessibilityAddTraits(locationSearch.isEnabled ? .isSelected : [])
            }
            .padding(14)
            .foodPanel(cornerRadius: 14)

            if !frequentPlaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frequentPlaces) { reusablePlace in
                            let isSelected = place.caseInsensitiveCompare(reusablePlace.place) == .orderedSame
                            Button {
                                applyReusablePlace(reusablePlace)
                            } label: {
                                Text(reusablePlace.place)
                                    .lineLimit(1)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(isSelected ? FoodTheme.onInk : FoodTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? FoodTheme.ink : FoodTheme.field, in: Capsule())
                            }
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }

            if locationSearch.isEnabled && focusedField == .place && !locationSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(locationSearch.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            place = locationSearch.select(suggestion)
                            focusedField = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin")
                                    .foregroundColor(FoodTheme.secondaryText)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .foregroundColor(FoodTheme.ink)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundColor(FoodTheme.secondaryText)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        if index < locationSearch.suggestions.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .foodPanel(cornerRadius: 14)
            }

            if let message = locationSearch.message {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(FoodTheme.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func applyLocationSelection(_ selection: LocationSelection) {
        placeCity = selection.city
        placeLatitude = selection.latitude
        placeLongitude = selection.longitude
        hasPlaceCoordinates = true
        selectedPlaceSavedName = selection.displayName
        selectedPlaceLabel = selection.fullAddress
        place = selection.fullAddress
    }

    private func applyReusablePlace(_ reusablePlace: ReusablePlace) {
        placeCity = reusablePlace.city
        placeLatitude = reusablePlace.latitude
        placeLongitude = reusablePlace.longitude
        hasPlaceCoordinates = reusablePlace.hasCoordinates
        selectedPlaceSavedName = reusablePlace.place
        selectedPlaceLabel = reusablePlace.place
        place = reusablePlace.place
        focusedField = nil
    }

    private func clearPlaceMetadata() {
        placeCity = ""
        placeLatitude = 0
        placeLongitude = 0
        hasPlaceCoordinates = false
        selectedPlaceSavedName = nil
        selectedPlaceLabel = nil
    }

    private func detailField(
        icon: String,
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(FoodTheme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(FoodTheme.secondaryText)
                TextField(placeholder, text: text)
                    .font(.system(.body, design: .rounded))
                    .focused($focusedField, equals: field)
            }
        }
        .padding(14)
        .foodPanel(cornerRadius: 14)
    }

    private func save() {
        let trimmedFood = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFood.isEmpty else { return }

        if let active = fasts.first(where: { $0.endDate == nil }),
           (entry == nil || active.startEntryID != entry?.id),
           let start = active.startDate, date > start {
            askAboutActiveFast = true
        } else {
            commitSave(endCurrentFast: false)
        }
    }

    private func commitSave(endCurrentFast: Bool) {
        let trimmedFood = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFood.isEmpty else { return }
        let active = fasts.first(where: { $0.endDate == nil })
        if startFastAfterMeal && active != nil && !endCurrentFast {
            fastingMessage = "End the current fast before starting another one."
            return
        }

        let target = entry ?? FoodEntry(context: context)
        if target.id == nil { target.id = UUID() }
        if target.createdAt == nil { target.createdAt = Date() }
        target.food = trimmedFood
        target.date = date
        target.mealType = mealType
        target.place = PlaceFormatting.savedPlaceName(
            typedValue: place,
            selectedDisplayName: selectedPlaceSavedName,
            hasCoordinates: hasPlaceCoordinates
        )
        target.placeCity = placeCity
        target.placeLatitude = placeLatitude
        target.placeLongitude = placeLongitude
        target.hasPlaceCoordinates = hasPlaceCoordinates
        target.replaceCompanions(with: selectedCompanions, in: context)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.photoData = photoData

        do {
            if entry != nil { try FastingStore.entryDateChanged(target, in: context) }
            if endCurrentFast, let active { try FastingStore.end(active, at: date, with: target.id) }
            if startFastAfterMeal {
                try FastingStore.create(start: date,
                                        target: FastTargetPreference.seconds(for: defaultFastTargetHours),
                                        startEntryID: target.id, in: context)
            }
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            context.rollback()
            fastingMessage = error.localizedDescription
        }
    }

    private func deleteEntry() {
        guard let entry else { return }
        do {
            try FastingStore.detachEntry(entry, in: context)
            context.delete(entry)
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            fastingMessage = error.localizedDescription
        }
    }

    private static func hasDetails(_ entry: FoodEntry?) -> Bool {
        guard let entry else { return false }
        return !entry.wrappedPlace.isEmpty
            || !entry.companionNames.isEmpty
            || !entry.wrappedNote.isEmpty
            || entry.photoData != nil
    }
}

private struct PhotoActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(FoodTheme.ink)
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .foodGlass(cornerRadius: 12, interactive: true)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private enum PhotoProcessor {
    static func prepare(_ image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 1_600
        let largestDimension = max(image.size.width, image.size.height)
        guard largestDimension > 0 else { return nil }
        let scale = min(1, maximumDimension / largestDimension)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
