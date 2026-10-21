class_name Models
## Procedural placeholder models in a Persian style, plus the hook that swaps in real GLB
## models (e.g. from Meshy) dropped into res://assets/models/.
##
## File names the game looks for (first match wins):
##   units:     assets/models/units/<type>_<faction>.glb, then assets/models/units/<type>.glb
##              type = spear, archer, cav, immortal, hero, div ; faction = iran, turan
##   buildings: assets/models/buildings/<type>_<faction>.glb, then assets/models/buildings/<type>.glb
##              type = keep, house, farm, woodcutter, quarry, barracks, tower, wall, gate, village
## Models should face -Z (Godot forward) and stand on Y = 0. They are scaled to fit automatically.

const SKIN := Color("#d29b72")
const STEEL := Color("#b9c0c7")
const GOLD := Color("#e0b44a")
const WOOD := Color("#7a5230")
const WOOD_DARK := Color("#4f341d")
const SAND := Color("#dcc596")
const SAND_DARK := Color("#b89b68")
const STONE := Color("#bdb19a")
const STONE_DARK := Color("#8f846f")
const MUD := Color("#c9a677")
const TURQ := Color("#3fb4a6")
const LAPIS := Color("#27407a")

const FACTION_KEY := ["iran", "turan", "divs"]

static var _mats := {}
static var _meshes := {}
static var _templates := {}

## Pivots that stay separate nodes after baking, so they can be animated.
const ANIMATED := ["body", "leg_l", "leg_r", "arm_r", "arm_l", "horse", "neck", "hleg0", "hleg1", "hleg2", "hleg3"]


static func mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## Soft round particle: a camera-facing quad with a radial fade. Additive for fire and
## sparks, normal blending for smoke and dust.
static func soft_particle(size: float, c: Color, additive := false, energy := 1.0) -> QuadMesh:
	var key := "soft_%.2f_%s_%s_%.1f" % [size, c.to_html(), additive, energy]
	return _mesh(key, func():
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = gt
		m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
		m.no_depth_test = false
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		q.material = m
		return q)


static func _mesh(key: String, maker: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = maker.call()
	return _meshes[key]


static func box_mesh(s: Vector3) -> Mesh:
	return _mesh("b%s" % s, func():
		var m := BoxMesh.new()
		m.size = s
		return m)


static func cyl_mesh(top: float, bottom: float, h: float, seg := 10) -> Mesh:
	return _mesh("c%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg], func():
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		return m)


static func sphere_mesh(r: float, h: float, seg := 12, hemi := false) -> Mesh:
	return _mesh("s%.3f_%.3f_%d_%s" % [r, h, seg, hemi], func():
		var m := SphereMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = seg
		m.rings = maxi(4, seg / 2)
		m.is_hemisphere = hemi
		return m)


static func prism_mesh(s: Vector3) -> Mesh:
	return _mesh("p%s" % s, func():
		var m := PrismMesh.new()
		m.size = s
		return m)


static func torus_mesh(inner: float, outer: float) -> Mesh:
	return _mesh("t%.3f_%.3f" % [inner, outer], func():
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 6
		return m)


static func part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, rough := 0.85, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c, rough, metal)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n


# ---------------- GLB override ----------------
static func load_override(kind: String, type: String, owner: int, target_height: float, footprint := 0.0) -> Node3D:
	var faction: String = FACTION_KEY[clampi(owner, 0, 2)]
	for path in ["res://assets/models/%s/%s_%s.glb" % [kind, type, faction], "res://assets/models/%s/%s.glb" % [kind, type]]:
		if ResourceLoader.exists(path):
			var ps: PackedScene = load(path)
			if ps == null:
				continue
			var inst: Node3D = ps.instantiate()
			var holder := Node3D.new()
			holder.name = "GLB"
			holder.add_child(inst)
			var aabb := _aabb(inst, Transform3D.IDENTITY)
			if aabb.size.y > 0.001:
				var k := target_height / aabb.size.y
				if inst.find_child("TRUE_SCALE", true, false):
					k = 1.0   # our Blender models are made at real size
				elif footprint > 0.0:
					# buildings fill their footprint on the ground
					k = footprint / maxf(aabb.size.x, aabb.size.z)
				inst.scale = Vector3.ONE * k
				var rigged := inst.find_children("*", "Skeleton3D", true, false).size() > 0
				if rigged:
					# rigged soldiers are modelled around their feet; weapons must not shift them
					inst.position = Vector3(0, -aabb.position.y * k, 0)
				else:
					inst.position = Vector3(-aabb.get_center().x * k, -aabb.position.y * k, -aabb.get_center().z * k)
			return holder
	return null


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a := t * (n as MeshInstance3D).mesh.get_aabb()
		if (n as MeshInstance3D).skin != null:
			# skinned meshes are posed by their skeleton; the armature scale does not apply
			a = (n as MeshInstance3D).mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var a := _aabb(c, t)
		if a.size == Vector3.ZERO:
			continue
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


static func find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := find_anim_player(c)
		if a:
			return a
	return null


