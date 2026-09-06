import CoreData
import PhotosUI
import SwiftUI
import UIKit

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
    @State private var people: String
    @State private var note: String
    @State private var photoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isLoadingPhoto = false
    @State private var photoMessage: String?
    @State private var confirmDelete = false
    @StateObject private var locationSearch = LocationSearchModel()
    @StateObject private var contactsSearch = ContactsSearchModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case food, place, people, note
    }

    init(entry: FoodEntry?) {
        self.entry = entry
        let initialDate = entry?.wrappedDate ?? Date()
        _food = State(initialValue: entry?.wrappedFood ?? "")
        _date = State(initialValue: initialDate)
        _mealType = State(initialValue: entry?.wrappedMealType ?? Self.suggestedMealType(for: initialDate))
        _place = State(initialValue: entry?.wrappedPlace ?? "")
        _people = State(initialValue: entry?.wrappedPeople ?? "")
        _note = State(initialValue: entry?.wrappedNote ?? "")
        _photoData = State(initialValue: entry?.photoData)
    }

    private var canSave: Bool {
        !food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var suggestions: [String] {
        let query = food.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return previousEntries.compactMap { item in
            let candidate = item.wrappedFood
            guard !candidate.isEmpty,
                  candidate.caseInsensitiveCompare(query) != .orderedSame,
                  query.isEmpty || candidate.localizedCaseInsensitiveContains(query),
                  seen.insert(candidate.lowercased()).inserted
            else { return nil }
            return candidate
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    whatSection
                    mealSection
                    whenSection
                    optionalDetails
                }
                .padding(.horizontal, 20)
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
        .onChange(of: locationSearch.resolvedPlace) { resolvedPlace in
            guard let resolvedPlace else { return }
            place = resolvedPlace
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
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT DID YOU EAT?")
                .sectionLabel()

            TextField("e.g. dosa and chutney", text: $food, axis: .vertical)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundColor(FoodTheme.ink)
                .lineLimit(1 ... 4)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .food)
                .padding(16)
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !suggestions.isEmpty && focusedField == .food {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                food = suggestion
                                focusedField = nil
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

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEAL")
                .sectionLabel()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.mealTypes, id: \.self) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { mealType = type }
                        } label: {
                            HStack(spacing: 6) {
                                Text(FoodTheme.emoji(for: type))
                                Text(type)
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(mealType == type ? .white : FoodTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                mealType == type ? FoodTheme.color(for: type) : FoodTheme.surface,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                        }
                    }
                }
            }
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHEN")
                .sectionLabel()
            DatePicker("Date and time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .padding(14)
                .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var optionalDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPTIONAL DETAILS")
                .sectionLabel()

            locationField
            contactsField
            photoSection

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
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(FoodTheme.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("With whom?")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(FoodTheme.secondaryText)
                    TextField("Friends, family…", text: $people)
                        .font(.system(.body, design: .rounded))
                        .focused($focusedField, equals: .people)
                        .onChange(of: people) { contactsSearch.updateQuery($0) }
                }

                Button {
                    contactsSearch.setEnabled(!contactsSearch.isEnabled, query: people)
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
                .accessibilityLabel(contactsSearch.isEnabled ? "Disable contact suggestions" : "Enable contact suggestions")
                .accessibilityAddTraits(contactsSearch.isEnabled ? .isSelected : [])
            }
            .padding(14)
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if contactsSearch.isEnabled && focusedField == .people && !contactsSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(contactsSearch.suggestions.enumerated()), id: \.offset) { index, name in
                        Button {
                            people = contactsSearch.select(name, in: people)
                            focusedField = nil
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
                        if index < contactsSearch.suggestions.count - 1 {
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
                        .onChange(of: place) { locationSearch.updateQuery($0) }
                }

                Button {
                    let enabled = !locationSearch.isEnabled
                    locationSearch.setEnabled(enabled, query: place)
                    if enabled {
                        locationSearch.requestCurrentPlace()
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
        target.people = people.trimmingCharacters(in: .whitespacesAndNewlines)
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
