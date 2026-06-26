# Local DB Structure

The app stores local note data in one SQLite database: `idea_vault.db`.

The database is opened by `IdeasDatabaseManager` in `lib/data/managers/local/ideas_database.dart`.

## Current Version

- Database version: `4`
- SQLite package: `sqflite`
- Foreign keys are enabled with `PRAGMA foreign_keys = ON`

## Tables

### `ideas`

Stores the main note/idea record.

- `id`: primary key
- `title`: idea title
- `created_at`: creation date
- `updated_at`: last update date
- `last_opened_section_id`: last section opened in the editor
- `is_locked`: whether the idea is protected by the note lock

Ideas are sorted by `updated_at` when loaded.

### `idea_sections`

Stores the sections inside each idea.

- `id`: primary key
- `idea_id`: links to `ideas.id`
- `name`: section name
- `content`: section markdown/text content
- `sort_order`: section order inside the idea

Deleting an idea deletes its sections automatically through `ON DELETE CASCADE`.

### `random_additions`

Stores quick-capture text before it is filed into an idea.

- `id`: primary key
- `content`: captured text
- `created_at`: creation date

## How Ideas Work

- The app model is `Idea`, not `Note`.
- Each `Idea` is loaded from one row in `ideas` plus its related rows from `idea_sections`.
- `IdeasRepo.getIdeas()` loads ideas and sections, then joins them in memory.
- `IdeasRepo.upsertIdea()` saves the idea row, deletes all old sections for that idea, then inserts the current sections again.
- `IdeasRepo.deleteIdeas()` deletes idea rows; sections are removed automatically.
- `IdeasRepo.saveIdeas()` wipes and replaces all ideas and sections, mainly for restore flows.

## Migrations

- Version 1: original `ideas` and `idea_sections` tables
- Version 2: added `random_additions`
- Version 3: added `last_opened_section_id` to `ideas`
- Version 4: added `is_locked` to `ideas`

The note lock feature stores lock state on `ideas`, because locking applies to the whole idea/note rather than to individual sections.