# ---------------- units ----------------
## Returns {root, rig: {body, leg_l, leg_r, arm_r, arm_l, horse legs...}, height, glb_anim}
static func make_unit(type: String, owner: int) -> Dictionary:
	var key := "u_%s_%d" % [type, owner]
	if not _templates.has(key):
		var built := _build_unit(type, owner)
		if built.get("glb", false):
			return built   # GLB models are used as-is
		built.root = bake(built.root)
		_templates[key] = built
	var tpl: Dictionary = _templates[key]
	var root: Node3D = tpl.root.duplicate()
	var rig := {}
	for nm in ANIMATED:
		var n := root.find_child(nm, true, false)
		if n:
			rig[nm] = n
	return {"root": root, "rig": rig, "height": tpl.height, "anim": null}


static func _build_unit(type: String, owner: int) -> Dictionary:
	var target_h := {"spear": 1.9, "archer": 1.85, "cav": 2.7, "immortal": 2.0, "hero": 2.5, "div": 3.6}
	var glb := load_override("units", type, owner, target_h.get(type, 2.0))
	if glb:
		return {"root": glb, "rig": {}, "height": target_h.get(type, 2.0), "anim": find_anim_player(glb), "glb": true}
	var root := Node3D.new()
	var rig := {}
	var tunic: Color = Defs.faction_color[owner]
	var dark: Color = Defs.faction_dark[owner]
	match type:
		"cav":
			var horse := _horse(root, Color("#6b4a2e") if owner == 0 else Color("#3a2c24"), tunic, rig)
			var rider := pivot(horse, Vector3(0, 1.25, 0.1), "rider")
			_humanoid(rider, tunic, dark, "cav", owner, rig, true)
			return {"root": root, "rig": rig, "height": 2.7, "anim": null}
		"div":
			var body := pivot(root, Vector3.ZERO, "scale")
			body.scale = Vector3.ONE * 1.85
			_humanoid(body, Color("#5d4a6e"), Color("#3a2c46"), "div", owner, rig, false)
			return {"root": root, "rig": rig, "height": 3.6, "anim": null}
		"hero":
			var body := pivot(root, Vector3.ZERO, "scale")
			body.scale = Vector3.ONE * 1.3
			var armour := Color("#b8782f") if owner == 0 else Color("#6b1d1a")
			_humanoid(body, armour, dark, "hero", owner, rig, false)
			return {"root": root, "rig": rig, "height": 2.5, "anim": null}
		_:
			_humanoid(root, tunic, dark, type, owner, rig, false)
			return {"root": root, "rig": rig, "height": 1.9, "anim": null}


