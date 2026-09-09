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
    @State private var isEditingTime = false
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
        _mealType = State(initialValue: entry?.wrappedMealType ?? Self.suggestedMealType(for: initialDate))
        _place = State(initialValue: entry?.wrappedPlace ?? "")
        _placeCity = State(initialValue: entry?.wrappedPlaceCity ?? "")
        _placeLatitude = State(initialValue: entry?.placeLatitude ?? 0)
        _placeLongitude = State(initialValue: entry?.placeLongitude ?? 0)
        _hasPlaceCoordinates = State(initialValue: entry?.hasPlaceCoordinates ?? false)
        _selectedPlaceLabel = State(initialValue: entry?.hasPlaceCoordinates == true ? entry?.wrappedPlace : nil)
        _selectedCompanions = State(initialValue: entry?.companionNames ?? [])
        _note = State(initialValue: entry?.wrappedNote ?? "")
        _photoData = State(initialValue: entry?.photoData)
        _detailsExpanded = State(initialValue: Self.hasDetails(entry))
    }

    private var canSave: Bool {
        !food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestions: [String] {
        var counts: [String: (name: String, count: Int)] = [:]

        for previousEntry in previousEntries where previousEntry.wrappedMealType == mealType {
            var countedForEntry = Set<String>()
            for item in Self.foodItems(in: previousEntry.wrappedFood) {
                let key = item.lowercased()
                guard countedForEntry.insert(key).inserted else { continue }
                let current = counts[key] ?? (item, 0)
                counts[key] = (current.name, current.count + 1)
            }
        }

        let currentItems = Set(Self.foodItems(in: food).map { $0.lowercased() })
        return counts.values
            .filter { !currentItems.contains($0.name.lowercased()) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(8)
            .map(\.name)
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
        VStack(spacing: 0) {
            topBar

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

            Button(action: save) {
                Text(entry == nil ? "Add to food log" : "Save changes")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundColor(FoodTheme.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        canSave ? FoodTheme.ink : FoodTheme.secondaryText.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(PressButtonStyle())
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(FoodTheme.background)
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
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FoodTheme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(FoodTheme.surface, in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            Text(entry == nil ? "New entry" : "Edit entry")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundColor(FoodTheme.ink)

            Spacer()

            if entry != nil {
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Delete entry")
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What did you eat?")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.secondaryText)

            TextField("e.g. dosa and chutney", text: $food, axis: .vertical)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(FoodTheme.ink)
                .lineLimit(2 ... 5)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .food)
                .padding(20)
                .frame(minHeight: 116, alignment: .topLeading)
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            if !suggestions.isEmpty && focusedField == .food {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                appendFoodSuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.ink)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(FoodTheme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private func appendFoodSuggestion(_ suggestion: String) {
        let existingItems = Self.foodItems(in: food)
        guard !existingItems.contains(where: {
            $0.caseInsensitiveCompare(suggestion) == .orderedSame
        }) else { return }

        let current = food.trimmingCharacters(in: .whitespacesAndNewlines)
        food = current.isEmpty ? suggestion : "\(current), \(suggestion)"
        focusedField = .food
    }

    private var mealAndTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                mealMenu
                datePicker
                timeButton
                Spacer(minLength: 0)
            }

            if isEditingTime {
                HStack(spacing: 8) {
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    Spacer(minLength: 4)

                    Button("Now", action: setTimeToNow)
                        .accessibilityLabel("Set time to now")
                    Button("−5 min") { adjustTime(by: -5) }
                        .accessibilityLabel("Subtract 5 minutes")
                    Button("+5 min") { adjustTime(by: 5) }
                        .accessibilityLabel("Add 5 minutes")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(FoodTheme.secondaryText)
                .padding(10)
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var mealMenu: some View {
        Menu {
            ForEach(Self.mealTypes, id: \.self) { type in
                Button {
                    switchMealType(to: type)
                } label: {
                    if type == mealType {
                        Label("\(FoodTheme.emoji(for: type))  \(type)", systemImage: "checkmark")
                    } else {
                        Text("\(FoodTheme.emoji(for: type))  \(type)")
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(FoodTheme.emoji(for: mealType))
                Text(mealType)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundColor(FoodTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 9)
            .frame(height: 40)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var datePicker: some View {
        DatePicker("Date", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .controlSize(.small)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var timeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEditingTime.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(FoodLogFormatters.time.string(from: date))
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundColor(FoodTheme.ink)
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Change time, currently \(FoodLogFormatters.time.string(from: date))")
    }

    private func switchMealType(to newMealType: String) {
        guard newMealType != mealType else { return }
        mealType = newMealType
        date = MealDefaultTimes.applyingDefault(for: newMealType, to: date)
    }

    private func adjustTime(by minuteOffset: Int) {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        let adjustedMinutes = (currentMinutes + minuteOffset + 24 * 60) % (24 * 60)
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.hour = adjustedMinutes / 60
        components.minute = adjustedMinutes % 60
        components.second = 0
        date = calendar.date(from: components) ?? date
    }

    private func setTimeToNow() {
        let calendar = Calendar.current
        let currentTime = calendar.dateComponents([.hour, .minute], from: Date())
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.hour = currentTime.hour
        components.minute = currentTime.minute
        components.second = 0
        date = calendar.date(from: components) ?? date
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
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                photoSection
            }
            .padding(.top, 14)
        } label: {
            Text("Add details")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(FoodTheme.secondaryText)
        }
        .tint(FoodTheme.secondaryText)
        .padding(16)
        .background(FoodTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .frame(width: 36, height: 36)
                    .background(contactsSearch.isEnabled ? FoodTheme.ink : FoodTheme.field, in: Circle())
                }
                .disabled(contactsSearch.isEnabled || contactsSearch.isLoading)
                .accessibilityLabel(contactsSearch.isEnabled ? "Contact suggestions enabled" : "Enable contact suggestions")
                .accessibilityAddTraits(contactsSearch.isEnabled ? .isSelected : [])
            }
            .padding(14)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .frame(width: 36, height: 36)
                    .background(locationSearch.isEnabled ? FoodTheme.ink : FoodTheme.field, in: Circle())
                }
                .accessibilityLabel(locationSearch.isEnabled ? "Disable location suggestions" : "Enable location suggestions")
                .accessibilityAddTraits(locationSearch.isEnabled ? .isSelected : [])
            }
            .padding(14)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                                Text(suggestion.title)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundColor(FoodTheme.ink)
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
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        selectedPlaceLabel = selection.displayName
        place = selection.displayName
    }

    private func applyReusablePlace(_ reusablePlace: ReusablePlace) {
        placeCity = reusablePlace.city
        placeLatitude = reusablePlace.latitude
        placeLongitude = reusablePlace.longitude
        hasPlaceCoordinates = reusablePlace.hasCoordinates
        selectedPlaceLabel = reusablePlace.place
        place = reusablePlace.place
        focusedField = nil
    }

    private func clearPlaceMetadata() {
        placeCity = ""
        placeLatitude = 0
        placeLongitude = 0
        hasPlaceCoordinates = false
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
        .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        let trimmedFood = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFood.isEmpty else { return }

        let target = entry ?? FoodEntry(context: context)
        if target.id == nil { target.id = UUID() }
        if target.createdAt == nil { target.createdAt = Date() }
        target.food = trimmedFood
        target.date = date
        target.mealType = mealType
        target.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        target.placeCity = placeCity
        target.placeLatitude = placeLatitude
        target.placeLongitude = placeLongitude
        target.hasPlaceCoordinates = hasPlaceCoordinates
        target.replaceCompanions(with: selectedCompanions, in: context)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.photoData = photoData

        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteEntry() {
        guard let entry else { return }
        context.delete(entry)
        try? context.save()
        dismiss()
    }

    private static func suggestedMealType(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5 ..< 11: return "Breakfast"
        case 11 ..< 15: return "Lunch"
        case 18 ..< 23: return "Dinner"
        default: return "Snack"
        }
    }

    private static func foodItems(in description: String) -> [String] {
        description.split(separator: ",", omittingEmptySubsequences: true).compactMap { item in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
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
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
