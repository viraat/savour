import Charts
import SwiftUI

/// When meals happen: one column per day and one dot per meal at its time of
/// day, coloured by meal type, mornings at the top. Shared by the Journal week
/// card and the Patterns "When" section; it shows rhythm, never a score.
struct FoodRhythmChart: View {
    let points: [FoodPatterns.RhythmPoint]
    let days: [Date]
    let calendar: Calendar
    var height: CGFloat = 170
    var onSelectDay: ((Date) -> Void)?

    private static let hour = 60

    /// Plotted upside down (minutes before midnight) so mornings sit at the top.
    private func plotted(_ minute: Int) -> Int { 1_440 - minute }

    /// 6 am to 10 pm by default, widened to the hour around any earlier or later meal.
    private var minuteRange: ClosedRange<Int> {
        let minutes = points.map(\.minute)
        let lower = min(minutes.min() ?? 6 * Self.hour, 6 * Self.hour) / Self.hour * Self.hour
        let upper = min(1_440, (max(minutes.max() ?? 22 * Self.hour, 22 * Self.hour) + Self.hour - 1) / Self.hour * Self.hour)
        return lower ... max(upper, lower + Self.hour)
    }

    private var mealTypes: [String] {
        let present = Set(points.map(\.mealType))
        return FoodEntryEditor.mealTypes.filter(present.contains)
    }

    private var xDomain: ClosedRange<Date> {
        let first = days.first ?? calendar.startOfDay(for: Date())
        let last = days.last ?? first
        return first ... (calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    private var axisHours: [Int] {
        stride(from: minuteRange.lowerBound, through: minuteRange.upperBound, by: 6 * Self.hour)
            .filter { $0 % (6 * Self.hour) == 0 }
    }

    var body: some View {
        if points.isEmpty {
            Text("Meals you log will appear here by time of day.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FoodTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: height / 2)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            PointMark(x: .value("Day", point.day, unit: .day),
                      y: .value("Time", plotted(point.minute)))
                .foregroundStyle(by: .value("Meal", point.mealType))
                .symbolSize(point.mealType == "Drink" ? 28 : 64)
        }
        .chartForegroundStyleScale(domain: mealTypes, range: mealTypes.map(FoodTheme.color(for:)))
        .chartXScale(domain: xDomain)
        .chartYScale(domain: plotted(minuteRange.upperBound) ... plotted(minuteRange.lowerBound))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 10 ? 7 : 1)) { value in
                AxisGridLine()
                AxisValueLabel(centered: days.count <= 10) {
                    if let date = value.as(Date.self) {
                        Text(days.count <= 10
                             ? date.formatted(.dateTime.weekday(.narrow))
                             : date.formatted(.dateTime.day().month(.abbreviated)))
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: axisHours.map(plotted)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let plottedMinute = value.as(Int.self) {
                        Text(timeLabel(1_440 - plottedMinute))
                            .foregroundStyle(FoodTheme.secondaryText)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(mealTypes, id: \.self) { type in
                    HStack(spacing: 5) {
                        Circle().fill(FoodTheme.color(for: type)).frame(width: 8, height: 8)
                        Text(type)
                    }
                }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(FoodTheme.secondaryText)
        }
        .chartOverlay { proxy in
            if let onSelectDay {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            if let date: Date = proxy.value(atX: x) {
                                onSelectDay(calendar.startOfDay(for: date))
                            }
                        }
                }
            }
        }
        .frame(height: height)
        // One element with a spoken summary: per-dot elements are narrower than
        // a usable touch target and slow to step through.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal times")
        .accessibilityValue(spokenSummary)
        .accessibilityIdentifier("food-rhythm-chart")
    }

    /// "Fri 9 Oct: Breakfast 8:00 AM, Dinner 8:00 PM; …" for days with meals.
    private var spokenSummary: String {
        let byDay = Dictionary(grouping: points, by: \.day)
        return days.compactMap { day -> String? in
            guard let meals = byDay[day] else { return nil }
            let times = meals.map { "\($0.mealType) \(spokenTime($0.minute))" }.joined(separator: ", ")
            return "\(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(times)"
        }
        .joined(separator: "; ")
    }

    private func spokenTime(_ minute: Int) -> String {
        let date = calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: Date())) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func timeLabel(_ minute: Int) -> String {
        let date = calendar.date(byAdding: .minute, value: minute % 1_440,
                                 to: calendar.startOfDay(for: Date())) ?? Date()
        return minute == 12 * Self.hour ? "Noon" : date.formatted(.dateTime.hour())
    }
}

/// When meals happen over a longer range, as one row per meal type: a line
/// from the earliest to the latest time, a bar for the usual middle half and a
/// tick at the median. Dots per meal get too dense beyond a week.
struct FoodTimeSpreadChart: View {
    let spreads: [FoodPatterns.TimeSpread]
    let calendar: Calendar

