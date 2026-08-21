# 002 — Make every vehicle action causal

- **Status**: DONE
- **Commit**: d2a3b09
- **Severity**: HIGH
- **Category**: Feedback, easing, multimodal cohesion
- **Estimated scope**: 3 files, about 180 lines

## Problem

`TeslaBLEKey/Design/AppTheme.swift:14` applies one generic scale/opacity treatment to every control, while `TeslaBLEKey/Views/VehicleControlView.swift:78` reports all command progress in a remote caption. A pressed control has no local executing or success state.

```swift
.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
.opacity(configuration.isPressed ? 0.66 : 1)
```

## Target

Use two press styles: primary controls scale to `0.97`, quick controls to `0.98`; both respond within 140ms with critically damped motion and never drop content opacity below `0.82`. The selected action locally morphs icon → compact progress → checkmark. State crossfade is 200ms with optional 2px visual bridging only if SwiftUI supports it without offscreen performance cost. Completion haptic fires on the same state change as the checkmark, not merely on connection.

Add an identifiable action state to `VehicleController` without changing protocol calls: expose the executing action and a short-lived last-success action. Success presentation may last 700ms but must not block another action.

## Repo conventions to follow

- Async commands remain `Task { await action() }`.
- `VehicleController.Phase` remains the source of connection truth.
- Use `sensoryFeedback` and SF Symbols available on iOS 17.

## Steps

1. Add reusable `PrimaryPressStyle` and `UtilityPressStyle` to `AppTheme.swift` with Reduced Motion handling.
2. Add stable action identifiers and transient completion state to `VehicleController.swift`; clear completion asynchronously without delaying command return.
3. Replace `MainAction`/`QuickAction` labels with an interruptible `ActionGlyph` driven by idle/executing/success.
4. Fire impact feedback on press and success/error feedback on resolved result, synchronized with visual state.
5. Prevent repeat submission only for the action currently executing; do not globally make the interface look disabled.

## Boundaries

- Do not change Tesla command ordering or retry semantics.
- Do not add sound.
- Do not animate failure alerts.

## Verification

- **Mechanical**: protocol tests and physical-iPhone Release build pass.
- **Feel check**: rapid taps never restart a keyframe from zero; progress appears in the pressed control; completion feels immediate and local.
- **Done when**: no action relies only on the remote status caption for feedback.
