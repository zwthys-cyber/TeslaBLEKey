import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "design-previews" / "vehicle3d"
OUT.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def material(name, color, metallic=0.0, roughness=0.35):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def parent_keep_world(obj, parent):
    """Attach to an unrotated animation pivot with deterministic local space."""
    world_location = obj.location.copy()
    obj.parent = parent
    obj.location = world_location - parent.location


def rounded_cube(name, location, scale, mat, bevel=0.12, rotation=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel_mod = obj.modifiers.new("SurfaceRadius", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 4
    obj.data.materials.append(mat)
    if parent:
        parent_keep_world(obj, parent)
    return obj


def uv_part(name, location, scale, mat, parent=None, segments=64, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if parent:
        parent_keep_world(obj, parent)
    return obj


def empty(name, location):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


def loft(name, sections, mat, parent=None, subdivision=2):
    """Build a closed longitudinal surface from ordered Y/Z cross sections."""
    vertices = []
    ring_size = len(sections[0][1])
    for x, ring in sections:
        vertices.extend((x, y, z) for y, z in ring)
    faces = []
    for section_index in range(len(sections) - 1):
        start = section_index * ring_size
        next_start = (section_index + 1) * ring_size
        for point_index in range(ring_size):
            nxt = (point_index + 1) % ring_size
            faces.append((start + point_index, start + nxt, next_start + nxt, next_start + point_index))
    faces.append(tuple(reversed(range(ring_size))))
    last = (len(sections) - 1) * ring_size
    faces.append(tuple(last + i for i in range(ring_size)))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if subdivision:
        modifier = obj.modifiers.new("ProductionSurface", "SUBSURF")
        modifier.levels = subdivision
        modifier.render_levels = subdivision
    if parent:
        parent_keep_world(obj, parent)
    return obj


def body_ring(width, top, shoulder, lower, bottom):
    return [
        (0.0, top),
        (width * 0.66, top - 0.055),
        (width, shoulder),
        (width, lower),
        (width * 0.70, bottom),
        (0.0, bottom - 0.035),
        (-width * 0.70, bottom),
        (-width, lower),
        (-width, shoulder),
        (-width * 0.66, top - 0.055),
    ]


def panel(name, points, mat, parent, bevel=0.018):
    # Authored in vehicle space; store in hinge-local space so the closed pose
    # remains aligned and later animation rotates around the intended pivot.
    local_points = [tuple(Vector(point) - parent.location) for point in points]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(local_points, [], [tuple(range(len(local_points)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    solidify = obj.modifiers.new("PanelThickness", "SOLIDIFY")
    solidify.thickness = 0.006
    bevel_mod = obj.modifiers.new("PanelEdge", "BEVEL")
    bevel_mod.width = bevel
    bevel_mod.segments = 3
    obj.parent = parent
    return obj


def wheel(name, x, y, tire, rim):
    pivot = empty(name, (x, y, 0.45))
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.39, depth=0.24, location=(x, y, 0.45), rotation=(math.pi / 2, 0, 0))
    tyre = bpy.context.object
    tyre.name = f"{name}_tire"
    tyre.data.materials.append(tire)
    parent_keep_world(tyre, pivot)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.275, depth=0.248, location=(x, y, 0.45), rotation=(math.pi / 2, 0, 0))
    hub = bpy.context.object
    hub.name = f"{name}_rim"
    hub.data.materials.append(rim)
    parent_keep_world(hub, pivot)
    return pivot


def build_vehicle():
    white = material("Paint_PearlWhite", (0.82, 0.84, 0.88), metallic=0.18, roughness=0.22)
    glass = material("Glass_Dark", (0.012, 0.018, 0.025), metallic=0.05, roughness=0.12)
    black = material("Trim_Black", (0.008, 0.009, 0.012), metallic=0.3, roughness=0.25)
    tire = material("Rubber", (0.006, 0.006, 0.007), roughness=0.7)
    rim = material("Wheel_Dark", (0.025, 0.027, 0.032), metallic=0.75, roughness=0.2)
    lamp = material("Lamp_Clear", (0.15, 0.18, 0.22), metallic=0.2, roughness=0.08)
    red = material("TailLamp_Red", (0.42, 0.005, 0.008), metallic=0.05, roughness=0.16)

    root = empty("vehicle_root", (0, 0, 0))
    body_profiles = [
        (-2.38, 0.30, 0.66, 0.59, 0.37, 0.25),
        (-2.20, 0.69, 0.76, 0.66, 0.35, 0.22),
        (-1.78, 0.87, 0.88, 0.73, 0.34, 0.20),
        (-1.28, 0.93, 0.99, 0.80, 0.34, 0.20),
        (-0.55, 0.95, 1.05, 0.85, 0.34, 0.20),
        (0.45, 0.94, 1.04, 0.85, 0.34, 0.20),
        (1.30, 0.91, 1.01, 0.82, 0.35, 0.21),
        (1.90, 0.82, 0.91, 0.74, 0.36, 0.23),
        (2.27, 0.57, 0.79, 0.65, 0.38, 0.27),
        (2.39, 0.25, 0.67, 0.58, 0.40, 0.31),
    ]
    body_sections = [(x, body_ring(width, top, shoulder, lower, bottom)) for x, width, top, shoulder, lower, bottom in body_profiles]
    loft("body_shell", body_sections, white, root, subdivision=2)

    cabin_profiles = [
        (-1.03, 0.49, 1.07, 0.98),
        (-0.72, 0.68, 1.28, 0.99),
        (-0.14, 0.75, 1.43, 1.00),
        (0.54, 0.73, 1.42, 1.00),
        (1.05, 0.64, 1.29, 0.98),
        (1.43, 0.39, 1.08, 0.94),
    ]
    cabin_sections = []
    for x, width, top, base in cabin_profiles:
        cabin_sections.append((x, [
            (0, top), (width * 0.72, top - 0.07), (width, base + 0.13),
            (width * 0.96, base), (-width * 0.96, base),
            (-width, base + 0.13), (-width * 0.72, top - 0.07),
        ]))
    loft("glasshouse", cabin_sections, glass, root, subdivision=2)
    rounded_cube("front_bumper_lower", (-2.20, 0, 0.42), (0.18, 0.62, 0.09), black, 0.07, parent=root)

    # Animation-ready pivots. Geometry remains independent even in the blockout.
    hood_pivot = empty("frunk_pivot", (-0.60, 0, 1.02)); hood_pivot.parent = root
    panel("frunk_panel", [(-1.92, -0.61, 0.795), (-1.92, 0.61, 0.795), (-0.67, 0.72, 0.965), (-0.67, -0.72, 0.965)], white, hood_pivot, 0.012)
    trunk_pivot = empty("trunk_pivot", (1.22, 0, 1.22)); trunk_pivot.parent = root
    panel("trunk_panel", [(1.26, -0.66, 0.955), (1.26, 0.66, 0.955), (1.98, 0.55, 0.815), (1.98, -0.55, 0.815)], white, trunk_pivot, 0.012)

    door_specs = [
        ("door_left_front_pivot", "door_left_front", -1.02, 0.956, -0.96, 0.05),
        ("door_left_rear_pivot", "door_left_rear", 0.04, 0.951, 0.10, 1.07),
        ("door_right_front_pivot", "door_right_front", -1.02, -0.956, -0.96, 0.05),
        ("door_right_rear_pivot", "door_right_rear", 0.04, -0.951, 0.10, 1.07),
    ]
    for pivot_name, panel_name, x0, y, panel_x0, panel_x1 in door_specs:
        pivot = empty(pivot_name, (x0, y, 0.82)); pivot.parent = root
        side = 1 if y > 0 else -1
        panel(panel_name, [
            (panel_x0, y - side * 0.075, 0.39), (panel_x1, y - side * 0.070, 0.39),
            (panel_x1, y + side * 0.002, 1.015), (panel_x0, y + side * 0.002, 1.01),
        ], white, pivot, 0.009)

    mirror_specs = [
        ("mirror_left_pivot", (-0.78, 1.00, 1.17)),
        ("mirror_right_pivot", (-0.78, -1.00, 1.17)),
    ]
    for name, loc in mirror_specs:
        pivot = empty(name, loc); pivot.parent = root
        rounded_cube(name.replace("_pivot", ""), loc, (0.17, 0.10, 0.055), black, 0.045, parent=pivot)

    charge_pivot = empty("charge_port_pivot", (1.66, -0.89, 1.00)); charge_pivot.parent = root
    rounded_cube("charge_port_door", (1.66, -0.91, 1.00), (0.15, 0.018, 0.12), white, 0.035, parent=charge_pivot)

    for name, x, y in [
        ("wheel_front_left", -1.42, 0.84), ("wheel_front_right", -1.42, -0.84),
        ("wheel_rear_left", 1.43, 0.84), ("wheel_rear_right", 1.43, -0.84),
    ]:
        pivot = wheel(name, x, y, tire, rim); pivot.parent = root

    for y in (-0.58, 0.58):
        uv_part(f"headlamp_{'left' if y > 0 else 'right'}", (-2.075, y, 0.745), (0.32, 0.115, 0.022), lamp, root)
        uv_part(f"taillamp_{'left' if y > 0 else 'right'}", (2.055, y, 0.735), (0.235, 0.105, 0.028), red, root)

    return root


def studio():
    world = bpy.context.scene.world
    world.color = (0.004, 0.004, 0.006)
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.003, 0.003, 0.005, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22

    bpy.ops.object.light_add(type="AREA", location=(-2.5, 3.0, 5.2))
    key = bpy.context.object; key.name = "studio_key"; key.data.energy = 950; key.data.shape = "DISK"; key.data.size = 4.5
    key.rotation_euler = (math.radians(24), 0, math.radians(218))
    bpy.ops.object.light_add(type="AREA", location=(3.4, -2.4, 3.6))
    rim = bpy.context.object; rim.name = "studio_rim"; rim.data.energy = 700; rim.data.size = 3.0
    rim.rotation_euler = (math.radians(50), 0, math.radians(40))

    bpy.ops.object.camera_add(location=(-5.8, 5.8, 3.4))
    camera = bpy.context.object
    camera.name = "vehicle_camera"
    direction = Vector((0.05, 0, 0.82)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 58
    bpy.context.scene.camera = camera


def export():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1536
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT / "model3-highland-surface-v5.png")
    scene.render.film_transparent = True
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "model3-highland-source-v5.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT / "model3-highland-runtime-v5.glb"), export_format="GLB", export_apply=True)
    bpy.ops.render.render(write_still=True)


clear_scene()
build_vehicle()
studio()
export()
