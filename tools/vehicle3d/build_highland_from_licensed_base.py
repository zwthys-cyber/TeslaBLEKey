import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
COMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged.glb"
UNCOMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged-uncompressed.glb"
SOURCE = UNCOMPRESSED_SOURCE if UNCOMPRESSED_SOURCE.exists() else COMPRESSED_SOURCE
OUT = ROOT / "design-previews/vehicle3d"


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

# Save an editable production source before runtime optimization.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "model3-highland-production-v5.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "model3-highland-runtime-uncompressed-v5.glb"),
    export_format="GLB",
    export_apply=True,
)

# Neutral workbench preview makes surface quality readable without relying on
# the headless machine's GPU material implementation.
bpy.ops.object.camera_add(location=(-410, 560, 265))
camera = bpy.context.object
camera.rotation_euler = ((Vector((0, 0, 5)) - camera.location).to_track_quat("-Z", "Y").to_euler())
camera.data.type = "ORTHO"
camera.data.ortho_scale = 650
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

camera.location = (410, -560, 285)
camera.rotation_euler = ((Vector((0, 0, 5)) - camera.location).to_track_quat("-Z", "Y").to_euler())
scene.render.filepath = str(OUT / "model3-highland-conversion-v5-rear.png")
bpy.ops.render.render(write_still=True)
