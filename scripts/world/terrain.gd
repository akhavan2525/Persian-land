class_name Terrain
extends Node3D
## Builds the battlefield: height-mapped ground, lakes, forests, stone outcrops and the
## mountain ring. Also answers "what is at this cell?" questions for building and pathing.

enum { GRASS, FOREST, ROCK, WATER, MOUNTAIN }

const G := Defs.GRID
const CELL := Defs.CELL
const HALF := Defs.HALF
const RES := 1.0                       # height samples per metre
const N := int(Defs.GRID * Defs.CELL) + 1  # samples per side

var heights := PackedFloat32Array()
var cell_type := PackedByteArray()
var terrain_material: ShaderMaterial
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

var _lakes := [Vector3(-38, -36, 13.0), Vector3(38, 36, 13.0), Vector3(-6, 28, 6.0), Vector3(6, -28, 6.0)]
var _forests := [Vector3(-62, 22, 13.0), Vector3(-26, 60, 12.0), Vector3(22, -62, 13.0), Vector3(62, -26, 12.0),
	Vector3(-14, -12, 9.0), Vector3(14, 12, 9.0), Vector3(-52, -6, 9.0), Vector3(52, 6, 9.0), Vector3(-30, 6, 7.0), Vector3(30, -6, 7.0)]
var _rocks := [Vector3(-30, 56, 5.5), Vector3(-62, 34, 4.5), Vector3(30, -56, 5.5), Vector3(62, -34, 4.5),
	Vector3(-4, -2, 4.0), Vector3(4, 2, 4.0), Vector3(-18, 30, 4.0), Vector3(18, -30, 4.0)]


func build(seed_value: int) -> void:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	detail.seed = seed_value + 7
	detail.frequency = 0.09
	_make_heights()
	_classify()
	_build_ground_mesh()
	_build_water()
	_build_far_ground()
	_scatter_trees()
	_scatter_rocks()


# ---------------- height field ----------------
func _raw_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 1.6 + detail.get_noise_2d(x, z) * 0.25
	# mountain ring at the map edge
	var e := maxf(absf(x), absf(z)) / HALF
	if e > 0.8:
		var k := (e - 0.8) / 0.2
		h += k * k * 16.0 + noise.get_noise_2d(x * 3.0, z * 3.0) * 3.0 * k
	# flat ground around both castles and villages
	for kc in Defs.KEEP_CELL:
		var c := cell_center_flat(kc)
		var d := Vector2(x - c.x, z - c.z).length()
		var f := clampf((d - 16.0) / 10.0, 0.0, 1.0)
		h = lerpf(0.35, h, f)
	for vc in Defs.VILLAGE_CELLS:
		var c := cell_center_flat(vc)
		var d := Vector2(x - c.x, z - c.z).length()
		h = lerpf(0.3, h, clampf((d - 6.0) / 6.0, 0.0, 1.0))
	for l in _lakes:
		var d := Vector2(x - l.x, z - l.y).length()
		if d < l.z * 1.6:
			var k := 1.0 - clampf(d / (l.z * 1.6), 0.0, 1.0)
			h -= smoothstep(0.0, 1.0, k) * 3.2
	for r in _rocks:
		var d := Vector2(x - r.x, z - r.y).length()
		if d < r.z * 1.8:
			h += (1.0 - d / (r.z * 1.8)) * 1.4
	return h


func _make_heights() -> void:
	heights.resize(N * N)
	for j in N:
		for i in N:
			heights[j * N + i] = _raw_height(i - HALF, j - HALF)


func height_at(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, N - 1.001)
	var fz := clampf(z + HALF, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


# ---------------- cells ----------------
static func cell_center_flat(c: Vector2i) -> Vector3:
	return Vector3(-HALF + (c.x + 0.5) * CELL, 0.0, -HALF + (c.y + 0.5) * CELL)


func cell_center(c: Vector2i) -> Vector3:
	var p := cell_center_flat(c)
	p.y = height_at(p.x, p.z)
	return p


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x + HALF) / CELL)), 0, G - 1), clampi(int(floor((p.z + HALF) / CELL)), 0, G - 1))


static func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < G and c.y < G


