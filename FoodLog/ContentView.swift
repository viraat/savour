import CoreData
import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("foodLogAppearance") private var appearance = 0
    @AppStorage(FoodAccentOption.settingKey) private var accentValue = FoodAccentOption.teal.rawValue

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private var accentColor: Color {
        FoodAccentOption(rawValue: accentValue)?.color ?? FoodAccentOption.teal.color
    }

    var body: some View {
        FoodLogRootView()
            .preferredColorScheme(preferredScheme)
            .tint(accentColor)
            .environment(\.foodAccentColor, accentColor)
    }
}

private enum FoodTab: String, CaseIterable {
    case journal = "Journal"
    case fasts = "Fasts"
    case patterns = "Patterns"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .journal: return "book.closed.fill"
        case .fasts: return "hourglass"
        case .patterns: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct FoodLogRootView: View {
    private struct EditorPresentation: Identifiable {
        let id = UUID()
        let entry: FoodEntry?
        let draftKey: FoodEntryDraftKey?
    }

    @Environment(\.managedObjectContext) private var context
    @State private var selectedTab: FoodTab = .journal
    @State private var editorPresentation: EditorPresentation?

    @ViewBuilder
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(FoodTab.allCases, id: \.self) { tab in
                NavigationStack {
                    content(for: tab)
                        .modifier(FoodBottomAddAction(action: addEntry))
                }
                .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                .tag(tab)
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            FoodEntryEditor(entry: presentation.entry, draftKey: presentation.draftKey)
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: resumeInterruptedDraft)
    }

    @ViewBuilder
    private func content(for tab: FoodTab) -> some View {
        switch tab {
        case .journal:
            JournalView()
        case .fasts:
            FastSessionsView()
        case .patterns:
            PatternsView()
        case .settings:
            FoodLogSettingsView()
        }
    }

    private func addEntry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editorPresentation = EditorPresentation(entry: nil, draftKey: .new)
    }

    private func resumeInterruptedDraft() {
        guard editorPresentation == nil,
              let key = try? FoodEntryDraftStore.shared.activeDraftKey() else { return }
        let entry: FoodEntry?
        if case let .edit(id) = key {
            let request: NSFetchRequest<FoodEntry> = FoodEntry.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            entry = try? context.fetch(request).first
        } else {
            entry = nil
        }
        DispatchQueue.main.async {
            guard editorPresentation == nil else { return }
            editorPresentation = EditorPresentation(entry: entry, draftKey: key)
        }
    }
}

private struct FoodBottomAddAction: ViewModifier {
    let action: () -> Void

    // A real TabView owns navigation and its selection animation. Add is an
    // action, not a fifth (or search-role) tab. safeAreaBar registers the control
    // with the system scroll edge effect and reserves room for the final row.
    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, alignment: .trailing, spacing: 0) {
                control
            }
        } else {
            content.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                control
            }
        }
#else
        content.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            control
        }
#endif
    }

    private var control: some View {
        roundButton
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private var roundButton: some View {
        if #available(iOS 17.0, *) {
            button.buttonBorderShape(.circle)
        } else {
            button.buttonBorderShape(.capsule)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label("Add entry", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2)
        }
        .controlSize(.large)
        .foodSecondaryActionStyle()
        .accessibilityLabel("Add entry")
        .accessibilityHint("Opens the food entry sheet")
        .accessibilityIdentifier("bottom-add-entry")
    }
}

struct FoodPageHeader<Actions: View>: View {
    let title: String
    let identifier: String
    let actions: Actions

    init(_ title: String, identifier: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.identifier = identifier
        self.actions = actions()
    }

