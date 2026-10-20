"""Builds the game's soldiers in Blender: rigged, animated GLB files.

Run with Blender's Python (bpy):
    python build_units.py <output_dir>                # all units
    python build_units.py <output_dir> archer_iran    # just some

Every soldier is made of smooth low-poly parts, each one bound rigidly to one bone of a
small skeleton. All colours live in one small palette texture, so a soldier is a single
draw call. Each file has three clips: idle_loop, walk_loop and attack.
Models face Blender +Y, which becomes Godot -Z (forward). Right hand is +X.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
ONLY = set(sys.argv[2:])
FPS = 24

# ---------------------------------------------------------------- palette
PAL = {
    "skin": (0.80, 0.56, 0.40), "skin_dark": (0.62, 0.41, 0.28), "beard": (0.13, 0.08, 0.05),
    "steel": (0.70, 0.73, 0.76), "iron": (0.33, 0.34, 0.36), "gold": (0.88, 0.66, 0.24),
    "bronze": (0.68, 0.45, 0.20), "wood": (0.48, 0.32, 0.17), "wood_dark": (0.28, 0.17, 0.09),
    "leather": (0.40, 0.25, 0.13), "leather_dark": (0.22, 0.14, 0.08), "rope": (0.83, 0.76, 0.58),
    "white": (0.90, 0.87, 0.80), "cream": (0.86, 0.78, 0.60), "fur": (0.42, 0.30, 0.20),
    "fur_light": (0.62, 0.50, 0.36), "black": (0.07, 0.07, 0.08),
    "horse_bay": (0.42, 0.24, 0.12), "horse_dark": (0.16, 0.11, 0.08), "horse_grey": (0.62, 0.60, 0.57),
    "hoof": (0.10, 0.08, 0.06), "mane": (0.08, 0.06, 0.05), "wicker": (0.70, 0.56, 0.30),
    # Iran
    "ir_main": (0.13, 0.30, 0.72), "ir_dark": (0.06, 0.13, 0.36), "ir_light": (0.42, 0.62, 0.92),
    "ir_turq": (0.10, 0.60, 0.60), "ir_trouser": (0.80, 0.74, 0.58),
    # Turan
    "tu_main": (0.62, 0.13, 0.10), "tu_dark": (0.26, 0.06, 0.05), "tu_light": (0.80, 0.36, 0.22),
    "tu_trouser": (0.30, 0.24, 0.20), "tu_black": (0.12, 0.10, 0.10),
}
CELLS = 8          # palette is CELLS x CELLS swatches
CELL_PX = 16
_pal_index = {}
METAL = {"steel", "iron", "gold", "bronze"}


def pal_uv(key):
    if key not in _pal_index:
        _pal_index[key] = len(_pal_index)
    i = _pal_index[key]
    return ((i % CELLS) + 0.5) / CELLS, 1.0 - ((i // CELLS) + 0.5) / CELLS


def make_palette_image(name):
    size = CELLS * CELL_PX
    img = bpy.data.images.new(name, size, size)
    px = [0.0] * (size * size * 4)
    for key, i in _pal_index.items():
        r, g, b = PAL[key]
        cx, cy = i % CELLS, CELLS - 1 - i // CELLS
        for y in range(cy * CELL_PX, (cy + 1) * CELL_PX):
            for x in range(cx * CELL_PX, (cx + 1) * CELL_PX):
                o = (y * size + x) * 4
                # vertical shade inside a swatch: each part is darker at its bottom
                k = 0.72 + 0.4 * (y - cy * CELL_PX) / (CELL_PX - 1)
                px[o:o + 4] = [min(r * k, 1.0), min(g * k, 1.0), min(b * k, 1.0), 1.0]
    img.pixels = px
    return img


# ---------------------------------------------------------------- scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


parts = []   # (object, bone, colour key)


def _add(o, bone, col, smooth=True, bevel=0.0):
    if bevel > 0:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 1
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="bevel")
    for p in o.data.polygons:
        p.use_smooth = smooth
    parts.append((o, bone, col))
    return o


def box(size, loc, bone, col, rot=(0, 0, 0), bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _add(o, bone, col, False, bevel)


def cyl(r, z0, z1, bone, col, r2=None, xy=(0, 0), verts=10, smooth=True, scale_y=1.0):
    """Vertical (tapered) cylinder from z0 to z1."""
    h = z1 - z0
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, vertices=verts, location=(xy[0], xy[1], z0 + h / 2))
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, vertices=verts, location=(xy[0], xy[1], z0 + h / 2))
    o = bpy.context.active_object
    if scale_y != 1.0:
        o.scale = (1, scale_y, 1)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _add(o, bone, col, smooth)


def rod(p0, p1, r, bone, col, r2=None, verts=8, smooth=True):
    """Cylinder between two points."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=d.length, vertices=verts)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    o.location = (p0 + p1) / 2
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    return _add(o, bone, col, smooth)


