# Cloud Backup and Restore Setup

This document explains what was added for Idea Vault cloud backup, and what still needs to be configured outside the Flutter project before the feature works on real Android and iOS devices.

## How Backup Works

### Enabling backup

Turning on **Cloud Backup** always checks the cloud before anything is uploaded:

| Cloud | This device | What happens |
|---|---|---|
| No backup | Anything | Backup turns on. If the device has data, the first backup runs immediately. |
| Backup exists | Empty | Sheet: backup date, device and counts → **Restore** or **Start fresh**. Start fresh deletes nothing in the cloud. |
| Backup exists, made by this device | Has data | Backup turns on silently. |
| Backup exists, made by another device | Has data | Sheet → **Merge**, **Replace this device** or **Keep this device's data**. |
| Check failed (offline, sign-in cancelled, iCloud unavailable) | Anything | Specific error; the switch returns to off. |

Auto backup only runs after this check has completed (`remoteStateResolved`). Closing the sheet counts as cancel. Users upgrading with backup already on are treated as resolved only if a last-backup time exists; otherwise the app re-checks silently on next open and shows "Backup needs attention" / "Finish setup" when a choice is needed.

**Change account** (Android) clears the last-backup time, size and resolved flag, then re-runs the same check for the new account.

### Automatic backups

- One coordinator (`lib/core/services/backup/cloud_backup_coordinator.dart`) runs every rule for both the foreground catch-up (app open/resume) and the `workmanager` background task.
- Never uploads automatically when the vault has 0 ideas and 0 random notes. A manual **Back Up Now** of an empty vault asks first when a non-empty cloud backup exists.
- Runs at most once per 24 hours; after a failure it waits 15 minutes before retrying.
- If the content hash equals the last uploaded snapshot (and that file is still in the cloud), nothing is uploaded and the backup is recorded as checked.
- A lock marker in shared preferences (`cloud_backup_upload_lock_v1`, stale after 10 minutes) stops foreground and background uploading at the same time.
- The background isolate reloads preferences before reading and writes only the status record (`cloud_backup_status_v1`), never the user settings (`cloud_backup_settings_v1`).
- Background runs never show UI. If Google authorization has lapsed the attempt is recorded as "needs sign-in".

### Backup files and history

Each backup is a new file. The name carries what the restore picker needs without downloading:

```text
idea_vault_backup_v3_<UTC yyyyMMddTHHmmssZ>_<8-char device id>_i<ideas>_n<notes>_<base64url device name>.json
```

- Format v3 header: `version`, `backupId`, `createdAt`, `deviceId`, `deviceName`, `appVersion`, `counts`, `contentHash` (`sha256:` over the ideas and random notes), and a `lock` block.
- `lock` is `null` until the device has a locked-note vault. Afterwards it is a copy of the local `note_vault` row: `{"v":1,"encrypted":true,"epoch":1,"keyId",createdAt,"pin":{pinKind,kdf,n,c},"recovery":{kdf,n,c}}` (wrapped vault key + KDF parameters, never the key itself). `encrypted:true` / `epoch` mark snapshots made after encryption shipped.
- Encrypted locked ideas carry `encryptedPayload` (AES-256-GCM envelope) and `titleHidden`, and have an empty `sections` list. Backups therefore contain no readable locked text; only titles (unless hidden), dates and ids.
- The upload fingerprint used to skip unchanged uploads covers the content hash **and** the lock block, so a PIN change produces a fresh snapshot with the new PIN wrap.
- Background backups copy ciphertext and the lock block straight from the database; no key or PIN is needed.
- Files are written without pretty-printing.
- Retention per device: the 7 newest snapshots plus the newest non-empty one; only 3 when the newest snapshot is larger than 5 MB. Other devices' files are never rotated. A failed delete never fails a backup.
- Ordering uses the cloud's own modified time, not the device clock.
- The old single file `idea_vault_backup.json` is never written or rotated, so older app versions can still restore it. The picker shows it as "Older backup (before update)". It is deleted by the plaintext clean-up below if it contains locked notes.

### Plaintext clean-up after encryption

