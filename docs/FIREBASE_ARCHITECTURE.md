# Firebase Architecture — Nexo

## Objectives
- Move from local-only persistence to managed cloud data.
- Keep offline-first behavior and low-friction ADHD UX.
- Enable auth, sync reliability, and observability.

## Stack
- Firebase Auth (Email/Password + Google)
- Cloud Firestore (primary cloud database)
- Firebase Analytics (product events)
- Firebase Crashlytics (runtime errors)
- Remote Config (feature flags / staged rollout)

## Environments
- `nexo-dev` (internal testing)
- `nexo-prod` (real users)

Use separate Firebase projects and service accounts per env.

## Data Model (Firestore)

All user data is scoped by UID.

### Collections

`users/{uid}`
- `displayName: string`
- `email: string`
- `baseCurrency: string`
- `createdAt: timestamp`
- `updatedAt: timestamp`

`users/{uid}/accounts/{accountId}`
- `name: string`
- `type: string` (cash/bank/card/etc)
- `currency: string`
- `initialBalance: number`
- `archived: bool`
- `createdAt, updatedAt`

`users/{uid}/transactions/{txId}`
- `type: string` (expense/income/transfer)
- `accountId: string`
- `amount: number`
- `currency: string`
- `categoryId: string`
- `note: string?`
- `occurredAt: timestamp`
- `source: string` (manual/recurring/import)
- `createdAt, updatedAt`

`users/{uid}/budgets/{budgetId}`
- `monthKey: string` (YYYY-MM)
- `categoryId: string`
- `limitAmount: number`
- `currency: string`
- `createdAt, updatedAt`

`users/{uid}/recurring/{recurringId}`
- `title: string`
- `amount: number`
- `currency: string`
- `cadence: string` (weekly/monthly/custom)
- `nextRunAt: timestamp`
- `enabled: bool`
- `templateTransaction: map`
- `createdAt, updatedAt`

`users/{uid}/debts/{debtId}`
- `direction: string` (lent/borrowed)
- `counterparty: string`
- `principal: number`
- `currency: string`
- `dueAt: timestamp?`
- `status: string` (open/settled)
- `createdAt, updatedAt`

`users/{uid}/syncMeta/state`
- `lastSyncAt: timestamp`
- `pendingWrites: number`
- `lastError: string?`
- `schemaVersion: number`

## Suggested Indexes
- transactions by `occurredAt desc`
- transactions by `categoryId + occurredAt`
- transactions by `accountId + occurredAt`
- budgets by `monthKey + categoryId`
- recurring by `enabled + nextRunAt`

## Security Rules (baseline)

```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

Then tighten with validation per collection (types, ranges, immutable fields).

## Migration Strategy (SQLite -> Firestore)

### Step 1: Hybrid mode
- Keep SQLite as source-of-truth locally.
- Add sync service that mirrors to Firestore.
- Add `updatedAt` to all local entities if missing.

### Step 2: Initial backfill
- One-time migration command:
  - read local DB
  - write batched docs to Firestore
  - mark migration checkpoint in `syncMeta`.

### Step 3: Ongoing sync
- Outbound queue (local changes -> Firestore)
- Inbound pull (Firestore updates -> local cache)
- Conflict policy: **last-write-wins** with UTC `updatedAt` + audit logs for risky merges.

### Step 4: Cutover by feature flags
- `firebase_auth_enabled`
- `firebase_sync_enabled`
- `firebase_source_of_truth_cloud`

Rollout: internal -> beta -> all users.

## Analytics Event Taxonomy
- `tx_create`
- `tx_edit`
- `tx_delete`
- `budget_set`
- `recurring_create`
- `debt_create`
- `sync_success`
- `sync_error`
- `quick_add_used`

Include params: `currency`, `amount_range`, `entry_source`, `latency_ms`.

## Crashlytics Strategy
- Capture all uncaught crashes.
- Log non-fatal sync/auth errors with context:
  - user signed in?
  - pending writes
  - endpoint/module
  - schema version

## Operational Checklist
1. Create Firebase dev/prod projects.
2. Run FlutterFire configure for all platforms.
3. Add auth UI + session guard.
4. Implement Firestore repositories + local adapters.
5. Add migration command and dry-run mode.
6. Add sync diagnostics screen.
7. Enable staged rollout with Remote Config.

## Definition of Done (Phase 7)
- User can sign in and recover session.
- New/edit/delete finance records sync to cloud.
- App works offline and reconciles when online.
- Crashlytics and Analytics events visible in Firebase.
- Rollback path to local-only mode validated.