def ball(r, loc, bone, col, scale=(1, 1, 1), segs=12, rings=8, hemi=False):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segs, ring_count=rings, location=(0, 0, 0))
    o = bpy.context.active_object
    if hemi:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.001], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    o.scale = scale
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    return _add(o, bone, col, True)


def torus(R, r, loc, bone, col, rot=(0, 0, 0), arc=1.0, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=20, minor_segments=6)
    o = bpy.context.active_object
    if arc < 1.0:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        lim = math.cos(math.pi * arc)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if Vector((v.co.x, v.co.y, 0)).normalized().y < lim], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    o.scale = scale
    o.rotation_euler = rot
    o.location = loc
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _add(o, bone, col, True)


def pose_space(objs, pivot, angle_x):
    """Parts are modelled where they sit once a limb is rotated by angle_x around pivot;
    rotate them back into the rest pose."""
    m = Matrix.Translation(pivot) @ Matrix.Rotation(-angle_x, 4, "X") @ Matrix.Translation(-Vector(pivot))
    for o in objs:
        o.matrix_world = m @ o.matrix_world


def collect(fn):
    before = len(parts)
    fn()
    return [p[0] for p in parts[before:]]


# ---------------------------------------------------------------- skeleton
# name: (head, tail, parent)
HUMAN = {
    "hips": ((0, 0, 0.90), (0, 0, 1.04), None),
    "spine": ((0, 0, 1.04), (0, 0, 1.44), "hips"),
    "head": ((0, 0, 1.47), (0, 0, 1.80), "spine"),
    "upperarm.L": ((-0.25, 0, 1.40), (-0.28, 0, 1.12), "spine"),
    "forearm.L": ((-0.28, 0, 1.12), (-0.29, 0, 0.86), "upperarm.L"),
    "upperarm.R": ((0.25, 0, 1.40), (0.28, 0, 1.12), "spine"),
    "forearm.R": ((0.28, 0, 1.12), (0.29, 0, 0.86), "upperarm.R"),
    "thigh.L": ((-0.11, 0, 0.90), (-0.11, 0, 0.50), "hips"),
    "shin.L": ((-0.11, 0, 0.50), (-0.11, 0, 0.08), "thigh.L"),
    "thigh.R": ((0.11, 0, 0.90), (0.11, 0, 0.50), "hips"),
    "shin.R": ((0.11, 0, 0.50), (0.11, 0, 0.08), "thigh.R"),
}
HORSE = {
    "horse": ((0, 0, 1.25), (0, 0.4, 1.25), None),
    "neck": ((0, 0.75, 1.45), (0, 1.1, 1.95), "horse"),
    "tail": ((0, -0.85, 1.4), (0, -1.1, 0.9), "horse"),
    "leg.FL": ((-0.2, 0.62, 1.05), (-0.2, 0.62, 0.05), "horse"),
    "leg.FR": ((0.2, 0.62, 1.05), (0.2, 0.62, 0.05), "horse"),
    "leg.BL": ((-0.2, -0.6, 1.05), (-0.2, -0.6, 0.05), "horse"),
    "leg.BR": ((0.2, -0.6, 1.05), (0.2, -0.6, 0.05), "horse"),
}
RIDER_DZ = 0.62   # rider is lifted onto the saddle


def bone_pos(name, mounted=False):
    h, t, _ = HUMAN[name]
    dz = RIDER_DZ if mounted else 0.0
    return Vector((h[0], h[1], h[2] + dz)), Vector((t[0], t[1], t[2] + dz))


