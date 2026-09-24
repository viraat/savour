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
    case patterns = "Patterns"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .journal: return "book.closed.fill"
        case .patterns: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct FoodLogRootView: View {
    @State private var selectedTab: FoodTab = .journal
    @State private var addingEntry = false

    @ViewBuilder
    var body: some View {
        NavigationStack {
            selectedContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FoodBottomBar(selection: $selectedTab, addEntry: addEntry)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(FoodTheme.background)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {})
                .zIndex(10)
        }
        .sheet(isPresented: $addingEntry, content: entrySheet)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .journal:
            JournalView()
        case .patterns:
            PatternsView()
        case .settings:
            FoodLogSettingsView()
        }
    }

    private func entrySheet() -> some View {
        FoodEntryEditor(entry: nil)
            .presentationDragIndicator(.visible)
    }

    private func addEntry() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        addingEntry = true
    }
}

private struct FoodBottomBar: View {
    @Environment(\.foodAccentColor) private var accentColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: FoodTab
    let addEntry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(FoodTab.allCases, id: \.self) { tab in
                    navigationButton(for: tab)
                }
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .foodGlass(cornerRadius: 32)

            addButton
        }
    }

    private func navigationButton(for tab: FoodTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.rawValue)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
            }
            .foregroundStyle(selection == tab ? FoodTheme.ink : FoodTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .background(
                selection == tab ? Color(uiColor: .tertiarySystemFill) : .clear,
                in: Capsule()
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    private var addButton: some View {
        Button(action: addEntry) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .frame(width: 48, height: 48)
        }
        .foodPrimaryActionStyle()
        .buttonBorderShape(.capsule)
        .tint(accentColor)
        .foregroundStyle(FoodTheme.onAccent)
        .accessibilityLabel("Add entry")
        .accessibilityHint("Opens the food entry sheet")
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
