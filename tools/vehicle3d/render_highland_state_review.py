import bpy
import math
from pathlib import Path
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
OUT_FRONT = ROOT / "design-previews/vehicle3d/model3-highland-state-review-v5-front.png"
OUT_REAR = ROOT / "design-previews/vehicle3d/model3-highland-state-review-v5-rear.png"


def rotate(name, axis, degrees):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Missing state pivot: {name}")
    obj.rotation_mode = "XYZ"
    obj.rotation_euler[axis] = math.radians(degrees)


# Use deliberately asymmetric poses so each hinge direction and pivot can be
# inspected independently in one review frame.
rotate("door_left_front_pivot", 1, 54)
rotate("door_right_rear_pivot", 1, -48)
rotate("frunk_pivot", 0, 34)
rotate("trunk_pivot", 0, -43)
rotate("charge_port_pivot", 1, 58)
rotate("mirror_left_pivot", 2, 56)
rotate("mirror_right_pivot", 2, -56)

bpy.ops.object.camera_add(location=(-3.9, 5.4, 2.8))
camera = bpy.context.object
camera.rotation_euler = ((Vector((0, 0, 0.05)) - camera.location).to_track_quat("-Z", "Y").to_euler())
camera.data.type = "ORTHO"
camera.data.ortho_scale = 5.9
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
scene.render.filepath = str(OUT_FRONT)
scene.render.film_transparent = True
bpy.ops.render.render(write_still=True)

camera.location = (3.9, -5.4, 2.8)
camera.rotation_euler = ((Vector((0, 0, 0.05)) - camera.location).to_track_quat("-Z", "Y").to_euler())
scene.render.filepath = str(OUT_REAR)
bpy.ops.render.render(write_still=True)
print(f"State reviews written to {OUT_FRONT} and {OUT_REAR}")
