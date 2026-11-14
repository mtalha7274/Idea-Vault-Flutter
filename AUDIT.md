# Idea Vault — App Audit

_13 Nov 2026 · based on a full read of the code, the analyzer and the test suite. Nothing here was tested on a real device; items marked **(verify on device)** need that._

## Fix first

1. Turning on Cloud Backup on a new phone can overwrite the old backup with an empty vault.
2. The home "Cloud backup found" banner restores in one tap, with no confirmation and no way to dismiss it.
3. Locked notes are not encrypted, and the lock can be bypassed by reinstalling and restoring.
4. Search misses most note content.
5. Every tap on "New Idea" leaves an empty "Untitled Idea" behind.

---

## 1. Cloud backup review

**Data-loss risks**

- **New device overwrites the old backup.** Restore is only reachable after Cloud Backup is switched on, and switching it on also turns on Auto Backup. Because the new device has never backed up, the next time the app is opened or resumed it uploads the current (empty) vault over the existing backup. A user who doesn't restore straight away loses everything.
- **Only one backup copy exists.** Each backup replaces the previous one. Accidental deletions, or a bad state, reach the cloud within a day and there is nothing older to go back to.
- **One-tap restore on the home banner.** It replaces all data without asking. The banner cannot be dismissed and stays after the user starts writing new ideas, so a later tap wipes that new work. It also only checks for ideas, so existing Random Additions are wiped too.
- **Restore is all-or-nothing.** No merge, and no preview of what is in the backup (date, number of ideas) before replacing local data.
- **Two devices on one account silently overwrite each other.** This is a backup, not a sync, but nothing tells the user.

**Reliability and honesty of the status**

- **Auto Backup can fail silently.** If Google access has lapsed or the network fails, the backup is skipped with no message. "Last Backup" simply gets older, and its green tick stays on even when the backup is weeks old.
- **"We back up your ideas every 24 hours" over-promises.** Both platforms run it only when the system allows; iOS especially may go days.
- **iOS says "Backup complete" too early.** The message appears when the file is handed to iCloud, not when the upload finishes.
- **Android restore prompt may rarely appear** on a fresh install, because it depends on Google granting access silently. **(verify on device)**
- **A damaged or newer-format backup is not rejected.** Unreadable entries are skipped quietly and local data is still replaced, so a partial restore looks like a success.

**Screen issues**

- On iOS the account row is titled "Google Account", shows "iCloud", and has a "Change" button that does nothing.
- Turning Cloud Backup off does not say what happens to the cloud copy, and there is no "Delete cloud backup" option. On Android it also fully revokes Google access — confirm the hidden backup survives this. **(verify on device)**
- Every failure shows the same message ("Cloud backup could not be updated"), including restore failures, no internet, and not being signed in to iCloud.

**Suggested direction:** check for an existing backup when Cloud Backup is turned on and offer "Restore" vs "Replace"; keep the last few backups; show backup date and idea count before restoring; warn on the home screen when the last backup is old or failed.

---

## 2. Security & privacy — where the user feels safer than they are

- **Locked notes are not encrypted.** The lock only hides the screen. The text is stored as plain text on the device and inside the cloud backup file.
- **The lock can be bypassed.** Reinstall the app (or clear its data), restore from cloud, and the app asks to create a *new* PIN — then opens the locked notes.
- **The PIN is 4 digits with unlimited tries.** No delay or lockout after wrong attempts.
- **Phone passcode also unlocks.** With biometric unlock enabled, the system falls back to the device passcode, so anyone who knows it can open locked notes.
- **Locked notes still leak.** Their titles show on the home screen and in search; search also matches their hidden text, revealing whether a word is inside. Random Additions can be filed into a locked note, and its section names are shown, without unlocking.
- **An opened locked note stays open.** It is not re-locked when the app goes to the background, and it is visible in the app switcher and to screenshots.
- **"Backup is off" is not the whole story on Android.** The phone's own system backup is not disabled, so notes may still be copied to Google.
- **Hidden network call.** On every launch the app contacts a third-party IP-location service over an insecure connection, only to add "Country" to the support email. Both platforms appear to block it by default, so it adds privacy risk without working. Remove it.

**Suggested direction:** encrypt locked notes with a key derived from the PIN (so backups are protected too), add attempt limits, hide locked titles optionally, re-lock on background, and block screenshots on locked notes. Until then, avoid wording like "secret" or "secure" for this feature.

---

## 3. Current issues

- **Search only looks at the title and the first non-empty section.** Text in other sections is never found, although the screen says "section content".
- **Empty "Untitled Idea" notes pile up.** A new idea is saved the moment the editor opens, even if nothing is typed.
- **"Filter" opens the Sort sheet.** The three-dot menu has a single, mislabelled item.
- **Android shows "Face ID / Touch ID"** wording on the PIN screen.
- **Deleting a section is instant** — no confirmation and no undo.
- **Two automated tests fail** (101 pass). Both are out of date with current behaviour rather than real bugs: one expects the old list layout, one expects locked notes to reopen on launch.
- **Leftovers from removed features:** billing permission on Android, ad/paywall strings, an unused in-app rating prompt, and a README that still describes AI, free trial and paywall.

---

## 4. Existing features that need enhancement

- **Markdown editor.** Preview was removed, so users only ever see raw symbols (`**bold**`); formatting appears only in the PDF. Add a reading view or live formatting.
- **Sections.** New ones are all called "Untitled" (duplicates allowed), renaming is hidden behind tapping the active tab again, and they cannot be reordered.
- **Random Additions.** Cannot be edited, and cannot become a new idea — they can only be filed into an existing one.
- **Note lock.** No "forgot PIN" path, the PIN cannot be removed, and biometrics cannot be switched off in Settings.
- **Sorting.** "Newest first" means last edited; no sort by title or created date, and no pin/favourite.
- **Export.** Only PDF and copy-for-AI, one idea at a time. No plain share, and no full export/import to a local file — cloud backup is the only way out.
- **Deleting ideas.** Permanent, with no trash or undo.

---

## 5. UX improvements

- Quick capture sends the user to the Random Additions screen after every note, which breaks the "quick" flow. Stay on home and show a small confirmation instead.
- Selection mode on home has no clear way to cancel and no "select all"; the only action is delete.
- The "Backup is off" pill is always on the home screen and cannot be dismissed.
- The save-failed icon in the editor is a "cloud off" symbol, although saving is local.
- Locked notes are not reopened after the app is killed, while unlocked ones are — fine, but inconsistent with the documented flow rules.
- Give failed backups and restores specific, actionable messages.

---

## 6. New features worth adding

- **Save links** _(your idea)_. Suggested shape: a "Links" area per idea plus link capture in the quick-add box; paste or share a URL from the browser, fetch the page title automatically, tap to open. Make links inside notes tappable and include them in backup.
- **Share into the app.** Accept text and links shared from other apps straight into Random Additions — pairs naturally with saved links.
- **Trash / recently deleted** with a 30-day window.
- **Backup history and encrypted backups.**
- **Tags or folders, and pinning** important ideas to the top.
- **Checklists** inside sections for next steps.
- **Section templates** (e.g. Problem / Solution / Requirements) when creating an idea.
- **Home-screen widget** for one-tap capture.
- **Whole-app lock** as an option alongside per-note lock.
