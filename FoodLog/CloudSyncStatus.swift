import CloudKit
import Combine

enum CloudConfiguration {
    static let containerIdentifier = "iCloud.com.viraat.foodlog"

    static var isCloudKitAvailableInCurrentBuild: Bool {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }
}

final class CloudSyncStatus: ObservableObject {
    @Published private(set) var label = "Checking…"

    func refresh() {
        guard CloudConfiguration.isCloudKitAvailableInCurrentBuild else {
            label = "Local only"
            return
        }

        CKContainer(identifier: CloudConfiguration.containerIdentifier).accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error != nil {
                    self.label = "Unavailable"
                    return
                }

                switch status {
                case .available:
                    self.label = "On"
                case .noAccount:
                    self.label = "Sign in to iCloud"
                case .restricted:
                    self.label = "Restricted"
                case .couldNotDetermine, .temporarilyUnavailable:
                    self.label = "Unavailable"
                @unknown default:
                    self.label = "Unavailable"
                }
            }
        }
    }
}
