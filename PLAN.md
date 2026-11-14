# Idea Vault — Fix & UI Plan

_13 Nov 2026 · covers the five "Fix first" items from AUDIT.md plus the four UI changes._
_Based on the current code, a dependency dry-run on this project's Flutter (3.38.4), and web research (sources at the end). Nothing here has been built or device-tested yet._

## Contents

- [0. Overview, order and decisions](#0-overview-order-and-decisions)
- [A. Backup safety (Fix 1 + Fix 2)](#a-backup-safety-fix-1--fix-2)
- [B. Locked notes: real protection (Fix 3)](#b-locked-notes-real-protection-fix-3)
- [C. Search (Fix 4)](#c-search-fix-4)
- [D. Empty "Untitled Idea" notes (Fix 5)](#d-empty-untitled-idea-notes-fix-5)
- [E. Home screen: top bar and quick-note button](#e-home-screen-top-bar-and-quick-note-button)
- [F. Selection: ideas and random notes](#f-selection-ideas-and-random-notes)
- [G. Editor: real formatting instead of markup](#g-editor-real-formatting-instead-of-markup)
- [H. Cross-cutting: tests, docs, rollout, risks](#h-cross-cutting-tests-docs-rollout-risks)
- [Sources](#sources)

---

## 0. Overview, order and decisions

### Release order

Ship in four releases so the data-loss fixes go out first and the two risky pieces (editor, encryption) each get their own release.

| Release | Contents | Size | Why this order |
|---|---|---|---|
| **R1 — Safety** | A1 backup guards, A2 banner fix, A3 restore validation, C search, D empty notes, B1 lock hardening | ~2 weeks | Stops data loss and the cheap lock bypasses. No format or dependency changes. |
| **R2 — Home & selection** | E top bar + quick-note button, F selection, A4 backup history + restore picker, A5 honest status | ~2 weeks | Visible UX wins; backup history needs the new file naming. |
| **R3 — Editor** | G WYSIWYG editor | ~3 weeks incl. spike | Largest UI risk; isolated so it can be rolled back alone. |
| **R4 — Encryption** | B2 encrypted locked notes, recovery code, backup lock block | ~3 weeks | Needs R2's backup format and benefits from R3's content pipeline. |

### Decisions taken in this plan (change any of them before work starts)

| # | Decision | Recommendation | Reason |
|---|---|---|---|
| 1 | Editor engine | **Fleather**, behind our own adapter, after a 2–3 day spike | Only candidate that installs on the current Flutter with no native code; its document model matches our content. Details in G. |
| 2 | Storage format for note text | **Keep plain markdown-style text** in the database and backups | No migration, backups stay readable by older versions, search/export keep working. |
| 3 | Locked-note encryption key | Random vault key, wrapped by the PIN (Argon2id) and by a recovery code | Lets backups stay protected and restorable on a new phone. |
| 4 | PIN length | New PINs are **6 digits**, with an optional passphrase; existing 4-digit PINs keep working | A 4-digit PIN cannot protect a stolen backup file, whatever the algorithm. |
| 5 | Locked-note titles | **Stay visible** by default; "Hide titles" as a setting in R4 | Users need to find their notes; titles are documented as not secret. |
| 6 | Restore with existing local data | Offer **Replace** and **Merge** | Removes the all-or-nothing trap. |
| 7 | Naming | Rename "Random Additions" to **"Random Notes"** in all user-facing text | Matches how the feature is actually described. |

---

## A. Backup safety (Fix 1 + Fix 2)

### What is wrong today

- Turning Cloud Backup on never looks at what is already in the cloud. Auto Backup defaults to on, and "never backed up" counts as "due now", so the next app open or resume uploads the current vault over the only backup file.
- Restore is hidden behind the Cloud Backup switch, which forces the user down exactly that path on a new phone.
- There is one backup file. Every upload overwrites it.
- The home banner restores on one tap, cannot be dismissed, and survives after new ideas exist.
- Restore replaces ideas and random notes in two separate steps, skips unreadable entries silently, and ignores the backup's format version.

### A1. Guards that stop the overwrite — R1

**Rule 1 — never upload an empty vault automatically.** Auto backup (foreground and background) is skipped when there are 0 ideas and 0 random notes. A manual "Back Up Now" with an empty vault while a non-empty cloud backup exists asks for confirmation.

**Rule 2 — auto backup stays off until the cloud state is "resolved".** Add a persisted flag `remoteStateResolved`. Auto backup refuses to run while it is false. It becomes true only at the end of the enable flow below.

**Rule 3 — the enable flow always checks the cloud first.**

| Cloud | Local | What the user sees | Result |
|---|---|---|---|
| No backup | Anything | Nothing extra | Enable; if local has data, run the first backup immediately with visible progress |
| Backup exists | Empty | Sheet: "Backup found — 12 ideas, 3 notes · 2 Nov 2026 · Pixel 8" → **Restore** / **Start fresh** | Either choice resolves; "Start fresh" deletes nothing in the cloud |
| Backup exists, made by this device | Has data | Nothing extra | Enable |
| Backup exists, made by another device | Has data | Sheet → **Merge** / **Replace this device** / **Keep this device's data** | Resolved after the choice |
| Check failed (offline, sign-in cancelled, iCloud unavailable) | Anything | Specific error, switch returns to off | Not enabled, not resolved |

**Rule 4 — restore no longer requires enabling backup.** The Restore section is always active. Tapping it connects to the account (user-initiated sign-in on Android) for reading only; it does not switch Auto Backup on.

**Rule 5 — one code path.** Foreground catch-up and the background task currently duplicate the "is it due" logic. Move all rules into one backup coordinator that both call, so a guard can never be present in one and missing in the other.

**Supporting changes**

- Give each install a random **device ID** and store the device model name; both go into every backup. Stored under its own key so that turning backup off does not erase it.
- "Change account" on Android re-runs the enable flow for the new account and clears last-backup time, size and the resolved flag (they belong to the old account).
- Prevent foreground and background from uploading at the same time with a lock marker (treated as stale after 10 minutes). The background isolate must reload preferences before reading and must only write the fields it owns, so it cannot resurrect settings the user just changed.

**Edge cases**

| Case | Handling |
|---|---|
| User enables backup, closes the sheet without choosing | Treated as cancel: switch off, nothing resolved |
| App killed in the middle of the enable flow | Flag never set → next launch backup is simply off; no upload happened |
| User on old phone and new phone at once | Each device writes its own files (A4), so neither overwrites the other; the screen shows "Also backed up from Pixel 8" |
| Vault emptied on purpose (user deleted everything) | Auto backup skips; history keeps the last non-empty snapshot; manual backup asks first |
| Vault has only random notes | Counts as non-empty everywhere (today only ideas are checked) |
| Google authorisation lapsed in background | Skipped, recorded as "needs sign-in" (A5), never prompts from background |
| User upgrades from the current version with backup already on | Treated as resolved **only if** a last-backup time exists; otherwise the enable check runs once on next open |

### A2. Home "Cloud backup found" banner — R1

- **Tap Restore:**
  - Vault completely empty (0 ideas, 0 random notes) → restore immediately. Nothing can be lost, and this keeps the documented "restore on first tap" rule.
  - Anything exists locally → confirmation sheet showing backup date, device and counts, with **Merge** and **Replace**.
- **Dismiss:** add a close button. Dismissal is remembered; restore stays available from the Backup screen.
- **Auto-hide:** the banner disappears as soon as the user has any idea or random note. It is an empty-vault helper, nothing more.
- **Failure:** keeps the banner and shows the specific reason (existing rule, unchanged).
- **Busy state:** disabled while any backup or restore is running.
- **Android first launch:** the silent check depends on Google granting access without UI, which is unreliable on a fresh install. Replace it with a neutral one-time card on an empty vault: "Have a backup? Restore". Tapping it starts sign-in. iOS keeps the silent check because iCloud needs no sign-in.
- Update FLOW_RULES.md to match.

### A3. Safe restore — R1

1. **Download and fully validate before touching local data.** Reject with a clear message if: the file is not valid JSON; the format version is newer than this app supports ("Update the app to restore this backup"); any idea or note fails to parse (no silent skipping); the stored content hash does not match.
2. **Local safety copy first.** Write the current vault to a private file on the device before every replace or merge. Keep the last 3. Offer "Undo restore" on the Backup screen for 7 days.
3. **One transaction.** Replace ideas, sections and random notes together, so a failure leaves the old data intact.
4. **Merge algorithm** (by idea ID):
   - Not on device → add.
   - On device and identical → skip.
   - On device and different → keep the newer one in place and add the older as "Title (from backup)", so nothing is ever discarded.
   - Random notes merge by ID the same way; duplicates by ID are skipped.
   - Result summary: "Added 8, kept 3 copies, skipped 12 identical".
5. **After restore:** clear the editor resume state, exit any selection mode, return to home.

**Edge cases**

| Case | Handling |
|---|---|
| Backup contains 0 ideas and 0 notes | Warn "This backup is empty" and do not replace |
| Download interrupted / times out (iCloud 30 s limit today) | Nothing changed locally; message says to retry; raise the timeout and show progress |
| App killed mid-restore | Transaction rolls back; safety copy also exists |
| Backup has locked notes but this device has no PIN | R1: current behaviour. R4: asks for the backup's PIN (see B2) |
| Restore started while an idea is open in the editor | Not reachable today (different screen), but the coordinator still flushes the editor's pending save first |
| Old-format backup (v1/v2, including the legacy "delta" content) | Still readable; conversion happens in memory |

### A4. Backup history — R2

- **One file per backup** instead of one file overwritten. Name carries what the restore picker needs without downloading: format version, UTC time, short device ID, idea count, note count.
- **Skip unchanged uploads.** If the content hash equals the last uploaded snapshot, do not upload; just record "checked". History then holds the last _distinct_ states rather than seven identical days.
- **Retention, per device:** keep the 7 newest snapshots, plus always keep the newest non-empty one. Never rotate another device's files. If a single snapshot exceeds 5 MB, keep 3.
- **Rotation is best-effort:** a failed delete never fails the backup.
- **Restore picker:** list of snapshots (date, device, counts, size), newest preselected.
- **The old single file** (`idea_vault_backup.json`) is left untouched so older app versions can still restore. It is shown in the picker as "Older backup (before update)". It is removed in R4 once encrypted backups exist (see B2, plaintext clean-up).
- **Format v3 header:** version, backup ID, created time, device ID and name, app version, counts, content hash, and a reserved optional `lock` block (filled in R4) so R4 needs no further format bump.
- Drop pretty-printing to cut size by roughly a third.
- **Ordering uses the cloud's own modified time**, not the device clock, so a phone with a wrong clock cannot make its backup look newest.

**Platform notes**

| | Google Drive | iCloud |
|---|---|---|
| Listing | Query the hidden app folder by name prefix, newest first, paged | List the container, filter by prefix, ignore files still uploading |
| Write | New file each time; a file only appears once fully uploaded | Upload, then **wait for the progress stream to finish** before reporting success (today "complete" is shown when the upload merely starts) |
| Pending | — | If the wait times out, show "Uploading to iCloud…" and confirm on next open |

### A5. Honest status — R2

- Track last attempt, last success, last error type and consecutive failures.
- Backup screen: green tick only when the last success is under 48 hours old; amber "Last backup 5 days ago" beyond that; red with an action ("Sign in again", "Turn on iCloud Drive", "No internet") when failing.
- Home: the existing "Backup is off" slot also shows "Backup needs attention" after 3 days of failures or when sign-in is required.
- Replace "We back up your ideas every 24 hours" with "We try to back up once a day, when you open the app or in the background."
- iOS: the account row reads "iCloud" with no "Change" button.
- **Turning backup off:** confirmation that says existing cloud backups are kept, with a separate, double-confirmed "Delete cloud backups". On Android, sign out instead of revoking access: Google's documentation only ties deletion of hidden app data to removing the app from Drive, and whether a revoke also triggers it is unconfirmed — so avoid the revoke and verify on a real account.
- One message per failure type instead of the single generic one.

### Acceptance for A

- New install, enable backup with an existing cloud backup, leave the app, come back the next day: cloud backup is unchanged until the user chooses.
- No path uploads an empty vault without an explicit confirmation.
- Restore can be started with Cloud Backup off.
- A corrupted or newer-format backup leaves local data untouched.
- Banner: dismissible, confirms when data exists, gone once the vault has content.

---

## B. Locked notes: real protection (Fix 3)

### What is wrong today

- Locked notes are plain text in the database and in the backup file.
- A fresh install clears the PIN; restoring then lets anyone create a new PIN and open every locked note.
- 4-digit PIN, unlimited attempts.
- Biometric unlock falls back to the phone passcode.
- Locked text is searchable, notes can be filed into locked ideas without unlocking, an open locked note stays open in the background and shows in the app switcher.
- Android system backup is not disabled, so the database can be copied to Google regardless of the in-app switch.

### What we can and cannot promise

| Attacker | After B1 | After B2 |
|---|---|---|
| Someone holding the unlocked phone, opening the app | Blocked by PIN + attempt limits | Blocked |
| Same person reinstalling and restoring | **Still works** (notes are plain text) | Blocked — restore asks for the original PIN |
| Someone who gets the backup file or the database | Reads everything | Sees ciphertext; must guess the PIN offline |
| Offline guessing of a 4-digit PIN | — | Feasible in hours or less. This is why new PINs are 6 digits and a passphrase is offered |
| Malware/root on an unlocked device while a note is open | Not protected | Not protected (no app can) |

The UI text must say this plainly. Do not use "secure" or "encrypted" until R4 ships.

### B1. Hardening without encryption — R1

1. **Attempt limits.** 5 free tries, then waits of 30 s, 1 min, 5 min, 15 min, 1 h (repeating). Counter and "locked until" time live in secure storage so restarting the app does not reset them. If the device clock moves backwards, the wait restarts. Applies everywhere a PIN is entered. Show a countdown.
2. **Biometrics only.** Biometric prompt no longer accepts the phone passcode; the fallback is the app PIN.
3. **Re-lock on background.** When the app is paused with a locked note open: save, drop the unlocked state, show the lock overlay on return. Do not trigger while the app's own biometric prompt, share sheet or PDF print dialog is in front.
4. **Privacy in the app switcher.** Android: turn on the secure-window flag only while a locked note or the PIN screen is visible (ordinary notes stay screenshot-able). Small native call, no new package. iOS: cover the window with a blur when the app becomes inactive while a locked note is open. iOS cannot block screenshots; say so.
5. **No content leaks.** Search matches locked notes by title only. Filing a random note into a locked idea asks for unlock first; locked ideas show a lock icon in the picker and do not list section names until unlocked.
6. **Disable Android system backup and device transfer** for the app (manifest flag plus backup-rules files for Android 12+). This is also the secure-storage plugin's own recommendation, because restored key material cannot be decrypted.
7. **Keyboard learning off** in locked notes (the "no personalised learning" input flag), so typed secrets do not enter the keyboard's dictionary.
8. **Correct labels.** Android shows "Use fingerprint" / "Use biometrics" instead of "Face ID / Touch ID".
9. **Settings additions:** turn biometric unlock on/off.

### B2. Encryption — R4

**Keys**

| Key | What it is | Where it lives |
|---|---|---|
| Vault key | 32 random bytes; encrypts every locked note | In the device's secure storage (for fast and biometric unlock); in memory only while a locked note is open |
| PIN wrap | The vault key encrypted with a key derived from the PIN | In the database, and therefore in backups |
| Recovery wrap | The vault key encrypted with a key derived from the recovery code | Same |
| PIN verifier | Fast on-device check of the PIN (existing salted hash) | Secure storage only |

- **Derivation:** Argon2id, starting at 19 MiB memory, 2 passes, 1 lane (OWASP baseline), run in a background isolate. Benchmark on a low-end Android phone during the spike; target under 1.5 s. The parameters are stored with the wrap so they can be raised later. If pure-Dart Argon2id is too slow, fall back to PBKDF2-SHA256 at 600,000 rounds using the platform implementation.
- **Encryption:** AES-256-GCM, fresh random nonce on every save, note ID bound in as associated data so a blob cannot be swapped between notes. Tampering or a wrong key is detected, never shown as garbage.
- **Package:** `cryptography` + `cryptography_flutter` (both resolve on the current Flutter; verified by dry-run).
- **Recovery code:** 160 random bits shown once as grouped characters at setup, with "Copy" and "I saved it". Can be regenerated while unlocked.

**What is encrypted**

- All section names and content of a locked idea, as one blob on the idea row. The plain section rows are deleted.
- Title stays readable (decision 5). With "Hide titles" on, the title moves into the blob and the card shows "Locked note".
- Not encrypted: IDs, dates, the locked flag, last-opened section ID.
- After migration run a secure-delete pass and compact the database, otherwise the old plain text survives in freed pages.
- The in-memory list of ideas no longer holds locked content at all; it is decrypted only into the editor session.

**Flows**

| Flow | Steps |
|---|---|
| First lock | Create PIN (6 digits or passphrase) → generate vault key → create both wraps → show recovery code → encrypt the note |
| Lock another note | Encrypt with the vault key; no PIN needed to _add_ protection |
| Open | Biometric or PIN → load vault key → decrypt into the editor → every autosave re-encrypts |
| Remove lock | Authenticate → decrypt → store as normal sections |
| Change PIN | Verify old → re-wrap the vault key → notes untouched |
| New phone / reinstall + restore | Locked notes arrive as ciphertext. App asks "Enter the PIN for your locked notes" (or recovery code). Correct → vault key cached, biometric offered. **No "create new PIN" path exists while encrypted notes are present** — this closes the bypass |
| Forgot PIN | Recovery code → set new PIN. If biometric unlock was already enabled → biometric → set new PIN. Otherwise the only option is "Delete all locked notes and reset", double-confirmed |
| Secure storage lost (OS quirk, cleared keystore) | Same as new phone: ask PIN, unwrap from the copy in the database |

**Migrating existing locked notes**

1. After the update, locked notes stay as they are until the user next enters the PIN. Biometric unlock is paused once, with the message "Enter your PIN once to finish securing your locked notes" — the PIN is needed to create the PIN wrap, and without it a backup would be unrestorable.
2. On that PIN entry: generate the vault key and wraps, offer the 6-digit upgrade (skippable), show the recovery code, encrypt all locked notes in one transaction, compact the database.
3. Immediately run a new backup, then **delete the old plaintext backups**: the legacy single file and any pre-encryption snapshots. Until this succeeds, show "Old backups still contain your locked notes — retry".
4. If the user has forgotten the PIN at this point, the notes are still plain: allow biometric (if enabled) to set a new PIN, otherwise offer delete-and-reset.

**Backup interaction**

- Background backup needs no key: it copies ciphertext.
- Restoring an **older snapshot made under a different PIN** needs the PIN from that time; the error must say so and offer the recovery code (which survives PIN changes).
- **Merge** with locked notes on both sides and different vault keys: ask for the backup's PIN once, re-encrypt imported notes under this device's key. If the user skips, locked notes from the backup are listed as "not imported".
- **Fresh install then new PIN, then restore:** same as above; never silently overwrite a vault key that still protects local notes.
- iOS Keychain survives reinstall: keep clearing stale key material on a genuinely fresh install, as today.

**Edge cases**

| Case | Handling |
|---|---|
| App killed during migration | One transaction; either all locked notes are encrypted or none. Vault key is stored before the transaction starts |
| Crash between encrypting and deleting old backups | Flag "plaintext clean-up pending" survives restart and retries |
| Autosave while backgrounding | Flush (encrypt + write) before dropping the key |
| Very long locked note | Encrypt in an isolate if above ~200 KB to avoid a typing stutter |
| Bulk delete including locked notes | One authentication, as today |
| Export / copy for AI of a locked note | Only from an unlocked editor session (already the case) |
| New fingerprint enrolled by someone who knows the phone passcode | Known limitation of app-level biometrics. Optional "strict mode": bind the stored vault key to biometrics so new enrolment invalidates it and the PIN is required |
| User turns off biometrics in system settings | Falls back to PIN |
| Data already copied by Android system backup before B1 | Cannot be force-deleted by the app; mention in release notes |
| Wrong PIN on restore | Attempt limits apply; the notes stay as ciphertext and nothing else in the restore is blocked |

### Acceptance for B

- Reinstall + restore does not open a locked note without the original PIN or recovery code.
- The backup file and the database contain no readable text from a locked note.
- Ten wrong PINs take more than six minutes.
- A locked note is not visible in the app switcher and is locked again after returning from the background.
- Changing the PIN does not rewrite any note, and biometric unlock keeps working afterwards.

---

## C. Search (Fix 4)

### What is wrong today

Search matches the title and the card preview, and the preview is only the first non-empty section. Everything in other sections is invisible to search.

### Plan — R1

1. **Search everything:** title, every section name, every section's text.
2. **Match on clean text.** Strip formatting markers before matching so "bold" finds `**bold**`. In R3 this uses the editor's own plain-text conversion (G); until then, the existing stripping applied per section.
3. **Normalise both sides:** lower-case, collapse whitespace, fold common accents, strip Arabic/Urdu vowel marks.
4. **Several words = all must appear** (anywhere in the idea, in any order).
5. **Rank:** title match, then section-name match, then content match; ties by last edited.
6. **Show why it matched.** The result card shows a short snippet around the first match with the term highlighted and "in _Section name_". Opening the result opens that section.
7. **Speed.** Keep a per-idea cache of the normalised text, rebuilt only when that idea changes. Debounce typing by ~150 ms. Move matching to an isolate only if the total text exceeds ~5 MB.
8. **Locked notes:** title only, no snippet.
9. Fix the screen's helper text if needed so it is true.

### Edge cases

| Case | Handling |
|---|---|
| Match only in section 3 of 5 | Found; snippet from section 3; opens section 3 (the regression test for this bug) |
| Query is only spaces | Empty prompt state |
| Query contains `*`, `_`, `#` | Treated as literal text |
| Emoji, Urdu/Arabic, mixed direction | Substring match works; snippet cut on character boundaries, never mid-emoji |
| Match at very start or end of long text | Snippet clamps, ellipsis only on the cut side |
| Idea edited while results are open | Cache entry refreshed; results update live |
| Idea with no sections / all empty | Matches by title only |
| 1,000+ ideas | Stays within one frame budget after debounce; verified with a generated dataset |

### Acceptance

Text in any section is found; locked content never appears; the snippet shows the matched words.

---

## D. Empty "Untitled Idea" notes (Fix 5)

### What is wrong today

Opening the editor for a new idea forces a save immediately, and an empty title is saved as "Untitled Idea". Close without typing and the empty note stays.

### Plan — R1

1. **Remove the save-on-open.** A new idea is only a draft in memory.
2. **Save when it becomes meaningful:** title not blank, **or** any section has text, **or** sections were added/renamed. Then normal autosave applies.
3. **On close:**
   - Never saved and not meaningful → nothing is stored.
   - Created in this session, saved, then emptied again → delete it silently.
   - An existing idea that the user emptied → keep it (never auto-delete something that existed before this session).
4. **Unsaved-draft UI:** lock button stays hidden (already the case); the options menu shows "Discard" instead of Export/Delete.
5. **The "save failed" indicator** must not light up for "nothing to save yet".
6. **One-time clean-up** of what the bug already created. Delete an idea only if all are true: title is exactly "Untitled Idea"; it has one section named "Idea"; that section is blank; it is not locked. Run once, guarded by a flag.

### Edge cases

| Case | Handling |
|---|---|
| App backgrounded after typing two characters | The existing save-on-pause runs; now meaningful → saved |
| App killed within the autosave delay without a pause event | Up to ~0.7 s of typing lost (same as today) |
| User types a title, deletes it, closes | Created this session and empty → removed |
| User only adds a second section and closes | Meaningful (structure changed) → saved as "Untitled Idea" |
| Resume-after-restart for a draft that was never saved | No resume state is written without a saved ID (already true) |
| Random-note filing "create an idea first" | Unaffected |
| Tests that expect an idea to exist right after opening the editor | Rewritten to the new rule |

### Acceptance

Open and close "New Idea" ten times: zero new items. Existing junk is gone after the update; no idea with any content or a custom title is touched.

---

## E. Home screen: top bar and quick-note button

### E1. Top bar with a small plus — R2

**Layout:** menu · "Idea Vault" · (space) · search · sort · **plus**

- **Title:** from 34 down to about 22, bold, single line with ellipsis. Matches the editor's header size so screens feel consistent.
- **Plus:** small filled circular button in the primary colour, about 40 px visible with a 48 px touch area, rightmost. Label for screen readers: "New idea".
- **Remove the floating button** and the bottom-padding maths that made room for it.
- **Sort:** replace the three-dot menu that holds a single mislabelled "Filter" item with a direct sort icon. Same sheet as today.
- **Empty state:** add a "Create your first idea" button inside the empty card, since the large floating button is gone.

**Edge cases**

| Case | Handling |
|---|---|
| Large system font / narrow phone | Title shrinks and ellipsises; the four icons never wrap |
| Selection mode | The whole bar is replaced by the selection bar (F) |
| Tablet width | Same bar, constrained to the content width as today |
| Double-tap on plus | Guard against pushing two editors |
| Existing tests keyed on the old button | Update keys |

### E2. Quick-note button instead of a text field — R2

- Replace the bottom text field with a **button that looks like the current pill**: note icon · "Add a random note…" · unfiled-count badge (if any) · forward arrow in a circle.
- **Tap anywhere** opens the Random Notes screen with the keyboard already up in the composer. Opening the same screen from the drawer does not auto-open the keyboard.
- Announced as a button to screen readers, not a text field.
- **Remove from home:** the text controller, focus handling, multi-line padding logic and the "submit then navigate" step.
- **On the Random Notes screen:** sending a note keeps the user there (this also removes the "bounce" problem from the audit).
- Hidden during selection mode, as the field is today.
- Keep the fade above it so list content does not collide with the button; reduce the list's bottom padding to the button height plus safe area.

**Edge cases**

| Case | Handling |
|---|---|
| Gesture-navigation inset / home indicator | Button sits above the safe area |
| Count above 99 | Shows "99+" |
| Returning from the screen | Home has no keyboard to restore; scroll position unchanged |
| Long translated label | Ellipsis; arrow and badge keep their size |

---

## F. Selection: ideas and random notes

### What is wrong today

A selected item only changes to a pale tint with a faint border. On random notes the bubble even loses contrast. There is no visible "selection mode", no cancel, no select-all, and Android back leaves the screen instead of leaving selection.

### Shared behaviour — R2

- One small selection controller used by both screens: selected IDs, toggle, select all, clear.
- **Enter** by long-press, with a haptic tick. **Tap** toggles while active. Deselecting the last item exits.
- **Back** (button or gesture) exits selection first.
- Selection drops IDs that no longer exist (after delete, restore, merge).
- Every selected item is announced as "selected" to screen readers, and no state relies on colour alone.

### F1. Idea cards

- **Selected:** 2 px primary border, tinted fill, and a filled check badge in the top-right corner that scales in.
- **Not selected, while selection is active:** an empty circle in the same corner, so the mode and the effect of a tap are obvious.
- **Top bar becomes a selection bar:** close · "3 selected" · select all · delete.
- Plus, search, sort, drawer swipe and the quick-note button are unavailable in selection mode.
- Locked cards can be selected; deleting them asks for authentication once (unchanged).

### F2. Random notes — WhatsApp pattern

- **Selected row:** a full-width tinted band from screen edge to screen edge behind the bubble. The bubble keeps its normal colour and text contrast.
- **Whole row is the tap target** in selection mode, not just the bubble.
- Adjacent selected rows merge into one continuous band (row spacing lives inside the row).
- **App bar becomes:** close · count · copy · file into idea · delete.
  - Copy: joins selected notes in time order.
  - File: one destination for all selected notes, appended in time order.
- Outside selection, a tap still opens the filing sheet as today.
- The composer stays usable, as in WhatsApp.

### Edge cases

| Case | Handling |
|---|---|
| Light and dark themes | Band and badge checked for visible contrast in both |
| Very long note bubble | Band covers the full row height |
| Right-to-left languages | Badge and band mirror correctly |
| List re-sorts or new note arrives during selection | Selection is by ID, so it stays on the right items |
| Select all with hundreds of items | Instant; only visible rows rebuild |
| Filing several notes fails halfway | Notes are removed only after their text is saved; the rest stay selected |
| Delete confirmation text | Uses the translated strings (two are hard-coded today) |

---

## G. Editor: real formatting instead of markup

### What is wrong today

The editor is a plain text field. Bold, italic, heading, bullet and code buttons insert symbols (`**`, `_`, `##`, `-`, ```` ``` ````) and the user sees the symbols. The preview that rendered them was removed, so formatting is only ever visible in a PDF.

### Options compared

| Option | Fits current Flutter (3.38.4) | Native code added | Notes |
|---|---|---|---|
| **Fleather** | Yes — 1.27.0 resolves, 5 dependency changes | None | Active (release ~2 months ago). Document model is markdown-shaped: bold, italic, strike, inline code, links; headings; bullet, numbered and check lists; code block; quote |
| flutter_quill | 11.5.0 resolves; latest 11.6.0 needs Flutter ≥ 3.44 | Yes (native bridge, keyboard plugin), 22 dependency changes | Largest community. Recommends its own JSON format; markdown via a separate package last published ~20 months ago |
| appflowy_editor | Not tested | Several | Last release ~11 months ago; heavy dependency list; built for Notion-style documents |
| super_editor | Not tested | — | Stable release is ~2 years old; current work is pre-release only |
| Custom editor on the text field | Yes | None | Full control and native typing behaviour, but weeks of work and limited to simple styles |

**Choice: Fleather, wrapped in our own adapter**, with flutter_quill as plan B and a custom editor as plan C.

**Important:** do **not** use any package's built-in markdown import/export. Fleather's drops blank lines, does not escape literal `*` or `_`, and separates every paragraph with a blank line; standard markdown parsers also merge lines separated by a single line break. Notes in this app were typed in a plain field where every line break is real. We need our own small converter.

### Architecture

1. **Stored text stays as it is** (decision 2). No database or backup change.
2. **Our own converter** between stored text and the editor's document. Line-based: each stored line is one editor line; blank lines are kept exactly.
3. **An adapter** hides the editor package behind our own widget and controller interface. The rest of the app never imports the package directly, so switching to plan B or C touches one folder.
4. **The classic plain editor remains** as a fallback for one release (see safety net).

### The text format (what the converter reads and writes)

| Kind | Stored as |
|---|---|
| Heading / subheading | `## ` / `### ` at line start (`# ` also read) |
| Bullet | `- ` (also reads `* ` and `+ `) |
| Numbered | `1. ` |
| Checklist | `- [ ] ` / `- [x] ` |
| Quote | `> ` |
| Code block | lines between ```` ``` ```` fences |
| Bold / italic / strike / inline code | `**x**` / `_x_` (also reads `*x*`) / `~~x~~` / `` `x` `` |
| Link | `[text](url)` |

**Reading rules that protect existing notes**

- A marker only counts when it has a matching partner **on the same line** and sits at a word edge. `snake_case_name`, `2 * 3 * 4`, a lone `**` and file paths stay literal.
- Unclosed code fence: the rest is treated as a code block rather than dropped.
- Unknown or broken syntax always falls back to literal text. Nothing is ever discarded.

**Writing rules**

- A literal character is escaped with a backslash **only** where it would otherwise be read as formatting. Ordinary text is stored untouched, so search, card previews and AI export stay clean.
- A section is rewritten only when the user actually edits it. Merely opening a note never changes stored text or its "last edited" time.

**The guarantee, enforced by tests:** reading stored text and writing it back, then reading again, gives the identical document; and the visible characters of any existing note are never changed by opening it.

### Editor behaviour

- **Toolbar** (same look as today): heading, bold, italic, bullet list, numbered list, checklist, code block, inline code, link, undo, redo. Buttons show an active state for the current selection.
- **No selection:** a style button applies to what is typed next.
- **Lists:** Enter continues the list; Enter on an empty item ends it; Backspace at the start of an item removes the bullet.
- **Typing shortcuts:** typing `- ` or `## ` at line start still converts, for people who are used to it.
- **Links:** tappable; auto-detected when typed or pasted. (Groundwork for the "save links" feature.)
- **Paste:** plain text pastes as plain text. If the pasted text is clearly markdown, run it through our converter so it arrives formatted.
- **Styling:** current font, size and line height; headings slightly larger and bolder; code in a monospaced font on a tinted background; correct colours in light and dark.
- **Preview mode is removed entirely** (state field, toolbar parameter, preview widget, and the markdown-rendering package if nothing else uses it).

### Changes around the editor

| Area | Change |
|---|---|
| Autosave | One document per section, created when first opened and kept for the session (keeps cursor and undo per section). Mark a section "dirty" on change; convert only dirty sections when the autosave timer fires. Removes today's whole-idea comparison on every keystroke |
| Section switching | Swap the document, not the text |
| Card previews and search | Use the converter's plain-text output; fixes today's mangling of underscores |
| Filing a random note into a section | Append as literal text through the converter, so `2*3` in a note cannot turn into formatting |
| PDF export | Build the print layout from the converted document so the PDF matches the editor line for line (today single line breaks are merged) |
| Copy for AI | Keeps the stored markdown-style text — the best input for an AI |
| Locked notes | Editor is read-only under the lock overlay; keyboard learning off (B1) |
| iOS "Done" bar | Keep; attach to the new editor's focus |

### Spike first (2–3 days, on real devices) — go / no-go

All must pass on one low-end Android phone and one iPhone:

1. Sits inside the current scrolling layout (collapsing title, pinned section tabs and toolbar) with the caret always kept visible above the keyboard and below the pinned bars.
2. Typing is correct with Gboard, Samsung keyboard (predictive text on), swipe typing, voice typing, and iOS autocorrect: no jumping caret, no duplicated or lost characters.
3. Urdu/Arabic and mixed-direction text, emoji, and long-press selection handles behave like a normal text field.
4. A 50,000-character note opens in under ~150 ms and types without visible lag.
5. Sentence auto-capitalisation and the "no personalised learning" flag are available.
6. Screen readers can read and edit the text.
7. Can be driven from widget tests well enough to keep our editor tests.

If 1–3 fail → repeat the spike with flutter_quill 11.5.0. If both fail → plan C.

**Plan C (custom):** keep the native text field and attach style ranges to the text in our own controller — no hidden characters, so the caret always matches what is visible. Supports bold, italic, inline code, heading size, and bullet/number/check prefixes as managed characters. No block backgrounds or tap-able checkboxes. Uses the same converter and the same adapter interface. Estimate: 3–4 weeks.

### Safety net and rollout

- **Background check on first launch after update:** run the converter over every section (off the main thread, nothing logged but counts). Any section that fails the guarantee opens in the classic plain editor, with a small "plain text" marker.
- **Hidden switch** to force the classic editor for all notes, for support cases.
- Remove the classic editor one release later if the failure count in testing is zero.

### Edge cases

| Case | Handling |
|---|---|
| Existing note with stray markers (`**` alone, odd underscores) | Stays literal by the word-edge and same-line rules |
| Existing note already using `**bold**` | Now shows as bold — the intended upgrade |
| Note written by the old AI feature using `*` bullets or `#` headings | Read correctly; rewritten in the standard form only after an edit |
| Multiple blank lines | Preserved exactly |
| Leading/trailing blank lines | Preserved |
| Tabs and indentation inside code blocks | Preserved; no formatting applied inside code |
| Formatting across several lines selected | Applied per line; stored per line |
| Bold inside a heading, italic inside a list item | Supported |
| Nested lists | One level in the first version; deeper indentation is kept as plain leading spaces rather than lost |
| Very long single line | No special handling needed |
| Undo after switching sections | Per-section history |
| Editor open during backup/restore | Flush pending edits before backup reads; restore closes the editor |
| Old app version restoring a backup made by the new editor | Sees the same markdown-style text it always did |
| Clipboard copy | Plain text (formatting markers not included) |
| App killed mid-typing | Same autosave guarantees as today |

### Acceptance

- Tapping bold makes the text bold, with no symbols visible, and the same for every toolbar action.
- Every existing note opens with exactly the same visible characters as before.
- Saved text is still readable markdown-style text in the database and backups.
- No regression in typing on the test devices listed in the spike.

---

## H. Cross-cutting: tests, docs, rollout, risks

### Testing

| Area | Tests |
|---|---|
| Backup | Fake cloud store driving every row of the enable-flow table; empty-vault guard in foreground and background; unchanged-content skip; retention; restore validation failures; merge results; undo restore |
| Lock | Attempt-limit timing with a fake clock; re-lock on pause; known-answer vectors for derivation and encryption; wrong PIN; tampered blob; migration all-or-nothing; restore on a clean install requires the PIN |
| Search | Match in later sections; multi-word; accents; locked title-only; snippet bounds |
| Empty notes | Open/close leaves nothing; emptied-in-session removed; pre-existing emptied note kept; clean-up criteria |
| Home & selection | New bar and button keys; selection enter/exit/back; select all; golden images for selected states in light and dark |
| Editor | Converter: fixed corpus of real-style notes, plus randomised round-trip tests; adapter-level widget tests; manual device matrix from the spike |
| Existing suite | Fix the 2 currently failing tests (one assumes list layout, one assumes locked notes reopen on launch) |

**Manual device pass before each release:** one low-end Android, one Samsung, one recent iPhone; fresh install, upgrade install, and reinstall-then-restore.

### Documents to update

FLOW_RULES.md (banner and lock rules), LOCAL_DB_STRUCTURE.md (R4 columns), CLOUD_BACKUP_SETUP.md (file naming, history, sign-out), README changelog, and the privacy policy wording for locked notes and backups.

### Top risks

| Risk | Mitigation |
|---|---|
| Editor package misbehaves with some keyboards | Spike gate, adapter, classic-editor fallback, plan B and C |
| Converter changes someone's note | Guarantee tests, first-launch check, write-only-on-edit rule |
| User forgets PIN after encryption | Recovery code, biometric reset, clear warnings at setup |
| Encryption migration interrupted | Single transaction, key stored first, clean-up flag that retries |
| Old plaintext backups linger | Explicit delete step with retry and visible status |
| Key derivation too slow on old phones | Benchmark in spike, stored parameters, PBKDF2 fallback |
| Backup history uses more cloud space | Per-device cap, size-based cap, skip unchanged uploads |
| Behaviour differs on real Drive/iCloud | Items marked "verify on device": silent Google access on fresh install, sign-out vs revoke, iCloud upload completion |

### Out of scope here (still in AUDIT.md)

Trash/undo for deletes, the IP-location call, saved links, tags, full-vault local export, section reordering.

---

## Sources

- [flutter_quill on pub.dev](https://pub.dev/packages/flutter_quill)
- [flutter_quill repository](https://github.com/singerdmx/flutter-quill)
- [markdown_quill on pub.dev](https://pub.dev/packages/markdown_quill)
- [fleather on pub.dev](https://pub.dev/packages/fleather)
- [Fleather markdown codec source](https://github.com/fleather-editor/fleather/blob/master/packages/parchment/lib/src/codecs/markdown.dart)
- [ParchmentMarkdownCodec API docs](https://pub.dev/documentation/parchment/latest/codecs/ParchmentMarkdownCodec-class.html)
- [appflowy_editor on pub.dev](https://pub.dev/packages/appflowy_editor)
- [super_editor on pub.dev](https://pub.dev/packages/super_editor)
- [Comparison of Flutter rich text editors (Walturn)](https://www.walturn.com/insights/a-comparison-between-various-rich-text-editors-for-flutter)
- [Building live-formatting text fields in Flutter](https://flutterdigest.com/posts/building-live-formatting-text-fields-in-flutter-a-guide-to-rich-text-input-20260317-2/)
- [TextEditingController.buildTextSpan](https://api.flutter.dev/flutter/widgets/TextEditingController/buildTextSpan.html)
- [Google Drive: store application-specific data](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Revoking app access in Google Drive (9to5Google)](https://9to5google.com/2022/07/15/revoke-app-access-in-google-drive/)
- [google_sign_in on pub.dev](https://pub.dev/packages/google_sign_in)
- [Google Sign-In 7 authentication flow](https://dev.to/_ashish_tandon_/flutter-google-sign-in-with-googlesignin-7-understanding-the-new-authentication-flow-2pbe)
- [icloud_storage on pub.dev](https://pub.dev/packages/icloud_storage)
- [icloud_storage upload method](https://pub.dev/documentation/icloud_storage/latest/icloud_storage_method_channel/MethodChannelICloudStorage/upload.html)
- [cryptography on pub.dev](https://pub.dev/packages/cryptography)
- [sodium on pub.dev](https://pub.dev/packages/sodium)
- [ALTCHA Flutter (pure-Dart vs native Argon2 speed)](https://github.com/altcha-org/altcha-flutter)
- [Password hashing decision framework 2026](https://securityboulevard.com/2026/06/bcrypt-vs-argon2-vs-scrypt-vs-pbkdf2-a-2026-decision-framework/)
- [Argon2 vs PBKDF2](https://mojoauth.com/security-guides/argon2-vs-pbkdf2)
- [flutter_secure_storage on pub.dev](https://pub.dev/packages/flutter_secure_storage)
- [OWASP Top 10 for Flutter — insecure data storage](https://docs.talsec.app/appsec-articles/articles/owasp-top-10-for-flutter-m9-insecure-data-storage-in-flutter-and-dart)
- [no_screenshot on pub.dev](https://pub.dev/packages/no_screenshot)
