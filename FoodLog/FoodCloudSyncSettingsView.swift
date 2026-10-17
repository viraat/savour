import SwiftUI

struct FoodCloudSyncSettingsView: View {
    @AppStorage(FoodCloudSyncConfiguration.enabledKey) private var requested = false
    @StateObject private var monitor = FoodCloudSyncMonitor.shared
    @State private var confirmEnable = false
    @State private var confirmDisable = false

    private var supported: Bool { Bundle.main.bundleIdentifier == FoodCloudSyncConfiguration.bundleIdentifier }
    private var needsRestart: Bool { requested != monitor.enabledForThisLaunch }
    private var showsDetails: Bool { supported && requested && monitor.enabledForThisLaunch && !needsRestart }

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
                Text("Savour copies your saved meals, photos, places and people to your private iCloud storage. Your other devices that use the same iCloud account get the same data. Drafts and settings stay on this device.")
            }
            Section {
                LabeledContent("Status", value: supported
                    ? (needsRestart ? "Restart Savour to apply" : monitor.status)
                    : "Not available in this version of Savour")
                    .accessibilityIdentifier("icloud-sync-status")
                if showsDetails, let date = monitor.lastTransfer {
                    LabeledContent("Last sync") {
                        if Date().timeIntervalSince(date) < 86_400 {
                            Text(date, format: .relative(presentation: .named))
                        } else {
                            Text(date, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    .accessibilityIdentifier("icloud-last-sync")
                }
                if showsDetails, let issue = monitor.issue {
                    Text(issue).foregroundStyle(.secondary)
                }
            } footer: {
                if needsRestart {
                    Text("To apply this change, close Savour from the app switcher. Then open Savour again. Your entries stay on this device. \(requested ? "Savour then copies your entries to iCloud." : "Your data in iCloud stays. Savour stops sync on this device only.")")
                } else {
                    Text("Savour saves your meals on this device first. Savour also works offline. Sync occurs automatically and can take some minutes. Sync is not a backup. To keep a separate copy, make a backup.")
                }
            }
            if showsDetails {
                Section {
                    LabeledContent("iCloud account", value: monitor.accountDescription)
                        .accessibilityIdentifier("icloud-account-status")
                } footer: {
                    Text("Savour uses the iCloud account that is signed in on this device. To see or change this account, open the Settings app and tap your name.")
                }
            }
            Section {
            } header: {
                Text("If you use more than one device")
            } footer: {
                Text("If you change the same entry on two devices before they sync, Savour keeps the most recent change.\nIf you delete an entry on one device, Savour deletes it on all your devices.\nIf you restore the same backup on two devices, Savour removes copies that are the same. Savour keeps copies that are different.")
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
        .alert("Turn on iCloud sync?", isPresented: $confirmEnable) {
            Button("Turn On") { requested = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Savour copies your saved entries, photos and people to your private iCloud storage. Your other devices can then get them. To start, close Savour and open it again.")
        }
        .alert("Turn off iCloud sync?", isPresented: $confirmDisable) {
            Button("Turn Off") {
                requested = false
                monitor.clearLastTransfer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sync stops on this device when you open Savour again. Your entries on this device stay. Your data in iCloud stays. Your other devices continue to sync.")
        }
    }
}
