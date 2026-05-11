# Cloud Backup and Restore Setup

This document explains what was added for Idea Vault cloud backup, and what still needs to be configured outside the Flutter project before the feature works on real Android and iOS devices.

## What Was Implemented

The Backup and Restore screen now has live cloud backup behavior without changing its design or layout.

Implemented behavior:

- Cloud Backup toggle enables/disables backup.
- Android uses the native Google account picker through `google_sign_in`.
- Android backups are uploaded to Google Drive `appDataFolder`, which is hidden from the user's normal Drive files.
- iOS uses iCloud, with no Google account connection step.
- The selected Google account email, or `iCloud` on iOS, is stored and shown on the screen.
- Auto Backup is enabled by default when Cloud Backup is first enabled.
- Auto Backup schedules a 24-hour background backup through `workmanager`.
- Turning Auto Backup off cancels the scheduled background task.
- Turning Cloud Backup off disconnects the stored Google session and cancels scheduled background work.
- Manual backup writes one versioned JSON file containing all ideas and sections.
- Last backup time and backup size are stored after successful backups.
- Restore shows a destructive confirmation, fetches the backup JSON, clears/replaces local SQLite data using the existing repository transaction, and returns to the idea list.
- On a fresh local install with no ideas, the home screen can show a subtle restore prompt if a cloud backup is detectable.

Main new code areas:

- `lib/models/backup/`
- `lib/core/services/backup/`
- `lib/data/repositories/local/cloud_backup_settings.dart`
- `lib/viewmodels/providers/backup/cloud_backup_provider.dart`
- `lib/widgets/backup_restore_prompt_banner.dart`

Small wire-up changes were made in:

- `lib/views/backup_restore_screen.dart`
- `lib/views/homepage.dart`
- `lib/viewmodels/providers/ideas_provider.dart`
- `lib/injection_container.dart`
- `lib/main.dart`

## Google Cloud Setup for Android

The Android backup uses Google Drive's hidden app-private folder:

```text
Drive API scope: https://www.googleapis.com/auth/drive.appdata
Backup file: idea_vault_backup.json
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

1. Install the app.
2. Open **Backup and Restore**.
3. Turn on **Cloud Backup**.
4. Confirm the native Google account picker appears.
5. Pick a Google account.
6. Tap **Back Up Now**.
7. Confirm the last backup time and size update.
8. Clear app data or reinstall.
9. Launch with no local ideas.
10. Confirm the restore prompt appears when a backup is detectable.
11. Restore and verify ideas/sections return.

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
3. Open **Backup and Restore**.
4. Turn on **Cloud Backup**.
5. Tap **Back Up Now**.
6. Confirm the last backup time and size update.
7. Delete/reinstall or use a clean device state.
8. Confirm restore works when local ideas are empty.

iCloud behavior should be tested on a real device. The simulator is not reliable for final iCloud validation.

## Background Backup Notes

Auto Backup schedules a periodic task every 24 hours.

Important platform caveats:

- Android generally honors periodic background work, but exact timing is controlled by the OS.
- iOS background fetch is opportunistic. The OS decides when the task runs based on app usage, battery, connectivity, and system policy.
- Manual **Back Up Now** remains the reliable immediate backup path on both platforms.

## Verification Already Run

These checks were run locally after implementation:

```bash
flutter build apk --debug
flutter build ios --debug --no-codesign
flutter test test/viewmodels/providers/ideas_provider_test.dart
dart analyze
```

The Android and iOS debug builds passed. `dart analyze` still reports existing unrelated warnings elsewhere in the project.

