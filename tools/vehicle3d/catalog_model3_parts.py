import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
COMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged.glb"
UNCOMPRESSED_SOURCE = ROOT / "design-previews/vehicle3d/community-base/model3-realistic-rigged-uncompressed.glb"
SOURCE = UNCOMPRESSED_SOURCE if UNCOMPRESSED_SOURCE.exists() else COMPRESSED_SOURCE
OUTPUT = ROOT / "design-previews/vehicle3d/community-base/parts-catalog.tsv"

bpy.ops.import_scene.gltf(filepath=str(SOURCE))

rows = ["object\tparent\tmaterials\tcenter_x\tcenter_y\tcenter_z\tsize_x\tsize_y\tsize_z\tvertices"]
for obj in bpy.context.scene.objects:
    if obj.type != "MESH" or obj.name == "Cube":
        continue
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[i] for point in corners) for i in range(3)))
    maximum = Vector(tuple(max(point[i] for point in corners) for i in range(3)))
    center = (minimum + maximum) / 2
    size = maximum - minimum
    materials = ",".join(material.name for material in obj.data.materials)
    rows.append(
        f"{obj.name}\t{obj.parent.name if obj.parent else ''}\t{materials}\t"
        f"{center.x:.3f}\t{center.y:.3f}\t{center.z:.3f}\t"
        f"{size.x:.3f}\t{size.y:.3f}\t{size.z:.3f}\t{len(obj.data.vertices)}"
    )

OUTPUT.write_text("\n".join(rows) + "\n", encoding="utf-8")
print(f"Wrote {len(rows) - 1} mesh records to {OUTPUT}")
