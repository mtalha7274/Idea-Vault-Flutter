# Idea Vault - AI Context Brief

## Purpose

This file is the handoff brief for AI agents working on Idea Vault. It explains the shipped app behavior, main architecture, feature flows, and where to start in the codebase. Treat this as engineering context, not marketing copy or a roadmap.

## App Overview

Idea Vault is a Flutter app for capturing, organizing, and exporting ideas. Users create ideas with multiple sections; each section has a title and Markdown content. The app supports local-first editing, quick random additions, AI organization, speech-to-text, image-to-text OCR, PDF export, AI-friendly text export, cloud backup, and subscriptions.

The app is available for iOS and Android and is built under Pocket Micros.

## Architecture

- Flutter app entrypoint is `lib/main.dart`.
- Dependency injection is configured in `lib/injection_container.dart` using GetIt.
- App navigation helpers live in `lib/config/router/app_router.dart`.
- Local structured data uses SQLite through `lib/data/managers/local/ideas_database.dart`.
- Lightweight local settings and counters use SharedPreferences through `lib/data/managers/local/local_storage.dart` and `lib/data/managers/local/shared_preference.dart`.
- State is mostly Provider / ChangeNotifier based, with providers under `lib/viewmodels/providers/`.
- Firebase Functions backend code lives under `functions/src/`.
- UI text keys live in `lib/core/constants/view_constants.dart`; translations are in `assets/translations/`.
- Theme definitions live in `lib/config/theme/` and shared app UI style helpers live in `lib/views/ideas/idea_vault_theme.dart`.

## Feature Map

### Home, Ideas, and Search

- `lib/views/home.dart` is a thin root widget that opens `Homepage`; it does not show the paywall on startup.
- `lib/views/homepage.dart` shows the idea list, layout/filter controls, drawer, empty state, and bottom quick-capture composer.
- `lib/views/search_ideas_screen.dart` provides idea search using `lib/core/utils/idea_search.dart`.
- Idea cards and responsive list/grid layout are in `lib/widgets/ideas/ideas_layout.dart`.
- Idea persistence is handled by `IdeasProvider` in `lib/viewmodels/providers/ideas_provider.dart` and `IdeasRepo` in `lib/data/repositories/local/ideas.dart`.
- Core idea models are in `lib/models/idea.dart`.

### Editor

- Main editor screen is `lib/views/idea_editor.dart`.
- Markdown editing UI and toolbar widgets are in `lib/widgets/idea_markdown_editor.dart`.
- Section add/edit/delete sheet is `lib/widgets/sheets/idea_editor_section_sheet.dart`.
- Organize confirmation and character-limit messaging are in `lib/widgets/sheets/organise_section_sheet.dart`.
- The editor autosaves with a 700ms debounce, saves on close/dispose/lifecycle pause, and persists resume state through `lib/data/repositories/local/idea_editor_state.dart`.
- AI organize warning starts around 4,000 characters and has a 4,200 character hard limit, aligned with the backend function.

### AI Organize

- Frontend entrypoint is the editor toolbar in `lib/views/idea_editor.dart`.
- Flutter calls `IdeaOrganizationRepository` in `lib/data/repositories/remote/idea_organization_repository.dart`.
- Backend function is `functions/src/organizeSection.ts`, exported from `functions/src/index.ts`.
- The function calls OpenRouter via the OpenAI SDK and currently uses `google/gemini-2.5-flash-lite`.
- Secrets use Firebase Secret Manager with `OPENROUTER_API_KEY`; local emulator uses `.env.local` in the functions project.

### Speech to Text

- Speech dictation is handled inside `lib/views/idea_editor.dart` using the `speech_to_text` package.
- Users long-press the mic control to dictate into the active section.
- A normal mic tap only shows the long-press tooltip and does not trigger paywall access.
- Permission prompts are handled in the editor with `permission_handler`.

### Image to Text OCR

- OCR is launched from the editor toolbar in `lib/views/idea_editor.dart`.
- Image picking/cropping uses `image_picker` and `image_cropper`.
- Text recognition service abstraction is in `lib/core/services/image_text_recognition_service.dart`.
- Current implementation uses Google ML Kit text recognition for Latin script.
- Recognized text is inserted into the current section at the cursor, or appended in a clean line position.

### Random Additions

- Quick-capture composer is `lib/widgets/random_addition_composer.dart`.
- Drawer screen is `lib/views/random_additions_screen.dart`.
- Provider and local repository are `lib/viewmodels/providers/random_additions_provider.dart` and `lib/data/repositories/local/random_additions.dart`.
- Model is `lib/models/random_addition.dart`.
- Users can capture stray thoughts, then file each one into an existing idea section; filing appends text and deletes the random addition.

### Export

- Editor more-options sheet is `lib/widgets/sheets/idea_options_sheet.dart`.
- Export screen is `lib/views/export_for_ai_screen.dart`.
- `ExportMode.aiExport` copies selected/reordered sections to the clipboard in an AI-friendly text format.
- `ExportMode.pdfExport` converts selected/reordered sections from Markdown to styled HTML and uses the `printing` package for native PDF share/save.
- Export paid-feature usage is counted when the primary export/copy button is tapped after section-selection validation.

