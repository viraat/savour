import SwiftUI

enum DateTimeSelection {
    static func roundedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }

    static func adjusting(_ date: Date, by minutes: Int) -> Date {
        roundedToMinute(date).addingTimeInterval(TimeInterval(minutes) * 60)
    }

    static func now() -> Date {
        roundedToMinute(Date())
    }
}

struct FoodLogDateTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let onDone: (Date) -> Void
    @State private var selection: Date

    init(title: String, date: Date, onDone: @escaping (Date) -> Void) {
        self.title = title
        self.onDone = onDone
        _selection = State(initialValue: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        sheetTitle
                        Spacer(minLength: 8)
                        doneButton
                    }
                } else {
                    ZStack(alignment: .trailing) {
                        sheetTitle.frame(maxWidth: .infinity)
                        doneButton
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    adjustment("−5m", label: "Subtract 5 minutes", minutes: -5)
                    adjustment("−1m", label: "Subtract 1 minute", minutes: -1)
                    Button("Now") { selection = DateTimeSelection.now() }
                        .accessibilityLabel("Set time to now")
                        .quickTimeButton()
                    adjustment("+1m", label: "Add 1 minute", minutes: 1)
                    adjustment("+5m", label: "Add 5 minutes", minutes: 5)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            DatePicker(title, selection: $selection, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("date-time-wheel")

            Spacer(minLength: 0)
        }
        .background(FoodTheme.background.ignoresSafeArea())
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(410), .large])
        .presentationDragIndicator(.visible)
    }

    private func adjustment(_ title: String, label: String, minutes: Int) -> some View {
        Button(title) { selection = DateTimeSelection.adjusting(selection, by: minutes) }
            .accessibilityLabel(label)
            .quickTimeButton()
    }

    private var sheetTitle: some View {
        Text(title)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(FoodTheme.ink)
    }

    private var doneButton: some View {
        Button("Done") {
            onDone(DateTimeSelection.roundedToMinute(selection))
            dismiss()
        }
        .font(.system(.body, design: .rounded).weight(.semibold))
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier("date-time-done")
    }
}

private extension View {
    func quickTimeButton() -> some View {
        self
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(FoodTheme.ink)
            .frame(minWidth: 48, minHeight: 44)
            .padding(.horizontal, 8)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .buttonStyle(.plain)
    }
}