def make_armature(mounted):
    arm = bpy.data.armatures.new("rig")
    ob = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    bones = {}
    if mounted:
        bones.update(HORSE)
    for k, (h, t, p) in HUMAN.items():
        if mounted and k.startswith(("thigh", "shin")):
            continue
        dz = RIDER_DZ if mounted else 0.0
        bones[k] = ((h[0], h[1], h[2] + dz), (t[0], t[1], t[2] + dz), p if (p or not mounted) else "horse")
    for k, (h, t, p) in bones.items():
        b = arm.edit_bones.new(k)
        b.head = h
        b.tail = t
        b.roll = 0.0
        eb[k] = b
    for k, (h, t, p) in bones.items():
        if p:
            eb[k].parent = eb[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


# ---------------------------------------------------------------- body
def body(c, mounted=False, coat_len=0.62, heavy=False):
    """c: dict of colour keys: main, dark, light, trouser, boot, belt, skin."""
    dz = RIDER_DZ if mounted else 0.0
    sk = c.get("skin", "skin")
    if not mounted:
        for s, L in ((-1, "L"), (1, "R")):
            x = 0.11 * s
            cyl(0.085, 0.50, 0.90, "thigh." + L, c["trouser"], r2=0.075, xy=(x, 0))
            cyl(0.07, 0.10, 0.50, "shin." + L, c["boot"], r2=0.075, xy=(x, 0))
            box((0.12, 0.24, 0.09), (x, 0.04, 0.045), "shin." + L, c["boot"], bevel=0.03)
            cyl(0.078, 0.46, 0.52, "shin." + L, c.get("garter", c["boot"]), xy=(x, 0))
    else:
        # riding legs: bent forward over the horse's flanks, bound to the hips
        for s in (-1, 1):
            rod((0.12 * s, 0, 0.92 + dz), (0.27 * s, 0.32, 0.72 + dz), 0.085, "hips", c["trouser"])
            rod((0.27 * s, 0.32, 0.72 + dz), (0.30 * s, 0.22, 0.30 + dz), 0.072, "hips", c["boot"])
            box((0.11, 0.24, 0.09), (0.31 * s, 0.30, 0.26 + dz), "hips", c["boot"], bevel=0.03)
    # long coat (skirt) and belt
    z_hem = 1.0 - coat_len + dz
    if not mounted:
        cyl(0.205, z_hem, 1.02 + dz, "hips", c["main"], r2=0.19, verts=12)
        cyl(0.21, z_hem - 0.03, z_hem + 0.03, "hips", c["light"], verts=12)
    else:
        cyl(0.24, 0.84 + dz, 1.02 + dz, "hips", c["main"], r2=0.19, verts=12)
    cyl(0.205, 0.98 + dz, 1.06 + dz, "spine", c["belt"], verts=12)
    box((0.08, 0.03, 0.07), (0, 0.2, 1.02 + dz), "spine", "gold", bevel=0.01)
    # torso
    cyl(0.19, 1.04 + dz, 1.44 + dz, "spine", c["main"], r2=0.22, verts=12, scale_y=0.72)
    ball(0.21, (0, 0, 1.40 + dz), "spine", c["main"], scale=(1.1, 0.75, 0.5))
    if heavy:
        cyl(0.205, 1.12 + dz, 1.42 + dz, "spine", c.get("armour", "steel"), r2=0.235, verts=12, scale_y=0.78)
    # chest trim (Persian coats cross over at the front)
    rod((-0.12, 0.155, 1.40 + dz), (0.10, 0.155, 1.08 + dz), 0.022, "spine", c["light"], verts=6)
    # neck + head
    cyl(0.055, 1.42 + dz, 1.52 + dz, "head", sk, verts=8)
    ball(0.12, (0, 0.01, 1.63 + dz), "head", sk, scale=(0.95, 1.0, 1.12))
    ball(0.025, (0, 0.125, 1.62 + dz), "head", c.get("skin_dark", "skin_dark"), segs=6, rings=4)   # nose
    if c.get("beard", True):
        rod((0, 0.075, 1.575 + dz), (0, 0.10, 1.45 + dz), 0.075, "head", "beard", r2=0.025, verts=8)
        rod((-0.06, 0.085, 1.60 + dz), (0.06, 0.085, 1.60 + dz), 0.02, "head", "beard", verts=6)    # moustache
    # arms with sleeves
    for s, L in ((-1, "L"), (1, "R")):
        sh, el = bone_pos("upperarm." + L, mounted)
        _, wr = bone_pos("forearm." + L, mounted)
        ball(0.085, sh, "upperarm." + L, c["main"], segs=10, rings=6)
        rod(sh, el, 0.065, "upperarm." + L, c["main"], r2=0.058)
        rod(el, wr + Vector((0, 0, 0.04)), 0.058, "forearm." + L, c["main"], r2=0.05)
        cyl(0.056, wr.z + 0.02, wr.z + 0.08, "forearm." + L, c["light"], xy=(wr.x, wr.y), verts=8)
        ball(0.045, wr + Vector((0, 0, -0.03)), "forearm." + L, sk, segs=8, rings=6)


def hand_r(mounted=False):
    return bone_pos("forearm.R", mounted)[1] + Vector((0, 0, -0.03))


def hand_l(mounted=False):
    return bone_pos("forearm.L", mounted)[1] + Vector((0, 0, -0.03))


def elbow(L, mounted=False):
    return bone_pos("forearm." + L, mounted)[0]


def spear(mounted=False, length=2.5, tip="steel", butt=None, shaft="wood"):
    """Upright spear held in the right hand with the forearm raised 90 degrees."""
    def mk():
        h = hand_r(mounted)
        # with forearm forward, the hand sits in front of the elbow
        e = elbow("R", mounted)
        hp = Vector((h.x, e.y + (e.z - h.z), e.z))
        rod(hp + Vector((0, 0, -0.9)), hp + Vector((0, 0, length - 0.9)), 0.022, "forearm.R", shaft, verts=6)
        rod(hp + Vector((0, 0, length - 0.92)), hp + Vector((0, 0, length - 0.6)), 0.05, "forearm.R", tip, r2=0.0, verts=6)
        rod(hp + Vector((0, 0, length - 0.95)), hp + Vector((0, 0, length - 0.9)), 0.03, "forearm.R", "gold", verts=6)
        if butt:
            ball(0.06, hp + Vector((0, 0, -0.92)), "forearm.R", butt, segs=8, rings=6)
    pose_space(collect(mk), elbow("R", mounted), math.radians(90))


def round_shield(col, rim, boss="bronze", r=0.30, mounted=False):
    """Round shield on the left forearm, forearm raised 90 degrees, facing forward."""
    def mk():
        h = hand_l(mounted)
        e = elbow("L", mounted)
        c = Vector((h.x - 0.06, e.y + (e.z - h.z) * 0.55 + 0.07, e.z))
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.045, vertices=16, location=c, rotation=(math.pi / 2, 0, 0))
        _add(bpy.context.active_object, "forearm.L", col, True)
        torus(r, 0.022, c, "forearm.L", rim, rot=(math.pi / 2, 0, 0))
        ball(0.075, c + Vector((0, 0.02, 0)), "forearm.L", boss, segs=10, rings=6, scale=(1, 0.7, 1))
    pose_space(collect(mk), elbow("L", mounted), math.radians(90))


