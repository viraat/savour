import Combine
import Contacts

final class ContactsSearchModel: ObservableObject {
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var photoDataByName: [String: Data] = [:]
    @Published private(set) var isEnabled = false
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var authorizationStatus: CNAuthorizationStatus

    private let store = CNContactStore()
    private let includesImages: Bool
    private var names: [String] = []
    private var pendingQuery = ""

    init(includesImages: Bool = false) {
        self.includesImages = includesImages
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    var canRequestAccess: Bool {
        authorizationStatus == .notDetermined
    }

    func loadIfAuthorized() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        guard hasAccess(authorizationStatus) else { return }
        isEnabled = true
        loadContactsIfNeeded()
    }

    func photoData(for name: String) -> Data? {
        photoDataByName[name.lowercased()]
    }

    func setEnabled(_ enabled: Bool, query: String) {
        isEnabled = enabled
        message = nil
        pendingQuery = query

        guard enabled else {
            suggestions = []
            return
        }

        let authorization = CNContactStore.authorizationStatus(for: .contacts)
        authorizationStatus = authorization
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
                self.authorizationStatus = authorization
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
            var fetchedPhotos: [String: Data] = [:]
            let nameDescriptor = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            var keysToFetch: [CNKeyDescriptor] = [nameDescriptor]
            if self?.includesImages == true {
                keysToFetch.append(CNContactThumbnailImageDataKey as CNKeyDescriptor)
            }
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.unifyResults = true

            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    if let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty {
                        fetchedNames.append(name)
                        if self?.includesImages == true, let photoData = contact.thumbnailImageData {
                            fetchedPhotos[name.lowercased()] = photoData
                        }
                    }
                }
                let uniqueNames = Dictionary(grouping: fetchedNames, by: { $0.lowercased() })
                    .compactMap { $0.value.first }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.names = uniqueNames
                    self.photoDataByName = fetchedPhotos
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
