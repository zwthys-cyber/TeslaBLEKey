# 003 — Recompose the control surface

- **Status**: DONE
- **Commit**: d2a3b09
- **Severity**: MEDIUM
- **Category**: Purpose, hierarchy, spatial mapping
- **Estimated scope**: 1 file, about 180 lines

## Problem

`TeslaBLEKey/Views/VehicleControlView.swift:87-112` presents two large lock buttons followed by six equal grid tiles. Frequency and safety are not expressed; reconnect has the same visual weight as vehicle commands.

## Target

Make the vehicle stage the top half of the screen. Place lock/unlock as one stateful primary control immediately below it. Place frunk, trunk, drive, flash, and horn in a horizontal, compact utility rail with 52pt minimum hit targets. Move reconnect into connection status/menu. Remote drive must remain visually distinct and require a native confirmation dialog because it has real-world safety impact.

No decorative looping animation. Utility rail entrance may stagger once at 40ms intervals, maximum 220ms per item, and never block interaction. Skip stagger after first appearance using `@SceneStorage`.

## Repo conventions to follow

- Pure black background and white semantic hierarchy.
- Native SwiftUI controls, Dynamic Type, and VoiceOver labels.
- Existing menu retains remove/disconnect operations.

## Steps

1. Replace the two-button lock row with one wide state-aware primary lock control.
2. Replace the 2×3 grid with a horizontally scrolling or adaptive compact utility rail.
3. Remove reconnect from the utility commands and make the status capsule/button actionable.
4. Add native confirmation for drive authorization.
5. Verify 44pt minimum touch targets, Dynamic Type wrapping, and safe-area spacing.

## Boundaries

- Do not hide any existing vehicle command.
- Do not add tabs or extra navigation levels.
- Do not infer the physical lock state; label the command honestly if no state is available.

## Verification

- **Mechanical**: iPhone Release build passes.
- **Feel check**: one-handed use makes lock/unlock obvious; reconnect no longer competes with car commands; first entrance is subtle and subsequent visits are instant.
- **Done when**: the screen no longer reads as six equal settings tiles.
