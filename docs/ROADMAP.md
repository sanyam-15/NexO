# Nexo Roadmap

Product roadmap based on phased delivery.

## Phase 0 — Foundation ✅
- Flutter project scaffold
- Material 3 baseline
- Feature-first structure
- Riverpod + GoRouter
- Linux run support

## Phase 1 — Core Finance MVP ✅
- [x] Add expense/income
- [x] Home dashboard (balance + charts)
- [x] Local persistence (SQLite)
- [x] Category monthly budget progress
- [x] Edit/delete transactions
- [x] Better empty/loading/error states

## Phase 2 — Cashew-inspired Power Features ✅
- [x] Recurring transactions (base CRUD)
- [x] Upcoming payments/reminders (state + action flow)
- [x] Debts and lent/borrowed tracking
- [x] Category limits per budget
- [x] Multi-account support
- [x] Multi-currency support (base)

## Phase 2.5 — Material 3 Expressive System (In progress)
- [x] Define Expressive UI principles for Nexo (shape, type, hierarchy)
- [x] Build shared expressive components:
  - [x] `DsScreenScaffold`
  - [x] `DsSectionCard`
  - [x] `DsListTile`
  - [x] `DsTopAppBar`
  - [x] `DsInput` / `DsSelect` expressive variants
- [x] Unify spacing/radius/elevation across core screens (initial pass)
- [x] Apply expressive pass to Home, Add, Recurring, Debts, Category Limits
- [x] Add interactive states consistency (hover/focus/pressed/disabled)
- [x] Add expressive motion patterns (enter/exit, list transitions, feedback)
- [x] Accessibility guardrails full pass (contrast + touch targets, initial pass)

## Phase 3 — Analytics & Insights (In progress)
- [x] P3-01 Date-range filters (7d / 30d / mes actual / custom)
- [x] P3-02 Period-over-period comparisons
- [x] P3-03 Cashflow and category trend analysis
- [x] P3-04 Smart insight cards (spending anomalies, budget risk)
- [x] P3-05 Analytics Period Hub (overview de periodos → detalle seleccionado)

## Phase 4 — Data Portability & Reliability
- [x] CSV import/export
- [x] Backup/restore (full JSON, upsert restore)
- [ ] Optional cloud sync
- [x] Data migration strategy/versioning (`PRAGMA user_version` runner)

## Phase 5 — Product Quality & OSS Maturity
- [x] Expanded test suite (unit + DB-migration tests; DI seam for in-memory DB)
- [ ] Performance profiling and optimization
- [ ] Accessibility audit (contrast, touch targets, semantics)
- [ ] Contributor onboarding improvements
- [x] CI: analyze + `flutter test --coverage` + Android build gate
- [ ] Release process and changelog automation

## Phase 6 — Android Studio Deployment & Release Readiness ✅
- [x] Generate and validate Android project setup (`flutter create .` sanity for android/)
- [x] Configure Android package/applicationId, min/target SDK, and Gradle compatibility
- [x] Add launcher icons, splash, and app name variants for Android
- [x] Build-type setup: debug/profile/release + signing config (keystore)
- [x] Verify runtime on Android emulator (Pixel) and at least one physical device
- [x] QA pass on Android: navigation, forms, analytics charts, DB migrations, performance
- [x] Permissions and platform behavior review (notifications, locale/timezone, storage expectations)
- [x] Produce release APK/AAB and document install/play-store-ready steps

## Phase 7 — Firebase Managed Platform (In progress)
Goal: move Nexo to a managed cloud data + auth + observability stack while keeping offline reliability.

### P7-01 Firebase foundation
- [ ] Create Firebase projects/environments (dev/prod) + app registration
- [ ] FlutterFire CLI setup and generated platform configs
- [ ] Remote Config baseline (feature flags for gradual rollout)

### P7-02 Authentication
- [ ] Firebase Auth integration (Email + Google)
- [ ] Session persistence + secure sign-out flows
- [ ] Route guards and onboarding/auth gating

### P7-03 Firestore data model + rules
- [ ] Define Firestore collections (users, accounts, transactions, budgets, recurring, debts)
- [ ] Security rules scoped by `request.auth.uid`
- [ ] Composite indexes for dashboard/analytics queries

