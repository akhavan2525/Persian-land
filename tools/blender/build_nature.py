"""Builds trees and rocks for the map in Blender and exports them as GLB files.

    python build_nature.py <output_dir> <ground_texture_dir>

Trees: a plane tree (chenar, two shapes) and a cypress (sarv). Trunks are tapered
branching tubes; foliage is many small leaf cards cut out by a generated leaf texture.
Leaf normals point away from the crown centre, so the crown is lit as one soft mass.
Rocks: three boulders, displaced and textured with the ground rock texture.
Everything stands on Z = 0 and is made at real size in metres.
"""
import math
import os
import random
import sys

import bpy
import bmesh  # noqa: E402  (needs bpy first)
import numpy as np
from mathutils import Matrix, Vector, noise

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
GROUND = sys.argv[2] if len(sys.argv) > 2 else "."


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- textures
def leaf_image(name, base, seed):
    """A square of overlapping small leaves on transparent background."""
    S = 512
    r = np.random.default_rng(seed)
    rgba = np.zeros((S, S, 4))
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    cx, cy = S / 2, S / 2
    for _ in range(420):
        # leaves cluster towards the middle of the card, so the card edge is ragged
        a = r.uniform(0, 2 * math.pi)
        d = abs(r.normal(0, 0.24)) * S
        px, py = cx + math.cos(a) * d, cy + math.sin(a) * d
        ang = r.uniform(0, math.pi)
        L = r.uniform(14, 26)
        W = L * r.uniform(0.35, 0.5)
        x0, x1 = int(max(px - L, 0)), int(min(px + L, S))
        y0, y1 = int(max(py - L, 0)), int(min(py + L, S))
        if x1 <= x0 or y1 <= y0:
            continue
        X = xs[y0:y1, x0:x1] - px
        Y = ys[y0:y1, x0:x1] - py
        u = X * math.cos(ang) + Y * math.sin(ang)
        v = -X * math.sin(ang) + Y * math.cos(ang)
        m = (u / L) ** 2 + (v / W) ** 2 < 1.0
        shade = r.uniform(0.7, 1.15)
        col = np.array(base) * shade
        # light vein along the leaf, darker towards the edge
        k = 1.0 - 0.35 * np.clip(np.abs(v) / W, 0, 1)
        patch = rgba[y0:y1, x0:x1]
        for ch in range(3):
            patch[..., ch] = np.where(m, col[ch] * k, patch[..., ch])
        patch[..., 3] = np.where(m, 1.0, patch[..., 3])
    img = bpy.data.images.new(name, S, S, alpha=True)
    img.pixels = np.flipud(rgba).flatten().tolist()
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def bark_image(name, c1, c2, seed):
    S = 256
    r = np.random.default_rng(seed)
    w = r.standard_normal((S, S))
    f = np.fft.fftfreq(S)
    fx, fy = np.meshgrid(f, f)
    # stretched vertically: long bark furrows
    k = np.sqrt((fx * 4.0) ** 2 + (fy * 0.6) ** 2)
    n = np.real(np.fft.ifft2(np.fft.fft2(w) / np.maximum(k, 0.01) ** 1.1))
    n = (n - n.min()) / (n.max() - n.min())
    t = n[..., None]
    col = np.array(c1) * (1 - t) + np.array(c2) * t
    col *= (0.6 + 0.4 * n)[..., None]
    rgba = np.dstack([col, np.ones((S, S))])
    img = bpy.data.images.new(name, S, S)
    img.pixels = rgba.flatten().tolist()
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def mat_tex(name, img, alpha=False, rough=0.85):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        m.blend_method = "CLIP"
        m.alpha_threshold = 0.5
    return m


# ---------------------------------------------------------------- tree parts
def tube(points, radii, verts=7):
    """Tapered tube along a list of points. Returns a bmesh-built object."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 0.01:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d)
        ring = []
        for k in range(verts):
            a = 2 * math.pi * k / verts
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radii[i]))
        rings.append(ring)
    length = 0.0
    vs = [0.0]
    for i in range(1, len(points)):
        length += (points[i] - points[i - 1]).length
        vs.append(length)
    for i in range(len(rings) - 1):
        for k in range(verts):
            k2 = (k + 1) % verts
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            f.smooth = True
            for loop, (uu, vv) in zip(f.loops, ((k / verts, vs[i]), ((k + 1) / verts, vs[i]), ((k + 1) / verts, vs[i + 1]), (k / verts, vs[i + 1]))):
                loop[uv].uv = (uu, vv * 0.5)
    me = bpy.data.meshes.new("tube")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("tube", me)
    bpy.context.scene.collection.objects.link(o)
    return o


def branch_points(start, direction, length, segs, wobble, rnd):
    pts = [start.copy()]
    d = direction.normalized()
    p = start.copy()
    for i in range(segs):
        d = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 0.6))) * wobble).normalized()
        p = p + d * (length / segs)
        pts.append(p.copy())
    return pts


def leaf_cards(centers, size, crown_center, rnd, squash=1.0):
    """One object holding many crossed leaf quads; normals point out of the crown."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    normals = []
    for c in centers:
        out = (c - crown_center)
        out.z *= 1.0 / max(squash, 0.01)
        if out.length < 0.01:
            out = Vector((0, 0, 1))
        out.normalize()
        out = (out + Vector((0, 0, 0.35))).normalized()
        s = size * rnd.uniform(0.75, 1.25)
        for q in range(2):
            rot = Matrix.Rotation(rnd.uniform(0, math.pi), 3, "Z") @ Matrix.Rotation(rnd.uniform(-0.9, 0.9), 3, "X")
            if q == 1:
                rot = rot @ Matrix.Rotation(math.pi / 2, 3, "Y")
            corners = [rot @ Vector((-s, 0, -s)), rot @ Vector((s, 0, -s)), rot @ Vector((s, 0, s)), rot @ Vector((-s, 0, s))]
            vs = [bm.verts.new(c + v) for v in corners]
            f = bm.faces.new(vs)
            f.smooth = True
            for loop, t in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
                loop[uv].uv = t
            normals.extend([out] * 4)
    me = bpy.data.meshes.new("leaves")
    bm.to_mesh(me)
    bm.free()
    # loops were created in the same order as the normals list
    me.normals_split_custom_set([tuple(n) for n in normals])
    o = bpy.data.objects.new("leaves", me)
    bpy.context.scene.collection.objects.link(o)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_image_format="AUTO", export_normals=True)
    print("exported", path)


