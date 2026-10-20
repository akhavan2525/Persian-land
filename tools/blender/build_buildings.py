"""Builds the game's buildings in Blender and exports them as GLB files.

Run with Blender's Python (bpy), for example:
    python build_buildings.py <output_dir>            # all buildings
    python build_buildings.py <output_dir> house wall # just some

Each model is made of bevelled primitives with procedural stone, brick, glazed-tile and
wood materials. The materials are baked (colour x ambient occlusion) into one texture per
model, so the GLB looks the same in Godot as in Blender.
Models face Blender +Y, which becomes Godot -Z (forward).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
ONLY = set(sys.argv[2:])
TEX = 1024

IRAN = (0.18, 0.39, 0.82)
TURAN = (0.76, 0.23, 0.19)


# ---------------------------------------------------------------- scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.bake_type = "DIFFUSE"
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    sc.render.bake.margin = 4


# ---------------------------------------------------------------- materials
_mats = {}


def _new_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.85
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    return m, nt, bsdf, tc


def _dirt(nt, tc, color_socket, bsdf, amount=0.25, scale=3.0):
    """Multiply a colour by large soft noise so surfaces are not flat."""
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (1 - amount, 1 - amount, 1 - amount * 1.1, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(color_socket, mix.inputs[6])
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def flat(name, rgb, rough=0.85, metal=0.0, dirt=0.15):
    key = ("flat", name)
    if key in _mats:
        return _mats[key]
    m, nt, bsdf, tc = _new_mat(name)
    rgbn = nt.nodes.new("ShaderNodeRGB")
    rgbn.outputs[0].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    _dirt(nt, tc, rgbn.outputs[0], bsdf, dirt)
    _mats[key] = m
    return m


def bricks(name, c1, c2, mortar, scale=4.0, row=0.25, width=0.5, dirt=0.3):
    key = ("brick", name)
    if key in _mats:
        return _mats[key]
    m, nt, bsdf, tc = _new_mat(name)
    b = nt.nodes.new("ShaderNodeTexBrick")
    b.inputs["Color1"].default_value = (*c1, 1)
    b.inputs["Color2"].default_value = (*c2, 1)
    b.inputs["Mortar"].default_value = (*mortar, 1)
    b.inputs["Scale"].default_value = scale
    b.inputs["Mortar Size"].default_value = 0.018
    b.inputs["Brick Width"].default_value = width
    b.inputs["Row Height"].default_value = row
    b.offset = 0.5
    # project bricks on the side faces: use object coords rotated per axis via a simple trick
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    nt.links.new(add.outputs[0], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    nt.links.new(comb.outputs[0], b.inputs["Vector"])
    _dirt(nt, tc, b.outputs["Color"], bsdf, dirt)
    _mats[key] = m
    return m


def tiles(name, c1, c2, grout, scale=10.0):
    """Glazed Persian tile band: small square tiles with a gloss finish."""
    m = bricks(name, c1, c2, grout, scale=scale, row=0.5, width=0.5, dirt=0.08)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.3
    return m


def wood(name, c1, c2):
    key = ("wood", name)
    if key in _mats:
        return _mats[key]
    m, nt, bsdf, tc = _new_mat(name)
    w = nt.nodes.new("ShaderNodeTexWave")
    w.inputs["Scale"].default_value = 6.0
    w.inputs["Distortion"].default_value = 4.0
    w.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].color = (*c2, 1)
    nt.links.new(w.outputs["Fac"], ramp.inputs["Fac"])
    _dirt(nt, tc, ramp.outputs["Color"], bsdf, 0.2)
    _mats[key] = m
    return m


def stone_rough(name, c1, c2, scale=2.5):
    key = ("stone", name)
    if key in _mats:
        return _mats[key]
    m, nt, bsdf, tc = _new_mat(name)
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = scale
    nt.links.new(tc.outputs["Object"], v.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*c1, 1)
    ramp.color_ramp.elements[1].color = (*c2, 1)
    nt.links.new(v.outputs["Distance"], ramp.inputs["Fac"])
    _dirt(nt, tc, ramp.outputs["Color"], bsdf, 0.3, 1.5)
    _mats[key] = m
    return m


# palette
def SANDSTONE():
    return bricks("sandstone", (0.80, 0.68, 0.48), (0.72, 0.59, 0.40), (0.55, 0.47, 0.36), 3.0)


def MUDBRICK():
    return bricks("mudbrick", (0.74, 0.58, 0.40), (0.68, 0.52, 0.35), (0.62, 0.49, 0.34), 7.0, dirt=0.35)


def GREYSTONE():
    return bricks("greystone", (0.62, 0.59, 0.53), (0.52, 0.49, 0.44), (0.36, 0.34, 0.31), 2.2, row=0.3, width=0.6)


def TURQ_TILE():
    return tiles("turq", (0.11, 0.62, 0.62), (0.08, 0.50, 0.55), (0.85, 0.82, 0.70), 14)


def LAPIS_TILE():
    return tiles("lapis", (0.10, 0.18, 0.48), (0.13, 0.24, 0.58), (0.86, 0.73, 0.38), 14)


def RED_TILE():
    return tiles("redtile", (0.55, 0.13, 0.10), (0.45, 0.10, 0.08), (0.20, 0.12, 0.08), 12)


def WOOD():
    return wood("wood", (0.36, 0.23, 0.12), (0.50, 0.34, 0.18))


def DARKWOOD():
    return wood("darkwood", (0.20, 0.12, 0.06), (0.30, 0.19, 0.10))


def GOLD():
    return flat("gold", (0.85, 0.62, 0.20), 0.3, 0.9, 0.05)


def CLOTH(rgb, name):
    return flat("cloth_" + name, rgb, 0.9, 0.0, 0.2)


def ROOF_RED():
    return bricks("roofred", (0.62, 0.28, 0.16), (0.55, 0.23, 0.13), (0.35, 0.15, 0.08), 6.0, row=0.35, width=0.35)


def THATCH():
    return wood("thatch", (0.72, 0.58, 0.30), (0.82, 0.68, 0.38))


def SOIL():
    return stone_rough("soil", (0.33, 0.22, 0.13), (0.42, 0.29, 0.17), 6.0)


def WHEAT():
    return flat("wheat", (0.86, 0.68, 0.25), 0.8, 0.0, 0.3)


def ROCK():
    return stone_rough("rock", (0.45, 0.43, 0.40), (0.62, 0.60, 0.56), 3.0)


# ---------------------------------------------------------------- geometry helpers
parts = []


def _finish(obj, mat, bevel=0.0, smooth=False):
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    parts.append(obj)
    return obj


def box(size, loc, mat, rot=(0, 0, 0), bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, mat, bevel)


def cyl(r, h, loc, mat, verts=24, r2=None, rot=(0, 0, 0), bevel=0.03, smooth=True):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=verts, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, vertices=verts, rotation=rot)
    o = bpy.context.active_object
    return _finish(o, mat, bevel, smooth)


def dome(r, loc, mat, height=1.0, onion=0.0, segs=32):
    """Persian dome: half sphere, optionally onion-shaped and pointed."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(0, 0, 0), segments=segs, ring_count=16)
    o = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in list(bm.verts):
        if v.co.z < -0.001:
            bm.verts.remove(v)
    for v in bm.verts:
        t = v.co.z / r  # 0..1
        bulge = 1.0 + onion * math.sin(t * math.pi) * 0.6
        tip = 1.0 - max(0.0, t - 0.75) * onion * 2.0
        v.co.x *= bulge * tip
        v.co.y *= bulge * tip
        v.co.z *= height
        if t > 0.97:
            v.co.z += onion * r * 0.35
    bm.to_mesh(o.data)
    bm.free()
    o.location = loc
    return _finish(o, mat, 0.0, True)