def wicker_shield(mounted=False):
    """Tall rectangular spara shield of the Immortals."""
    def mk():
        h = hand_l(mounted)
        e = elbow("L", mounted)
        c = Vector((h.x - 0.05, e.y + (e.z - h.z) * 0.55 + 0.07, e.z - 0.1))
        box((0.50, 0.04, 0.95), c, "forearm.L", "wicker", bevel=0.01)
        box((0.53, 0.05, 0.05), c + Vector((0, 0.01, 0.46)), "forearm.L", "leather", bevel=0.0)
        box((0.53, 0.05, 0.05), c + Vector((0, 0.01, -0.46)), "forearm.L", "leather", bevel=0.0)
        box((0.30, 0.05, 0.42), c + Vector((0, 0.02, 0.0)), "forearm.L", "ir_main", bevel=0.01)
        ball(0.06, c + Vector((0, 0.05, 0.0)), "forearm.L", "gold", segs=8, rings=6, scale=(1, 0.6, 1))
    pose_space(collect(mk), elbow("L", mounted), math.radians(90))


def bow(col="wood_dark", mounted=False):
    """Recurve bow in the left hand, arm stretched forward at shoulder height."""
    sh, _ = bone_pos("upperarm.L", mounted)
    def mk():
        h = hand_l(mounted)
        reach = sh.z - h.z
        c = Vector((h.x, sh.y + reach, sh.z))
        torus(0.55, 0.018, c + Vector((0, 0.18, 0)), "forearm.L", col, rot=(0, math.pi / 2, math.pi), arc=0.36, scale=(1, 0.42, 1))
        cyl(0.03, c.z - 0.06, c.z + 0.06, "forearm.L", "leather", xy=(c.x, c.y + 0.18), verts=6)
    pose_space(collect(mk), sh, math.radians(90))


def quiver(col="leather", mounted=False):
    dz = RIDER_DZ if mounted else 0.0
    rod((0.12, -0.17, 0.98 + dz), (-0.10, -0.2, 1.52 + dz), 0.07, "spine", col, verts=8)
    for i in range(4):
        x = -0.12 + i * 0.025
        rod((x, -0.2, 1.50 + dz), (x - 0.03, -0.21, 1.62 + dz), 0.008, "spine", "wood", verts=4)
        box((0.03, 0.005, 0.05), (x - 0.03, -0.21, 1.64 + dz), "spine", "white", bevel=0.0)


def sword_at_hip(mounted=False, col="steel"):
    dz = RIDER_DZ if mounted else 0.0
    rod((-0.2, 0.12, 1.0 + dz), (-0.22, -0.32, 0.55 + dz), 0.03, "hips", "leather_dark", verts=6)
    rod((-0.2, 0.14, 1.02 + dz), (-0.19, 0.22, 1.1 + dz), 0.018, "hips", "gold", verts=6)


