import AppIntents
import CoreData
import LocalAuthentication
import SwiftUI

enum ShortcutMealType: String, AppEnum {
    case automatic, breakfast, lunch, dinner, snack, drink, other

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal type")
    static let caseDisplayRepresentations: [ShortcutMealType: DisplayRepresentation] = [
        .automatic: "Automatic", .breakfast: "Breakfast", .lunch: "Lunch",
        .dinner: "Dinner", .snack: "Snack", .drink: "Drink", .other: "Other"
    ]

    func storedValue(for date: Date, calendar: Calendar) -> String {
        self == .automatic ? MealTypeSuggestion.suggested(for: date, calendar: calendar) : rawValue.capitalized
    }
}

enum FoodShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case emptyFood, authenticationFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyFood: return "Enter the food you ate before logging it."
        case .authenticationFailed: return "Authentication was not completed. Your food was not logged."
        }
    }
}

/// A shortcut creates a saved entry independently of any unfinished editor draft.
struct FoodShortcutEntry {
    let food: String
    let date: Date
    let mealType: String
    let place: String
    let companions: [String]
    let note: String

    init(food: String, date: Date? = nil, mealType: ShortcutMealType = .automatic,
         place: String? = nil, companions: [String]? = nil, note: String? = nil,
         now: Date = Date(), calendar: Calendar = .current) throws {
        self.food = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !self.food.isEmpty else { throw FoodShortcutError.emptyFood }
        self.date = date ?? now
        self.mealType = mealType.storedValue(for: self.date, calendar: calendar)
        self.place = (place ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.companions = CompanionNames.normalized(companions ?? [])
        self.note = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum FoodShortcutLogger {
    static func authenticateIfNeeded() async throws {
        guard UserDefaults.standard.bool(forKey: BiometricAuthentication.settingKey) else { return }
        let authentication = LAContext()
        defer { authentication.invalidate() }
        do {
            let success = try await authentication.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "Log food in your Savour journal"
            )
            guard success else { throw FoodShortcutError.authenticationFailed }
        } catch {
            throw FoodShortcutError.authenticationFailed
        }
    }

    @discardableResult
    static func save(_ input: FoodShortcutEntry, in container: NSPersistentContainer,
                     now: Date = Date(), authorize: () async throws -> Void) async throws -> UUID {
        try await authorize()
        try Task.checkCancellation()
        // Never save or roll back the view context: the editor may have unsaved work.
        let context = container.newBackgroundContext()
        context.transactionAuthor = FoodCloudSyncConfiguration.transactionAuthor
        return try await context.perform {
            do {
                try Task.checkCancellation()
                let entry = FoodEntry(context: context)
                let id = UUID()
                entry.id = id
                entry.createdAt = now
                entry.food = input.food
                entry.date = input.date
                entry.mealType = input.mealType
                entry.place = input.place
                entry.note = input.note
                entry.replaceCompanions(with: input.companions, in: context)
                try context.save()
                return id
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription(
        "Save food to your Savour journal. The time defaults to now and the meal type is suggested from that time."
    )
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Food", requestValueDialog: "What did you eat?")
    var food: String

    @Parameter(title: "Date", description: "When you ate. Leave empty to use the current time.")
    var date: Date?

    @Parameter(title: "Meal type", default: .automatic)
    var mealType: ShortcutMealType

    @Parameter(title: "Place")
    var place: String?

    @Parameter(title: "Companions")
    var companions: [String]?

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$food)") {
            \.$date
            \.$mealType
            \.$place
            \.$companions
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard !food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $food.needsValueError("What did you eat?")
        }
        let input = try FoodShortcutEntry(food: food, date: date, mealType: mealType,
                                          place: place, companions: companions, note: note)
        try await FoodShortcutLogger.save(input, in: PersistenceController.shared.container,
                                          authorize: FoodShortcutLogger.authenticateIfNeeded)
        return .result(value: input.food, dialog: "Food logged in Savour.")
    }
}

struct SavourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: [
            "Log food in \(.applicationName)",
            "Add food to \(.applicationName)",
            "Log a meal in \(.applicationName)"
        ], shortTitle: "Log Food", systemImageName: "fork.knife")
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}

struct FoodShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Say “Log food in Savour”, then tell Siri what you ate.")
                SiriTipView(intent: LogFoodIntent())
                ShortcutsLink()
            } header: {
                Text("Log with Siri")
            } footer: {
                Text("Siri saves the entry at the current time and suggests a meal type. Your device must be unlocked. With App lock enabled, authentication is required before saving.")
            }
            Section {
                Text("In Shortcuts, add Savour’s Log Food action. Supply Food directly, use Ask Each Time, or pass the result of Dictate Text.")
                Text("Expand the action to set a date, meal type, place, companions, or note. Leave the date empty to use the time the shortcut runs.")
            } header: {
                Text("Build your own shortcut")
            } footer: {
                Text("Shortcut entries appear in your journal. Any unfinished draft is kept separately.")
            }
        }
        .formStyle(.grouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(FoodTheme.background)
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
