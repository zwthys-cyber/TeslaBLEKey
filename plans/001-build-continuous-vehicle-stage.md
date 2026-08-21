# 001 — Build a continuous vehicle stage

- **Status**: DONE
- **Commit**: d2a3b09
- **Severity**: HIGH
- **Category**: Physicality, cohesion, missed opportunities
- **Estimated scope**: 3 files, about 220 lines

## Problem

`TeslaBLEKey/Views/PairVehicleView.swift:51` and `TeslaBLEKey/Views/VehicleControlView.swift:67` render unrelated static SF Symbols. `TeslaBLEKey/Views/RootView.swift:10` swaps the complete screens with no spatial continuity:

```swift
if vehicle.isPaired { VehicleControlView() } else { PairVehicleView() }
```

Vehicle discovery, card confirmation, and connection therefore teleport between text states instead of feeling like one vehicle progressing through one secure flow.

## Target

Create `TeslaBLEKey/Views/Components/VehicleStage.swift`, a reusable, original SwiftUI vehicle silhouette built from `Shape`/`Path`, not `car.side.fill`. It must accept a semantic stage (`searching`, `found`, `awaitingCard`, `connecting`, `ready`, `executing`, `success`) and render all changes in the same fixed coordinate space. On-screen morph/movement uses `.spring(response: 0.36, dampingFraction: 1)`; entering/exiting supporting labels uses `.easeOut(duration: 0.22)`. Reduced Motion keeps opacity changes but removes position and scale changes.

Pairing and control screens must share `@Namespace`/`matchedGeometryEffect` identity for the stage when possible; otherwise use the same geometry and a 220ms opacity transition. The root transition must never slide a whole screen.

## Repo conventions to follow

- Theme tokens remain in `TeslaBLEKey/Design/AppTheme.swift`.
- All artwork stays pure monochrome and uses semantic white opacity.
- Existing accessibility labels remain and the stage is one combined accessibility element.

## Steps

1. Add `VehicleStage.swift` with a deterministic `VehicleSilhouette: Shape`, stage enum, fixed aspect ratio, and semantic state rendering.
2. Replace the hero in `PairVehicleView.swift`; map scanner and pairing phases to one stage and animate only stage, opacity, and transform.
3. Replace `vehicleSummary` in `VehicleControlView.swift` with the same component.
4. Give `RootView` an explicit `.opacity` transition for the rare paired/unpaired swap; do not animate the `NavigationStack` itself.
5. Branch all movement on `accessibilityReduceMotion`.

## Boundaries

- Do not change Bluetooth, cryptography, pairing, or command behavior.
- Do not add image assets or dependencies.
- Do not use Tesla trademarks or manufacturer logos.

## Verification

- **Mechanical**: run the existing iOS Release CI build.
- **Feel check**: discovery, card waiting, connecting, and ready must read as states of one vehicle; no whole-screen slide; at 10% playback there is no double-exposed car.
- **Done when**: no `car.side.fill` hero remains and Reduced Motion removes geometric movement.
