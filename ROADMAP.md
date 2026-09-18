# ROADMAP

This roadmap prioritizes improvements that strengthen product quality and GitHub professionalism.

## Quick wins

- Add `docs/DEVELOPMENT.md` with local workflow, quality checks, and troubleshooting.
- Add `docs/ENVIRONMENT.md` consolidating Firebase/local env setup pointers.
- Add lightweight smoke checks in CI docs (`flutter analyze`, `flutter test`).
- Expand README architecture section with links to existing system docs.

## Medium

- Add golden tests for key design-system components.
- Add integration tests for core transaction flows (create/edit/delete).
- Introduce feature-level metrics logging for sync reliability and failures.
- Improve offline-first conflict resolution docs and retry UX.

## Big bets

- Migrate persistence layer to support encrypted local storage by default.
- Add background sync queue with robust conflict strategies.
- Add budgeting insights engine (forecast + anomaly alerts).
- Introduce modular plugin surface for import/export providers.

## Strategic rewrites

- Refactor feature modules toward stricter domain/application/infrastructure boundaries.
- Evaluate replacing ad-hoc repositories with a unified data access abstraction.
- Introduce a dedicated state/event architecture for sync-heavy features.
- Prepare multi-platform packaging strategy (desktop + mobile parity roadmap).
