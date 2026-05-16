Idea Vault — Full Project Summary

App Overview: Idea Vault is a Flutter app for capturing and developing random ideas. Users create ideas with multiple sections, each section has a title and markdown content. Available on iOS and Android. Built by Talha under Pocket Micros.

Tech Stack:

Flutter with SQLite for local storage
Firebase Functions (TypeScript) for backend
Supabase for cloud backup (planned)
Markdown editor with preview mode for section content
OCR for image-to-text via camera or gallery (Google ML Kit Text Recognition, Latin script)
Flutter native splash screen configured
AI Feature — Organize Section: Firebase onCall function in functions/src/organizeSection.ts using OpenAI SDK pointed at OpenRouter. Currently using google/gemini-2.5-flash-lite model. Takes raw markdown section content, reorganizes grammar and structure, returns clean markdown. Secrets stored in Firebase Secret Manager as OPENROUTER_API_KEY. Local emulator uses .env.local file. Includes retry logic with exponential backoff, AbortController timeout, and input validation with 2000 character soft guidance.

Editor: Plain markdown editor with preview mode. Toolbar has Title, Bold, Italic, Bullet List, Code Block buttons. Auto-save implemented with 800ms debounce timer. Saves on dispose and app lifecycle pause. Save button replaced with subtle "Saved" checkmark indicator. OCR from camera or gallery inserts recognized text into the section at the cursor.

Bottom Sheet (more_vert icon in editor): Three options — Export for AI, Export to PDF, Delete Idea.

Export for AI: Opens ExportForAIScreen with ExportMode.aiExport. Reorderable list of sections with checkboxes, all checked by default. Fixed Copy to Clipboard button at bottom. Copies formatted text in this format:

Idea: [Title]

[Section 1 Title]
[Section 1 Content]
Shows toast "Copied! Paste into any AI chat." Feature is called "Idea Export for any AI" in marketing.

Export to PDF: Reuses ExportForAIScreen with ExportMode.pdfExport. Same reorderable section selection screen. Bottom button says Export to PDF. Uses markdown package to convert to HTML, printing package for native share/save dialog. Styled HTML with clean typography.

Delete Idea: Confirmation dialog reused from homepage.dart. On confirm deletes from SQLite and navigates back to listing screen.

Paywall — Idea Vault Pro: Full screen paywall shown 1-2 seconds after app launch. Yearly plan selected by default showing $1.67/month, billed $19.99/year, Save 44% badge, 3 day free trial. Monthly plan $2.99/month no trial. CTA says "Start Free Trial" on yearly and "Get Pro Monthly" on monthly. Restore Purchases, Privacy Policy, Terms of Service at bottom. Close X button top right.

Pro Features:

Extended AI Organize
Extended AI Brainstorm Chat
Speech to text dictation
Cloud backup via Supabase
Export to PDF
Idea Export for any AI
Priority support
Free Tier:

Unlimited ideas and sections
Basic markdown editor
Limited AI Organize
Limited AI Brainstorm Chat
Local storage only
Monetization:

Yearly: $19.99/year ($1.67/month) with 3 day free trial
Monthly: $2.99/month no trial
Apple/Google take 15% (small developer tier)
API costs per heavy user: ~$0.11/year organize only
Net per user after fees and API costs: ~$16.88/year
AI Limits Strategy: Vague limits — say "Extended" not specific numbers. Show progress indicator like "3 of 5 remaining" without specifying reset period. Free users get enough to feel value but not enough to rely on it.

UI Notes:

App uses dark green primary color, rounded cards, clean typography, light background
Empty state is centered on listing screen
Grammar fix: "1 section" not "1 sections"
Paywall checkmarks are dark filled, "Most popular" badge on yearly plan
IdeaPreprocessor max input 2000 characters before truncation
Pending / Planned:

Supabase authentication and cloud backup
RevenueCat or in_app_purchase integration for actual subscriptions
App Check enforcement once app is live on both stores
AI Brainstorm Chat feature (future, after launch)
Search bar on listing screen
Sort options on listing screen
Add Section tab rename from "+"
Auto-title prompt on new idea creation