- When locked notes are encrypted for the first time (migration of existing locked notes, or encrypting plain locked notes that arrived from an old backup) and Cloud Backup is on, the flag `vault_plaintext_cleanup_pending_v1` is set **before** encryption starts.
- The clean-up first runs a new backup (must upload, be pending, or be unchanged), then downloads every backup file in the account except the one just uploaded and deletes each one that still contains a locked note without `encryptedPayload` (legacy single file, pre-encryption v3 snapshots, from any device).
- Only when every check and delete succeeds is the flag cleared. Otherwise it stays set, is retried when the app opens or resumes, and the Backup screen shows "Old backups still contain your locked notes" with **Retry**.
- Restore safety copies on the device that contain plain locked notes are rewritten encrypted (or deleted if that fails).
- Each install gets a random device ID (stored under `backup_device_identity_v1`, kept when backup is turned off) plus the device model name.

### Restore

- Restore is always available, even with Cloud Backup off. With backup off it signs in for reading only and never turns on Auto Backup.
- The restore picker lists every snapshot (date, device, counts, size), newest first and preselected.
- The chosen file is downloaded and fully validated before anything local changes: valid JSON, format version not newer than supported ("Update the app to restore this backup"), every idea and note parses (no silent skipping), and the content hash matches. Empty backups are refused. v1/v2 files (including legacy `delta` section content) are still accepted. Encrypted ideas are accepted when their envelope is well-formed, they are locked, have no plain sections, and the backup has a valid `lock` block.
- Locked notes in old v1/v2 or pre-encryption v3 backups arrive plain and are encrypted on the next unlock.
- Encrypted locked notes: if this device has no vault, the backup's vault is adopted (local PIN/biometric/cached key are cleared) and the notes stay ciphertext until the user enters that backup's PIN or recovery code. If this device has a different vault, the user is asked once for the backup's PIN (or its recovery code, which survives PIN changes); the imported notes are re-encrypted under this device's key. Skipping or a wrong PIN imports everything else and reports "N locked notes were not imported". A vault that protects local notes is never replaced.
- A safety copy of the current vault is written to the app support directory (`backup_safety_copies/`, last 3 kept) before every replace or merge. **Undo restore** is offered for 7 days.
- **Replace** swaps ideas, sections and random notes in one SQLite transaction.
- **Merge** by ID: missing items are added, identical items skipped, and when an idea differs the newer version stays in place and the older one is added as "Title (from backup)" or "Title (from this device)". A changed random note with the same ID is added as a copy. The result is shown as "Added N, kept N copies, skipped N identical". Encrypted notes are compared after decryption when the key is available; an encrypted copy that gets a new id is re-encrypted for that id (the id is bound into the ciphertext). Without the key, conflicting encrypted notes are left as they are on the device and reported as not imported.
- Afterwards the editor resume state is cleared and the app returns home.

### Status

- Tracked: last attempt, last success, last error type, consecutive failures, first failure time, pending iCloud upload.
- Green tick only when the last success is under 48 hours old; amber "Last backup N days ago" after that; red with an action ("Sign in again" / "Try again") when failing.
- The home "Backup is off" slot also shows "Backup needs attention" after 3 days of failures, when sign-in is required, or when setup is unfinished.
- Each failure type has its own message (offline, timeout, sign-in required, sign-in cancelled, iCloud unavailable, no backup, empty, damaged, newer version, integrity failure).

### Turning backup off and deleting backups

- Turning Cloud Backup off asks for confirmation and states that existing cloud backups are kept.
- On Android it **signs out** of Google instead of revoking access (`disconnect`). Google only documents that hidden app data is deleted when the app is removed from Drive; whether a revoke also triggers deletion is unconfirmed, so revoke is avoided. **Verify on a real account.**
- **Delete cloud backups** is a separate, double-confirmed action on the Backup screen. It deletes every Idea Vault backup file in the account, including the legacy file.

Main code areas:

- `lib/models/backup/`
- `lib/core/services/backup/`
- `lib/data/repositories/local/cloud_backup_settings.dart`, `backup_device_identity.dart`, `local_vault.dart`
- `lib/viewmodels/providers/backup/cloud_backup_provider.dart`
- `lib/views/backup_restore_screen.dart`, `lib/widgets/backup_restore_prompt_banner.dart`, `lib/widgets/backup/`

## Google Cloud Setup for Android

The Android backup uses Google Drive's hidden app-private folder:

```text
Drive API scope: https://www.googleapis.com/auth/drive.appdata
Backup files: idea_vault_backup_v3_*.json (legacy: idea_vault_backup.json)
Drive space: appDataFolder
```

Do this in Google Cloud Console:

1. Open the Google Cloud project connected to the app.
2. Enable **Google Drive API**.
3. Configure the **OAuth consent screen**.
4. Add the app name, support email, developer contact email, and privacy policy links.
5. Add the Drive app data scope:

```text
.../auth/drive.appdata
```

6. While testing, add yourself and other testers as OAuth test users if the app is in testing mode.
7. Create or verify an **Android OAuth client ID**.
8. Set the package name to:

```text
com.pocketmicros.ideavault
```

9. Add SHA fingerprints for every signing identity you use:

- Debug SHA-1 / SHA-256
- Local release SHA-1 / SHA-256
- Google Play App Signing SHA-1 / SHA-256

For Play Store builds, the Play App Signing certificate is the important one. The local upload key alone is not enough for production sign-in.

## Android Testing Checklist

On a real Android device:

1. Install the app with a non-empty vault on another device already backed up to the same account.
2. On a fresh install, confirm the home card "Have a backup? Restore" appears and that tapping it starts Google sign-in and restores.
3. Open **Backup and Restore**, turn on **Cloud Backup** and confirm the cloud check sheet appears before anything is uploaded.
4. Leave the app, come back the next day: confirm the cloud backup is unchanged until a choice was made.
5. Tap **Back Up Now**; confirm a new `idea_vault_backup_v3_*` file appears (history grows, nothing overwritten) and last backup time and size update.
6. Turn **Cloud Backup** off; confirm the Drive app data still contains the backups (sign-out, not revoke).
7. Revoke the app's Drive access from the Google account settings, then open the app: confirm "Backup needs attention" with "Sign in again".
8. Confirm the old `idea_vault_backup.json` is untouched and listed as "Older backup (before update)".

The backup should not appear in the user's normal Google Drive UI because it is stored in `appDataFolder`.

## Apple Developer Setup for iOS

iOS backup uses iCloud Documents storage through this container:

```text
iCloud.com.pocketmicros.ideavault
```

The project now includes:

- `ios/Runner/Runner.entitlements`
- iCloud Documents entitlement
- Background fetch mode in `ios/Runner/Info.plist`
- iOS deployment target aligned to `15.0`

Do this in Apple Developer:

1. Open **Certificates, Identifiers & Profiles**.
2. Open the App ID for:

```text
com.pocketmicros.ideavault
```

3. Enable **iCloud**.
4. Select **iCloud Documents**.
5. Create or attach this iCloud container:

```text
iCloud.com.pocketmicros.ideavault
```

6. Enable **Background Modes** for the App ID.
7. Regenerate development and distribution provisioning profiles after enabling these capabilities.
8. Download/use the updated profiles in Xcode or let automatic signing refresh them.

## iOS Testing Checklist

On a real iOS device signed into iCloud:

1. Make sure iCloud Drive is enabled for the Apple ID.
2. Install the app with a provisioning profile that includes the iCloud container.
3. Open **Backup and Restore**; the account row reads "iCloud" with no Change button.
4. Turn on **Cloud Backup**, tap **Back Up Now**, and confirm "Backup complete" appears only after the upload finishes (or "Uploading to iCloud…" when it takes longer than 60 seconds, confirmed on the next open).
5. Delete/reinstall or use a clean device state; confirm the "Cloud backup found" banner appears on an empty vault and restores on the first tap.
6. Turn iCloud Drive off and confirm the specific "iCloud Drive is not available" message.

iCloud behavior should be tested on a real device. The simulator is not reliable for final iCloud validation.

## Background Backup Notes

Auto Backup schedules a periodic task every 24 hours and also catches up when the app is opened or resumed. Both paths go through the same coordinator.

Important platform caveats:

- Android generally honors periodic background work, but exact timing is controlled by the OS.
- iOS background fetch is opportunistic. The OS decides when the task runs based on app usage, battery, connectivity, and system policy.
- Manual **Back Up Now** remains the reliable immediate backup path on both platforms.

## Verification

Automated coverage for the rules above lives in `test/core/services/backup/` (including `vault_backup_test.dart` for encrypted backups, restore with different keys and plaintext clean-up), `test/core/services/vault/`, `test/models/backup/`, `test/viewmodels/providers/cloud_backup_provider_test.dart` and `test/widgets/backup_restore_prompt_banner_test.dart` (fake cloud store, no network). Run:

```bash
flutter test --no-pub
flutter analyze --no-pub
```

Items that still need real-device verification: silent Google access on a fresh install, sign-out vs revoke and the hidden app data, iCloud upload completion timing, Argon2id timing on a low-end Android (falls back to PBKDF2 when the measured estimate exceeds 3 s), and reinstall + restore with the iOS Keychain still holding an old vault key.