def merlons(w, d, z, mat, step=0.8, mw=0.42, mh=0.5, thick=0.35):
    nx = max(2, int(w / step))
    ny = max(2, int(d / step))
    for i in range(nx):
        x = -w / 2 + (i + 0.5) * w / nx
        box((mw, thick, mh), (x, -d / 2 + thick / 2, z), mat)
        box((mw, thick, mh), (x, d / 2 - thick / 2, z), mat)
    for i in range(ny):
        y = -d / 2 + (i + 0.5) * d / ny
        box((thick, mw, mh), (-w / 2 + thick / 2, y, z), mat)
        box((thick, mw, mh), (w / 2 - thick / 2, y, z), mat)


def ring_merlons(r, z, mat, n=10, mw=0.4, mh=0.5):
    for i in range(n):
        a = i * 2 * math.pi / n
        box((mw, 0.3, mh), (math.cos(a) * r, math.sin(a) * r, z), mat, rot=(0, 0, a + math.pi / 2))


def arch_door(w, h, loc, facing_y, mat_dark, mat_frame=None):
    """Pointed Persian arch doorway set into a wall facing +Y or -Y."""
    x, y, z = loc
    s = 1 if facing_y > 0 else -1
    box((w, 0.12, h * 0.7), (x, y + 0.06 * s, z + h * 0.35), mat_dark, bevel=0.0)
    cyl(w / 2, 0.12, (x, y + 0.06 * s, z + h * 0.7), mat_dark, verts=20, rot=(math.pi / 2, 0, 0), bevel=0.0)
    if mat_frame:
        box((w + 0.5, 0.1, 0.18), (x, y + 0.11 * s, z + h + 0.05), mat_frame)
        box((0.18, 0.1, h + 0.1), (x - w / 2 - 0.2, y + 0.11 * s, z + h / 2), mat_frame)
        box((0.18, 0.1, h + 0.1), (x + w / 2 + 0.2, y + 0.11 * s, z + h / 2), mat_frame)


