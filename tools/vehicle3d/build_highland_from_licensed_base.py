import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
COMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged.glb"
UNCOMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged-uncompressed.glb"
SOURCE = UNCOMPRESSED_SOURCE if UNCOMPRESSED_SOURCE.exists() else COMPRESSED_SOURCE
OUT = ROOT / "design-previews/vehicle3d"
TARGET_LENGTH_METERS = 4.72


def material(name, color, metallic=0.0, roughness=0.3):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def panel(name, points, mat, thickness=1.2, bevel=1.4):
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(points, [], [tuple(range(len(points)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    solidify = obj.modifiers.new("HighlandThickness", "SOLIDIFY")
    solidify.thickness = thickness
    edge = obj.modifiers.new("HighlandEdge", "BEVEL")
    edge.width = bevel
    edge.segments = 4
    return obj


def rounded_bar(name, location, scale, mat, bevel=3.0, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    edge = obj.modifiers.new("HighlandRadius", "BEVEL")
    edge.width = bevel
    edge.segments = 6
    return obj


def rename_required_node(source_name, runtime_name):
    obj = bpy.data.objects.get(source_name)
    if obj is None:
        raise RuntimeError(f"Required movable node is missing: {source_name}")
    obj.name = runtime_name
    return obj


def descendant_meshes(root):
    result = []
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        stack.extend(obj.children)
        if obj.type == "MESH":
            result.append(obj)
    return result


def insert_mirror_pivot(source_name, runtime_name):
    source = bpy.data.objects.get(source_name)
    if source is None or source.parent is None:
        raise RuntimeError(f"Required mirror hierarchy is missing: {source_name}")
    meshes = descendant_meshes(source)
    if not meshes:
        raise RuntimeError(f"Mirror hierarchy contains no mesh: {source_name}")
    corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    center = sum(corners, Vector()) / len(corners)
    # The fold axis sits at the inboard edge of each mirror housing.
    center.x = max(point.x for point in corners) if center.x < 0 else min(point.x for point in corners)
    parent = source.parent
    source_world = source.matrix_world.copy()
    pivot = bpy.data.objects.new(runtime_name, None)
    pivot.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(pivot)
    pivot.parent = parent
    pivot.matrix_world.translation = center
    source.parent = pivot
    source.matrix_world = source_world
    return pivot


def normalize_vehicle_scale(vehicle_objects):
    mesh_objects = []
    for root in vehicle_objects:
        if root.type == "MESH":
            mesh_objects.append(root)
        mesh_objects.extend(descendant_meshes(root))
    corners = [obj.matrix_world @ Vector(corner) for obj in mesh_objects for corner in obj.bound_box]
    source_length = max(point.y for point in corners) - min(point.y for point in corners)
    if source_length <= 0:
        raise RuntimeError("Vehicle source has an invalid longitudinal size")
    root = bpy.data.objects.new("xiaote_vehicle_root", None)
    root.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root)
    for obj in vehicle_objects:
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_world = world
    scale = TARGET_LENGTH_METERS / source_length
    root.scale = (scale, scale, scale)
    root["target_length_meters"] = TARGET_LENGTH_METERS
    root["source_length"] = source_length
    return root


bpy.ops.import_scene.gltf(filepath=str(SOURCE))
helper = bpy.data.objects.get("Cube")
if helper:
    bpy.data.objects.remove(helper, do_unlink=True)

paint = material("HighlandPearlWhite", (0.72, 0.74, 0.78), metallic=0.22, roughness=0.24)
glass = material("HighlandGlass", (0.012, 0.018, 0.026), metallic=0.05, roughness=0.12)
black = material("HighlandSatinBlack", (0.008, 0.009, 0.012), metallic=0.38, roughness=0.23)
lamp = material("HighlandLamp", (0.10, 0.13, 0.17), metallic=0.42, roughness=0.08)
red = material("HighlandTailLamp", (0.38, 0.003, 0.006), metallic=0.08, roughness=0.13)

# Rebuild material presentation for a predictable native-app render.
for obj in bpy.context.scene.objects:
    if obj.type != "MESH":
        continue
    names = " ".join(mat.name.lower() for mat in obj.data.materials)
    obj.data.materials.clear()
    if "glass" in names or "mirror_inside" in names:
        obj.data.materials.append(glass)
    elif "wheel" in names or "black" in names or "plastic" in names or "dvor" in names:
        obj.data.materials.append(black)
    elif "light" in names or "indicator" in names or "break" in names:
        corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        center_y = sum(corner.y for corner in corners) / len(corners)
        obj.data.materials.append(red if center_y < 0 else lamp)
    else:
        obj.data.materials.append(paint)

# Retire legacy front lamp/fog-light geometry while preserving the body shell.
for name in ["Object_78", "Object_81", "Object_410", "Object_413", "Object_416", "Object_419", "Object_422"]:
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True

# Reuse the production-quality lamp bowls and compress their vertical profile
# into Highland's narrower signature. This remains conformal to the fenders,
# unlike a floating overlay surface.
for name in ["Object_84", "Object_86", "Object_95", "Object_104", "Object_107"]:
    obj = bpy.data.objects.get(name)
    if obj:
        obj.scale.z *= 0.62

drl = material("HighlandDRL", (0.62, 0.70, 0.82), metallic=0.2, roughness=0.08)
rounded_bar("highland_drl_left", (-69, 231.0, -2.0), (25, 1.0, 0.85), drl, 0.8,
            rotation=(0, -0.055, 0))
rounded_bar("highland_drl_right", (69, 231.0, -2.0), (25, 1.0, 0.85), drl, 0.8,
            rotation=(0, 0.055, 0))

# A restrained lower intake replaces the older fog-light-heavy fascia.
rounded_bar("highland_lower_intake", (0, 263.0, -49.0), (66, 2.0, 4.2), black, 3.8)

# Preserve the licensed base's movable hierarchy while giving every runtime
# control a stable semantic name. These nodes are the public contract consumed
# by the future RealityKit/SceneKit state renderer.
for source_name, runtime_name in {
    "door_lf_dummy_184": "door_left_front_pivot",
    "door_lr_dummy_202": "door_left_rear_pivot",
    "door_rf_dummy_218": "door_right_front_pivot",
    "door_rr_dummy_235": "door_right_rear_pivot",
    "bonnet_dummy_279": "frunk_pivot",
    "boot_dummy_158": "trunk_pivot",
    "charge_dummy": "charge_port_pivot",
}.items():
    rename_required_node(source_name, runtime_name)

insert_mirror_pivot("door_lf_mirror_inside.0_0_197", "mirror_left_pivot")
insert_mirror_pivot("door_rf_mirror_inside.0_0_230", "mirror_right_pivot")

vehicle_top_level = [
    obj for obj in bpy.context.scene.objects
    if obj.parent is None and obj.type not in {"CAMERA", "LIGHT"}
]
normalize_vehicle_scale(vehicle_top_level)

# Save an editable production source before runtime optimization.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "model3-highland-production-v5.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "model3-highland-runtime-uncompressed-v5.glb"),
    export_format="GLB",
    export_apply=True,
    use_visible=True,
    use_renderable=True,
)

# Neutral workbench preview makes surface quality readable without relying on
# the headless machine's GPU material implementation.
bpy.ops.object.camera_add(location=(-3.67, 5.02, 2.37))
camera = bpy.context.object
camera.rotation_euler = ((Vector((0, 0, 0.05)) - camera.location).to_track_quat("-Z", "Y").to_euler())
camera.data.type = "ORTHO"
camera.data.ortho_scale = 5.82
bpy.context.scene.camera = camera

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1536
scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "model3-highland-conversion-v5-front.png")
scene.render.film_transparent = True
bpy.ops.render.render(write_still=True)

camera.location = (3.67, -5.02, 2.55)
camera.rotation_euler = ((Vector((0, 0, 0.05)) - camera.location).to_track_quat("-Z", "Y").to_euler())
scene.render.filepath = str(OUT / "model3-highland-conversion-v5-rear.png")
bpy.ops.render.render(write_still=True)
