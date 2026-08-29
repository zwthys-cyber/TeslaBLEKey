# Model 3 Highland production workflow

This directory contains reproducible Blender scripts for the Xiaote vehicle
visualization. Generated `.blend` files and uncompressed GLBs are intentionally
excluded from Git because each iteration is large.

## Legal base asset

The geometry base is `design-previews/vehicle3d/community-base/model3-realistic-rigged.glb`.
It is the modified CC BY 4.0 asset documented in the adjacent `CREDITS.md`.
Keep that attribution in the app and distribution materials.

Tesla's public `custom-wraps` template is retained only as a visual/UV reference.
It does not contain Tesla's proprietary production GLB.

## Build on macOS

Install Blender, then run from the repository root:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background \
  --python tools/vehicle3d/build_highland_from_licensed_base.py
```

Official Blender builds include Draco support and can read the committed
compressed GLB directly. If a Blender installation lacks Draco support, create
the ignored intermediate first:

```bash
npx --yes @gltf-transform/cli copy \
  design-previews/vehicle3d/community-base/model3-realistic-rigged.glb \
  design-previews/vehicle3d/community-base/model3-realistic-rigged-uncompressed.glb
```

The current script writes an editable production `.blend`, an uncompressed GLB,
and front/rear review renders. These outputs are production intermediates, not
yet the final App Store runtime asset.

Audit the rebuilt source before editing or runtime export:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background design-previews/vehicle3d/model3-highland-production-v5.blend \
  --python tools/vehicle3d/audit_highland_asset.py
```

The audit records scene scale, bounds, geometry budget, materials, negative
transforms and discoverable movable parts in
`design-previews/vehicle3d/model3-highland-audit-v5.json`. Treat missing active
parts or named pivots as a release blocker; geometry names must remain stable
through USDZ conversion so the iOS state renderer can address them directly.

Export the audited source as an experimental USDZ, then validate the archive
with Apple's USD tools:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background design-previews/vehicle3d/model3-highland-production-v5.blend \
  --python tools/vehicle3d/export_highland_runtime.py

usdchecker design-previews/vehicle3d/model3-highland-runtime-v5.usdz
```

The exporter refuses to run if any movable pivot is missing. It strips the
hidden legacy conversion geometry and caps embedded textures at 1024 px. The
v5 USDZ is still an experimental compatibility artifact; do not bundle it in
the iOS target until geometry, appearance and device performance gates pass.

Render an asymmetric state pose to inspect every animation axis before iOS
integration:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background design-previews/vehicle3d/model3-highland-production-v5.blend \
  --python tools/vehicle3d/render_highland_state_review.py
```

The resulting front/rear `model3-highland-state-review-v5-*.png` files are
diagnostic renders, not marketing artwork. Any detached panel, incorrect hinge
direction or intersection must be fixed in the production hierarchy before app
integration.
