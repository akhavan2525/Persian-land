"""Re-exports a static GLB with its textures scaled down to 1024 pixels.

    python shrink_textures.py <in.glb> <out.glb>
"""
import sys

import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=sys.argv[1])
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, int(1024 * img.size[1] / img.size[0]))
bpy.ops.export_scene.gltf(filepath=sys.argv[2], export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
print("exported", sys.argv[2])