func type_at(c: Vector2i) -> int:
	if not in_grid(c):
		return MOUNTAIN
	return cell_type[c.y * G + c.x]


func walkable(c: Vector2i) -> bool:
	var t := type_at(c)
	return t == GRASS or t == FOREST


func _in_blob(p: Vector3, list: Array, scale := 1.0) -> float:
	var best := 0.0
	for b in list:
		var d: float = Vector2(p.x - b.x, p.z - b.y).length() / (b.z * scale)
		best = maxf(best, 1.0 - d)
	return best


func _classify() -> void:
	cell_type.resize(G * G)
	for j in G:
		for i in G:
			var c := Vector2i(i, j)
			var p := cell_center(c)
			var lo := INF
			var hi := -INF
			for dx in [-0.9, 0.9]:
				for dz in [-0.9, 0.9]:
					var h := height_at(p.x + dx, p.z + dz)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			var t := GRASS
			if lo < Defs.WATER_LEVEL + 0.1:
				t = WATER
			elif p.y > 3.2 or hi - lo > 1.6:
				t = MOUNTAIN
			elif _in_blob(p, _rocks) > 0.0:
				t = ROCK
			elif _in_blob(p, _forests) + detail.get_noise_2d(p.x * 2.0, p.z * 2.0) * 0.35 > 0.15:
				t = FOREST
			cell_type[j * G + i] = t
	# keep castle and village grounds clear
	for kc in Defs.KEEP_CELL:
		_clear_area(kc, 7)
	for vc in Defs.VILLAGE_CELLS:
		_clear_area(vc, 3)


func _clear_area(c: Vector2i, r: int) -> void:
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			if in_grid(Vector2i(i, j)) and cell_type[j * G + i] != WATER:
				cell_type[j * G + i] = GRASS


# ---------------- ground mesh ----------------
func _ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := noise.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5
	var grass := Color("#6f9a3e").lerp(Color("#9aa84a"), n)
	grass = grass.lerp(Color("#b7a65c"), clampf(detail.get_noise_2d(x * 0.7, z * 0.7) * 0.8, 0.0, 0.55))
	var c := grass
	var forest := _in_blob(Vector3(x, 0, z), _forests)
	if forest > 0.0:
		c = c.lerp(Color("#4c6f2c"), clampf(forest * 2.0, 0.0, 0.8))
	if h < Defs.WATER_LEVEL + 0.35:
		c = c.lerp(Color("#cdb88a"), clampf((Defs.WATER_LEVEL + 0.35 - h) * 2.5, 0.0, 1.0))
	if h < Defs.WATER_LEVEL - 0.3:
		c = Color("#7d7356")
	var rock := clampf((slope - 0.55) * 2.5, 0.0, 1.0)
	rock = maxf(rock, clampf((h - 2.8) * 0.6, 0.0, 1.0))
	rock = maxf(rock, clampf(_in_blob(Vector3(x, 0, z), _rocks, 1.3) * 2.2, 0.0, 0.85))
	c = c.lerp(Color("#8d8578").lerp(Color("#6e675d"), n), rock)
	if h > 9.0:
		c = c.lerp(Color("#f2efe8"), clampf((h - 9.0) * 0.35, 0.0, 1.0))
	return c


