"""Prepare the licensed Highland source asset for the Xiaote iOS runtime."""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "imported-highland" / "Tesla.blend"
OUTPUT_BLEND = ROOT / "imported-highland" / "Tesla-Highland-runtime.blend"
OUTPUT_USD = ROOT / "imported-highland" / "Model3Highland.usdc"


def select_only(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def separate_loose(obj: bpy.types.Object) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [obj, *sorted(set(bpy.data.objects) - before, key=lambda item: item.name)]


def separate_faces(obj: bpy.types.Object, name: str, predicate) -> bpy.types.Object:
    select_only(obj)
    for polygon in obj.data.polygons:
        polygon.select = bool(predicate(polygon.center))
    selected = sum(1 for polygon in obj.data.polygons if polygon.select)
    if selected == 0:
        raise RuntimeError(f"No faces selected for {name}")
    before = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    created = list(set(bpy.data.objects) - before)
    if len(created) != 1:
        raise RuntimeError(f"Unexpected split result for {name}: {len(created)} objects")
    created[0].name = name
    return created[0]


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in corners), min(p.y for p in corners), min(p.z for p in corners))),
        Vector((max(p.x for p in corners), max(p.y for p in corners), max(p.z for p in corners))),
    )


def local_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [Vector(corner) for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in corners), min(p.y for p in corners), min(p.z for p in corners))),
        Vector((max(p.x for p in corners), max(p.y for p in corners), max(p.z for p in corners))),
    )


def classify_body_part(obj: bpy.types.Object) -> str | None:
    low, high = local_bounds(obj)
    center = (low + high) * 0.5
    width = high.x - low.x
    length = high.z - low.z
    if center.y > 0.72 and width > 1.2 and center.z > 1.35:
        return "frunk_panel"
    if center.x > 0.75 and -0.05 < center.z < 0.75 and length > 0.8:
        return "door_left_front"
    if center.x < -0.75 and -0.05 < center.z < 0.75 and length > 0.8:
        return "door_right_front"
    if center.x > 0.72 and center.z < -0.45 and length > 0.75:
        return "door_left_rear"
    if center.x < -0.72 and center.z < -0.45 and length > 0.75:
        return "door_right_rear"
    if center.x > 0.88 and center.y > 0.9 and 0.45 < center.z < 0.85:
        return "mirror_left"
    if center.x < -0.88 and center.y > 0.9 and 0.45 < center.z < 0.85:
        return "mirror_right"
    return None


def classify_window_part(obj: bpy.types.Object) -> str | None:
    low, high = local_bounds(obj)
    center = (low + high) * 0.5
    length = high.z - low.z
    if center.x > 0.62 and -0.05 < center.z < 0.5 and length > 0.7:
        return "door_left_front_glass"
    if center.x < -0.62 and -0.05 < center.z < 0.5 and length > 0.7:
        return "door_right_front_glass"
    if center.x > 0.62 and -1.1 < center.z < -0.45 and length > 0.55:
        return "door_left_rear_glass"
    if center.x < -0.62 and -1.1 < center.z < -0.45 and length > 0.55:
        return "door_right_rear_glass"
    return None


def make_pivot(
    name: str,
    location: Vector,
    reference: bpy.types.Object,
) -> bpy.types.Object:
    pivot = bpy.data.objects.new(name, None)
    pivot.empty_display_type = "PLAIN_AXES"
    pivot.empty_display_size = 0.12
    bpy.context.collection.objects.link(pivot)
    pivot.matrix_world = Matrix.LocRotScale(
        location,
        reference.matrix_world.to_quaternion(),
        Vector((1.0, 1.0, 1.0)),
    )
    return pivot


