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
