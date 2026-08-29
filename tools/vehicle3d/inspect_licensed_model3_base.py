import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
COMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged.glb"
UNCOMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged-uncompressed.glb"
SOURCE = UNCOMPRESSED_SOURCE if UNCOMPRESSED_SOURCE.exists() else COMPRESSED_SOURCE
OUTPUT = ROOT / "design-previews/vehicle3d/model3-licensed-base-front.png"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))

# The source includes a helper cube that is unrelated to the vehicle.
helper = bpy.data.objects.get("Cube")
if helper:
    bpy.data.objects.remove(helper, do_unlink=True)

# Neutral clay override for geometry inspection; original materials remain in
# the source GLB and will be rebuilt during the Highland conversion.
clay = bpy.data.materials.new("InspectionClay")
clay.diffuse_color = (0.62, 0.64, 0.68, 1)
clay.metallic = 0.15
clay.roughness = 0.3
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.data.materials.clear()
        obj.data.materials.append(clay)

world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.008, 0.011, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.18

for location, energy, size in [((-360, -260, 520), 1350, 420), ((310, 190, 360), 950, 300)]:
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = ((Vector((0, 0, 0)) - light.location).to_track_quat("-Z", "Y").to_euler())

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
scene.render.filepath = str(OUTPUT)
scene.render.film_transparent = True
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)