def flag(loc, rgb, name, h=2.4, w=1.0):
    x, y, z = loc
    cyl(0.05, h, (x, y, z + h / 2), DARKWOOD(), verts=8)
    cyl(0.09, 0.18, (x, y, z + h + 0.05), GOLD(), verts=10)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    o = bpy.context.active_object
    o.scale = (w, 0.62, 1)
    bpy.ops.object.transform_apply(scale=True)
    o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    sub.subdivision_type = "SIMPLE"
    bpy.ops.object.modifier_apply(modifier="sub")
    for v in o.data.vertices:
        v.co.y += math.sin((v.co.x + 0.5) * 5.0) * 0.08 * (v.co.x + 0.5)
    o.location = (x + w / 2 + 0.04, y, z + h - 0.38)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.03
    return _finish(o, CLOTH(rgb, name), 0.0)


# ---------------------------------------------------------------- bake + export
def bake_and_export(name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    for o in parts:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # lightmap-style UVs for baking
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    color = bpy.data.images.new(name + "_col", TEX, TEX)
    ao = bpy.data.images.new(name + "_ao", TEX, TEX)
    for m in obj.data.materials:
        nt = m.node_tree
        node = nt.nodes.new("ShaderNodeTexImage")
        node.name = "BAKE"
        node.image = color
        nt.nodes.active = node
    sc = bpy.context.scene
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True, margin=4)
    for m in obj.data.materials:
        m.node_tree.nodes["BAKE"].image = ao
    sc.cycles.samples = 32
    bpy.ops.object.bake(type="AO", use_clear=True, margin=4)

    # colour x (soft) AO
    import numpy as np
    c = np.array(color.pixels[:]).reshape(-1, 4)
    a = np.array(ao.pixels[:]).reshape(-1, 4)
    k = 0.35 + 0.65 * a[:, :1]
    c[:, :3] *= k
    final = bpy.data.images.new(name + "_tex", TEX, TEX)
    final.pixels = c.flatten().tolist()
    final.filepath_raw = os.path.join(OUT, name + "_tex.png")
    final.file_format = "PNG"

    # gold / metal faces keep their own shiny material, everything else shares the baked one
    baked = bpy.data.materials.new(name + "_mat")
    baked.use_nodes = True
    bsdf = baked.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.82
    tex = baked.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = final
    baked.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    shiny = bpy.data.materials.new(name + "_metal")
    shiny.use_nodes = True
    sb = shiny.node_tree.nodes["Principled BSDF"]
    sb.inputs["Roughness"].default_value = 0.35
    sb.inputs["Metallic"].default_value = 0.85
    st = shiny.node_tree.nodes.new("ShaderNodeTexImage")
    st.image = final
    shiny.node_tree.links.new(st.outputs["Color"], sb.inputs["Base Color"])
    metal_idx = {i for i, m in enumerate(obj.data.materials) if m.name.startswith("gold")}
    tiles_idx = {i for i, m in enumerate(obj.data.materials) if m.name.startswith(("turq", "lapis", "redtile"))}
    glaze = bpy.data.materials.new(name + "_glaze")
    glaze.use_nodes = True
    gb = glaze.node_tree.nodes["Principled BSDF"]
    gb.inputs["Roughness"].default_value = 0.25
    gt = glaze.node_tree.nodes.new("ShaderNodeTexImage")
    gt.image = final
    glaze.node_tree.links.new(gt.outputs["Color"], gb.inputs["Base Color"])
    for p in obj.data.polygons:
        p.material_index = 1 if p.material_index in metal_idx else (2 if p.material_index in tiles_idx else 0)
    obj.data.materials.clear()
    obj.data.materials.append(baked)
    obj.data.materials.append(shiny)
    obj.data.materials.append(glaze)
    # keep only the UV map used for the bake
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                              export_apply=True, export_image_format="JPEG", export_jpeg_quality=88)
    print("exported", path, len(obj.data.polygons), "faces")