### P7-04 Hybrid migration strategy (SQLite -> Firestore)
- [ ] Keep SQLite as local cache/fallback during migration
- [ ] One-time migration tool (local data push to Firestore)
- [ ] Bidirectional sync service with conflict policy (last-write-wins + audit timestamps)

### P7-05 Reliability & observability
- [ ] Crashlytics integration + non-fatal error logging
- [ ] Firebase Analytics event taxonomy (capture, edit, budget, debt, reminder)
- [ ] Sync health diagnostics screen (last sync, pending writes, retry status)

### P7-06 Release hardening
- [ ] Rollout by feature flag (internal -> beta -> full)
- [ ] Fallback mode to local-only when Firebase unavailable
- [ ] Backfill tests for auth/sync/rules critical paths

---

## Phase 8 — Cashew Parity + AI (delivered)
Goal: reach feature parity with Cashew, enhanced with on-device-friendly AI.

### Core finance
- [x] Accounts as entities: balances, transfers, net worth
- [x] Categories as entities: emoji/color/type, subcategories
- [x] Budgets: weekly/monthly/yearly/custom cycles, category filters, pacing
- [x] Savings goals: contributions, deadline, suggested monthly
- [x] Transactions: search + filters, transfers, notes, date picker, swipe-delete
- [x] Labels/tags + per-transaction labeling
- [x] Multi-currency with live FX rates (cached, static fallback)

### AI (Anthropic Messages API, raw HTTP — no Dart SDK)
- [x] Natural-language capture ("café 45 ayer con débito")
- [x] Receipt OCR via vision (camera/gallery)
- [x] Auto-categorization (also surfaced in the manual add flow)
- [x] Spending insights / financial coach
- [x] Opt-in API key + model selection (Haiku default)

### Platform
- [x] Local notifications for upcoming payments
- [x] Biometric / device-credential app lock
- [x] Theme mode + accent color customization
- [x] Spanish (es-MX) localization delegates
- [ ] Money as integer cents (correctness refactor — pending)
- [ ] AutoCapture (Android notification → transaction — separate design)

---

## ADHD UX Layer (Cross-phase, aligned to roadmap)
Goal: maximize capture consistency for users with ADHD (low friction, low cognitive load, high habit retention).

### Phase 2 scope (no major module expansion)
- [x] Quick Add flow (capture in 10–15s)
- [ ] Progressive disclosure in forms (minimum required first)
- [x] Recurrent templates (rent, subscriptions, payroll, gym)
- [x] Clear save confirmation with next execution date
- [x] Upcoming list prioritized by urgency: Hoy / Mañana / Esta semana
- [ ] Undo after create/delete (short snackbar window)

### Phase 3 scope (behavior + adherence)
- [ ] Lightweight streaks / consistency indicators
- [ ] Daily check-in prompt (“¿Te faltó registrar algo hoy?”)
- [ ] Gentle reminders with snooze (non-intrusive)
- [ ] Insight cards optimized for action, not just analytics

### Phase 5 scope (validation + quality)
- [ ] ADHD-focused usability review (task completion + time-to-log)
- [ ] Accessibility conformance pass (WCAG AA + touch ergonomics)
- [ ] UX copy consistency audit (clear language, low ambiguity)

### Success metrics
- [ ] Median time-to-log <= 15s
- [ ] % of days with at least one log (weekly adherence)
- [ ] % of entries created via Quick Add
- [ ] Drop-off rate during add flow

---

## Design System Track (Material 3 Expressive)
Runs in parallel with feature phases.

- [x] DS tokens: spacing, radius, motion, typography
- [x] DS components: section title, card, primary button
- [x] DS components: feature header, stat card, empty state
- [x] DS components: top app bar, section card, expressive list tile, scaffold shell
- [x] Expressive shape + elevation strategy (initial implementation)
- [ ] Interaction states (hover/focus/pressed) consistency
- [x] Motion choreography guide (durations, easing, sequence)
- [x] Theming documentation (initial) in `lib/design_system/README.md`
