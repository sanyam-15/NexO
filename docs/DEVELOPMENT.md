# Development Guide

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (bundled with Flutter)
- Linux desktop dependencies (if running `-d linux`)
- Firebase project configured (optional for local-only flows)

## Setup

```bash
export PATH=/home/diego/clawd/.tooling/flutter/bin:$PATH
cd /home/diego/Proyectos/nexo
flutter pub get
```

## Run

```bash
flutter run -d linux
```

## Quality checks

Run before opening a PR:

```bash
flutter analyze
flutter test
```

## Useful paths

- App code: `lib/`
- Architecture docs: `docs/FIREBASE_ARCHITECTURE.md`, `docs/SYNC_ARCHITECTURE.md`
- Product roadmap: `../ROADMAP.md`

## Contribution workflow

1. Branch from `main` (or active integration branch).
2. Keep PRs focused by feature/module.
3. Run `flutter analyze` and `flutter test` before push.
4. Document behavior or architecture changes in `docs/`.
