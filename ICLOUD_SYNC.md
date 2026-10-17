# Savour iCloud sync

## User experience

Open **Settings → Your data → iCloud sync** in the new Savour app. Sync is off
by default. Enabling it asks for confirmation before uploading journal data.
The setting takes effect after closing Savour from the app switcher and reopening
it; changing an open store's mirroring delegate while editors or exports are
using it is deliberately avoided. Enable it on each participating device.

Saved food entries, original photos, locations/coordinates, people and their
relationships use the user's **private** CloudKit database. Existing manually
saved FastSession records are preserved and mirrored too; automatic fast estimates
are still calculated from meal timestamps, never created as new session records.
Drafts, reminders, Contacts data outside saved companion names, appearance,
fasting goals and biometric preferences stay local. There is no Savour login.

The app saves to its existing local SQLite store first and remains usable offline.
Apple controls transfer timing and retries. Status shows account availability,
active transfers, the last successful sync time (saved on this device and cleared
when sync is turned off) and neutral errors; it does not claim that every device
is instantly up to date. The account status refreshes when the page opens, when
the app becomes active and when the iCloud account changes. Apps cannot read the
Apple ID name or email, so Savour only shows whether an iCloud account is signed
in and points to the Settings app. The page also explains conflicts: the most
recent synced change wins, deletes propagate, and duplicate repair merges
identical copies from restored backups while keeping different ones.

Turning sync off stops mirroring at the next launch without deleting the local
store or purging CloudKit. Other devices may continue syncing. When enabled,
deleting an entry or using Erase all entries also propagates deletions. Keep
full backups for a separate recovery copy: sync is not an archive.

## Apple account setup (required before live sync)

Use the **Savour** scheme in **Savour.xcodeproj**, not the older FoodLog target.

1. Sign your paid Apple Developer account into **Xcode → Settings → Accounts**.
   The configured Savour team is `829WP93FV4` and its App ID is
   `tech.buildboring.Savour`.
2. In **Savour target → Signing & Capabilities**, use automatic signing. The
   project declares iCloud/CloudKit, Push Notifications and Background Modes →
   Remote notifications. Register/select **`iCloud.tech.buildboring.Savour`**
   under iCloud Containers. Ensure the App ID/profile authorizes this exact
   container and both capabilities. No alert-notification permission is needed
   for the silent updates used by sync.
3. Run a signed Debug build on an iCloud-signed-in device, opt into sync and
   restart Savour. Develop/test with the container's Development environment.
4. To explicitly initialize all development record types, add the Run scheme
   argument **`--initialize-cloudkit-schema`** for one Debug run after sync is
   enabled, then remove it. The operation is gated behind DEBUG and that
   argument; it never runs on routine launches or in Release builds. Don't
   reset a container with user data.
5. Verify on two devices using the same iCloud account. Before TestFlight, review
   and deploy the development schema to Production in CloudKit Console. This
   copies schema, not development data. Production promotion is intentionally
   not performed by this implementation.

The checked-in entitlement uses the usual development push environment;
distribution signing/export must supply the appropriate production entitlements.
Verify the signed archive's CloudKit and APNs environment before TestFlight.

Apple references:

- [Setting up Core Data with CloudKit](https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit)
- [Creating a CloudKit-compatible model](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)
- [Syncing a Core Data store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit)
- [Deploying the container schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)

## Data integrity and migration

- FoodLogV6 is a new model version. V1–V5 are unmodified. V6 makes three legacy
  FastSession attributes optional to meet CloudKit's model constraints; the
  app's create/edit validation still requires valid identifiers/start dates.
- The database path does not change. Lightweight migration preserves UUIDs,
  dates, photos, locations, companion relationships and saved fasting sessions.
  Existing launch repair and its metadata marker remain intact.
- Persistent history and remote-change notifications are enabled. UI contexts
  auto-merge and a background history reader merges object-ID changes without
  resetting the UI context. It replays only this launch's history; initial UI
  fetches already see persisted imports. History is not pruned out from under
  Apple's mirroring delegate.
- Standard Core Data/CloudKit conflict handling applies to edits of the same
  mirrored object. Independently restored/imported copies may have the same
  application UUID but different CloudKit records. A background repair coalesces
  only identical, complete FoodEntry/companion graphs with identical photo data.
  Every device selects the same surviving CloudKit record name. Missing cloud
  identities or incomplete relationships defer repair. Differing records are
  retained rather than silently discarding an edit or photo. The sole ignored
  attribute is import-created `createdAt`; otherwise-identical imports retain
  the earliest known creation timestamp.
- The editor preserves its local draft if the entry is deleted remotely during
  editing; it doesn't write to a deleted managed object. Reopening that recovered
  draft allows saving a new entry.
- CSV and ZIP backup/restore continue to use the local store. No changes to their
  formats are required. Automatic fasting data stays excluded from backup.
- Explicit temporary stores, in-memory tests and the old FoodLog bundle identity
  never activate CloudKit, even if the preference is enabled.

## Verification and release gate

On 2026-10-09, 127 local Mac tests passed, including 12 new tests for privacy
gating, CloudKit model constraints, migration from every previous model, UUID/
photo/relationship preservation, duplicate safety, remote update/deletion merging
and retention of unfinished edits. Savour Debug app/test targets, the original
FoodLog reliability test targets and the iPhone Release app compile without
signing. No simulator or personal journal was used.

A development signing attempt is blocked: Xcode reports **No Accounts** and
the available wildcard profile lacks iCloud, Push and the specified container.
No container registration, schema upload, production deployment or successful
cross-device transfer has been verified. Complete account setup above, then test:

- Initial upload of an existing journal and download on a second device.
- Add/edit/delete, companion changes, large photos, coordinates and fast estimates.
- Offline edits, reconnect, relaunch and simultaneous edits on both devices.
- Restore the same backup on both devices and verify identical duplicates coalesce;
  conflicting versions are retained without data loss.
- iCloud signed out/unavailable, account switching, quota exhaustion and recovery.
- App lock/background concealment; drafts and settings must not sync.
- Disable/re-enable on one device; other devices and existing data stay intact.
- A signed TestFlight build against the deployed Production schema.
