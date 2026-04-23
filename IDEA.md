# Idea Vault

Idea Vault is a focused idea-capturing app built for speed, clarity, and continuity. The goal is to give people a quick way to save raw ideas, expand them into structured sections, and return to them later without losing momentum. The experience should feel lightweight and deliberate rather than overloaded with note-taking complexity.

## Core Product Direction

The app starts with an ideas listing screen that acts as the vault. This screen shows all saved ideas in a clean card-based layout with the title, a short preview, section count, and the last updated time. A floating action button lets the user create a new idea immediately. Tapping an idea opens the editor for that idea.

The editor is designed around the provided visual direction:

- a close button on the top left
- a save button on the top right
- a large title field
- a horizontally scrollable section tab bar
- an editing area for the active section
- a lightweight formatting toolbar

The editor supports the default sections `Idea`, `Requirements`, and `Design`, and users can add more custom sections through the `+` action in the tab bar.

## Editing Experience

The editor uses a custom lightweight markdown workflow instead of a heavy rich text package. Editing happens inside a plain `TextField`, while preview mode renders the same content as markdown. The editor has two modes:

- Edit mode: shows the markdown toolbar and the editable text area
- Preview mode: shows the rendered markdown output

The toolbar includes exactly five actions:

- H1 heading
- Bold
- Italic
- Bullet list
- Code block

These actions insert or wrap markdown syntax around the current selection so the editing experience stays simple and fast while still supporting structure.

The tab bar and section content should move together like a page view. Swiping between sections or tapping on tabs should animate the content horizontally while the active indicator stays aligned with the divider.

## Persistence Strategy

Idea content is stored in SQLite so the same structure can later be reused for a backend or sync layer. The data model is intentionally simple:

- `ideas`
  - `id`
  - `title`
  - `created_at`
  - `updated_at`
- `idea_sections`
  - `id`
  - `idea_id`
  - `name`
  - `content`
  - `sort_order`

This keeps idea data relational, ordered, and ready to evolve into a shared client/server schema later.

UI state is stored separately using shared preferences. This includes:

- which idea editor should reopen after app relaunch
- which tab was selected in that editor
- whether the editor was in edit mode or preview mode

If the user opens an existing idea, leaves the app, and comes back later, the app should reopen directly into that editor with the saved editor UI state restored. This should not change the explicit save flow for the actual idea content.

## Ideas List Interactions

The ideas list should support quick management without changing the current visual language.

- Long press on an idea enters selection mode
- Selected ideas show a selected count in the header
- The saved-ideas pill is replaced with a delete action while selection mode is active
- Tapping the delete action opens a confirmation popup
- Confirming the action deletes all selected ideas

The floating action button should stay visible in normal mode and disappear while selection mode is active.

## Product Constraints

- Keep the existing overall design direction intact
- Do not change core save behavior from explicit save to auto-save
- Keep search and settings out of scope for now
- Use shared preferences only for lightweight UI state
- Use SQLite for persistent idea data
- Keep the app cross-platform with no extra native setup required beyond standard Flutter packages

## v1 Outcome

Idea Vault v1 should feel like a clean, modern place to collect sparks of thought, break them into sections, preview them in markdown, and return exactly where the user left off when they reopen the app.