# ---------------------------------------------------------------- buildings
def keep(roof_mat, tile_mat, banner, door_y=1):
    h = 6.6
    box((8.0, 8.0, 1.6), (0, 0, -0.3), GREYSTONE())
    box((6.4, 6.4, h), (0, 0, 0.5 + h / 2), SANDSTONE())
    box((6.7, 6.7, 0.3), (0, 0, 0.5 + h), SANDSTONE())
    merlons(6.6, 6.6, 0.5 + h + 0.4, SANDSTONE())
    box((6.46, 6.46, 0.5), (0, 0, 0.5 + h - 0.9), tile_mat, bevel=0.0)
    # iwan portal on the front
    yf = 3.2 * door_y
    box((3.4, 0.5, 5.0), (0, yf, 0.5 + 2.5), SANDSTONE())
    box((2.8, 0.1, 4.3), (0, yf + 0.26 * door_y, 0.5 + 2.4), tile_mat, bevel=0.0)
    arch_door(1.7, 3.0, (0, yf + 0.3 * door_y, 0.5), door_y, DARKWOOD(), GOLD())
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = 3.2 * sx, 3.2 * sy
            cyl(1.05, h + 2.2, (x, y, 0.5 + (h + 2.2) / 2), SANDSTONE(), verts=20, r2=0.95)
            cyl(1.12, 0.35, (x, y, 0.5 + h + 1.3), tile_mat, verts=20)
            ring_merlons(1.0, 0.5 + h + 2.45, SANDSTONE(), n=10, mw=0.35, mh=0.45)
            cyl(0.95, 0.2, (x, y, 0.5 + h + 2.2), SANDSTONE(), verts=20)
            dome(0.85, (x, y, 0.5 + h + 2.3), roof_mat, 1.5, 0.5, 20)
            cyl(0.04, 0.6, (x, y, 0.5 + h + 3.85), GOLD(), verts=6)
    top = 0.5 + h
    cyl(2.0, 1.4, (0, 0, top + 0.7), SANDSTONE(), verts=32)
    cyl(2.06, 0.4, (0, 0, top + 1.3), tile_mat, verts=32)
    dome(2.0, (0, 0, top + 1.45), roof_mat, 1.2, 0.35, 40)
    cyl(0.06, 1.1, (0, 0, top + 4.4), GOLD(), verts=8)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, top + 5.0))
    _finish(bpy.context.active_object, GOLD(), 0, True)
    for sx in (-1.9, 1.9):
        box((0.85, 0.06, 2.6), (sx, yf + 0.3 * door_y, top - 2.4), CLOTH(banner, "banner"), bevel=0.0)
    flag((3.2, -3.2 * door_y, top + 3.9), banner, "keepflag", 2.6, 1.3)


