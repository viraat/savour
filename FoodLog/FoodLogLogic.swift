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
    let date: Date

    init(mealType: String, food: String, date: Date = .distantPast) {
        self.mealType = mealType
        self.food = food
        self.date = date
    }
}

enum FoodSuggestionEngine {
    private struct Candidate {
        let name: String
        var count: Int
        var mealCount: Int
        var lastUsed: Date
    }

    static func suggestions(
        from sources: [FoodSuggestionSource],
        mealType: String,
        currentFood: String,
        limit: Int = 8
    ) -> [String] {
        let query = key(for: currentSegment(in: currentFood))
        let selected = Set(FoodItemParser.items(in: currentFood).map(key(for:)))
        let selectedMeal = key(for: mealType)
        var candidates: [String: Candidate] = [:]

        for source in sources {
            var countedForEntry = Set<String>()
            for item in FoodItemParser.items(in: source.food) {
                let name = normalizedWhitespace(item)
                let itemKey = key(for: name)
                guard countedForEntry.insert(itemKey).inserted else { continue }
                var candidate = candidates[itemKey] ?? Candidate(
                    name: name,
                    count: 0,
                    mealCount: 0,
                    lastUsed: .distantPast
                )
                candidate.count += 1
                if key(for: source.mealType) == selectedMeal {
                    candidate.mealCount += 1
                }
                candidate.lastUsed = max(candidate.lastUsed, source.date)
                candidates[itemKey] = candidate
            }
        }

        return candidates.compactMap { itemKey, candidate -> (Candidate, Int)? in
            guard !selected.contains(itemKey), let match = matchRank(itemKey, query: query) else {
                return nil
            }
            return (candidate, match)
        }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if ($0.0.mealCount > 0) != ($1.0.mealCount > 0) {
                    return $0.0.mealCount > 0
                }
                if $0.0.mealCount != $1.0.mealCount {
                    return $0.0.mealCount > $1.0.mealCount
                }
                if $0.0.count != $1.0.count { return $0.0.count > $1.0.count }
                if $0.0.lastUsed != $1.0.lastUsed { return $0.0.lastUsed > $1.0.lastUsed }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(max(limit, 0))
            .map { $0.0.name }
    }

    static func replacingCurrentSegment(in description: String, with suggestion: String) -> String {
        guard let comma = description.lastIndex(of: ",") else { return suggestion }
        return "\(description[...comma]) \(suggestion)"
    }

    private static func currentSegment(in description: String) -> String {
        guard let comma = description.lastIndex(of: ",") else { return description }
        return String(description[description.index(after: comma)...])
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func key(for value: String) -> String {
        normalizedWhitespace(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func matchRank(_ candidate: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if candidate.hasPrefix(query) { return 4 }
        let words = candidate.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(query) }) { return 3 }
        if candidate.contains(query) { return 2 }

        guard query.count >= 3 else { return nil }
        let distance = query.count >= 5 ? 2 : 1
        if isWithinEditDistance(query, of: candidate, limit: distance)
            || words.contains(where: { isWithinEditDistance(query, of: $0, limit: distance) }) {
            return 1
        }
        return nil
    }

    private static func isWithinEditDistance(_ query: String, of word: String, limit: Int) -> Bool {
        let left = Array(query)
        let right = Array(word)
        guard abs(left.count - right.count) <= limit else { return false }
        var previous = Array(0 ... right.count)

        for (leftIndex, character) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, other) in right.enumerated() {
                let cost = character == other ? 0 : 1
                let result = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost
                )
                current.append(result)
                rowMinimum = min(rowMinimum, result)
            }
            if rowMinimum > limit { return false }
            previous = current
        }
        return previous[right.count] <= limit
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
    case invalidID(row: Int)
    case invalidPeople(row: Int)
    case invalidTimestamp(row: Int)

    var errorDescription: String? {
        switch self {
        case .unterminatedQuotedField: return "A quoted field is not closed."
        case .unexpectedQuote: return "A quote appears in an unquoted field."
        case .charactersAfterClosingQuote: return "Unexpected characters follow a closing quote."
        case .missingHeader: return "The CSV header is missing."
        case .invalidHeader: return "The CSV columns do not match Savour."
        case let .wrongColumnCount(row, expected, actual):
            return "Row \(row) has \(actual) columns; \(expected) are required."
        case let .invalidCoordinate(row): return "Row \(row) has invalid coordinates."
        case let .emptyFood(row): return "Row \(row) has no food description."
        case let .invalidDate(row): return "Row \(row) has an invalid date."
        case let .invalidTime(row): return "Row \(row) has an invalid time."
        case let .invalidID(row): return "Row \(row) has an invalid entry ID."
        case let .invalidPeople(row): return "Row \(row) has invalid companion data."
        case let .invalidTimestamp(row): return "Row \(row) has an invalid timestamp."
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
    static let extendedHeader = header + ["entry_id", "people_json", "timestamp_unix"]

    static func encode(dataRows: [[String]]) -> String {
        CSVCodec.encode(rows: [header] + dataRows)
    }

    static func encodeExtended(dataRows: [[String]]) -> String {
        CSVCodec.encode(rows: [extendedHeader] + dataRows)
    }

    static func decode(_ text: String) throws -> [[String]] {
        let rows = try CSVCodec.decode(text)
        guard let first = rows.first else { throw CSVCodecError.missingHeader }
        guard first == header || first == extendedHeader else { throw CSVCodecError.invalidHeader }

        for (index, row) in rows.dropFirst().enumerated() {
            try validate(row, rowNumber: index + 2, columnCount: first.count)
        }

        return Array(rows.dropFirst())
    }

    static func validate(_ row: [String], rowNumber: Int, columnCount: Int) throws {
        guard row.count == columnCount else {
            throw CSVCodecError.wrongColumnCount(
                row: rowNumber,
                expected: columnCount,
                actual: row.count
            )
        }

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

        if columnCount == extendedHeader.count {
            guard row[10].isEmpty || UUID(uuidString: row[10]) != nil else {
                throw CSVCodecError.invalidID(row: rowNumber)
            }
            guard let data = row[11].data(using: .utf8),
                  let names = try? JSONDecoder().decode([String].self, from: data),
                  names.joined(separator: ", ") == row[8],
                  names == CompanionNames.normalized(names) else {
                throw CSVCodecError.invalidPeople(row: rowNumber)
            }
            guard let timestamp = Double(row[12]), timestamp.isFinite,
                  (-62_135_596_800 ... 253_402_300_799).contains(timestamp) else {
                throw CSVCodecError.invalidTimestamp(row: rowNumber)
            }
        }
    }
}
