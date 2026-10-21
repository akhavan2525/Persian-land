"""Shrinks every texture in a GLB to at most MAX pixels (JPEG), without Blender.

    python shrink_glb.py <in.glb> <out.glb> [max_px]
"""
import io
import json
import struct
import sys

from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
MAX = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
raw = open(src, "rb").read()
jlen = struct.unpack_from("<I", raw, 12)[0]
gltf = json.loads(raw[20:20 + jlen])
blen = struct.unpack_from("<I", raw, 20 + jlen)[0]
bin_ = raw[28 + jlen:28 + jlen + blen]
views = gltf["bufferViews"]
image_views = {img["bufferView"] for img in gltf.get("images", []) if "bufferView" in img}
chunks = []
for i, v in enumerate(views):
    data = bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    if i in image_views:
        im = Image.open(io.BytesIO(data))
        has_alpha = im.mode in ("RGBA", "LA")
        if max(im.size) > MAX:
            k = MAX / max(im.size)
            im = im.resize((round(im.size[0] * k), round(im.size[1] * k)), Image.LANCZOS)
        out = io.BytesIO()
        if has_alpha:
            im.save(out, "PNG", optimize=True)
        else:
            im.convert("RGB").save(out, "JPEG", quality=88)
        data = out.getvalue()
        for img in gltf["images"]:
            if img.get("bufferView") == i:
                img["mimeType"] = "image/png" if has_alpha else "image/jpeg"
    chunks.append(data)
new_bin = b""
for v, data in zip(views, chunks):
    while len(new_bin) % 4:
        new_bin += b"\0"
    v["byteOffset"] = len(new_bin)
    v["byteLength"] = len(data)
    new_bin += data
while len(new_bin) % 4:
    new_bin += b"\0"
gltf["buffers"] = [{"byteLength": len(new_bin)}]
js = json.dumps(gltf, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
total = 12 + 8 + len(js) + 8 + len(new_bin)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", 0x46546C67, 2, total))
    f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    f.write(struct.pack("<II", len(new_bin), 0x004E4942) + new_bin)
print("wrote", dst, total)
