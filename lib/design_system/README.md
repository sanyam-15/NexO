# Nexo Design System (Material 3 Expressive)

Base principles aligned to Material 3 Expressive for Flutter.

## 1) Expressive hierarchy (not flat UI)
- Prioritize one focal action per screen.
- Use strong title contrast + clear section grouping.
- Prefer meaningful iconography and shape rhythm to guide attention.

## 2) Color roles over hardcoded colors
- Use `Theme.of(context).colorScheme` roles.
- Prefer `surfaceContainer*` for layered surfaces.
- Use `primary/secondary/tertiary` for emphasis hierarchy.

## 3) Components first (no ad-hoc widgets)
- Layout shell: `DsScreenScaffold`
- Header: `DsFeatureHeader`
- Section container: `DsSectionCard`
- Lists: `DsListTile`
- States: `DsEmptyState`
- Metrics: `DsStatCard`
- Actions: `DsPrimaryButton`, `FilledButton`, `SegmentedButton`, chips

## 4) Consistent tokens
- Spacing: `tokens/ds_spacing.dart`
- Radius: `tokens/ds_radius.dart`
- Motion: `tokens/ds_motion.dart`
- Typography: `tokens/ds_typography.dart`

## 5) Motion
- Fast: 150ms
- Standard: 250ms
- Emphasized: 380ms
- Use motion to clarify state change, never as decoration only.
- Detailed choreography: `lib/design_system/MOTION.md`

## 6) Accessibility guardrails
- Keep high contrast using M3 on-colors.
- Minimum tap target and semantic labels.
- Keep typography legible in both dark/light and dense layouts.

## 7) Dynamic color
- Enabled via `dynamic_color` package.
- App falls back to seeded `ColorScheme.fromSeed` when dynamic color is unavailable.
