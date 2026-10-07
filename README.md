# Keepr — AI receipt & warranty vault

Snap a receipt and Keepr reads it with AI, tracks return windows and warranty end dates, reminds you before deadlines, and builds a claim-ready PDF when something breaks. One Flutter codebase for **Android, iOS and Web**, with a **Supabase** backend.

Built from the product requirements in [`docs/Keepr_PRD.docx`](docs/Keepr_PRD.docx).

## Features

| Area | What it does |
|---|---|
| **Scan + auto-fill** | Take or pick a photo and Keepr fills in the store, date, items, prices, total, currency, payment method, return window and warranties. On Android and iOS the receipt is read **on the device** (Apple Vision / Google ML Kit + Keepr's receipt parser): free, unlimited, offline, no account needed. With a cloud account, a Claude vision model (Edge Function) is used first for harder receipts, falling back to the device. Low-confidence fields are highlighted for checking. |
| **Vault** | Search by store, item, serial number or amount; filter by status (Protected, Expiring soon, Returnable, Drafts) and category; duplicate detection. |
| **Protection** | Return window and warranty tracking with status and progress; reminders 3 days before a return deadline and 30 / 7 days before a warranty ends (local notifications on Android and iOS). |
| **Claim pack** | One tap generates an A4 PDF with purchase summary, items and serials, warranty status, the problem description, a claim letter and the receipt photos, then opens the share sheet. |
| **Offline-first** | Everything works without a network. Changes go into an outbox and sync when you reconnect; receipts scanned offline are read by AI later. |
| **Household sharing** | Invite family by code with Owner / Editor / Viewer roles, enforced by Postgres Row-Level Security. |
| **Insights** | Monthly spend chart, spend by category, protected value, CSV export. |
| **Plans** | Free (15 AI scans, 3 claim packs per month) and Premium, with quotas enforced on the server. |
| **Polish** | Light and dark themes, responsive layout (bottom bar on phones, navigation rail on tablets and desktop web), 30-day trash, sample data for demos. |

## Architecture

Clean Architecture with three layers per feature, the **MVP pattern** in the presentation layer, and **Riverpod** for state and dependency injection.

```
View (ConsumerWidget) ──intent──▶ Presenter (Riverpod Notifier) ──▶ Use case (Domain)
      ▲                                │                                   │
      └──────── immutable UiState ◀────┘                     Repository interface (port)
                                                                           │
                                         Repository impl (Data) ──▶ Hive (local) / Supabase (remote)
```

- **Domain** (`features/*/domain`): pure Dart entities, value objects (`Money`), business rules (`ProtectionRules`, `ReceiptValidator`, `ReminderPlanner`), use cases and repository interfaces. It imports no Flutter, Supabase or storage packages.
- **Data** (`features/*/data`): repository implementations, local/remote data sources, JSON models and platform adapters (notifications, PDF, image capture, sharing). Exceptions are converted to domain `AppFailure`s here.
- **Presentation** (`features/*/presentation`): passive Views render a sealed `UiState`; Presenters (Riverpod `Notifier` / `AsyncNotifier`) call use cases and map `Result<T>` to state.
- **Composition root**: [`lib/app/di/providers.dart`](lib/app/di/providers.dart) wires every dependency; tests override any provider with a fake.

```
lib/
├─ app/            # app widget, router, theme, shell, DI providers
├─ core/           # Result, failures, Money, formatting, storage, shared widgets
└─ features/
   ├─ auth/        ├─ receipts/     ├─ protection/   ├─ claims/
   ├─ insights/    ├─ household/    ├─ billing/      ├─ settings/
   └─ sync/
supabase/
├─ migrations/     # schema, RLS policies, sync and invite functions
└─ functions/      # extract-receipt, delete-account, revenuecat-webhook
```

## Getting started

Requirements: Flutter 3.44+ (Dart 3.12+). Xcode for iOS, Android Studio / SDK for Android.

```bash
flutter pub get
flutter run -d chrome
```

Without any configuration Keepr runs in **local mode**: you create an on-device profile, receipts are read automatically on your phone, and everything works except cloud backup, sharing and cloud AI. Use **Settings → Add sample receipts** to explore with demo data.

### Connect the backend (Supabase)

1. Create a project at [supabase.com](https://supabase.com) and install the [Supabase CLI](https://supabase.com/docs/guides/cli).
2. Link and push the schema:
   ```bash
   supabase link --project-ref YOUR-PROJECT-REF
   supabase db push
   ```
3. Set the Edge Function secrets and deploy:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase secrets set REVENUECAT_WEBHOOK_SECRET=choose-a-long-random-string
   supabase functions deploy extract-receipt
   supabase functions deploy delete-account
   supabase functions deploy revenuecat-webhook --no-verify-jwt
   ```
   The extraction model defaults to `claude-opus-5-5`. To trade some accuracy for lower cost, set `KEEPR_EXTRACTION_MODEL` (for example `claude-haiku-4-5`, the model named in the PRD's cost target).
4. In **Authentication → URL Configuration**, add `io.keepr.app://login-callback` as a redirect URL. To enable Google sign-in, configure the Google provider in **Authentication → Providers**.
5. Copy `env.example.json` to `env.json`, fill in your project URL and publishable (anon) key, and run:
   ```bash
   flutter run --dart-define-from-file=env.json
   ```

## Testing

```bash
flutter analyze
flutter test
```

The suite covers the business rules (BR-01 … BR-13), the data layer against a real Hive store, the AI response mapping, the PDF renderer, use cases with fakes, presenters through `ProviderContainer` overrides, and a widget test for the item editor.

## Security notes

- The app ships only the Supabase publishable key. The Anthropic key lives in Edge Function secrets.
- Every table has Row-Level Security; receipts, items and storage objects are visible only to household members, and only owners/editors can change them.
- Sync writes go through the `upsert_receipt` database function so a receipt and its items are saved atomically, with last-write-wins conflict handling.
- AI scans are rate-limited (30 per hour per user) and quota-checked on the server.

## Production checklist

- **Payments:** `DemoBillingGateway` simulates purchases. Replace it with a RevenueCat-backed `BillingGateway` (`purchases_flutter`) and point RevenueCat's webhook at `revenuecat-webhook`.
- **Web scanning:** browsers have no on-device text recognition, so the web app needs the cloud AI backend to auto-fill receipts.
- **Server push reminders (v1.1):** reminders are local notifications today; web users see them in the Protection tab.
- App icons, store listings, release signing and a privacy policy URL.
