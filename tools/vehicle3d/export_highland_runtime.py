import bpy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "design-previews/vehicle3d/model3-highland-runtime-v5.usdz"
REQUIRED_PIVOTS = [
    "door_left_front_pivot",
    "door_left_rear_pivot",
    "door_right_front_pivot",
    "door_right_rear_pivot",
    "frunk_pivot",
    "trunk_pivot",
    "charge_port_pivot",
    "mirror_left_pivot",
    "mirror_right_pivot",
]
TARGET_TRIANGLES = 240_000


def hierarchy_name(obj):
    names = []
    current = obj
    while current:
        names.append(current.name.lower())
        current = current.parent
    return " ".join(names)


def triangle_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def runtime_ratio(obj):
    names = hierarchy_name(obj)
    if any(token in names for token in ("light", "lamp", "indicator", "glass", "mirror")):
        return 0.58
    if any(token in names for token in ("wheel", "hub_", "suspensi")):
        return 0.28
    if any(token in names for token in ("seat", "leather", "carpet", "steer", "interior", "putih")):
        return 0.20
    if any(token in names for token in ("body", "primary", "door_", "bonnet", "boot", "bumper")):
        return 0.44
    return 0.34


def optimize_geometry():
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    before = sum(triangle_count(obj) for obj in meshes)
    for obj in meshes:
        triangles = triangle_count(obj)
        if triangles < 500:
            continue
        modifier = obj.modifiers.new("XiaoteRuntimeLOD", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = runtime_ratio(obj)
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    after = sum(triangle_count(obj) for obj in meshes)
    if after > TARGET_TRIANGLES:
        raise RuntimeError(f"Runtime geometry budget exceeded: {after} > {TARGET_TRIANGLES} triangles")
    print(f"Runtime geometry optimized from {before} to {after} triangles")


missing = [
    name for name in REQUIRED_PIVOTS
    if (node := bpy.data.objects.get(name)) is None or not node.children
]
if missing:
    raise RuntimeError(f"Runtime export blocked; missing movable nodes: {', '.join(missing)}")

# Hidden legacy conversion geometry is useful for source comparison but must not
# consume runtime memory or distort the USD stage bounds.
for obj in list(bpy.data.objects):
    if obj.hide_render or obj.hide_viewport:
        bpy.data.objects.remove(obj, do_unlink=True)

optimize_geometry()

bpy.ops.wm.usd_export(
    filepath=str(OUT),
    export_animation=False,
    export_materials=True,
    export_meshes=True,
    export_normals=True,
    export_uvmaps=True,
    export_cameras=False,
    export_lights=False,
    export_textures_mode="KEEP",
    generate_preview_surface=True,
    usdz_downscale_size="1024",
    convert_scene_units="METERS",
    meters_per_unit=1.0,
    root_prim_path="/XiaoteModel3Highland",
    xform_op_mode="TRS",
)

print(f"Runtime USDZ written to {OUT} ({OUT.stat().st_size} bytes)")