# ---------------------------------------------------------------- hats and helmets
def hat_persian(c, mounted=False):
    """Soft Median cap (bashlyk) with cheek flaps."""
    dz = RIDER_DZ if mounted else 0.0
    ball(0.135, (0, 0.0, 1.66 + dz), "head", c, scale=(1.0, 1.05, 1.05), hemi=True)
    rod((0, -0.01, 1.70 + dz), (0, -0.06, 1.84 + dz), 0.09, "head", c, r2=0.035, verts=10)
    for s in (-1, 1):
        box((0.035, 0.09, 0.15), (0.12 * s, 0.0, 1.58 + dz), "head", c, bevel=0.012)
    box((0.08, 0.10, 0.16), (0, -0.11, 1.57 + dz), "head", c, bevel=0.012)


def helmet_conical(col="steel", aventail="iron", plume=None, mounted=False):
    dz = RIDER_DZ if mounted else 0.0
    cyl(0.135, 1.66 + dz, 1.86 + dz, "head", col, r2=0.02, verts=12)
    cyl(0.14, 1.64 + dz, 1.69 + dz, "head", "bronze", verts=12)
    rod((0, 0.13, 1.66 + dz), (0, 0.15, 1.56 + dz), 0.015, "head", col, verts=4)   # nose guard
    # mail curtain around neck and sides, open at the face
    bpy.ops.mesh.primitive_cylinder_add(radius=0.145, depth=0.16, vertices=14, end_fill_type="NOTHING", location=(0, -0.01, 1.58 + dz))
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().y > 0.07], context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    sol = o.modifiers.new("s", "SOLIDIFY")
    sol.thickness = 0.015
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="s")
    _add(o, "head", aventail, True)
    if plume:
        rod((0, 0, 1.86 + dz), (0, -0.05, 2.0 + dz), 0.012, "head", "gold", verts=4)
        ball(0.05, (0, -0.07, 2.0 + dz), "head", plume, scale=(0.6, 1.4, 0.8), segs=8, rings=6)


def fur_hat(c="fur", top="tu_main", mounted=False):
    dz = RIDER_DZ if mounted else 0.0
    cyl(0.15, 1.64 + dz, 1.74 + dz, "head", c, r2=0.15, verts=12)
    ball(0.12, (0, 0, 1.74 + dz), "head", top, scale=(1, 1, 1.25), hemi=True)
    torus(0.15, 0.03, (0, 0, 1.69 + dz), "head", c)


def immortal_tiara(mounted=False):
    dz = RIDER_DZ if mounted else 0.0
    cyl(0.14, 1.66 + dz, 1.86 + dz, "head", "gold", r2=0.15, verts=14)
    cyl(0.152, 1.83 + dz, 1.87 + dz, "head", "ir_turq", verts=14)
    torus(0.142, 0.012, (0, 0, 1.70 + dz), "head", "ir_turq")
    # cloth that wraps the chin, as on the Susa reliefs
    box((0.26, 0.05, 0.14), (0, 0.10, 1.53 + dz), "head", "white", bevel=0.02)


