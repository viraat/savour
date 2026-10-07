# SavourBackup-v1

Settings → Your data offers **Export full backup** and **Restore full backup**.
CSV remains the lightweight food-entry interchange format; full backups are ZIPs
with a typed JSON manifest and original, unmodified binary attachments.

## Contents

```text
SavourBackup-v1/
  manifest.json
  photos/<sha256>.jpg | .png | .bin
  attachments/<sha256>.bin
```

The manifest includes the format/version, creation time, app version/build,
export-time timezone, model identifiers, entity schemas and every committed food
entry and companion object, even if orphaned or missing an optional UUID. Fasting
records are excluded. Automatic fasting estimates are recalculated from meal
times. Restore leaves existing older manually saved fasting records untouched.
Drafts, preferences, biometric settings and reminder schedules are not included.

Each object has its original stable UUID attribute (when present), every
non-transient attribute, and all non-transient relationships. Core Data object URI
strings are archive-local graph references, not identifiers to reuse in a new
store. Restore recreates the graph using new Core Data object IDs while retaining
UUID attributes. Missing/duplicate UUIDs are preserved, not silently repaired.

Values have explicit `type` and `value` keys: null, string, uuid, date, integer,
number, boolean, decimal, uri, binary. Dates are Double seconds since
`2001-01-01T00:00:00Z` (Foundation reference date); no locale-specific date parsing
or timezone conversion occurs. Binary references contain a relative path, byte
count and lowercase SHA-256 digest. Identical blobs are stored once. Photos are
not resized or decoded/re-encoded; unrecognized image formats retain their bytes
with a `.bin` suffix. Nil data and zero-length data remain distinct.

## Restore

Selecting a ZIP stages a private copy, validates it and previews new, identical
and conflicting records. Nothing is saved until **Restore backup** is pressed.
Restore is an additive merge, not replacement of the journal:

- Connected meal/companion graphs which match completely are skipped.
- A graph with a UUID already present but different content is left unchanged
  as a conflict. Its children are not attached to the existing meal.
- Other graphs are inserted with all fields, binary data and relationships.
- UUID-less exact graphs are matched by their full contents where possible.
- The journal is rechecked at confirmation. One transaction saves the new
  records; any validation/save failure rolls back the whole restore.

Known older schemas can restore into the current model using defaults for newly
added fields. Unknown versions, entities or fields fail closed. All relationship
references/inverses, typed values, ZIP CRCs and attachment sizes/hashes must
validate. Absolute paths, traversal, symlinks, duplicate paths and unexpected
files are rejected. Limits are 100,000 objects, 64 MiB for the manifest or any
single binary attachment and 2 GiB compressed/uncompressed archive size; larger
backups cannot currently be exported/restored. Oversized exports fail with a
clear error instead of producing an unrestorable file. These defensive limits
are checked before restore writes.

## Privacy

ZIPs are **not encrypted**. Export contains journal content and photos; store the
shared file in a private location. App-owned temporary files use restrictive
permissions and complete iOS file protection. They are removed after sharing or
after the restore preview is dismissed. The normal app lock protects access to
the Settings screen and sheets; an exported file is outside that lock.

ZIPFoundation 0.9.20 is used under the MIT license; its license notice ships in
the app's bundle/repository and is referenced in About. Foundation creates export ZIPs.