# ---------------------------------------------------------------- trees
def chenar(name, seed, height=6.5, crown=2.8):
    rnd = random.Random(seed)
    bark = mat_tex("bark", bark_image("bark_chenar", (0.42, 0.36, 0.28), (0.62, 0.56, 0.46), seed), rough=0.95)
    leaf = mat_tex("leaves", leaf_image("leaf_chenar_%d" % seed, (0.34, 0.52, 0.16), seed), alpha=True, rough=0.7)
    parts = []
    trunk = branch_points(Vector((0, 0, 0)), Vector((0, 0, 1)), height * 0.5, 5, 0.12, rnd)
    parts.append(tube(trunk, [0.34 - 0.04 * i for i in range(len(trunk))], 9))
    # root flare
    parts.append(tube([Vector((0, 0, -0.1)), Vector((0, 0, 0.5))], [0.55, 0.34], 9))
    top = trunk[-1]
    crown_c = top + Vector((0, 0, crown * 0.55))
    tips = []
    for b in range(6):
        a = b * 2 * math.pi / 6 + rnd.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), rnd.uniform(0.9, 1.6)))
        start = trunk[rnd.randint(3, len(trunk) - 1)]
        pts = branch_points(start, d, crown * rnd.uniform(0.8, 1.1), 4, 0.25, rnd)
        parts.append(tube(pts, [0.15 - 0.03 * i for i in range(len(pts))], 6))
        tips.extend(pts[2:])
    for o in parts:
        o.data.materials.append(bark)
    # leaf clumps on a lumpy crown made of a few spheres
    blobs = [(crown_c, crown)] + [(t + Vector((0, 0, 0.3)), crown * rnd.uniform(0.45, 0.6)) for t in tips[::2]]
    centers = []
    for c, r in blobs:
        n = int(24 * r)
        for _ in range(n):
            v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
            centers.append(c + Vector((v.x, v.y, v.z * 0.72)) * r * rnd.uniform(0.6, 1.0))
    lv = leaf_cards(centers, 0.95, crown_c, rnd, 0.72)
    lv.data.materials.append(leaf)
    join(parts + [lv], name)
    export(name)


def cypress(name, seed, height=8.0):
    rnd = random.Random(seed)
    bark = mat_tex("bark", bark_image("bark_cypress", (0.30, 0.22, 0.15), (0.45, 0.34, 0.24), seed), rough=0.95)
    leaf = mat_tex("leaves", leaf_image("leaf_cypress_%d" % seed, (0.20, 0.38, 0.16), seed), alpha=True, rough=0.75)
    trunk = branch_points(Vector((0, 0, 0)), Vector((0, 0, 1)), height * 0.9, 5, 0.03, rnd)
    t = tube(trunk, [0.2 - 0.03 * i for i in range(len(trunk))], 7)
    t.data.materials.append(bark)
    centers = []
    for i in range(220):
        z = rnd.uniform(0.9, height)
        # flame shape: widest at a third of the height, pointed top
        k = (z - 0.9) / (height - 0.9)
        r = 1.05 * math.sin(math.pi * min(1.0, 0.25 + k * 0.9)) * (1.0 - k * 0.55)
        a = rnd.uniform(0, 2 * math.pi)
        rr = r * math.sqrt(rnd.uniform(0.3, 1.0))
        centers.append(Vector((math.cos(a) * rr, math.sin(a) * rr, z)))
    lv = leaf_cards(centers, 0.55, Vector((0, 0, height * 0.45)), rnd, 3.0)
    lv.data.materials.append(leaf)
    join([t, lv], name)
    export(name)


# ---------------------------------------------------------------- rocks
def boulder(name, seed, size=(1.6, 1.3, 1.0)):
    rnd = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    o = bpy.context.active_object
    off = Vector((rnd.uniform(0, 100), rnd.uniform(0, 100), rnd.uniform(0, 100)))
    for v in o.data.vertices:
        p = v.co.copy()
        d = noise.fractal(p * 1.3 + off, 0.6, 2.0, 4) * 0.35
        p = p * (1.0 + d)
        # flatten the bottom and give it a few cut faces
        p.z = max(p.z, -0.35)
        v.co = Vector((p.x * size[0], p.y * size[1], (p.z + 0.35) * size[2]))
    for p in o.data.polygons:
        p.use_smooth = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=2.5)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.load(os.path.join(GROUND, "rock_albedo.png"))
    m = mat_tex("rock", img, rough=0.9)
    o.data.materials.append(m)
    o.name = name
    export(name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        lambda: chenar("tree_chenar_a", 3, 6.5, 2.8),
        lambda: chenar("tree_chenar_b", 8, 5.2, 2.3),
        lambda: cypress("tree_cypress", 5, 8.0),
        lambda: boulder("rock_a", 1, (1.6, 1.3, 1.0)),
        lambda: boulder("rock_b", 2, (1.1, 1.0, 1.3)),
        lambda: boulder("rock_c", 4, (2.0, 1.4, 0.8)),
    ]
    for j in jobs:
        reset()
        j()