def house():
    box((3.4, 3.4, 0.6), (0, 0, -0.1), GREYSTONE())
    box((3.0, 2.8, 2.4), (0, 0, 1.4), MUDBRICK())
    box((3.2, 3.0, 0.2), (0, 0, 2.7), MUDBRICK())
    box((3.2, 0.25, 0.35), (0, -1.4, 2.95), MUDBRICK())
    box((3.2, 0.25, 0.35), (0, 1.4, 2.95), MUDBRICK())
    box((0.25, 3.0, 0.35), (-1.5, 0, 2.95), MUDBRICK())
    box((0.25, 3.0, 0.35), (1.5, 0, 2.95), MUDBRICK())
    arch_door(0.75, 1.5, (-0.6, 1.4, 0.2), 1, DARKWOOD())
    box((0.5, 0.1, 0.55), (0.75, 1.42, 1.6), DARKWOOD(), bevel=0.0)
    box((0.62, 0.12, 0.08), (0.75, 1.44, 1.3), WOOD())
    # badgir (wind-catcher)
    box((0.85, 0.85, 1.9), (0.8, -0.6, 3.6), MUDBRICK())
    for dx in (-0.25, 0.0, 0.25):
        box((0.12, 0.9, 0.7), (0.8 + dx, -0.6, 3.95), DARKWOOD(), bevel=0.0)
    box((1.0, 1.0, 0.15), (0.8, -0.6, 4.6), MUDBRICK())
    # pots and a bench
    cyl(0.22, 0.5, (1.25, 1.75, 0.45), flat("clay", (0.66, 0.36, 0.2)), verts=12, r2=0.15)
    box((1.0, 0.35, 0.35), (0.3, 1.7, 0.3), WOOD())


def farm():
    w = 5.8
    box((w, w, 0.25), (0, 0, 0.0), SOIL(), bevel=0.02)
    rows = 8
    for i in range(rows):
        y = -w / 2 + 0.7 + i * (w - 1.8) / (rows - 1)
        box((w - 1.8, 0.32, 0.12), (-0.4, y, 0.17), flat("furrow", (0.25, 0.17, 0.1)), bevel=0.01)
        for j in range(12):
            x = -w / 2 + 0.6 + j * (w - 2.4) / 11
            cyl(0.07, 0.75, (x, y, 0.55), WHEAT(), verts=5, r2=0.02, bevel=0.0)
    box((1.4, 1.4, 1.5), (w / 2 - 0.9, w / 2 - 0.9, 0.85), MUDBRICK())
    cyl(1.05, 0.9, (w / 2 - 0.9, w / 2 - 0.9, 2.05), THATCH(), verts=10, r2=0.05)
    for i in range(9):
        t = -w / 2 + i * w / 8
        cyl(0.05, 0.8, (t, -w / 2 + 0.05, 0.45), WOOD(), verts=6)
        cyl(0.05, 0.8, (-w / 2 + 0.05, t, 0.45), WOOD(), verts=6)
    box((w, 0.05, 0.06), (0, -w / 2 + 0.05, 0.7), WOOD(), bevel=0.0)
    box((0.05, w, 0.06), (-w / 2 + 0.05, 0, 0.7), WOOD(), bevel=0.0)
    # scarecrow
    cyl(0.04, 1.6, (0.2, 0.3, 1.0), WOOD(), verts=6)
    box((0.9, 0.06, 0.06), (0.2, 0.3, 1.45), WOOD(), bevel=0.0)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0.2, 0.3, 1.85))
    _finish(bpy.context.active_object, THATCH(), 0, True)


def woodcutter():
    box((2.4, 2.2, 0.3), (-0.5, 0.3, 0.1), GREYSTONE())
    box((2.2, 2.0, 1.8), (-0.5, 0.3, 1.15), WOOD())
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.85, depth=1.3, location=(-0.5, 0.3, 2.7), rotation=(0, 0, math.pi / 4))
    _finish(bpy.context.active_object, THATCH(), 0.02)
    arch_door(0.6, 1.2, (-0.5, 1.3, 0.25), 1, DARKWOOD())
    for i in range(3):
        for j in range(4 - i):
            cyl(0.2, 1.8, (1.25, -0.9 + j * 0.42 + i * 0.21, 0.25 + i * 0.36), wood("log", (0.45, 0.30, 0.17), (0.62, 0.45, 0.28)),
                verts=10, rot=(0, math.pi / 2, 0))
    cyl(0.34, 0.5, (0.8, 1.2, 0.25), wood("stump", (0.48, 0.34, 0.2), (0.66, 0.5, 0.32)), verts=12)
    box((0.06, 0.06, 0.7), (0.8, 1.2, 0.75), DARKWOOD(), rot=(0.3, 0, 0), bevel=0.0)
    box((0.3, 0.05, 0.16), (0.8, 1.32, 1.05), flat("iron", (0.45, 0.46, 0.48), 0.4, 0.8))


