# Motion Choreography Guide (Material 3 Expressive)

## Durations
- Fast: 150ms
- Standard: 250ms
- Emphasized: 380ms

## Easing
- Enter/expand: `easeOutCubic`
- Exit/collapse: `easeInOut`

## Patterns
1. **Page section switch**
   - Use `AnimatedSwitcher` with emphasized in / standard out.
2. **Action feedback**
   - Snackbar for success/error states.
3. **Form details reveal**
   - Use `ExpansionTile` for optional fields (progressive disclosure).
4. **List interactions**
   - Keep interaction immediate; avoid long decorative animations.

## Accessibility notes
- Animation should clarify state, not block task completion.
- Avoid chained transitions for core financial actions (save/delete/edit).