### Cloud Backup

- User-facing screen is `lib/views/backup_restore_screen.dart`.
- Provider is `lib/viewmodels/providers/backup/cloud_backup_provider.dart`.
- Settings are persisted by `lib/data/repositories/local/cloud_backup_settings.dart`.
- Backup orchestration is in `lib/core/services/backup/cloud_backup_service.dart`.
- Android backup store is `lib/core/services/backup/google_drive_backup_store.dart`.
- iOS backup store is `lib/core/services/backup/icloud_backup_store.dart`.
- Daily scheduling and background task support live in `lib/core/services/backup/cloud_backup_scheduler.dart` and `lib/core/services/backup/cloud_backup_background_task.dart`.
- Backup snapshots are serialized with `lib/models/backup/cloud_backup_snapshot.dart`.

## Monetization / Paywall Rules

- Startup paywall is removed; the app opens directly to the idea vault.
- Paywall UI is `lib/views/paywall_screen.dart`.
- Paywall and access policy live in `lib/viewmodels/providers/premium/paywall_view_model.dart`.
- Subscription abstractions and RevenueCat implementation live in `lib/core/services/premium/`.
- Premium feature enum is `lib/models/premium/premium_feature.dart`.
- Free-use counter is `lib/data/repositories/local/paid_feature_usage.dart`.
- Adjustable free-use limit is `Config.paidFeatureFreeUsageLimit` in `lib/config/config.dart`.
- Non-Pro users get 30 local lifetime paid-feature uses shared across AI Organize, speech to text, image to text, Export for AI, and Export to PDF.
- Pro users bypass the free-use counter.
- The 30th counted use is allowed; the 31st counted use shows the paywall.
- Cloud backup does not increment the counter.
- Cloud backup is allowed for non-Pro users while they are under the free-use limit.
- When a non-Pro user reaches the limit, cloud backup is disabled and scheduled backup is cancelled.
- After a successful purchase or restore, `AppRouter.showPaywall` opens `BackupRestoreScreen` so the user can re-enable cloud backup.
- Debug bypass support is in `lib/core/services/premium/bypass_paywall_subscription_service.dart` and is controlled by `Config.debug` plus `Config.bypassPaywall`.

## Key File Map

- Boot and dependency setup: `lib/main.dart`, `lib/injection_container.dart`
- Routing: `lib/config/router/app_router.dart`
- Global config: `lib/config/config.dart`
- Home/list/search: `lib/views/home.dart`, `lib/views/homepage.dart`, `lib/views/search_ideas_screen.dart`
- Editor: `lib/views/idea_editor.dart`, `lib/widgets/idea_markdown_editor.dart`
- Editor sheets: `lib/widgets/sheets/idea_editor_section_sheet.dart`, `lib/widgets/sheets/idea_options_sheet.dart`, `lib/widgets/sheets/organise_section_sheet.dart`
- Idea data: `lib/models/idea.dart`, `lib/data/repositories/local/ideas.dart`, `lib/viewmodels/providers/ideas_provider.dart`
- Random additions: `lib/views/random_additions_screen.dart`, `lib/widgets/random_addition_composer.dart`, `lib/data/repositories/local/random_additions.dart`
- AI organize: `lib/data/repositories/remote/idea_organization_repository.dart`, `functions/src/organizeSection.ts`
- OCR: `lib/core/services/image_text_recognition_service.dart`
- Export: `lib/views/export_for_ai_screen.dart`
- Backup: `lib/views/backup_restore_screen.dart`, `lib/viewmodels/providers/backup/cloud_backup_provider.dart`, `lib/core/services/backup/`
- Paywall/subscriptions: `lib/views/paywall_screen.dart`, `lib/viewmodels/providers/premium/paywall_view_model.dart`, `lib/core/services/premium/`
- Local usage counter: `lib/data/repositories/local/paid_feature_usage.dart`
- Themes and visual style: `lib/config/theme/`, `lib/views/ideas/idea_vault_theme.dart`

## Testing Notes

- Flutter tests live under `test/`.
- Idea persistence tests: `test/data/repositories/local/ideas_repo_test.dart`
- Provider tests: `test/viewmodels/providers/ideas_provider_test.dart`, `test/viewmodels/providers/random_additions_provider_test.dart`, `test/viewmodels/providers/paywall_view_model_test.dart`
- Free-use counter tests: `test/data/repositories/local/paid_feature_usage_test.dart`
- Backup snapshot tests: `test/models/backup/cloud_backup_snapshot_test.dart`
- Homepage/editor flow widget tests: `test/views/homepage_test.dart`
- Editor text insertion utility tests: `test/core/utils/editor_text_insertion_test.dart`
- Usual verification commands are `flutter analyze` and `flutter test`.