def parent_keep_world(obj: bpy.types.Object, parent: bpy.types.Object) -> None:
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def decimate(obj: bpy.types.Object, target_faces: int) -> None:
    if obj.type != "MESH" or len(obj.data.polygons) <= target_faces:
        return
    modifier = obj.modifiers.new(name="Xiaote mobile optimization", type="DECIMATE")
    modifier.ratio = max(0.01, target_faces / len(obj.data.polygons))
    modifier.use_collapse_triangulate = True
    select_only(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def build() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

    for obj in list(bpy.context.scene.objects):
        if obj.type in {"LIGHT", "CAMERA"} or obj.name.startswith("Plane"):
            bpy.data.objects.remove(obj, do_unlink=True)

    body_parts = separate_loose(bpy.data.objects["body"])
    main_shell = max(body_parts, key=lambda item: len(item.data.polygons))
    trunk = separate_faces(
        main_shell,
        "trunk_panel",
        lambda center: center.z < -1.48 and center.y > 0.78 and abs(center.x) < 0.76,
    )
    charge_port = separate_faces(
        main_shell,
        "charge_port_panel",
        lambda center: center.x > 0.74 and -2.03 < center.z < -1.62 and 0.66 < center.y < 1.02,
    )
    named: dict[str, bpy.types.Object] = {}
    for part in body_parts:
        role = classify_body_part(part)
        if role:
            part.name = role
            named[role] = part

    window_parts = separate_loose(bpy.data.objects["windows"])
    for part in window_parts:
        role = classify_window_part(part)
        if role:
            part.name = role
            named[role] = part

    door_specs = {
        "left_front": ("door_left_front", "door_left_front_glass"),
        "right_front": ("door_right_front", "door_right_front_glass"),
        "left_rear": ("door_left_rear", "door_left_rear_glass"),
        "right_rear": ("door_right_rear", "door_right_rear_glass"),
    }
    for key, children in door_specs.items():
        panel = named.get(children[0])
        if panel is None:
            raise RuntimeError(f"Missing required panel: {children[0]}")
        low, high = local_bounds(panel)
        hinge_x = high.x if "left" in key else low.x
        hinge = panel.matrix_world @ Vector((hinge_x, low.y, high.z - 0.04))
        pivot = make_pivot(f"door_{key}_pivot", hinge, panel)
        for child_name in children:
            child = named.get(child_name)
            if child:
                parent_keep_world(child, pivot)

    hood = named.get("frunk_panel")
    if hood is None:
        raise RuntimeError("Missing Highland frunk panel")
    hood_low, _ = local_bounds(hood)
    hood_hinge = hood.matrix_world @ Vector((0.0, hood_low.y, hood_low.z + 0.03))
    hood_pivot = make_pivot("frunk_pivot", hood_hinge, hood)
    parent_keep_world(hood, hood_pivot)

    trunk_low, trunk_high = local_bounds(trunk)
    trunk_hinge = trunk.matrix_world @ Vector((0.0, trunk_low.y, trunk_high.z - 0.02))
    trunk_pivot = make_pivot("trunk_pivot", trunk_hinge, trunk)
    parent_keep_world(trunk, trunk_pivot)

    port_low, port_high = local_bounds(charge_port)
    port_hinge = charge_port.matrix_world @ Vector((port_low.x, port_low.y, port_high.z - 0.01))
    port_pivot = make_pivot("charge_port_pivot", port_hinge, charge_port)
    parent_keep_world(charge_port, port_pivot)

    for mirror_name, pivot_name in (
        ("mirror_left", "mirror_left_pivot"),
        ("mirror_right", "mirror_right_pivot"),
    ):
        mirror = named.get(mirror_name)
        if mirror:
            low, high = local_bounds(mirror)
            x = low.x if "left" in mirror_name else high.x
            hinge = mirror.matrix_world @ Vector(
                (x, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5)
            )
            pivot = make_pivot(
                pivot_name,
                hinge,
                mirror,
            )
            parent_keep_world(mirror, pivot)

    decimate(bpy.data.objects["wheels"], 85000)
    decimate(bpy.data.objects["int_body"], 42000)
    decimate(bpy.data.objects["int_leather"], 8000)

    root = bpy.data.objects.get("Tesla")
    if root:
        root.name = "xiaote_highland_root"

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    bpy.ops.wm.usd_export(
        filepath=str(OUTPUT_USD),
        selected_objects_only=False,
        export_animation=False,
        export_materials=True,
        export_textures_mode="NEW",
        relative_paths=True,
        evaluation_mode="RENDER",
    )
    total_faces = sum(len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type == "MESH")
    print(f"XIAOTE_RUNTIME_READY faces={total_faces} usd={OUTPUT_USD}")


if __name__ == "__main__":
    build()
