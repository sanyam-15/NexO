# Contributing to Nexo

Thanks for your interest in contributing.

## Development workflow

1. Fork and clone the repo
2. Create a branch from `main`
   - `feat/<topic>`
   - `fix/<topic>`
   - `refactor/<topic>`
3. Make focused changes
4. Run checks:
   - `flutter analyze`
   - `flutter test`
5. Open a pull request

## Commit convention

Use Conventional Commits:

- `feat(scope): ...`
- `fix(scope): ...`
- `refactor(scope): ...`
- `chore(scope): ...`
- `docs(scope): ...`

## Pull request checklist

- [ ] Feature/fix is scoped and coherent
- [ ] Lint/analyze passes
- [ ] Tests updated or added when relevant
- [ ] Documentation updated

## Design system and UI

When touching UI, follow `lib/design_system/README.md` and Material 3 role-based theming.