    private var heading: some View {
        Text(title)
            .font(.system(.largeTitle).weight(.bold))
            .foregroundStyle(FoodTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            actions
        }
        .fixedSize()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                heading.fixedSize()
                Spacer(minLength: 0)
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                heading
                HStack { Spacer(); controls }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

extension FoodPageHeader where Actions == EmptyView {
    init(_ title: String, identifier: String) {
        self.init(title, identifier: identifier) { EmptyView() }
    }
}

enum FoodTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let onInk = Color(uiColor: .systemBackground)
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let secondaryText = Color(uiColor: .label).opacity(0.75)
    static let outline = Color(uiColor: .separator).opacity(0.35)
    static let fastGoalBorder = Color(uiColor: UIColor { traits in
        UIColor(Color(hex: traits.userInterfaceStyle == .dark ? "D4D8DE" : "777F8A"))
    })
    static func color(for mealType: String) -> Color {
        switch mealType {
        case "Breakfast": return Color(hex: "E9A23B")
        case "Lunch": return Color(hex: "5AAE78")
        case "Dinner": return Color(hex: "6D7FE8")
        case "Snack": return Color(hex: "D982A6")
        case "Drink": return Color(hex: "55A8C8")
        default: return Color(hex: "9B8A7E")
        }
    }

    static func symbol(for mealType: String) -> String {
        switch mealType {
        case "Breakfast": return "sunrise.fill"
        case "Lunch": return "leaf.fill"
        case "Dinner": return "fork.knife"
        case "Snack": return "takeoutbag.and.cup.and.straw.fill"
        case "Drink": return "cup.and.saucer.fill"
        default: return "ellipsis"
        }
    }
}

enum FoodAccentOption: String, CaseIterable, Identifiable {
    static let settingKey = "foodLogAccentColor"

    case teal = "30BA8F"
    case ocean = "3498B8"
    case blue = "4E86D8"
    case violet = "8A70C9"
    case rose = "D56F8C"

    var id: String { rawValue }
    var color: Color {
        Color(uiColor: UIColor { traits in
            let hex: String
            if traits.userInterfaceStyle == .dark {
                switch self {
                case .teal: hex = "65DDB7"
                case .ocean: hex = "73C8E2"
                case .blue: hex = "9AC1FF"
                case .violet: hex = "C6A8FF"
                case .rose: hex = "FFADC4"
                }
            } else {
                switch self {
                case .teal: hex = "087A5B"
                case .ocean: hex = "006C89"
                case .blue: hex = "2B5FAB"
                case .violet: hex = "6947A3"
                case .rose: hex = "A74162"
                }
            }
            return UIColor(Color(hex: hex))
        })
    }

    var name: String {
        switch self {
        case .teal: return "Teal"
        case .ocean: return "Ocean"
        case .blue: return "Blue"
        case .violet: return "Violet"
        case .rose: return "Rose"
        }
    }
}

private struct FoodAccentColorKey: EnvironmentKey {
    static let defaultValue = FoodAccentOption.teal.color
}

extension EnvironmentValues {
    var foodAccentColor: Color {
        get { self[FoodAccentColorKey.self] }
        set { self[FoodAccentColorKey.self] = newValue }
    }
}

private struct FoodPrimaryActionModifier: ViewModifier {
    @Environment(\.foodAccentColor) private var accentColor

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
                .tint(accentColor)
        }
#else
        content.buttonStyle(.borderedProminent)
            .tint(accentColor)
#endif
    }
}

private struct FoodSecondaryActionModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
#else
        content.buttonStyle(.bordered)
#endif
    }
}

private struct FoodGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
#else
        content.background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
#endif
    }
}

private struct FoodPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(FoodTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FoodTheme.outline, lineWidth: 0.5)
            }
    }
}

extension View {
    func foodSecondaryActionStyle() -> some View {
        modifier(FoodSecondaryActionModifier())
    }

    func foodPrimaryActionStyle() -> some View {
        modifier(FoodPrimaryActionModifier())
    }

    func foodGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(FoodGlassModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func foodPanel(cornerRadius: CGFloat) -> some View {
        modifier(FoodPanelModifier(cornerRadius: cornerRadius))
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}

enum FoodLogFormatters {
    static let dayHeading: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct EntryDayGroup: Identifiable {
    let date: Date
    let entries: [FoodEntry]
    var id: Date { date }
}

func groupEntriesByDay(_ entries: [FoodEntry]) -> [EntryDayGroup] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.wrappedDate) }
    return grouped.keys.sorted(by: >).map { day in
        EntryDayGroup(date: day, entries: grouped[day, default: []].sorted { $0.wrappedDate > $1.wrappedDate })
    }
}
