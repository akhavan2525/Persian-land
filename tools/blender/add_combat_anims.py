"""Adds idle and attack clips to rigged character GLBs (e.g. from Meshy) in Blender.

    python add_combat_anims.py <in.glb> <out.glb> <style>

style: swing (overhead blow with mace, sword or club), thrust (spear), bow (draw and loose).
Works with Mixamo-style bone names (Hips, Spine, RightArm, RightForeArm, ...).
Poses are given as rotations around the character's own axes, so they do not depend on
how each bone's local axes were set up by the rigger. The walk clip is kept as it is.
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

IN, OUT, STYLE = sys.argv[1], sys.argv[2], sys.argv[3]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
bones = arm.pose.bones

# character axes in armature space: work out forward from the feet/toes and up from the spine
hips = arm.data.bones["Hips"].head_local
head = arm.data.bones["Head"].head_local
UP = (head - hips).normalized()
lt = arm.data.bones.get("LeftToeBase") or arm.data.bones["LeftFoot"]
lf = arm.data.bones["LeftFoot"]
fwd = lt.head_local - lf.head_local
fwd = (fwd - UP * fwd.dot(UP)).normalized()
if "headfront" in arm.data.bones:
    hf = arm.data.bones["headfront"]
    fwd = (hf.tail_local - hf.head_local)
    fwd = (fwd - UP * fwd.dot(UP)).normalized()
FWD = fwd
RIGHT = FWD.cross(UP).normalized()      # character's right hand side
print("up", UP, "forward", FWD, "right", RIGHT)

# rotation axes: "pitch" swings a hanging limb forward (positive) / bends the spine forward,
# "yaw" turns around the up axis (positive turns the chest to the left), "roll" tips sideways
AX = {"pitch": RIGHT, "yaw": UP, "roll": FWD}


def has(n):
    return n in bones


ORDER = [b.name for b in arm.data.bones]   # parents come before children


def apply_pose(pose):
    """pose: {bone: [(axis, degrees), ...]} in character space, applied parent-first."""
    for pb in bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for name in ORDER:
        if name not in pose:
            continue
        pb = bones[name]
        m0 = pb.matrix.copy()
        r = Matrix.Identity(3)
        for axis, deg in pose[name]:
            # pitch about RIGHT: positive moves a downward limb towards FWD
            r = Matrix.Rotation(math.radians(deg) * (-1 if axis == "pitch" else 1), 3, AX[axis]) @ r
        h = m0.to_translation()
        m = Matrix.Translation(h) @ r.to_4x4() @ Matrix.Translation(-h) @ m0
        pb.matrix = m
        bpy.context.view_layer.update()


def key(frame):
    for pb in bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)


def make_action(name, frames):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for f, pose in frames:
        apply_pose(pose)
        key(f)
    return act


def P(**kw):
    """Shorthand: P(RightArm=[('pitch', 60)], ...)."""
    return kw


# check the pitch sign once: a forward swing must move the right hand forward
apply_pose({})
hand0 = (arm.matrix_world @ bones["RightHand"].head).copy()
apply_pose({"RightArm": [("pitch", 60)]})
hand1 = (arm.matrix_world @ bones["RightHand"].head).copy()
fw_world = (arm.matrix_world.to_3x3() @ FWD).normalized()
if (hand1 - hand0).dot(fw_world) < 0:
    print("pitch sign flipped")
    AX["pitch"] = -RIGHT

# arms come down from the rig's A/T pose to the sides
arms_down = {"LeftArm": [("roll", -18)], "RightArm": [("roll", 18)]}
if STYLE == "bow":
    base = dict(arms_down)
else:
    base = {"LeftArm": [("roll", -18)], "RightArm": [("roll", 18), ("pitch", 15)], "RightForeArm": [("pitch", 35)]}


def merge(*ps):
    out = {}
    for p in ps:
        for k, v in p.items():
            out[k] = out.get(k, []) + list(v)
    return out


breath = P(Spine01=[("pitch", 2)], Head=[("pitch", -2), ("yaw", 4)])
make_action("idle_loop", [(1, base), (25, merge(base, breath)), (49, base)])

if STYLE == "swing":
    wind = merge(base, P(RightArm=[("pitch", 150), ("roll", 10)], RightForeArm=[("pitch", 30)],
                         Spine01=[("yaw", 18), ("pitch", -6)], LeftArm=[("pitch", 30)]))
    hit = merge(base, P(RightArm=[("pitch", 22)], RightForeArm=[("pitch", 10)],
                        Spine01=[("yaw", -22), ("pitch", 18)], Spine=[("pitch", 6)], Head=[("pitch", -10)],
                        LeftUpLeg=[("pitch", 25)], LeftLeg=[("pitch", -20)], RightUpLeg=[("pitch", -12)], LeftArm=[("pitch", -20)]))
    make_action("attack", [(1, base), (7, wind), (10, hit), (13, hit), (20, base)])
elif STYLE == "thrust":
    wind = merge(base, P(RightArm=[("pitch", -25)], RightForeArm=[("pitch", 70)], Spine01=[("yaw", 20)]))
    hit = merge(base, P(RightArm=[("pitch", 75)], RightForeArm=[("pitch", -20)], Spine01=[("yaw", -18), ("pitch", 14)],
                        LeftUpLeg=[("pitch", 30)], LeftLeg=[("pitch", -25)], RightUpLeg=[("pitch", -15)], LeftArm=[("pitch", 40)]))
    make_action("attack", [(1, base), (6, wind), (9, hit), (12, hit), (18, base)])
else:
    draw = merge(base, P(LeftArm=[("pitch", 90), ("roll", 18)], RightArm=[("pitch", 85), ("yaw", 30)],
                         RightForeArm=[("yaw", 100)], Spine01=[("yaw", -25)], Head=[("yaw", 25)]))
    loose = merge(draw, P(RightForeArm=[("yaw", -50)], RightArm=[("yaw", -15)]))
    make_action("attack", [(1, base), (8, draw), (13, draw), (15, loose), (22, base)])

# leave the rig at rest so the exported bind pose is unchanged
for pb in bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
arm.animation_data.action = bpy.data.actions["idle_loop"]
# phones do not need 4K textures; 1024 keeps the install file small
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, int(1024 * img.size[1] / img.size[0]))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_image_format="JPEG", export_jpeg_quality=88, export_skins=True)
print("exported", OUT, [a.name for a in bpy.data.actions])
