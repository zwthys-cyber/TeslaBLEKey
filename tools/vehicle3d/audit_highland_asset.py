import bpy
import json
from pathlib import Path
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = ROOT / "design-previews/vehicle3d/model3-highland-production-v5.blend"
REPORT = ROOT / "design-previews/vehicle3d/model3-highland-audit-v5.json"

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


def world_bounds(objects):
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector((min(point.x for point in corners), min(point.y for point in corners), min(point.z for point in corners)))
    maximum = Vector((max(point.x for point in corners), max(point.y for point in corners), max(point.z for point in corners)))
    return {
        "min": [round(value, 4) for value in minimum],
        "max": [round(value, 4) for value in maximum],
        "size": [round(value, 4) for value in maximum - minimum],
    }


def mesh_issues(obj):
    mesh = obj.data
    mesh.validate(verbose=False, clean_customdata=False)
    mesh.calc_loop_triangles()
    negative_scale = obj.matrix_world.to_3x3().determinant() < 0
    loose_vertices = sum(1 for vertex in mesh.vertices if not vertex.link_edges) if hasattr(mesh.vertices[0] if mesh.vertices else None, "link_edges") else 0
    return {
        "name": obj.name,
        "parent": obj.parent.name if obj.parent else None,
        "vertices": len(mesh.vertices),
        "triangles": len(mesh.loop_triangles),
        "materials": [slot.material.name for slot in obj.material_slots if slot.material],
        "hidden": bool(obj.hide_render or obj.hide_viewport),
        "negative_world_scale": negative_scale,
        "loose_vertices": loose_vertices,
    }


all_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
meshes = [obj for obj in all_meshes if not obj.hide_render and not obj.hide_viewport]
hidden_meshes = [obj for obj in all_meshes if obj not in meshes]
empties = [obj for obj in bpy.context.scene.objects if obj.type == "EMPTY"]
mesh_details = [mesh_issues(obj) for obj in meshes]
active_parts = {
    name: {
        "present": (obj := bpy.data.objects.get(name)) is not None,
        "children": len(obj.children) if obj else 0,
        "parent": obj.parent.name if obj and obj.parent else None,
    }
    for name in REQUIRED_PIVOTS
}

report = {
    "source": str(bpy.data.filepath or DEFAULT_SOURCE),
    "blender_version": bpy.app.version_string,
    "scene_units": {
        "system": bpy.context.scene.unit_settings.system,
        "scale_length": bpy.context.scene.unit_settings.scale_length,
    },
    "bounds": world_bounds(meshes),
    "object_counts": {
        "total": len(bpy.context.scene.objects),
        "meshes": len(meshes),
        "hidden_meshes": len(hidden_meshes),
        "empties": len(empties),
        "materials": len(bpy.data.materials),
        "images": len(bpy.data.images),
    },
    "geometry": {
        "vertices": sum(item["vertices"] for item in mesh_details),
        "triangles": sum(item["triangles"] for item in mesh_details),
        "negative_scale_objects": [item["name"] for item in mesh_details if item["negative_world_scale"]],
    },
    "active_parts": active_parts,
    "missing_active_parts": [name for name, details in active_parts.items() if not details["present"] or details["children"] == 0],
    "named_pivots": sorted(obj.name for obj in empties if obj.name in REQUIRED_PIVOTS),
    "meshes": mesh_details,
}

REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: report[key] for key in ("bounds", "object_counts", "geometry", "missing_active_parts", "named_pivots")}, indent=2))
print(f"Audit report written to {REPORT}")