# ---------------------------------------------------------------- horse
def horse(coat, cloth, trim, armour=False):
    cyl(0.33, -0.70, 0.75, "horse", coat, r2=0.30, verts=14)   # placeholder, rotated below
    o = parts[-1][0]
    o.matrix_world = Matrix.Translation((0, 0, 1.22)) @ Matrix.Rotation(math.radians(-90), 4, "X") @ o.matrix_world
    ball(0.34, (0, 0.72, 1.24), "horse", coat, scale=(0.95, 1.1, 1.0))      # chest
    ball(0.36, (0, -0.70, 1.26), "horse", coat, scale=(1.0, 1.1, 0.98))      # haunch
    # neck and head
    rod((0, 0.78, 1.38), (0, 1.08, 1.92), 0.2, "neck", coat, r2=0.13, verts=10)
    rod((0, 1.05, 1.98), (0, 1.48, 1.72), 0.12, "neck", coat, r2=0.085, verts=10)
    ball(0.12, (0, 1.05, 1.98), "neck", coat)
    for s in (-1, 1):
        rod((0.05 * s, 1.05, 2.07), (0.06 * s, 1.0, 2.18), 0.03, "neck", coat, r2=0.0, verts=5)  # ears
    box((0.05, 0.42, 0.14), (0, 0.9, 1.78), "neck", "mane", rot=(math.radians(-58), 0, 0), bevel=0.02)
    rod((0, 1.47, 1.72), (0, 1.0, 1.70), 0.012, "neck", "leather_dark", verts=4)   # reins
    # tail
    rod((0, -0.88, 1.38), (0, -1.06, 0.82), 0.07, "tail", "mane", r2=0.03, verts=8)
    # legs
    for k, (x, y) in (("FL", (-0.2, 0.62)), ("FR", (0.2, 0.62)), ("BL", (-0.2, -0.6)), ("BR", (0.2, -0.6))):
        rod((x, y, 1.1), (x, y + 0.02, 0.55), 0.09 if y < 0 else 0.08, "leg." + k, coat, r2=0.06)
        rod((x, y + 0.02, 0.55), (x, y, 0.1), 0.05, "leg." + k, coat, r2=0.045)
        cyl(0.065, 0.0, 0.12, "leg." + k, "hoof", r2=0.055, xy=(x, y), verts=8)
    # saddle cloth and saddle
    box((0.78, 0.86, 0.04), (0, 0.02, 1.52), "horse", cloth, bevel=0.02)
    box((0.80, 0.88, 0.05), (0, 0.02, 1.50), "horse", trim, bevel=0.0)
    box((0.36, 0.48, 0.10), (0, 0.04, 1.58), "horse", "leather", bevel=0.04)
    box((0.30, 0.06, 0.12), (0, 0.27, 1.64), "horse", "leather_dark", bevel=0.02)
    if armour:
        # cloth caparison hanging over the chest
        cyl(0.36, 0.95, 1.40, "horse", cloth, r2=0.34, xy=(0, 0.8), verts=12, scale_y=0.6)
        for s in (-1, 1):
            box((0.03, 0.74, 0.3), (0.36 * s, 0.02, 1.33), "horse", cloth, bevel=0.01)


# ---------------------------------------------------------------- soldiers
IR = {"main": "ir_main", "dark": "ir_dark", "light": "gold", "trouser": "ir_trouser", "boot": "leather", "belt": "leather_dark"}
TU = {"main": "tu_main", "dark": "tu_dark", "light": "fur_light", "trouser": "tu_trouser", "boot": "leather_dark", "belt": "tu_black"}


def u_archer_iran():
    body(dict(IR, light="ir_turq", main="ir_light"), coat_len=0.55)
    hat_persian("ir_main")
    bow("wood_dark")
    quiver("leather")
    return "archer"


def u_archer_turan():
    body(dict(TU, main="tu_light", light="fur"), coat_len=0.5)
    fur_hat("fur", "tu_main")
    bow("leather_dark")
    quiver("fur")
    return "archer"


def u_spear_turan():
    body(dict(TU, armour="iron"), coat_len=0.58, heavy=True)
    helmet_conical("iron", "iron")
    spear(length=2.4, tip="iron")
    round_shield("tu_main", "iron", "iron")
    return "spear"


def u_immortal_iran():
    body(dict(IR, main="cream", light="ir_main", trouser="ir_main", boot="gold", armour="gold"), coat_len=0.8, heavy=False)
    # long robe sleeves and gold-scale chest
    cyl(0.215, 1.15, 1.42, "spine", "gold", r2=0.235, verts=12, scale_y=0.78)
    immortal_tiara()
    spear(length=2.3, tip="steel", butt="gold")
    wicker_shield()
    quiver("ir_main")
    return "immortal"


def u_immortal_turan():
    body(dict(TU, main="tu_dark", light="tu_main", armour="iron"), coat_len=0.72, heavy=True)
    # lamellar skirt plates
    for i in range(10):
        a = i * 2 * math.pi / 10
        box((0.11, 0.03, 0.2), (math.sin(a) * 0.235, math.cos(a) * 0.235 * 0.9, 0.86), "hips", "iron", rot=(0, 0, -a), bevel=0.0)
    helmet_conical("steel", "iron", plume="tu_main")
    box((0.18, 0.04, 0.12), (0, 0.13, 1.62), "head", "steel", bevel=0.02)   # face mask
    spear(length=2.6, tip="steel")
    round_shield("tu_dark", "steel", "steel", r=0.34)
    return "immortal"


def u_cav(c, coat, cloth, trim, helm, lance_tip, plume=None, fur=False):
    horse(coat, cloth, trim, armour=True)
    body(c, mounted=True, heavy=True)
    if fur:
        fur_hat("fur", c["main"], mounted=True)
    else:
        helmet_conical(helm, "iron", plume=plume, mounted=True)
    spear(mounted=True, length=3.1, tip=lance_tip)
    # pennant on the lance
    sword_at_hip(mounted=True)
    return "cav"


def u_cav_iran():
    return u_cav(dict(IR, armour="steel"), "horse_bay", "ir_main", "gold", "steel", "steel", plume="ir_turq")


