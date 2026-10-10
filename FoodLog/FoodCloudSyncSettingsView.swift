import SwiftUI

struct FoodCloudSyncSettingsView: View {
    @AppStorage(FoodCloudSyncConfiguration.enabledKey) private var requested = false
    @StateObject private var monitor = FoodCloudSyncMonitor.shared
    @State private var confirmEnable = false
    @State private var confirmDisable = false

    private var supported: Bool { Bundle.main.bundleIdentifier == FoodCloudSyncConfiguration.bundleIdentifier }
    private var needsRestart: Bool { requested != monitor.enabledForThisLaunch }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: Binding(
                    get: { requested },
                    set: { enabled in
                        if enabled { confirmEnable = true } else { confirmDisable = true }
                    }
                ))
                .disabled(!supported)
                .accessibilityIdentifier("icloud-sync-enabled")
            } footer: {
                Text("Sync saved meals, photos, places and people between devices signed in to the same iCloud account. Drafts and app preferences stay on this device.")
            }
            Section {
                LabeledContent("Status", value: supported
                    ? (needsRestart ? "Restart Savour to apply" : monitor.status)
                    : "Available in the new Savour app")
                    .accessibilityIdentifier("icloud-sync-status")
                if let date = monitor.lastTransfer, !needsRestart, requested {
                    LabeledContent("Last transfer") { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                if let issue = monitor.issue, !needsRestart, requested {
                    Text(issue).foregroundStyle(.secondary)
                }
                if requested, !needsRestart {
                    Button("Check iCloud status") { Task { await monitor.refreshAccount() } }
                        .disabled(monitor.checkingAccount)
                        .accessibilityIdentifier("icloud-check-status")
                }
            } footer: {
                if needsRestart {
                    Text("Close Savour from the app switcher, then open it again. Your entries stay on this device. \(requested ? "Existing entries will also sync to iCloud." : "This stops syncing on this device; it doesn't erase the data already in iCloud.")")
                } else {
                    Text("Meals are saved locally first, including when offline. iCloud sync happens automatically and may take a little time. Keep backups for a separate copy of your journal.")
                }
            }
        }
        .formStyle(.grouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(FoodTheme.background)
        .navigationTitle("iCloud sync")
        .navigationBarTitleDisplayMode(.inline)
        .font(.body)
        .task { await monitor.refreshAccount() }
        .alert("Enable iCloud sync?", isPresented: $confirmEnable) {
            Button("Enable") { requested = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved entries, including photos and people, will be stored in your private iCloud database and synced with your other devices. Restart Savour to begin. You can keep using Savour offline.")
        }
        .alert("Turn off iCloud sync?", isPresented: $confirmDisable) {
            Button("Turn off") { requested = false }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restart Savour to stop syncing on this device. Your local entries and the copy already in iCloud will not be erased. Other devices can continue syncing.")
        }
    }
}
