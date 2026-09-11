import Foundation

enum FoodItemParser {
    static func items(in description: String) -> [String] {
        description
            .split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }
}

struct FoodSuggestionSource {
    let mealType: String
    let food: String
}

enum FoodSuggestionEngine {
    static func suggestions(
        from sources: [FoodSuggestionSource],
        mealType: String,
        currentFood: String,
        limit: Int = 8
    ) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]

        for source in sources where source.mealType == mealType {
            var countedForEntry = Set<String>()
            for item in FoodItemParser.items(in: source.food) {
                let key = item.lowercased()
                guard countedForEntry.insert(key).inserted else { continue }
                let current = counts[key] ?? (item, 0)
                counts[key] = (current.name, current.count + 1)
            }
        }

        let selected = Set(FoodItemParser.items(in: currentFood).map { $0.lowercased() })
        return counts.values
            .filter { !selected.contains($0.name.lowercased()) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(max(limit, 0))
            .map(\.name)
    }
}

enum MealTypeSuggestion {
    static func suggested(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 11: return "Breakfast"
        case 11 ..< 15: return "Lunch"
        case 18 ..< 23: return "Dinner"
        default: return "Snack"
        }
    }
}

struct FrequencyCount: Equatable {
    let name: String
    let count: Int
}

enum FoodLogStatistics {
    static func frequencies(_ values: [String]) -> [FrequencyCount] {
        var counts: [String: FrequencyCount] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            let existing = counts[key] ?? FrequencyCount(name: trimmed, count: 0)
            counts[key] = FrequencyCount(name: existing.name, count: existing.count + 1)
        }
        return counts.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func currentStreak(
        entryDates: [Date],
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let loggedDays = Set(entryDates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: referenceDate)
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
}

enum CSVCodecError: Error, Equatable, LocalizedError {
    case unterminatedQuotedField
    case unexpectedQuote
    case charactersAfterClosingQuote
    case missingHeader
    case invalidHeader
    case wrongColumnCount(row: Int, expected: Int, actual: Int)
    case invalidCoordinate(row: Int)
    case emptyFood(row: Int)
    case invalidDate(row: Int)
    case invalidTime(row: Int)

    var errorDescription: String? {
        switch self {
        case .unterminatedQuotedField: return "A quoted field is not closed."
        case .unexpectedQuote: return "A quote appears in an unquoted field."
        case .charactersAfterClosingQuote: return "Unexpected characters follow a closing quote."
        case .missingHeader: return "The CSV header is missing."
        case .invalidHeader: return "The CSV columns do not match FoodLog."
        case let .wrongColumnCount(row, expected, actual):
            return "Row \(row) has \(actual) columns; \(expected) are required."
        case let .invalidCoordinate(row): return "Row \(row) has invalid coordinates."
        case let .emptyFood(row): return "Row \(row) has no food description."
        case let .invalidDate(row): return "Row \(row) has an invalid date."
        case let .invalidTime(row): return "Row \(row) has an invalid time."
        }
    }
}

enum CSVCodec {
    static func encode(rows: [[String]]) -> String {
        rows.map { row in
            row.map(escape).joined(separator: ",")
        }.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    static func decode(_ text: String) throws -> [[String]] {
        guard !text.isEmpty else { return [] }

        let characters = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var closedQuote = false
        var index = 0

        func finishField() {
            row.append(field)
            field = ""
            closedQuote = false
        }

        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < characters.count {
            let character = characters[index]

            if isQuoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        isQuoted = false
                        closedQuote = true
                    }
                } else {
                    field.append(character)
                }
            } else if closedQuote {
                switch character {
                case ",": finishField()
                case "\n": finishRow()
                case "\r":
                    finishRow()
                    if index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                default: throw CSVCodecError.charactersAfterClosingQuote
                }
            } else {
                switch character {
                case "\"":
                    guard field.isEmpty else { throw CSVCodecError.unexpectedQuote }
                    isQuoted = true
                case ",": finishField()
                case "\n": finishRow()
                case "\r":
                    finishRow()
                    if index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                default: field.append(character)
                }
            }
            index += 1
        }

        guard !isQuoted else { throw CSVCodecError.unterminatedQuotedField }
        if closedQuote || !field.isEmpty || !row.isEmpty {
            finishRow()
        }
        return rows
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum FoodLogCSVDocument {
    static let header = [
        "food", "date", "time", "meal", "place", "city",
        "latitude", "longitude", "people", "note"
    ]

    static func encode(dataRows: [[String]]) -> String {
        CSVCodec.encode(rows: [header] + dataRows)
    }

    static func decode(_ text: String) throws -> [[String]] {
        let rows = try CSVCodec.decode(text)
        guard let first = rows.first else { throw CSVCodecError.missingHeader }
        guard first == header else { throw CSVCodecError.invalidHeader }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.isLenient = false
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.isLenient = false

        for (index, row) in rows.dropFirst().enumerated() {
            let rowNumber = index + 2
            guard row.count == header.count else {
                throw CSVCodecError.wrongColumnCount(
                    row: rowNumber,
                    expected: header.count,
                    actual: row.count
                )
            }
            guard !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CSVCodecError.emptyFood(row: rowNumber)
            }
            guard dateFormatter.date(from: row[1]) != nil else {
                throw CSVCodecError.invalidDate(row: rowNumber)
            }
            guard timeFormatter.date(from: row[2]) != nil else {
                throw CSVCodecError.invalidTime(row: rowNumber)
            }

            let latitude = row[6]
            let longitude = row[7]
            let bothEmpty = latitude.isEmpty && longitude.isEmpty
            let validPair = Double(latitude).map { (-90 ... 90).contains($0) } == true
                && Double(longitude).map { (-180 ... 180).contains($0) } == true
            guard bothEmpty || validPair else { throw CSVCodecError.invalidCoordinate(row: rowNumber) }
        }

        return Array(rows.dropFirst())
    }
}