    private static let hour = 60

    /// 6 am to 10 pm by default, widened to the hour around any earlier or later meal.
    private var minuteRange: ClosedRange<Int> {
        let lower = min(spreads.map(\.earliest).min() ?? 6 * Self.hour, 6 * Self.hour) / Self.hour * Self.hour
        let latest = max(spreads.map(\.latest).max() ?? 22 * Self.hour, 22 * Self.hour)
        let upper = min(1_440, (latest + Self.hour - 1) / Self.hour * Self.hour)
        // Half an hour either side keeps the edge hour labels centred on their lines.
        return max(0, lower - Self.hour / 2) ... min(1_440, max(upper, lower + Self.hour) + Self.hour / 2)
    }

    private var axisHours: [Int] {
        stride(from: 0, through: 1_440, by: 6 * Self.hour).filter(minuteRange.contains)
    }

    var body: some View {
        if spreads.isEmpty {
            Text("Meals you log will appear here by time of day.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(FoodTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chart
                Text("Line: earliest to latest · bar: the middle half · tick: the middle meal")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(FoodTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(spreads, id: \.mealType) { spread in
                HStack(spacing: 10) {
                    Text(spread.mealType)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(FoodTheme.secondaryText)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    GeometryReader { geometry in
                        let x = { (minute: Int) in self.x(minute, width: geometry.size.width) }
                        let color = FoodTheme.color(for: spread.mealType)
                        let mid = geometry.size.height / 2
                        ZStack(alignment: .topLeading) {
                            Capsule().fill(color.opacity(0.55))
                                .frame(width: max(2, x(spread.latest) - x(spread.earliest)), height: 2)
                                .position(x: (x(spread.earliest) + x(spread.latest)) / 2, y: mid)
                            Capsule().fill(color.opacity(0.85))
                                .frame(width: max(8, x(spread.upperQuartile) - x(spread.lowerQuartile)), height: 14)
                                .position(x: (x(spread.lowerQuartile) + x(spread.upperQuartile)) / 2, y: mid)
                            Capsule().fill(FoodTheme.ink)
                                .frame(width: 3, height: 22)
                                .position(x: x(spread.median), y: mid)
                        }
                    }
                    .frame(height: 30)
                    .background(alignment: .leading) { gridLines }
                }
            }
            HStack(spacing: 10) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                GeometryReader { geometry in
                    ForEach(axisHours, id: \.self) { minute in
                        Text(timeLabel(minute))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(FoodTheme.secondaryText)
                            .fixedSize()
                            .position(x: x(minute, width: geometry.size.width), y: 8)
                    }
                }
                .frame(height: 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal times")
        .accessibilityValue(spokenSummary)
        .accessibilityIdentifier("food-time-spread-chart")
    }

    private static let labelWidth: CGFloat = 70

    private func x(_ minute: Int, width: CGFloat) -> CGFloat {
        let span = CGFloat(minuteRange.upperBound - minuteRange.lowerBound)
        return CGFloat(minute - minuteRange.lowerBound) / span * width
    }

    private var gridLines: some View {
        GeometryReader { geometry in
            ForEach(axisHours, id: \.self) { minute in
                Rectangle().fill(FoodTheme.secondaryText.opacity(0.25))
                    .frame(width: 1)
                    .position(x: x(minute, width: geometry.size.width), y: geometry.size.height / 2)
                    .frame(height: geometry.size.height)
            }
        }
    }

    /// "Breakfast, 24 meals: usually 8:00 to 9:00 AM, middle 8:30 AM, earliest 7:00 AM, latest 11:00 AM; …"
    private var spokenSummary: String {
        spreads.map { spread in
            "\(spread.mealType), \(spread.count) \(spread.count == 1 ? "meal" : "meals"): usually \(spokenTime(spread.lowerQuartile)) to \(spokenTime(spread.upperQuartile)), middle \(spokenTime(spread.median)), earliest \(spokenTime(spread.earliest)), latest \(spokenTime(spread.latest))"
        }
        .joined(separator: "; ")
    }

    private func spokenTime(_ minute: Int) -> String {
        let date = calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: Date())) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func timeLabel(_ minute: Int) -> String {
        let date = calendar.date(byAdding: .minute, value: minute % 1_440,
                                 to: calendar.startOfDay(for: Date())) ?? Date()
        return minute == 12 * Self.hour ? "Noon" : date.formatted(.dateTime.hour())
    }
}

extension FoodEntry {
    /// The Core Data-free form that pattern calculations work on.
    var patternMeal: PatternMeal {
        PatternMeal(date: wrappedDate, mealType: wrappedMealType, food: wrappedFood,
                    place: wrappedPlace, companions: companionNames)
    }
}