def quarry():
    cyl(1.6, 0.35, (0.3, 0.2, 0.0), ROCK(), verts=14, bevel=0.05)
    cyl(1.1, 0.4, (0.3, 0.2, 0.05), flat("pit", (0.22, 0.2, 0.18)), verts=14)
    import random
    random.seed(4)
    for p in [(-1.2, -1.0, 0.35), (-0.5, -1.25, 0.35), (-1.3, -0.3, 0.35), (-0.85, -0.75, 1.0), (1.4, -1.2, 0.35)]:
        box((0.7, 0.7, 0.7), p, GREYSTONE(), rot=(0, 0, random.random() * 0.5), bevel=0.06)
    cyl(0.09, 3.4, (1.1, -0.9, 1.7), WOOD(), verts=8)
    cyl(0.07, 2.6, (0.45, -0.9, 3.1), WOOD(), verts=8, rot=(0, math.radians(72), 0))
    cyl(0.012, 1.6, (-0.4, -0.9, 2.4), flat("rope", (0.8, 0.72, 0.55)), verts=4)
    box((0.42, 0.42, 0.32), (-0.4, -0.9, 1.5), GREYSTONE())
    box((1.4, 1.2, 1.2), (1.2, 1.2, 0.6), WOOD())
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.1, depth=0.7, location=(1.2, 1.2, 1.55), rotation=(0, 0, math.pi / 4))
    _finish(bpy.context.active_object, THATCH(), 0.02)


def barracks(banner):
    box((6.0, 4.8, 0.5), (0, 0, 0.0), GREYSTONE())
    box((5.4, 3.6, 2.9), (0, -0.3, 1.7), SANDSTONE())
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=3.6, depth=1.5, location=(0, -0.3, 3.9), rotation=(0, 0, math.pi / 4))
    o = bpy.context.active_object
    o.scale = (1.05, 0.72, 1)
    _finish(o, ROOF_RED(), 0.03)
    # colonnade (talar)
    for x in (-2.0, -0.7, 0.7, 2.0):
        cyl(0.16, 2.7, (x, 1.75, 1.6), SANDSTONE(), verts=12)
        cyl(0.24, 0.25, (x, 1.75, 3.0), GOLD(), verts=12)
    box((5.6, 0.9, 0.3), (0, 1.6, 3.2), SANDSTONE())
    box((5.62, 0.1, 0.3), (0, 2.06, 3.2), LAPIS_TILE(), bevel=0.0)
    arch_door(1.3, 2.0, (0, 1.5, 0.25), 1, DARKWOOD())
    flag((-2.7, 2.2, 0.25), banner, "barr", 3.8, 1.1)
    flag((2.7, 2.2, 0.25), banner, "barr", 3.8, 1.1)
    for i in range(5):
        cyl(0.025, 2.0, (-1.4 + i * 0.25, 2.3, 1.2), WOOD(), verts=5, rot=(0.15, 0, 0))
        cyl(0.0, 0.06, (-1.4 + i * 0.25, 2.45, 2.25), flat("iron", (0.45, 0.46, 0.48), 0.4, 0.8), verts=5, r2=0.0)
    # training dummy
    cyl(0.05, 1.5, (1.5, 2.6, 0.95), WOOD(), verts=6)
    box((0.8, 0.08, 0.08), (1.5, 2.6, 1.35), WOOD(), bevel=0.0)
    cyl(0.18, 0.6, (1.5, 2.6, 1.3), THATCH(), verts=10)


def tower(banner):
    cyl(1.15, 0.8, (0, 0, 0.2), GREYSTONE(), verts=20)
    cyl(1.0, 6.2, (0, 0, 3.4), GREYSTONE(), verts=20, r2=0.92)
    cyl(1.22, 0.45, (0, 0, 6.6), GREYSTONE(), verts=20)
    cyl(1.24, 0.25, (0, 0, 6.2), LAPIS_TILE(), verts=20)
    ring_merlons(1.1, 7.05, GREYSTONE(), n=10, mw=0.4, mh=0.5)
    for z, a in ((2.4, 0.0), (4.4, math.pi)):
        box((0.14, 0.12, 0.7), (math.sin(a) * 0.98, math.cos(a) * 0.98, z), DARKWOOD(), rot=(0, 0, a), bevel=0.0)
    arch_door(0.65, 1.3, (0, 1.0, 0.55), 1, DARKWOOD())
    flag((0, 0, 6.85), banner, "tower", 1.9, 0.9)


