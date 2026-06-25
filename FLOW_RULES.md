# Flow Rules

## Note Lock

- If a user presses the lock button and no local PIN exists, the app must show PIN setup before marking the note as locked.
- If PIN setup is canceled or fails, the note must remain unlocked.
- After first-time setup from the editor lock button, the current editor session may keep the note visible until the user leaves the editor.
- Once the user leaves a locked note, every later entry from homepage, search, or editor resume must require PIN or biometric authentication.
- If a restored locked note is opened on a device with no local PIN, the app must show PIN setup first.
- After first-time setup for a restored locked note succeeds, the app may open that note immediately without asking for the newly created PIN again.

## Backup Restore

- Homepage restore UI must appear only when a cloud backup is available for restore.
- Pressing restore from the homepage must attempt the restore on the first tap.
- Restore failures must show user feedback and must not dismiss the restore prompt.
- The restore prompt must be dismissed only after a successful restore.