func _build_ground_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 1
	var verts := N
	for j in verts:
		for i in verts:
			var x := i - HALF
			var z := j - HALF
			var h := heights[j * N + i]
			var hx := heights[j * N + mini(i + 1, N - 1)] - heights[j * N + maxi(i - 1, 0)]
			var hz := heights[mini(j + 1, N - 1) * N + i] - heights[maxi(j - 1, 0) * N + i]
			var nrm := Vector3(-hx * 0.5, 1.0, -hz * 0.5).normalized()
			var slope := 1.0 - nrm.y
			st.set_color(_ground_color(x, z, h, slope * 4.0))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h, z))
	for j in range(0, verts - 1, step):
		for i in range(0, verts - 1, step):
			var a := j * verts + i
			var b := a + 1
			var c := a + verts
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://assets/shaders/terrain.gdshader")
	mi.material_override = terrain_material
	add_child(mi)


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2.0, HALF * 2.0)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	mi.mesh = pm
	mi.position.y = Defs.WATER_LEVEL
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_far_ground() -> void:
	# a wide skirt of mountains/ground so the camera never sees the void
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	mi.mesh = pm
	mi.position.y = -2.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#7c7466")
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------- decoration ----------------
func _multimesh(mesh: Mesh, xforms: Array, colors: Array, mat: Material, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static func vc_material(rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	return m


func _scatter_trees() -> void:
	var cypress := SphereMesh.new()
	cypress.radius = 0.75
	cypress.height = 4.6
	cypress.radial_segments = 8
	cypress.rings = 6
	var round_top := SphereMesh.new()
	round_top.radius = 1.5
	round_top.height = 2.6
	round_top.radial_segments = 8
	round_top.rings = 5
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.22
	trunk.height = 1.6
	trunk.radial_segments = 5
	var cx := []; var cc := []; var rx := []; var rc := []; var tx := []; var tc := []
	for j in G:
		for i in G:
			if cell_type[j * G + i] != FOREST:
				continue
			var base := cell_center(Vector2i(i, j))
			var count := 1 + rng.randi() % 2
			for _k in count:
				var p := base + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
				p.y = height_at(p.x, p.z)
				var s := rng.randf_range(0.8, 1.25)
				var rot := Basis(Vector3.UP, rng.randf() * TAU)
				tx.append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 0.75 * s, 0)))
				tc.append(Color("#5d4128"))
				if rng.randf() < 0.55:
					cx.append(Transform3D(rot.scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), p + Vector3(0, 2.6 * s, 0)))
					cc.append(Color("#2f5a2c").lerp(Color("#3f6d33"), rng.randf()))
				else:
					rx.append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 2.3 * s, 0)))
					rc.append(Color("#4f7a2e").lerp(Color("#6b8f35"), rng.randf()))
	var leaf := vc_material(0.85)
	_multimesh(trunk, tx, tc, vc_material())
	_multimesh(cypress, cx, cc, leaf)
	_multimesh(round_top, rx, rc, leaf)


func _scatter_rocks() -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.4
	rock.radial_segments = 6
	rock.rings = 3
	var xs := []; var cs := []
	for j in G:
		for i in G:
			if cell_type[j * G + i] != ROCK:
				continue
			var base := cell_center(Vector2i(i, j))
			for _k in 2:
				var p := base + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
				p.y = height_at(p.x, p.z)
				var s := Vector3(rng.randf_range(0.6, 1.2), rng.randf_range(0.5, 1.1), rng.randf_range(0.6, 1.2))
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
				xs.append(Transform3D(b.scaled(s), p + Vector3(0, 0.25, 0)))
				cs.append(Color("#9a9286").lerp(Color("#76706a"), rng.randf()))
	_multimesh(rock, xs, cs, vc_material(1.0))


func _scatter_grass() -> void:
	var blade := PrismMesh.new()
	blade.size = Vector3(0.22, 0.38, 0.05)
	var xs := []; var cs := []
	var tries := 0
	while xs.size() < 6000 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-HALF * 0.82, HALF * 0.82)
		var z := rng.randf_range(-HALF * 0.82, HALF * 0.82)
		var c := cell_of(Vector3(x, 0, z))
		if type_at(c) != GRASS:
			continue
		var h := height_at(x, z)
		var s := rng.randf_range(0.6, 1.3)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h + 0.2 * s, z)))
		cs.append(Color("#4f7a2a").lerp(Color("#7f9a3a"), rng.randf()))
	_multimesh(blade, xs, cs, vc_material(1.0), false)


# ---------------- territory overlay ----------------
func set_zones(zones: Array) -> void:
	# zones: [Vector4(x, z, radius, owner)], at most 12
	var arr := PackedFloat32Array()
	arr.resize(48)
	for i in mini(zones.size(), 12):
		var z: Vector4 = zones[i]
		arr[i * 4] = z.x
		arr[i * 4 + 1] = z.y
		arr[i * 4 + 2] = z.z
		arr[i * 4 + 3] = z.w
	terrain_material.set_shader_parameter("zones", arr)
	terrain_material.set_shader_parameter("zone_count", mini(zones.size(), 12))


func set_grid_visible(v: bool) -> void:
	terrain_material.set_shader_parameter("grid_alpha", 0.35 if v else 0.0)