def u_cav_turan():
    return u_cav(dict(TU, armour="iron"), "horse_dark", "tu_main", "tu_black", "iron", "iron", fur=True)


UNITS = {
    "archer_iran": u_archer_iran,
    "archer_turan": u_archer_turan,
    "spear_turan": u_spear_turan,
    "immortal_iran": u_immortal_iran,
    "immortal_turan": u_immortal_turan,
    "cav_iran": u_cav_iran,
    "cav_turan": u_cav_turan,
}


# ---------------------------------------------------------------- animation
def R(deg):
    return math.radians(deg)


def key(rig, frame, pose):
    """pose: {bone: (x, y, z) degrees, 'hips_z': lift}."""
    for b in rig.pose.bones:
        rot = pose.get(b.name, (0, 0, 0))
        b.rotation_mode = "XYZ"
        b.rotation_euler = (R(rot[0]), R(rot[1]), R(rot[2]))
        b.keyframe_insert("rotation_euler", frame=frame)
        if b.parent is None:
            lift = pose.get("lift", 0.0)
            # hips point up (local Y is world up); the horse points forward (local Z is up)
            b.location = (0, 0, lift) if b.name == "horse" else (0, lift, 0)
            b.keyframe_insert("location", frame=frame)


def action(rig, name, frames):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for f, pose in frames:
        key(rig, f, pose)
    if name.endswith("_loop"):
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
    return act


# Bone sign conventions (checked in renders):
#  limbs pointing down: +X swings forward. spine/head pointing up: +X leans back.
def hold(kind):
    """Base upper-body pose while standing with the weapon."""
    if kind == "archer":
        return {"upperarm.L": (20, 0, -8), "forearm.L": (35, 0, 0), "upperarm.R": (5, 0, 8), "forearm.R": (25, 0, 0)}
    return {"upperarm.R": (8, 0, 6), "forearm.R": (82, 0, 0), "upperarm.L": (12, 0, -10), "forearm.L": (78, 0, 0)}


def merge(*ps):
    out = {}
    for p in ps:
        for k, v in p.items():
            if k in out and isinstance(v, tuple):
                out[k] = tuple(a + b for a, b in zip(out[k], v))
            else:
                out[k] = v
    return out


def anims_human(rig, kind):
    base = hold(kind)
    # idle: breathing, 2 s
    action(rig, "idle_loop", [
        (1, merge(base, {"spine": (0, 0, 0), "head": (0, 0, 0)})),
        (25, merge(base, {"spine": (-2, 0, 1), "head": (2, 3, 0), "upperarm.R": (2, 0, 0), "upperarm.L": (2, 0, 0)})),
        (49, merge(base, {"spine": (0, 0, 0), "head": (0, 0, 0)})),
    ])
    # walk: one stride cycle in 0.66 s
    def stride(s):
        legs = {"thigh.L": (26 * s, 0, 0), "shin.L": (-10 if s > 0 else -38, 0, 0),
                "thigh.R": (-26 * s, 0, 0), "shin.R": (-38 if s > 0 else -10, 0, 0)}
        arms = {} if kind != "archer" else {"upperarm.R": (-22 * s, 0, 0)}
        return merge(base, legs, arms, {"spine": (-5, 4 * s, 0), "hips": (0, 6 * s, 0)})
    def passing(s):
        legs = {"thigh.L": (0, 0, 0), "shin.L": (-35 if s > 0 else 0, 0, 0),
                "thigh.R": (0, 0, 0), "shin.R": (0 if s > 0 else -35, 0, 0)}
        return merge(base, legs, {"spine": (-5, 0, 0), "lift": 0.05})
    action(rig, "walk_loop", [(1, stride(1)), (5, passing(-1)), (9, stride(-1)), (13, passing(1)), (17, stride(1))])
    # attack
    if kind == "archer":
        draw = {"upperarm.L": (88, 0, -4), "forearm.L": (2, 0, 0), "upperarm.R": (85, 0, 40), "forearm.R": (60, 0, 0), "spine": (0, 0, -15), "head": (0, 0, 12)}
        loose = merge(draw, {"upperarm.R": (0, 0, 15), "forearm.R": (-30, 0, 0)})
        action(rig, "attack", [(1, base), (6, draw), (11, draw), (13, loose), (18, base)])
    else:
        wind = merge(base, {"upperarm.R": (-25, 0, 0), "forearm.R": (-2, 0, 0), "spine": (4, 0, -10)})
        thrust = {"upperarm.R": (62, 0, 6), "forearm.R": (12, 0, 0), "upperarm.L": (30, 0, -10), "forearm.L": (60, 0, 0),
                  "spine": (-10, 0, 12), "thigh.L": (20, 0, 0), "shin.L": (-10, 0, 0), "thigh.R": (-15, 0, 0)}
        action(rig, "attack", [(1, base), (5, wind), (9, thrust), (12, thrust), (18, base)])


