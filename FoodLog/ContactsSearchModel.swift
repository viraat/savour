import Combine
import Contacts

final class ContactsSearchModel: ObservableObject {
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private let store = CNContactStore()
    private var names: [String] = []
    private var pendingQuery = ""

    func setEnabled(_ enabled: Bool, query: String) {
        isEnabled = enabled
        message = nil
        pendingQuery = query

        guard enabled else {
            suggestions = []
            return
        }

        let authorization = CNContactStore.authorizationStatus(for: .contacts)
        if hasAccess(authorization) {
            loadContactsIfNeeded()
        } else if authorization == .notDetermined {
            requestAccess()
        } else {
            isEnabled = false
            message = "Contact access is disabled in Settings."
        }
    }

    func updateQuery(_ query: String) {
        pendingQuery = query
        guard isEnabled else {
            suggestions = []
            return
        }

        let fragment = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else {
            suggestions = []
            return
        }

        suggestions = names.filter {
            $0.localizedCaseInsensitiveContains(fragment)
        }.prefix(5).map { $0 }
    }

    private func requestAccess() {
        isLoading = true
        store.requestAccess(for: .contacts) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                let authorization = CNContactStore.authorizationStatus(for: .contacts)
                guard error == nil, self.hasAccess(authorization) else {
                    self.isEnabled = false
                    self.message = "Contact access was not granted."
                    return
                }
                self.loadContactsIfNeeded()
            }
        }
    }

    private func loadContactsIfNeeded() {
        guard names.isEmpty, !isLoading else {
            updateQuery(pendingQuery)
            return
        }

        isLoading = true
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var fetchedNames: [String] = []
            let nameDescriptor = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            let request = CNContactFetchRequest(keysToFetch: [nameDescriptor])
            request.unifyResults = true

            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    if let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty {
                        fetchedNames.append(name)
                    }
                }
                let uniqueNames = Dictionary(grouping: fetchedNames, by: { $0.lowercased() })
                    .compactMap { $0.value.first }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.names = uniqueNames
                    self.isLoading = false
                    self.updateQuery(self.pendingQuery)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLoading = false
                    self.isEnabled = false
                    self.message = "Contacts could not be loaded."
                }
            }
        }
    }

    private func hasAccess(_ authorization: CNAuthorizationStatus) -> Bool {
        if authorization == .authorized { return true }
        if #available(iOS 18.0, *), authorization == .limited { return true }
        return false
    }
}
