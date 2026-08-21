# 004 — Centralize the motion language

- **Status**: DONE
- **Commit**: d2a3b09
- **Severity**: MEDIUM
- **Category**: Cohesion, accessibility
- **Estimated scope**: 3 files, about 80 lines

## Problem

Motion values are typed directly in `AppTheme.swift:18`, `PairVehicleView.swift:31`, and `VehicleControlView.swift:83`. There is no named distinction between press, state, and rare page transitions.

## Target

Create `AppMotion` tokens in `AppTheme.swift`:

```swift
static let press = Animation.easeOut(duration: 0.14)
static let state = Animation.easeOut(duration: 0.22)
static let spatial = Animation.spring(response: 0.36, dampingFraction: 1)
```

High-frequency button feedback uses `press`; text/icon state replacement uses `state`; only vehicle geometry and the rare pairing completion use `spatial`. Reduced Motion substitutes `.easeOut(duration: 0.20)` opacity changes and removes transform movement.

## Repo conventions to follow

- Keep design tokens in `AppTheme.swift`.
- Avoid indefinite animations.
- Animate transform and opacity, not layout dimensions.

## Steps

1. Add named `AppMotion` tokens and document intended frequency.
2. Replace all inline animation declarations in pairing/control views.
3. Audit every `withAnimation`, `.animation`, `.transition`, and `.symbolEffect` for an explicit purpose.
4. Ensure Reduce Motion branches retain state feedback without scale/position movement.

## Boundaries

- Do not animate scroll position, padding, frame dimensions, or background blur.
- Do not introduce bouncy springs.

## Verification

- **Mechanical**: `rg` finds no unexplained inline duration/spring values outside `AppMotion`; CI passes.
- **Feel check**: controls respond fastest, state follows next, spatial transition is slowest; nothing overshoots.
- **Done when**: motion has one consistent, named vocabulary.