static func _humanoid(root: Node3D, tunic: Color, dark: Color, type: String, owner: int, rig: Dictionary, mounted: bool) -> void:
	var skin := Color("#8a7a96") if type == "div" else SKIN
	var body := pivot(root, Vector3.ZERO, "body")
	rig["body"] = body
	if not mounted:
		for side in [-1, 1]:
			var hip := pivot(body, Vector3(0.12 * side, 0.86, 0), "leg_l" if side < 0 else "leg_r")
			part(hip, box_mesh(Vector3(0.17, 0.8, 0.2)), dark, Vector3(0, -0.4, 0))
			part(hip, box_mesh(Vector3(0.19, 0.12, 0.3)), WOOD_DARK, Vector3(0, -0.8, -0.04))
			rig["leg_l" if side < 0 else "leg_r"] = hip
	var y0 := 0.0 if not mounted else -0.75
	# torso and skirt
	part(body, box_mesh(Vector3(0.48, 0.62, 0.3)), tunic, Vector3(0, 1.2 + y0, 0))
	part(body, cyl_mesh(0.2, 0.3, 0.32, 8), tunic.darkened(0.15), Vector3(0, 0.84 + y0, 0))
	part(body, box_mesh(Vector3(0.5, 0.07, 0.32)), Color("#5a3b1e"), Vector3(0, 0.95 + y0, 0))
	if type in ["immortal", "hero", "spear"]:
		part(body, box_mesh(Vector3(0.5, 0.36, 0.32)), STEEL if type != "hero" else GOLD, Vector3(0, 1.32 + y0, 0), Vector3.ZERO, Vector3.ONE, 0.4, 0.6)
	# head
	var head := pivot(body, Vector3(0, 1.66 + y0, 0), "head")
	part(head, sphere_mesh(0.16, 0.34, 10), skin, Vector3.ZERO)
	if type != "div":
		part(head, box_mesh(Vector3(0.22, 0.14, 0.08)), Color("#2b1d14"), Vector3(0, -0.1, -0.12))  # beard
	match type:
		"spear":
			part(head, cyl_mesh(0.02, 0.18, 0.26, 8), STEEL, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.7)
		"archer":
			part(head, cyl_mesh(0.12, 0.17, 0.16, 8), tunic.lightened(0.2), Vector3(0, 0.12, 0))
		"immortal":
			part(head, cyl_mesh(0.17, 0.15, 0.3, 8), GOLD, Vector3(0, 0.18, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.8)
			part(head, box_mesh(Vector3(0.36, 0.3, 0.05)), tunic, Vector3(0, -0.02, 0.14))
		"cav":
			part(head, sphere_mesh(0.18, 0.2, 10, true), STEEL, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.7)
			part(head, cyl_mesh(0.005, 0.03, 0.22, 4), STEEL, Vector3(0, 0.25, 0))
		"hero":
			part(head, sphere_mesh(0.19, 0.22, 12, true), GOLD, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, 0.3, 0.85)
			if owner == 0:
				# Rostam's ox-head helmet horns
				for s in [-1, 1]:
					part(head, cyl_mesh(0.005, 0.04, 0.26, 5), Color("#efe6d2"), Vector3(0.16 * s, 0.16, 0), Vector3(0, 0, -0.7 * s))
			else:
				part(head, cyl_mesh(0.03, 0.03, 0.25, 6), Color("#7a1010"), Vector3(0, 0.26, 0))
		"div":
			for s in [-1, 1]:
				part(head, cyl_mesh(0.005, 0.05, 0.3, 5), Color("#e8dcc0"), Vector3(0.11 * s, 0.17, 0), Vector3(0, 0, -0.5 * s))
			part(head, sphere_mesh(0.035, 0.07, 6), Color("#ffd26a"), Vector3(-0.06, 0.02, -0.14))
			part(head, sphere_mesh(0.035, 0.07, 6), Color("#ffd26a"), Vector3(0.06, 0.02, -0.14))
	# arms
	var arm_r := pivot(body, Vector3(0.31, 1.45 + y0, 0), "arm_r")
	part(arm_r, box_mesh(Vector3(0.14, 0.58, 0.15)), tunic.darkened(0.1), Vector3(0, -0.27, 0))
	part(arm_r, sphere_mesh(0.07, 0.14, 6), skin, Vector3(0, -0.58, 0))
	rig["arm_r"] = arm_r
	var arm_l := pivot(body, Vector3(-0.31, 1.45 + y0, 0), "arm_l")
	part(arm_l, box_mesh(Vector3(0.14, 0.58, 0.15)), tunic.darkened(0.1), Vector3(0, -0.27, 0))
	part(arm_l, sphere_mesh(0.07, 0.14, 6), skin, Vector3(0, -0.58, 0))
	rig["arm_l"] = arm_l
	var hand_r := pivot(arm_r, Vector3(0, -0.58, 0), "hand_r")
	var hand_l := pivot(arm_l, Vector3(0, -0.58, 0), "hand_l")
	match type:
		"spear", "immortal", "cav":
			var len := 2.6 if type != "cav" else 3.0
			part(hand_r, cyl_mesh(0.025, 0.025, len, 5), WOOD, Vector3(0, 0.2, 0), Vector3(-PI / 2, 0, 0) if type == "cav" else Vector3.ZERO)
			var tip := Vector3(0, 0.2 + len / 2, 0) if type != "cav" else Vector3(0, 0.2, -len / 2)
			part(hand_r, cyl_mesh(0.0, 0.05, 0.22, 5), STEEL, tip, Vector3(-PI / 2, 0, 0) if type == "cav" else Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
			if type != "cav":
				var shield_c := tunic if type == "spear" else Color("#c9a24a")
				part(hand_l, box_mesh(Vector3(0.06, 0.62, 0.42)) if type == "immortal" else cyl_mesh(0.27, 0.27, 0.05, 12), shield_c, Vector3(-0.06, 0.1, -0.05), Vector3(0, 0, PI / 2) if type == "spear" else Vector3.ZERO)
		"archer":
			part(hand_l, torus_mesh(0.5, 0.54), WOOD_DARK, Vector3(0, 0.05, -0.1), Vector3(0, PI / 2, PI / 2), Vector3(1, 1, 0.45))
			part(body, cyl_mesh(0.08, 0.08, 0.6, 6), Color("#6b4423"), Vector3(0.12, 1.25, 0.2), Vector3(0.35, 0, 0.2))
		"hero":
			if owner == 0:
				part(hand_r, cyl_mesh(0.035, 0.035, 1.1, 6), WOOD_DARK, Vector3(0, 0.3, 0))
				part(hand_r, sphere_mesh(0.17, 0.3, 8), STEEL, Vector3(0, 0.9, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.7)  # gorz-e gavsar
				part(hand_r, cyl_mesh(0.005, 0.04, 0.18, 4), STEEL, Vector3(0.13, 1.0, 0), Vector3(0, 0, -0.9))
				part(hand_r, cyl_mesh(0.005, 0.04, 0.18, 4), STEEL, Vector3(-0.13, 1.0, 0), Vector3(0, 0, 0.9))
			else:
				part(hand_r, box_mesh(Vector3(0.06, 1.1, 0.02)), STEEL, Vector3(0, 0.55, 0), Vector3.ZERO, Vector3.ONE, 0.25, 0.85)
				part(hand_r, box_mesh(Vector3(0.28, 0.05, 0.06)), GOLD, Vector3(0, 0.02, 0))
			# cape
			part(body, box_mesh(Vector3(0.5, 0.9, 0.04)), Color("#7a1a1a") if owner == 0 else Color("#1e1e2a"), Vector3(0, 1.05, 0.2), Vector3(0.12, 0, 0))
		"div":
			part(hand_r, cyl_mesh(0.12, 0.05, 1.2, 6), WOOD_DARK, Vector3(0, 0.5, 0))


static func _horse(root: Node3D, coat: Color, cloth: Color, rig: Dictionary) -> Node3D:
	var horse := pivot(root, Vector3.ZERO, "horse")
	rig["body"] = horse
	part(horse, cyl_mesh(0.34, 0.34, 1.5, 10), coat, Vector3(0, 1.15, 0), Vector3(PI / 2, 0, 0))
	part(horse, sphere_mesh(0.34, 0.68, 10), coat, Vector3(0, 1.15, -0.72))
	part(horse, sphere_mesh(0.34, 0.68, 10), coat, Vector3(0, 1.15, 0.72))
	part(horse, box_mesh(Vector3(0.74, 0.08, 0.8)), cloth, Vector3(0, 1.48, 0.05))   # saddle cloth
	var neck := pivot(horse, Vector3(0, 1.35, -0.8), "neck")
	part(neck, box_mesh(Vector3(0.24, 0.7, 0.32)), coat, Vector3(0, 0.25, -0.1), Vector3(-0.5, 0, 0))
	part(neck, box_mesh(Vector3(0.22, 0.24, 0.55)), coat, Vector3(0, 0.55, -0.42), Vector3(0.3, 0, 0))
	part(neck, box_mesh(Vector3(0.06, 0.5, 0.2)), Color("#2a1a10"), Vector3(0, 0.38, 0.02), Vector3(-0.5, 0, 0))
	part(horse, cyl_mesh(0.03, 0.08, 0.7, 5), Color("#2a1a10"), Vector3(0, 1.0, 1.05), Vector3(0.6, 0, 0))
	var i := 0
	for p in [Vector3(-0.2, 0.95, -0.6), Vector3(0.2, 0.95, -0.6), Vector3(-0.2, 0.95, 0.6), Vector3(0.2, 0.95, 0.6)]:
		var leg := pivot(horse, p, "hleg%d" % i)
		part(leg, box_mesh(Vector3(0.13, 0.95, 0.15)), coat.darkened(0.1), Vector3(0, -0.47, 0))
		part(leg, box_mesh(Vector3(0.15, 0.12, 0.18)), Color("#1d140c"), Vector3(0, -0.92, 0))
		rig["hleg%d" % i] = leg
		i += 1
	return horse


# ---------------- buildings ----------------
static func make_building(type: String, owner: int, level := 1) -> Node3D:
	var key := "b_%s_%d_%d" % [type, owner, level]
	if not _templates.has(key):
		var built := _build_building(type, owner, level)
		if built.name == "GLB":
			return built
		_templates[key] = bake(built)
	return _templates[key].duplicate()


## Banners and gilding that show a building's level from afar: level 2 gets two banners
## at the front corners, level 3 gold caps and two more at the back, level 4 a gold ring.
static func level_marks(type: String, owner: int, level: int) -> Node3D:
	var root := Node3D.new()
	if level < 2 or type in ["keep", "village"]:
		return root
	var fc: Color = Defs.faction_color[clampi(owner, 0, 2)] if owner >= 0 else Color("#9a9488")
	var gold := Color("#d9a53a")
	var lapis := Color("#2a4fa8")
	if type in ["wall", "gate"]:
		part(root, box_mesh(Vector3(2.12, 0.18, 2.12)), lapis if level == 2 else gold, Vector3(0, 2.25, 0), Vector3.ZERO, Vector3.ONE, 0.5, 0.3 if level > 2 else 0.0)
		return root
	var h: float = Defs.BUILDINGS[type].size * Defs.CELL * 0.5 - 0.25
	var spots := [Vector3(-h, 0, h), Vector3(h, 0, h)]
	if level >= 3:
		spots += [Vector3(-h, 0, -h), Vector3(h, 0, -h)]
	var tall := 4.2 if type != "tower" else 3.0
	for p in spots:
		var base: Vector3 = p
		if type == "tower":
			base = Vector3(p.x * 0.35, 7.0, p.z * 0.35)
		part(root, cyl_mesh(0.05, 0.06, tall, 6), Color("#3b2a1c"), base + Vector3(0, tall * 0.5, 0))
		part(root, box_mesh(Vector3(0.04, 1.1, 0.75)), fc, base + Vector3(0, tall - 0.6, 0.4), Vector3.ZERO, Vector3.ONE, 0.9)
		part(root, box_mesh(Vector3(0.05, 0.14, 0.77)), gold, base + Vector3(0, tall - 1.12, 0.4), Vector3.ZERO, Vector3.ONE, 0.4, 0.6)
		if level >= 3:
			part(root, cyl_mesh(0.0, 0.12, 0.35, 8), gold, base + Vector3(0, tall + 0.15, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.8)
	if level >= 4:
		var r: float = h + 0.2
		for side in [-1.0, 1.0]:
			part(root, box_mesh(Vector3(r * 2.0, 0.12, 0.12)), gold, Vector3(0, 0.45, side * r), Vector3.ZERO, Vector3.ONE, 0.35, 0.8)
			part(root, box_mesh(Vector3(0.12, 0.12, r * 2.0)), gold, Vector3(side * r, 0.45, 0), Vector3.ZERO, Vector3.ONE, 0.35, 0.8)
	return root


static func _build_building(type: String, owner: int, level := 1) -> Node3D:
	var size: int = Defs.BUILDINGS[type].size
	var target := {"keep": 9.0 + level * 1.5, "house": 3.5, "farm": 2.5, "woodcutter": 3.2, "quarry": 3.0,
		"barracks": 4.5, "tower": 7.0, "wall": 3.2, "gate": 3.8, "village": 4.0}
	var fit := {"keep": 0.84 + level * 0.08, "tower": 1.1, "house": 0.9, "village": 0.95, "farm": 1.0, "barracks": 0.98}
	var glb := load_override("buildings", type, owner, target.get(type, 3.0), size * Defs.CELL * fit.get(type, 0.96))
	if glb:
		return glb
	var root := Node3D.new()
	var fc: Color = Defs.faction_color[clampi(owner, 0, 2)] if owner >= 0 else Color("#9a9488")
	var w := size * Defs.CELL
	match type:
		"keep": _keep(root, fc, level, owner)
		"house": _house(root)
		"woodcutter": _woodcutter(root)
		"quarry": _quarry(root)
		"farm": _farm(root, w)
		"barracks": _barracks(root, fc)
		"tower": _tower(root, fc)
		"wall": _wall(root)
		"gate": _gate(root)
		"village": _village(root, fc)
	return root


static func _merlons(root: Node3D, w: float, d: float, y: float, c: Color, step := 0.7, mw := 0.38) -> void:
	var nx := maxi(2, int(w / step))
	var nz := maxi(2, int(d / step))
	for i in nx:
		var x := -w / 2 + (i + 0.5) * w / nx
		part(root, box_mesh(Vector3(mw, 0.45, 0.3)), c, Vector3(x, y, -d / 2 + 0.15))
		part(root, box_mesh(Vector3(mw, 0.45, 0.3)), c, Vector3(x, y, d / 2 - 0.15))
	for i in nz:
		var z := -d / 2 + (i + 0.5) * d / nz
		part(root, box_mesh(Vector3(0.3, 0.45, mw)), c, Vector3(-w / 2 + 0.15, y, z))
		part(root, box_mesh(Vector3(0.3, 0.45, mw)), c, Vector3(w / 2 - 0.15, y, z))


static func _flag(root: Node3D, pos: Vector3, c: Color, h := 2.2) -> MeshInstance3D:
	part(root, cyl_mesh(0.04, 0.05, h, 5), WOOD_DARK, pos + Vector3(0, h / 2, 0))
	var f := part(root, box_mesh(Vector3(0.9, 0.55, 0.04)), c, pos + Vector3(0.47, h - 0.35, 0))
	f.name = "flag"
	part(root, sphere_mesh(0.07, 0.14, 6), GOLD, pos + Vector3(0, h + 0.05, 0), Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
	return f


static func _keep(root: Node3D, fc: Color, level: int, owner: int) -> void:
	var h := 5.0 + level * 1.6
	var roof := TURQ if owner == 0 else Color("#8a2f28")
	part(root, box_mesh(Vector3(7.8, 2.0, 7.8)), STONE_DARK, Vector3(0, -0.6, 0))
	part(root, box_mesh(Vector3(6.2, h, 6.2)), SAND, Vector3(0, 0.4 + h / 2, 0))
	part(root, box_mesh(Vector3(6.5, 0.3, 6.5)), SAND_DARK, Vector3(0, 0.4 + h, 0))
	_merlons(root, 6.4, 6.4, 0.4 + h + 0.35, SAND)
	# decorated band of glazed tiles
	part(root, box_mesh(Vector3(6.26, 0.35, 6.26)), LAPIS, Vector3(0, 0.4 + h - 0.8, 0), Vector3.ZERO, Vector3.ONE, 0.4)
	# gate arch facing the enemy side
	var door_z := -3.12 if owner == 0 else 3.12
	part(root, box_mesh(Vector3(1.6, 2.4, 0.2)), Color("#3b2a1a"), Vector3(0, 1.6, door_z))
	part(root, cyl_mesh(0.8, 0.8, 0.22, 12), Color("#3b2a1a"), Vector3(0, 2.8, door_z), Vector3(PI / 2, 0, 0))
	part(root, box_mesh(Vector3(2.3, 3.6, 0.15)), SAND_DARK, Vector3(0, 2.0, door_z * 1.02))
	# corner towers
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p := Vector3(3.1 * sx, 0, 3.1 * sz)
			part(root, cyl_mesh(1.0, 1.15, h + 2.0, 12), SAND.darkened(0.04), p + Vector3(0, 0.4 + (h + 2.0) / 2, 0))
			part(root, cyl_mesh(1.15, 1.15, 0.25, 12), LAPIS, p + Vector3(0, 0.4 + h + 1.2, 0))
			part(root, cyl_mesh(0.0, 1.25, 1.6, 12), roof, p + Vector3(0, 0.4 + h + 2.8, 0), Vector3.ZERO, Vector3.ONE, 0.45)
	# central dome
	var top := 0.4 + h
	part(root, cyl_mesh(1.7, 1.7, 1.2, 16), SAND, Vector3(0, top + 0.6, 0))
	part(root, sphere_mesh(1.75, 2.4, 18, true), roof, Vector3(0, top + 1.2, 0), Vector3.ZERO, Vector3(1, 1.25, 1), 0.35)
	part(root, cyl_mesh(0.05, 0.1, 0.9, 6), GOLD, Vector3(0, top + 3.6, 0), Vector3.ZERO, Vector3.ONE, 0.3, 0.9)
	part(root, sphere_mesh(0.16, 0.32, 8), GOLD, Vector3(0, top + 4.1, 0), Vector3.ZERO, Vector3.ONE, 0.3, 0.9)
	# hanging banners
	for sx in [-1.4, 1.4]:
		part(root, box_mesh(Vector3(0.8, 2.6, 0.06)), fc, Vector3(sx, top - 2.1, door_z * 1.03))
		part(root, sphere_mesh(0.18, 0.36, 8), GOLD, Vector3(sx, top - 1.8, door_z * 1.05), Vector3.ZERO, Vector3.ONE, 0.3, 0.8)
	_flag(root, Vector3(3.1, top + 3.6, 3.1), fc, 2.4)
	if level >= 2:
		part(root, box_mesh(Vector3(7.6, 1.6, 0.6)), STONE, Vector3(0, 0.8, -3.9))
		part(root, box_mesh(Vector3(7.6, 1.6, 0.6)), STONE, Vector3(0, 0.8, 3.9))
	if level >= 3:
		for sx in [-1, 1]:
			part(root, cyl_mesh(0.6, 0.6, 3.0, 10), SAND, Vector3(1.2 * sx, top + 1.5, -1.2 * sx))
			part(root, sphere_mesh(0.62, 0.9, 10, true), GOLD, Vector3(1.2 * sx, top + 3.0, -1.2 * sx), Vector3.ZERO, Vector3.ONE, 0.3, 0.85)


static func _house(root: Node3D) -> void:
	part(root, box_mesh(Vector3(3.2, 0.6, 3.2)), STONE_DARK, Vector3(0, -0.1, 0))
	part(root, box_mesh(Vector3(3.0, 2.2, 2.8)), MUD, Vector3(0, 1.3, 0))
	part(root, box_mesh(Vector3(3.15, 0.18, 2.95)), MUD.darkened(0.15), Vector3(0, 2.45, 0))
	part(root, box_mesh(Vector3(0.7, 1.3, 0.1)), WOOD_DARK, Vector3(-0.6, 0.85, -1.42))
	part(root, box_mesh(Vector3(0.45, 0.45, 0.1)), Color("#2a1d12"), Vector3(0.7, 1.5, -1.42))
	# badgir (wind-catcher)
	part(root, box_mesh(Vector3(0.75, 1.6, 0.75)), MUD.lightened(0.05), Vector3(0.8, 3.2, 0.6))
	for s in [-1, 1]:
		part(root, box_mesh(Vector3(0.12, 0.6, 0.78)), Color("#3a2a1c"), Vector3(0.8 + 0.25 * s, 3.55, 0.6))
	part(root, box_mesh(Vector3(0.9, 0.12, 0.9)), MUD.darkened(0.1), Vector3(0.8, 4.05, 0.6))


static func _woodcutter(root: Node3D) -> void:
	part(root, box_mesh(Vector3(2.2, 1.8, 2.0)), WOOD, Vector3(-0.6, 0.9, 0.4))
	part(root, prism_mesh(Vector3(2.5, 1.1, 2.2)), WOOD_DARK, Vector3(-0.6, 2.35, 0.4))
	part(root, box_mesh(Vector3(0.6, 1.1, 0.08)), Color("#2b1d12"), Vector3(-0.6, 0.6, -0.62))
	for i in 3:
		for j in 3 - i:
			part(root, cyl_mesh(0.2, 0.2, 1.6, 7), Color("#a7774a"), Vector3(1.2, 0.2 + i * 0.36, -0.9 + j * 0.42 + i * 0.21), Vector3(0, 0, PI / 2))
	part(root, cyl_mesh(0.32, 0.36, 0.5, 8), Color("#8a6a45"), Vector3(1.0, 0.25, 1.0))
	part(root, box_mesh(Vector3(0.05, 0.6, 0.05)), WOOD_DARK, Vector3(1.0, 0.75, 1.0), Vector3(0, 0, 0.4))


static func _quarry(root: Node3D) -> void:
	part(root, cyl_mesh(1.4, 1.2, 0.3, 10), Color("#5d564c"), Vector3(0.4, 0.0, 0.3))
	for p in [Vector3(-1.1, 0.35, -0.9), Vector3(-0.4, 0.35, -1.1), Vector3(-1.2, 0.35, -0.2), Vector3(-0.8, 1.0, -0.7)]:
		part(root, box_mesh(Vector3(0.65, 0.65, 0.65)), STONE.lightened(0.05), p, Vector3(0, randf() * 0.4, 0))
	# wooden crane
	part(root, cyl_mesh(0.08, 0.08, 3.2, 6), WOOD, Vector3(1.0, 1.6, -0.8))
	part(root, cyl_mesh(0.06, 0.06, 2.4, 6), WOOD, Vector3(0.4, 3.0, -0.8), Vector3(0, 0, 1.25))
	part(root, cyl_mesh(0.01, 0.01, 1.5, 4), Color("#d8c9a8"), Vector3(-0.4, 2.4, -0.8))
	part(root, box_mesh(Vector3(0.4, 0.3, 0.4)), STONE, Vector3(-0.4, 1.55, -0.8))
	part(root, box_mesh(Vector3(1.3, 1.2, 1.1)), WOOD_DARK, Vector3(1.2, 0.6, 1.1))


static func _farm(root: Node3D, w: float) -> void:
	part(root, box_mesh(Vector3(w - 0.2, 0.12, w - 0.2)), Color("#7a5a36"), Vector3(0, 0.05, 0))
	var rows := 7
	for i in rows:
		var z := -w / 2 + 0.6 + i * (w - 1.6) / (rows - 1)
		part(root, box_mesh(Vector3(w - 1.6, 0.55, 0.35)), Color("#d9b552").lerp(Color("#c9a040"), randf()), Vector3(-0.2, 0.38, z))
	part(root, box_mesh(Vector3(1.2, 1.3, 1.2)), MUD, Vector3(w / 2 - 0.8, 0.65, w / 2 - 0.8))
	part(root, prism_mesh(Vector3(1.4, 0.6, 1.3)), Color("#c8a04b"), Vector3(w / 2 - 0.8, 1.6, w / 2 - 0.8))
	for i in 8:
		var t := -w / 2 + i * w / 7.0
		part(root, cyl_mesh(0.04, 0.04, 0.7, 4), WOOD, Vector3(t, 0.35, -w / 2 + 0.05))
	part(root, box_mesh(Vector3(w, 0.05, 0.05)), WOOD, Vector3(0, 0.55, -w / 2 + 0.05))


static func _barracks(root: Node3D, fc: Color) -> void:
	part(root, box_mesh(Vector3(5.6, 0.5, 4.6)), STONE_DARK, Vector3(0, 0.0, 0))
	part(root, box_mesh(Vector3(5.2, 2.8, 3.6)), SAND, Vector3(0, 1.6, 0.3))
	part(root, prism_mesh(Vector3(5.5, 1.2, 3.9)), Color("#9c5b37"), Vector3(0, 3.6, 0.3), Vector3(0, PI / 2, 0), Vector3(3.9 / 5.5, 1, 5.5 / 3.9))
	for x in [-1.8, -0.6, 0.6, 1.8]:
		part(root, cyl_mesh(0.14, 0.16, 2.6, 8), SAND.lightened(0.1), Vector3(x, 1.5, -1.65))
	part(root, box_mesh(Vector3(5.2, 0.3, 0.4)), LAPIS, Vector3(0, 2.9, -1.6))
	_flag(root, Vector3(-2.3, 0.2, -2.0), fc, 3.6)
	_flag(root, Vector3(2.3, 0.2, -2.0), fc, 3.6)
	# weapon rack
	for i in 4:
		part(root, cyl_mesh(0.02, 0.02, 1.8, 4), WOOD, Vector3(-1.0 + i * 0.25, 0.9, -2.15), Vector3(0.15, 0, 0))


static func _tower(root: Node3D, fc: Color) -> void:
	part(root, cyl_mesh(1.0, 1.15, 6.0, 12), STONE, Vector3(0, 3.0, 0))
	part(root, cyl_mesh(1.2, 1.0, 0.5, 12), STONE_DARK, Vector3(0, 6.2, 0))
	for i in 8:
		var a := i * TAU / 8.0
		part(root, box_mesh(Vector3(0.38, 0.5, 0.3)), STONE, Vector3(cos(a) * 1.05, 6.7, sin(a) * 1.05), Vector3(0, -a, 0))
	part(root, box_mesh(Vector3(0.12, 0.7, 0.12)), Color("#2a1d12"), Vector3(0, 4.2, -1.08))
	part(root, box_mesh(Vector3(0.12, 0.7, 0.12)), Color("#2a1d12"), Vector3(0, 2.4, 1.1))
	_flag(root, Vector3(0, 6.4, 0), fc, 1.8)


static func _wall(root: Node3D) -> void:
	part(root, box_mesh(Vector3(2.02, 3.2, 2.02)), STONE, Vector3(0, 1.1, 0))
	part(root, box_mesh(Vector3(2.06, 0.25, 2.06)), STONE_DARK, Vector3(0, 2.6, 0))
	for x in [-0.6, 0.6]:
		for z in [-0.6, 0.6]:
			part(root, box_mesh(Vector3(0.5, 0.45, 0.5)), STONE, Vector3(x, 2.95, z))


static func _gate(root: Node3D) -> void:
	for s in [-1, 1]:
		part(root, box_mesh(Vector3(0.5, 3.8, 2.02)), STONE, Vector3(0.76 * s, 1.4, 0))
	part(root, box_mesh(Vector3(2.02, 0.8, 2.02)), STONE, Vector3(0, 3.1, 0))
	part(root, box_mesh(Vector3(1.0, 2.3, 0.12)), Color("#5b3a1e"), Vector3(0, 1.15, 0))
	for y in [0.5, 1.2, 1.9]:
		part(root, box_mesh(Vector3(1.02, 0.08, 0.16)), Color("#2b2b2b"), Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, 0.5, 0.6)
	for x in [-0.6, 0.0, 0.6]:
		part(root, box_mesh(Vector3(0.45, 0.45, 0.5)), STONE, Vector3(x, 3.7, 0))


static func _village(root: Node3D, fc: Color) -> void:
	for p in [Vector3(-1.6, 0, -1.2), Vector3(1.5, 0, -1.4), Vector3(-1.2, 0, 1.6), Vector3(1.8, 0, 1.4)]:
		var h := pivot(root, p, "house")
		h.scale = Vector3.ONE * 0.62
		h.rotation.y = randf() * 0.6
		_house(h)
	part(root, cyl_mesh(0.55, 0.6, 0.6, 10), STONE, Vector3(0, 0.3, 0))
	part(root, cyl_mesh(0.42, 0.42, 0.62, 10), Color("#24485a"), Vector3(0, 0.32, 0))
	_flag(root, Vector3(0.4, 0, 0.9), fc, 3.4)


# ---------------- baking ----------------
## Merges a tree of primitive parts into one mesh per animated pivot (two surfaces:
## matte and metal), which cuts draw calls from dozens to a handful per model.
static func bake(src: Node3D) -> Node3D:
	var dst := Node3D.new()
	if src.name != "":
		dst.name = src.name
	var acc := {}
	_bake_into(src, dst, Transform3D.IDENTITY, acc)
	_finish(dst, acc)
	src.free()
	return dst


static func _bake_into(src: Node3D, dst: Node3D, xf: Transform3D, acc: Dictionary) -> void:
	for c in src.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			_acc_mesh(acc, mi.mesh, xf * mi.transform, m.albedo_color, m.metallic > 0.3)
		elif c is Node3D:
			if ANIMATED.has(String(c.name)):
				var nd := Node3D.new()
				nd.name = c.name
				nd.transform = xf * (c as Node3D).transform
				dst.add_child(nd)
				var acc2 := {}
				_bake_into(c, nd, Transform3D.IDENTITY, acc2)
				_finish(nd, acc2)
			else:
				_bake_into(c, dst, xf * (c as Node3D).transform, acc)


static func _acc_mesh(acc: Dictionary, mesh: Mesh, xf: Transform3D, col: Color, metal: bool) -> void:
	var key := "metal" if metal else "matte"
	if not acc.has(key):
		acc[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	var a: Dictionary = acc[key]
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var base: int = a.v.size()
	var nb := xf.basis.inverse().transposed()
	for i in verts.size():
		a.v.append(xf * verts[i])
		a.n.append((nb * norms[i]).normalized())
		a.c.append(col)
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx == null or idx.size() == 0:
		for i in verts.size():
			a.i.append(base + i)
	else:
		for i in idx:
			a.i.append(base + i)


static var _vc_matte: StandardMaterial3D
static var _vc_metal: StandardMaterial3D


static func _finish(dst: Node3D, acc: Dictionary) -> void:
	if acc.is_empty():
		return
	if _vc_matte == null:
		_vc_matte = StandardMaterial3D.new()
		_vc_matte.vertex_color_use_as_albedo = true
		_vc_matte.vertex_color_is_srgb = true
		_vc_matte.roughness = 0.82
		_vc_metal = StandardMaterial3D.new()
		_vc_metal.vertex_color_use_as_albedo = true
		_vc_metal.vertex_color_is_srgb = true
		_vc_metal.roughness = 0.35
		_vc_metal.metallic = 0.75
	var am := ArrayMesh.new()
	for key in ["matte", "metal"]:
		if not acc.has(key):
			continue
		var a: Dictionary = acc[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a.v
		arrays[Mesh.ARRAY_NORMAL] = a.n
		arrays[Mesh.ARRAY_COLOR] = a.c
		arrays[Mesh.ARRAY_INDEX] = a.i
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, _vc_matte if key == "matte" else _vc_metal)
	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	mi.mesh = am
	dst.add_child(mi)
	dst.move_child(mi, 0)