def anims_cav(rig):
    base = {"upperarm.R": (10, 0, 8), "forearm.R": (80, 0, 0), "upperarm.L": (25, 0, -5), "forearm.L": (60, 0, 0)}
    action(rig, "idle_loop", [
        (1, merge(base, {"neck": (0, 0, 0), "tail": (0, 0, 0)})),
        (25, merge(base, {"neck": (-6, 0, 3), "tail": (0, 0, 10), "spine": (-2, 0, 0)})),
        (49, merge(base, {"neck": (0, 0, 0), "tail": (0, 0, 0)})),
    ])
    # canter: diagonal pairs, 0.5 s
    def phase(s, up):
        return merge(base, {"leg.FL": (35 * s, 0, 0), "leg.BR": (35 * s, 0, 0), "leg.FR": (-35 * s, 0, 0), "leg.BL": (-35 * s, 0, 0),
                            "horse": (4 * s, 0, 0), "neck": (-8 * s, 0, 0), "tail": (-12, 0, 0), "spine": (-6 + 3 * s, 0, 0),
                            "lift": 0.08 if up else 0.0})
    action(rig, "walk_loop", [(1, phase(1, False)), (4, phase(0, True)), (7, phase(-1, False)), (10, phase(0, True)), (13, phase(1, False))])
    wind = merge(base, {"upperarm.R": (-20, 0, 0), "spine": (6, 0, -12)})
    thrust = merge(base, {"upperarm.R": (70, 0, 6), "forearm.R": (-60, 0, 0), "spine": (-14, 0, 10), "neck": (-10, 0, 0)})
    action(rig, "attack", [(1, base), (5, wind), (9, thrust), (12, thrust), (18, base)])


# ---------------------------------------------------------------- assemble + export
def build(name, fn):
    reset()
    parts.clear()
    _pal_index.clear()
    kind = fn()
    mounted = kind == "cav"
    rig = make_armature(mounted)
    # bind every part rigidly to its bone, colour it through the palette
    objs = []
    for o, bone, col in parts:
        vg = o.vertex_groups.new(name=bone)
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
        u, v = pal_uv(col)
        zs = [(o.matrix_world @ vt.co).z for vt in o.data.vertices]
        z0, z1 = min(zs), max(zs)
        v_bottom = v - 0.5 / CELLS
        for li, l in enumerate(o.data.uv_layers.active.data):
            zn = (zs[o.data.loops[li].vertex_index] - z0) / max(z1 - z0, 1e-4)
            l.uv = (u, v_bottom + (0.15 + 0.7 * zn) / CELLS)
        o["metal"] = col in METAL
        objs.append(o)
    # metal parts get their own material slot so they can shine
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    img = make_palette_image(name + "_pal")
    img.filepath_raw = os.path.join(OUT, name + "_pal.png")
    img.file_format = "PNG"
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.78
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    metal = bpy.data.materials.new(name + "_metal")
    metal.use_nodes = True
    mb = metal.node_tree.nodes["Principled BSDF"]
    mb.inputs["Roughness"].default_value = 0.32
    mb.inputs["Metallic"].default_value = 0.8
    mt = metal.node_tree.nodes.new("ShaderNodeTexImage")
    mt.image = img
    mt.interpolation = "Closest"
    metal.node_tree.links.new(mt.outputs["Color"], mb.inputs["Base Color"])
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        o.data.materials.append(metal)
        for p in o.data.polygons:
            p.material_index = 1 if o["metal"] else 0
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    mesh = bpy.context.active_object
    mesh.name = name
    # merge the duplicated material slots left by the join
    bpy.ops.object.material_slot_remove_unused()
    mod = mesh.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    mesh.parent = rig
    if mounted:
        anims_cav(rig)
    else:
        anims_human(rig, kind)
    rig.animation_data.action = bpy.data.actions["idle_loop"]
    # marker: the game uses this model at its real size instead of fitting its height
    marker = bpy.data.objects.new("TRUE_SCALE", None)
    bpy.context.scene.collection.objects.link(marker)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_frame_range=False, export_image_format="AUTO", export_skins=True,
                              export_def_bones=False, export_optimize_animation_size=True)
    print("exported", path, len(mesh.data.polygons), "faces", len(_pal_index), "colours")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n, f in UNITS.items():
        if ONLY and n not in ONLY:
            continue
        build(n, f)
