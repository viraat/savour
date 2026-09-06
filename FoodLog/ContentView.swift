import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("foodLogAppearance") private var appearance = 0

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        FoodLogRootView()
            .preferredColorScheme(preferredScheme)
    }
}

private enum FoodTab: String, CaseIterable {
    case journal = "Journal"
    case patterns = "Patterns"
    case browse = "Browse"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .journal: return "book.closed.fill"
        case .patterns: return "chart.bar.fill"
        case .browse: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

struct FoodLogRootView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FoodEntry.date, ascending: false)],
        animation: .default
    ) private var entries: FetchedResults<FoodEntry>

    @State private var selectedTab: FoodTab = .journal
    @State private var addingEntry = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FoodTheme.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .journal:
                    JournalView(openBrowse: { selectedTab = .browse })
                case .patterns:
                    PatternsView()
                case .browse:
                    BrowseView()
                case .settings:
                    FoodLogSettingsView()
                }
            }
            .padding(.bottom, 82)

            FoodTabBar(selectedTab: $selectedTab, addingEntry: $addingEntry, isEmpty: entries.isEmpty)
        }
        .fullScreenCover(isPresented: $addingEntry) {
            FoodEntryEditor(entry: nil)
        }
    }
}

private struct FoodTabBar: View {
    @Binding var selectedTab: FoodTab
    @Binding var addingEntry: Bool
    let isEmpty: Bool

    var body: some View {
        HStack(spacing: 3) {
            tabButton(.journal)
            tabButton(.patterns)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addingEntry = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(FoodTheme.onInk)
                    .frame(width: 64, height: 40)
                    .background(FoodTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if isEmpty {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(FoodTheme.ink.opacity(0.16), lineWidth: 7)
                                .scaleEffect(1.18)
                        }
                    }
            }
            .buttonStyle(PressButtonStyle())
            .accessibilityLabel("Add food entry")

            tabButton(.browse)
            tabButton(.settings)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(FoodTheme.background.shadow(color: .black.opacity(0.05), radius: 10, y: -2))
    }

    private func tabButton(_ tab: FoodTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundColor(selectedTab == tab ? FoodTheme.ink : FoodTheme.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum FoodTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let onInk = Color(uiColor: .systemBackground)
    static let secondaryText = Color(uiColor: .secondaryLabel)
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

    static func emoji(for mealType: String) -> String {
        switch mealType {
        case "Breakfast": return "🌤️"
        case "Lunch": return "🥗"
        case "Dinner": return "🍽️"
        case "Snack": return "🍎"
        case "Drink": return "🥤"
        default: return "📝"
        }
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
