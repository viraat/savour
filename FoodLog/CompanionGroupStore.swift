import Combine
import Foundation

struct CompanionGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var people: [String]
    var useCount: Int
}

@MainActor
final class CompanionGroupStore: ObservableObject {
    @Published private(set) var groups: [CompanionGroup] = []

    private let defaults: UserDefaults
    private let storageKey = "foodLogCompanionGroups"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var frequentGroups: [CompanionGroup] {
        groups.sorted {
            if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func save(name: String, people: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPeople = CompanionNames.normalized(people)
        guard !trimmedName.isEmpty, normalizedPeople.count >= 2 else { return }

        if let index = groups.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            groups[index].name = trimmedName
            groups[index].people = normalizedPeople
        } else {
            groups.append(CompanionGroup(
                id: UUID(),
                name: trimmedName,
                people: normalizedPeople,
                useCount: 0
            ))
        }
        persist()
    }

    func markUsed(_ group: CompanionGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].useCount += 1
        persist()
    }

    func remove(_ group: CompanionGroup) {
        groups.removeAll { $0.id == group.id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let storedGroups = try? JSONDecoder().decode([CompanionGroup].self, from: data)
        else { return }
        groups = storedGroups
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
