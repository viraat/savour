import CoreData
import Foundation

struct FoodLogCSVImportRow: Identifiable {
    let rowNumber: Int
    let fields: [String]
    let date: Date
    let companionNames: [String]
    let entryID: UUID?
    let isDuplicate: Bool

    var id: Int { rowNumber }
    var food: String { fields[0] }
    var dateText: String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
    var meal: String { fields[3] }
    var place: String { fields[4] }
    var people: String { fields[8] }
    var note: String { fields[9] }
}

struct FoodLogCSVImportIssue: Identifiable {
    let rowNumber: Int
    let message: String

    var id: Int { rowNumber }
}

struct FoodLogCSVImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let rows: [FoodLogCSVImportRow]
    let issues: [FoodLogCSVImportIssue]
    let isLegacyFormat: Bool

    var importableCount: Int { rows.filter { !$0.isDuplicate }.count }
    var duplicateCount: Int { rows.count - importableCount }
}

enum FoodLogCSVImporter {
    static func preview(
        _ text: String,
        fileName: String,
        existingEntries: [FoodEntry]
    ) throws -> FoodLogCSVImportPreview {
        let rawRows = try CSVCodec.decode(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let columns = rawRows.first else { throw CSVCodecError.missingHeader }
        guard columns == FoodLogCSVDocument.header || columns == FoodLogCSVDocument.extendedHeader else {
            throw CSVCodecError.invalidHeader
        }

        let isLegacyFormat = columns == FoodLogCSVDocument.header
        let formatters = FoodLogCSVDateFormatters()
        var identities = FoodLogCSVIdentities(existingRows: existingEntries.lazy.map {
            CSVExporter.row(for: $0, formatters: formatters)
        })
        var rows: [FoodLogCSVImportRow] = []
        var issues: [FoodLogCSVImportIssue] = []

        for (index, fields) in rawRows.dropFirst().enumerated() {
            let rowNumber = index + 2
            do {
                try FoodLogCSVDocument.validate(fields, rowNumber: rowNumber, columnCount: columns.count,
                                                formatters: formatters)
                let date: Date
                if isLegacyFormat {
                    let dateText = "\(fields[1]) \(fields[2])"
                    guard let parsed = formatters.legacyDate(dateText) else {
                        throw CSVCodecError.invalidDate(row: rowNumber)
                    }
                    date = parsed
                } else {
                    guard let timestamp = Double(fields[12]) else {
                        throw CSVCodecError.invalidTimestamp(row: rowNumber)
                    }
                    date = Date(timeIntervalSince1970: timestamp)
                }

                let entryID = isLegacyFormat ? nil : UUID(uuidString: fields[10])
                let companionNames: [String]
                if isLegacyFormat {
                    companionNames = CompanionNames.parse(fields[8])
                } else {
                    companionNames = try JSONDecoder().decode([String].self, from: Data(fields[11].utf8))
                }

                let duplicate = identities.contains(fields, entryID: entryID, isLegacyFormat: isLegacyFormat)
                rows.append(FoodLogCSVImportRow(
                    rowNumber: rowNumber,
                    fields: fields,
                    date: date,
                    companionNames: companionNames,
                    entryID: entryID,
                    isDuplicate: duplicate
                ))
                if !duplicate {
                    identities.insert(fields, entryID: entryID, isLegacyFormat: isLegacyFormat)
                }
            } catch {
                issues.append(FoodLogCSVImportIssue(rowNumber: rowNumber, message: error.localizedDescription))
            }
        }

        return FoodLogCSVImportPreview(
            fileName: fileName,
            rows: rows,
            issues: issues,
            isLegacyFormat: isLegacyFormat
        )
    }

    @discardableResult
    static func commit(_ preview: FoodLogCSVImportPreview, to context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<FoodEntry> = FoodEntry.fetchRequest()
        let existingEntries = try context.fetch(request)
        let formatters = FoodLogCSVDateFormatters()
        var identities = FoodLogCSVIdentities(existingRows: existingEntries.lazy.map {
            CSVExporter.row(for: $0, formatters: formatters)
        })
        var count = 0

        for row in preview.rows where !row.isDuplicate {
            let duplicate = identities.contains(row.fields, entryID: row.entryID,
                                                isLegacyFormat: preview.isLegacyFormat)
            guard !duplicate else { continue }

            let entryID = row.entryID ?? UUID()
            let entry = FoodEntry(context: context)
            entry.id = entryID
            entry.createdAt = Date()
            entry.food = row.food
            entry.date = row.date
            entry.mealType = row.meal
            entry.place = row.place
            entry.placeCity = row.fields[5]
            if let latitude = Double(row.fields[6]), let longitude = Double(row.fields[7]) {
                entry.hasPlaceCoordinates = true
                entry.placeLatitude = latitude
                entry.placeLongitude = longitude
            } else {
                entry.hasPlaceCoordinates = false
            }
            entry.replaceCompanions(with: row.companionNames, in: context)
            entry.note = row.note

            identities.insert(row.fields, entryID: entryID, isLegacyFormat: preview.isLegacyFormat)
            count += 1
        }

        if count > 0 {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        return count
    }
}