def wall():
    box((2.04, 2.04, 3.1), (0, 0, 1.25), GREYSTONE(), bevel=0.02)
    box((2.1, 2.1, 0.22), (0, 0, 2.85), GREYSTONE(), bevel=0.02)
    for x in (-0.62, 0.62):
        for y in (-0.62, 0.62):
            box((0.52, 0.52, 0.55), (x, y, 3.2), GREYSTONE())


def gate():
    for s in (-1, 1):
        box((0.55, 2.04, 3.9), (0.74 * s, 0, 1.6), GREYSTONE())
        cyl(0.42, 0.5, (0.74 * s, 0, 3.75), LAPIS_TILE(), verts=12)
    box((2.04, 2.04, 0.9), (0, 0, 3.35), GREYSTONE())
    box((0.95, 0.14, 2.5), (0, 0, 1.25), wood("gatewood", (0.35, 0.21, 0.1), (0.46, 0.29, 0.14)), bevel=0.02)
    for z in (0.5, 1.25, 2.0):
        box((0.98, 0.18, 0.08), (0, 0, z), flat("iron", (0.3, 0.3, 0.32), 0.4, 0.8), bevel=0.0)
    cyl(0.48, 0.16, (0, 0, 2.5), GREYSTONE(), verts=16, rot=(math.pi / 2, 0, 0))
    for x in (-0.65, 0.0, 0.65):
        box((0.48, 0.5, 0.5), (x, 0.6, 4.05), GREYSTONE())
        box((0.48, 0.5, 0.5), (x, -0.6, 4.05), GREYSTONE())


def village():
    import random
    random.seed(7)
    for (x, y, rot) in [(-1.7, -1.3, 0.2), (1.6, -1.5, -0.3), (-1.3, 1.7, 0.5), (1.9, 1.5, 0.0)]:
        s = 0.62
        box((3.0 * s, 2.8 * s, 2.3 * s), (x, y, 1.15 * s), MUDBRICK(), rot=(0, 0, rot))
        box((3.2 * s, 3.0 * s, 0.2 * s), (x, y, 2.35 * s), MUDBRICK(), rot=(0, 0, rot))
        box((0.45, 0.1, 0.8), (x + math.sin(rot) * 0.9, y + math.cos(rot) * 0.88, 0.45), DARKWOOD(), rot=(0, 0, -rot), bevel=0.0)
        if random.random() < 0.6:
            box((0.5, 0.5, 1.1), (x + 0.4, y - 0.3, 2.0), MUDBRICK(), rot=(0, 0, rot))
    cyl(0.6, 0.7, (0, 0, 0.35), GREYSTONE(), verts=16)
    cyl(0.45, 0.72, (0, 0, 0.37), flat("water", (0.1, 0.28, 0.36), 0.15), verts=16)
    for s in (-1, 1):
        cyl(0.05, 1.3, (0.55 * s, 0, 1.0), WOOD(), verts=6)
    cyl(0.05, 1.2, (0, 0, 1.6), WOOD(), verts=6, rot=(0, math.pi / 2, 0))
    flag((0.6, 1.0, 0.0), (0.85, 0.82, 0.72), "village", 3.4, 1.0)
    for i in range(6):
        cyl(0.25, 0.5, (-2.6 + i * 0.3, 0.2 + (i % 2) * 0.3, 0.25), flat("sack", (0.72, 0.6, 0.42)), verts=8, r2=0.18)


BUILDERS = {
    "keep_turan": lambda: keep(RED_TILE(), RED_TILE(), TURAN, door_y=-1),
    "house": house,
    "farm": farm,
    "woodcutter": woodcutter,
    "quarry": quarry,
    "barracks_iran": lambda: barracks(IRAN),
    "barracks_turan": lambda: barracks(TURAN),
    "tower_iran": lambda: tower(IRAN),
    "tower_turan": lambda: tower(TURAN),
    "wall": wall,
    "gate": gate,
    "village": village,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in BUILDERS.items():
        if ONLY and name not in ONLY:
            continue
        reset()
        _mats.clear()
        parts.clear()
        fn()
        bake_and_export(name)
