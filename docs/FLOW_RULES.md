# Flow Rules

## Note Lock

Locked notes are encrypted on this device and in backups (AES-256-GCM with a random vault key). The title stays readable unless "Hide locked note titles" is on. The UI may say "encrypted on this device and in backups"; it must not promise more than that (malware on an unlocked phone and screenshots on iOS are out of scope).

- **First lock:** if no vault exists and no PIN exists, the lock action first asks for a new 6-digit PIN (or a passphrase of at least 8 characters), creates the vault key and both wraps, shows the recovery code (grouped, Copy, "I saved it"), then encrypts the note. If setup is cancelled or fails, the note stays unlocked.
- **Lock another note:** needs no PIN once the vault exists; the note is encrypted immediately and the plain sections are securely deleted.
- **Open:** biometric (if turned on) or PIN, then the vault key is loaded and the note is decrypted into the editor only. Every autosave re-encrypts. Leaving the editor drops the key from memory.
- **Background:** with a locked note open, pausing the app saves (encrypt + write) first, then drops the decrypted content and the key, and shows the lock overlay on return.
- **Remove lock:** authenticate, decrypt, store as normal sections.
- **Change PIN:** verify the old PIN, then only the PIN wrap is rewritten. Notes are untouched; biometric unlock keeps working; the recovery code keeps working.
- **New phone / reinstall / secure storage lost:** if the database holds a vault (for example after a restore) but this device has no matching cached key, every locked-note action asks "Enter the PIN for your locked notes" (with "Use recovery code"). There is **no create-new-PIN path while a vault exists**. Correct PIN → key cached, local PIN check recreated, biometric offered.
- **Forgot PIN:** recovery code → set a new PIN; or, if biometric unlock is already on and the key is cached, biometric → set a new PIN; otherwise only "Delete all locked notes and reset", confirmed twice.
- **Existing 4-digit PINs** keep working. On the first PIN entry after the update the app (biometric paused once, message "Enter your PIN once to finish securing your locked notes") creates the vault, offers a 6-digit upgrade (skippable), shows the recovery code, encrypts all locked notes in one transaction and compacts the database, then backs up and removes old plaintext backups.
- Attempt limits (5 free tries, then 30 s / 1 min / 5 min / 15 min / 1 h) apply to every PIN, passphrase, backup PIN and recovery-code entry.
- A fresh install still clears the local PIN, biometric flag and cached vault key (the iOS Keychain survives reinstall); a restore that brings encrypted notes then leads to the "Enter the PIN for your locked notes" prompt.
- A locked note opened with no local PIN and **no vault** (only possible for plaintext locked notes from a pre-encryption backup) shows PIN setup; the note is encrypted right after.
- Export / copy for AI of a locked note is only available from an unlocked editor session. Bulk delete that includes locked notes asks for one authentication.

## Backup Restore

- The homepage restore UI is an empty-vault helper: it appears only while the device has 0 ideas and 0 random notes, and it disappears for good as soon as any idea or random note exists.
- iOS: a silent iCloud check runs once per install on an empty vault; if a backup is found, the banner reads "Cloud backup found".
- Android: no silent check. A neutral one-time card "Have a backup? Restore" is shown on an empty vault; tapping it starts Google sign-in. If no backup is found the card hides itself.
- Pressing Restore on the banner restores the newest backup immediately (first tap) only when the vault is completely empty. If anything exists locally, a confirmation sheet with backup date, device and counts offers Merge or Replace.
- The banner has a close button. Dismissal is remembered; restore stays available from the Backup screen.
- The banner is disabled while any backup or restore is running.
- Restore failures show the specific reason and keep the banner visible. The banner is dismissed only after a successful restore, a dismiss tap, or once the vault has content.
- Restore never requires Cloud Backup to be on. Restoring with Cloud Backup off signs in for reading only and does not turn on Auto Backup.
- Every restore downloads and fully validates the backup first (valid JSON, format version not newer than the app supports, every idea and note parses, content hash matches). A backup with 0 ideas and 0 notes is refused. Nothing local changes until validation passes.
- Before every replace or merge, a safety copy of the current vault is written on the device (last 3 kept) and "Undo restore" is offered on the Backup screen for 7 days.
- Replace swaps ideas, sections and random notes in one database transaction. Merge never discards anything: identical items are skipped, changed ideas keep the newer version in place and add the older one as a titled copy.
- After a restore the editor resume state is cleared and the app returns to home.
- Encrypted locked notes in a backup: with no vault on this device the backup's vault is adopted and the notes stay ciphertext until "Enter the PIN for your locked notes"; with a different vault on this device the app asks once for the backup's PIN or recovery code and re-encrypts the imported notes under this device's key. Skipping or a wrong PIN never blocks the rest of the restore; those notes are reported as "not imported". A vault key that protects local notes is never silently replaced.
