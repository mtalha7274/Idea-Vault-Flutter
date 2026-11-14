# Local DB Structure

The app stores local note data in one SQLite database: `idea_vault.db`.

The database is opened by `IdeasDatabaseManager` in `lib/data/managers/local/ideas_database.dart`.

## Current Version

- Database version: `5`
- SQLite package: `sqflite`
- Foreign keys are enabled with `PRAGMA foreign_keys = ON`
- `PRAGMA secure_delete = ON` is set on every connection, so deleted rows (for example the plain sections of a note that was just locked) are overwritten instead of left in free pages
- `IdeasDatabaseManager.compact()` runs `VACUUM` (plus a WAL checkpoint) after the locked-note migration, after every lock, after a restore and after "Delete all locked notes and reset"

## Tables

### `ideas`

Stores the main note/idea record.

- `id`: primary key
- `title`: idea title
- `created_at`: creation date
- `updated_at`: last update date
- `last_opened_section_id`: last section opened in the editor
- `is_locked`: whether the idea is protected by the note lock
- `encrypted_payload`: `NULL` for normal notes. For an encrypted locked note it holds a JSON envelope `{"v":1,"alg":"A256GCM","kid":<vault key id>,"n":<base64 nonce>,"c":<base64 ciphertext + GCM tag>}`. The plaintext inside is `{"v":1,"title"?:…,"sections":[{id,name,content}]}`; the idea `id` is the associated data, so a blob cannot be moved to another row.
- `title_hidden`: `1` when "Hide locked note titles" is on for this note. The `title` column is then empty and the real title lives inside the encrypted payload; cards show "Locked note".

Not encrypted on purpose: `id`, dates, `is_locked`, `last_opened_section_id`.

Ideas are sorted by `updated_at` when loaded.

### `idea_sections`

Stores the sections inside each idea.

- `id`: primary key
- `idea_id`: links to `ideas.id`
- `name`: section name
- `content`: section markdown/text content
- `sort_order`: section order inside the idea

Deleting an idea deletes its sections automatically through `ON DELETE CASCADE`.

An encrypted locked note has **no** rows here. Its sections exist only inside `ideas.encrypted_payload` and are decrypted into the editor session when the note is opened.

### `random_additions`

Stores quick-capture text before it is filed into an idea.

- `id`: primary key
- `content`: captured text
- `created_at`: creation date

### `note_vault`

One row (`id = 1`) describing the locked-note vault. It is copied verbatim into every backup's `lock` block.

- `id`: always `1`
- `key_id`: random id of the current vault key (also stored in each payload's `kid`)
- `lock_block`: JSON `{"v":1,"encrypted":true,"epoch":1,"keyId",createdAt,"pin":{pinKind,kdf,n,c},"recovery":{kdf,n,c}}`. `pin` is the 32-byte vault key wrapped with AES-256-GCM under a key derived from the PIN (Argon2id m=19 MiB, t=2, p=1, or PBKDF2-HMAC-SHA256 600,000 rounds when Argon2id is measured too slow); `recovery` is the same key wrapped under an HKDF-SHA256 key from the 160-bit recovery code. KDF parameters and salts are stored with each wrap so they can be raised later.
- `updated_at`: last change (PIN change and new recovery code rewrite only this row, never the notes)

The vault key itself is never in the database. It is cached in the platform secure storage (`note_vault_key_v1`, `note_vault_key_id_v1`) and held in memory only while a locked note is open.

## How Ideas Work

- The app model is `Idea`, not `Note`.
- Each `Idea` is loaded from one row in `ideas` plus its related rows from `idea_sections`.
- `IdeasRepo.getIdeas()` loads ideas and sections, then joins them in memory.
- `IdeasRepo.upsertIdea()` saves the idea row, deletes all old sections for that idea, then inserts the current sections again.
- `IdeasRepo.deleteIdeas()` deletes idea rows; sections are removed automatically.
- `IdeasRepo.saveIdeas()` wipes and replaces all ideas and sections, mainly for restore flows.
- `IdeasRepo.writeIdeasAtomically()` writes many ideas in one transaction; the locked-note migration uses it so either every locked note is encrypted or none is.
- `IdeasProvider` never keeps decrypted locked content: its list holds the ciphertext row; `openLockedIdea()` decrypts into the editor session only, and every autosave re-encrypts.

## Migrations

- Version 1: original `ideas` and `idea_sections` tables
- Version 2: added `random_additions`
- Version 3: added `last_opened_section_id` to `ideas`
- Version 4: added `is_locked` to `ideas`
- Version 5: added `encrypted_payload` and `title_hidden` to `ideas`, and the `note_vault` table. Existing locked notes stay plain until the next PIN entry, when they are encrypted in one transaction and the database is compacted.

The note lock feature stores lock state on `ideas`, because locking applies to the whole idea/note rather than to individual sections.
