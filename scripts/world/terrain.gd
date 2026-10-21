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
var tree_cells := {}               # cell index -> true where a tree trunk stands
var terrain_material: ShaderMaterial
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

var _lakes := [Vector3(-38, -36, 13.0), Vector3(38, 36, 13.0), Vector3(-6, 28, 6.0), Vector3(6, -28, 6.0)]
var _forests := [Vector3(-62, 22, 13.0), Vector3(-26, 60, 12.0), Vector3(22, -62, 13.0), Vector3(62, -26, 12.0),
	Vector3(-14, -12, 9.0), Vector3(14, 12, 9.0), Vector3(-52, -6, 9.0), Vector3(52, 6, 9.0), Vector3(-30, 6, 7.0), Vector3(30, -6, 7.0)]
var _rocks := [Vector3(-30, 56, 5.5), Vector3(-62, 34, 4.5), Vector3(30, -56, 5.5), Vector3(62, -34, 4.5),
	Vector3(-4, -2, 4.0), Vector3(4, 2, 4.0), Vector3(-18, 30, 4.0), Vector3(18, -30, 4.0)]


var biome := "meadow"
# materials the coming of winter repaints (see set_winter)
var _water_mat: ShaderMaterial
var _far_mat: StandardMaterial3D
var _leaf_mats: Array = []
var _bare_mats: Array = []      # leaves of the plane trees, which fall in winter
var _bark_mats: Array = []
var _grass_mat: StandardMaterial3D
var _chenar := [[], []]          # plane tree transforms per model, for their winter twins
var _chenar_mmis: Array = []     # the leafy plane trees
var _snow_mmis: Array = []       # the same trees bare and snowy (built when the snow comes)


## Builds the land. The first stage keeps its hand-made layout; later stages scatter
## lakes, woods and rocks from the seed in amounts that suit their biome.
## extras: "river" (a river crossing the map, fordable where the roads cross it) and
## "peaks" (how many tall mountains rise inside the map).
func build(seed_value: int, biome_name := "meadow", layout_seed := 0, extras := {}) -> void:
	biome = biome_name
	if layout_seed != 0:
		_gen_layout(layout_seed)
	if extras.get("river", false):
		_river = RIVER_PATH.duplicate()
		# the river is the water of this land: only small ponds besides it
		_lakes = _lakes.filter(func(l): return l.z < 8.0 and _river_dist(l.x, l.y) > l.z * 1.6 + 10.0)
	if int(extras.get("peaks", 0)) > 0:
		_gen_peaks(int(extras.peaks), layout_seed + 17)
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	detail.seed = seed_value + 7
	detail.frequency = 0.09
	_paint_roads()      # first, so lakes and rocks can keep clear of the roads
	_make_heights()
	_classify()
	_build_ground_mesh()
	_build_water()
	_build_far_ground()
	_scatter_trees()
	_scatter_rocks()


# ---------------- river and mountains ----------------
## A river from the northern mountains to the east, between the middle village and
## Afrasiab's side. Points are (x, z) in metres.
const RIVER_PATH := [Vector2(-62, -92), Vector2(-52, -60), Vector2(-30, -38), Vector2(-14, -22),
	Vector2(8, -16), Vector2(28, -14), Vector2(52, -4), Vector2(70, 8), Vector2(95, 14)]
const RIVER_HALF_WIDTH := 4.2
var _river: Array = []
var _peaks: Array = []     # (x, z, radius)


func _river_dist(x: float, z: float) -> float:
	var best := INF
	var p := Vector3(x, 0, z)
	for i in _river.size() - 1:
		var a: Vector2 = _river[i]
		var b: Vector2 = _river[i + 1]
		best = minf(best, _dist_to_segment(p, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y)))
	return best


## Tall peaks away from the castles, villages and roads; they block the way, so armies
## must go round through the passes.
func _gen_peaks(count: int, peak_seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = peak_seed
	var keeps := []
	for kc in Defs.KEEP_CELL:
		keeps.append(cell_center_flat(kc))
	var vills := []
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		vills.append(cell_center_flat(vc))
	var segs := []
	for seg in _road_lines():
		segs.append([cell_center_flat(seg[0]), cell_center_flat(seg[1])])
	_peaks = _scatter_blobs(r, [count, 7.0, 11.0], keeps, vills, segs, 1.5, 3.0)
	# no lakes or woods where the peaks rise
	_lakes = _lakes.filter(func(l): return _peaks.all(func(pk): return Vector2(l.x - pk.x, l.y - pk.y).length() > l.z + pk.z * 1.4))


# ---------------- stage layouts ----------------
## How many lakes, woods and rocks each biome gets, with their size ranges.
const LAYOUT := {
	"meadow": {"lakes": [4, 6.0, 12.0], "forests": [10, 7.0, 13.0], "rocks": [8, 4.0, 5.5]},
	"steppe": {"lakes": [2, 6.0, 9.0], "forests": [5, 6.0, 10.0], "rocks": [11, 4.0, 6.0]},
	"forest": {"lakes": [3, 6.0, 10.0], "forests": [17, 9.0, 14.0], "rocks": [6, 4.0, 5.0]},
	"snow": {"lakes": [4, 7.0, 12.0], "forests": [10, 7.0, 12.0], "rocks": [11, 4.0, 6.0]},
	"desert": {"lakes": [2, 5.0, 7.0], "forests": [4, 4.0, 7.0], "rocks": [15, 4.0, 6.5]},
}


## Ground and tree colours per biome. grass: tint on the grass texture; snow/sand: cover on top.
const LOOK := {
	"meadow": {"grass": Color(1, 1, 1), "snow": 0.0, "sand": 0.0, "leaf": Color(1, 1, 1), "leaf_snow": 0.0, "ice": 0.0, "far": Color("#7c7466"), "cypress": 0.28},
	"steppe": {"grass": Color(1.18, 1.02, 0.62), "snow": 0.0, "sand": 0.15, "leaf": Color(1.25, 1.0, 0.55), "leaf_snow": 0.0, "ice": 0.0, "far": Color("#8f7f5c"), "cypress": 0.35},
	"forest": {"grass": Color(0.78, 0.92, 0.72), "snow": 0.0, "sand": 0.0, "leaf": Color(0.85, 1.0, 0.85), "leaf_snow": 0.0, "ice": 0.0, "far": Color("#4e5a45"), "cypress": 0.22},
	"snow": {"grass": Color(0.85, 0.9, 0.95), "snow": 0.92, "sand": 0.0, "leaf": Color(0.7, 0.85, 0.8), "leaf_snow": 0.38, "ice": 1.0, "far": Color("#c9d2dc"), "cypress": 0.75},
	"desert": {"grass": Color(1.3, 1.1, 0.7), "snow": 0.0, "sand": 0.85, "leaf": Color(1.05, 1.05, 0.8), "leaf_snow": 0.0, "ice": 0.0, "far": Color("#b99a6a"), "cypress": 0.5},
}


func look() -> Dictionary:
	return LOOK.get(biome, LOOK.meadow)


func _gen_layout(layout_seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = layout_seed
	var lay: Dictionary = LAYOUT.get(biome, LAYOUT.meadow)
	var keeps := []
	for kc in Defs.KEEP_CELL:
		keeps.append(cell_center_flat(kc))
	var vills := []
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		vills.append(cell_center_flat(vc))
	var segs := []
	for seg in _road_lines():
		segs.append([cell_center_flat(seg[0]), cell_center_flat(seg[1])])
	_lakes = _scatter_blobs(r, lay.lakes, keeps, vills, segs, 1.6, 2.0)
	_rocks = _scatter_blobs(r, lay.rocks, keeps, vills, segs, 1.8, 1.0)
	_forests = _scatter_blobs(r, lay.forests, keeps, vills, [], 1.0, 0.0)


## Places blobs (x, z, radius) away from the castles, the villages and (if given) the roads.
func _scatter_blobs(r: RandomNumberGenerator, spec: Array, keeps: Array, vills: Array, segs: Array, reach: float, road_gap: float) -> Array:
	var out := []
	var tries := 0
	while out.size() < spec[0] and tries < 400:
		tries += 1
		var rad := r.randf_range(spec[1], spec[2])
		var p := Vector3(r.randf_range(-HALF * 0.78, HALF * 0.78), 0, r.randf_range(-HALF * 0.78, HALF * 0.78))
		var ok := true
		for k in keeps:
			if Vector2(p.x - k.x, p.z - k.z).length() < rad * reach + 22.0:
				ok = false
		for v in vills:
			if Vector2(p.x - v.x, p.z - v.z).length() < rad * reach + 9.0:
				ok = false
		for sg in segs:
			if _dist_to_segment(p, sg[0], sg[1]) < rad * reach + road_gap:
				ok = false
		for o in out:
			if Vector2(p.x - o.x, p.z - o.y).length() < (rad + o.z) * 0.9:
				ok = false
		if ok:
			out.append(Vector3(p.x, p.z, rad))
	return out


static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (ap - ab * t).length()


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
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		var c := cell_center_flat(vc)
		var d := Vector2(x - c.x, z - c.z).length()
		h = lerpf(0.3, h, clampf((d - 6.0) / 6.0, 0.0, 1.0))
	var on_road := road[int(clampf(z + HALF, 0, N - 1)) * N + int(clampf(x + HALF, 0, N - 1))] if road.size() == N * N else 0.0
	var keep_dry := 1.0 - clampf(on_road * 1.6, 0.0, 1.0)   # a road never sinks into a lake
	for l in _lakes:
		var d := Vector2(x - l.x, z - l.y).length()
		if d < l.z * 1.6:
			var k := 1.0 - clampf(d / (l.z * 1.6), 0.0, 1.0)
			h -= smoothstep(0.0, 1.0, k) * 3.2 * keep_dry
	for r in _rocks:
		var d := Vector2(x - r.x, z - r.y).length()
		if d < r.z * 1.8:
			h += (1.0 - d / (r.z * 1.8)) * 1.4 * keep_dry
	for pk in _peaks:
		var d := Vector2(x - pk.x, z - pk.y).length()
		if d < pk.z * 1.5:
			var k: float = 1.0 - d / (pk.z * 1.5)
			# a rough cone with ridges
			h += (smoothstep(0.0, 1.0, k) * 15.0 + k * k * 4.0 + k * noise.get_noise_2d(x * 4.0, z * 4.0) * 3.5) * keep_dry
	if not _river.is_empty():
		var d := _river_dist(x, z)
		var w := RIVER_HALF_WIDTH + noise.get_noise_2d(x * 2.0, z * 2.0) * 1.2
		if d < w * 2.2:
			var k := 1.0 - clampf((d - w * 0.55) / (w * 1.65), 0.0, 1.0)
			# the river keeps clear of the castles, villages and camps, and fords at the roads
			var guard := 1.0
			for kc in Defs.KEEP_CELL:
				var c := cell_center_flat(kc)
				guard = minf(guard, clampf((Vector2(x - c.x, z - c.z).length() - 22.0) / 8.0, 0.0, 1.0))
			for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
				var c := cell_center_flat(vc)
				guard = minf(guard, clampf((Vector2(x - c.x, z - c.z).length() - 9.0) / 5.0, 0.0, 1.0))
			h -= smoothstep(0.0, 1.0, k) * 3.4 * guard * keep_dry
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
	return (t == GRASS or t == FOREST) and not has_tree(c)


## Cells with a tree trunk block movement; forest clearings stay open.
func has_tree(c: Vector2i) -> bool:
	return in_grid(c) and tree_cells.has(c.y * G + c.x)


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
			elif _in_blob(p, _rocks) > 0.0 and road[int(p.z + HALF) * N + int(p.x + HALF)] < 0.3:
				t = ROCK
			elif _in_blob(p, _forests) + detail.get_noise_2d(p.x * 2.0, p.z * 2.0) * 0.35 > 0.15:
				t = FOREST
			if t == FOREST and road[int(p.z + HALF) * N + int(p.x + HALF)] > 0.3:
				t = GRASS   # keep the roads free of trees
			cell_type[j * G + i] = t
	# keep castle and village grounds clear
	for kc in Defs.KEEP_CELL:
		_clear_area(kc, 7)
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		_clear_area(vc, 3)


func _clear_area(c: Vector2i, r: int) -> void:
	for j in range(c.y - r, c.y + r + 1):
		for i in range(c.x - r, c.x + r + 1):
			if in_grid(Vector2i(i, j)) and cell_type[j * G + i] != WATER:
				cell_type[j * G + i] = GRASS


# ---------------- ground mesh ----------------
## Dirt roads that link both castles and the villages, as cell-coordinate polylines.
func _road_lines() -> Array:
	var ik: Vector2i = Defs.KEEP_CELL[0]
	var tk: Vector2i = Defs.KEEP_CELL[1]
	var v: Array = Defs.VILLAGE_CELLS
	return [[ik, v[0]], [ik, v[1]], [v[1], tk], [v[2], tk], [v[1], v[2]], [v[0], v[1]]]


var road := PackedFloat32Array()


func _paint_roads() -> void:
	road.resize(N * N)
	road.fill(0.0)
	for seg in _road_lines():
		var a := cell_center_flat(seg[0])
		var b := cell_center_flat(seg[1])
		var steps := int(a.distance_to(b) / 1.5)
		var side := Vector3(-(b.z - a.z), 0, b.x - a.x).normalized()
		var prev := a
		for k in range(1, steps + 1):
			var t := float(k) / steps
			# gentle bends, pinned at both ends
			var bend := sin(t * PI) * noise.get_noise_2d(a.x + t * 40.0, a.z) * 14.0
			var q := a.lerp(b, t) + side * bend
			_stamp_road(prev, q)
			prev = q


func _stamp_road(a: Vector3, b: Vector3) -> void:
	var r := 2.2
	var x0 := int(minf(a.x, b.x) - r - 1.0 + HALF)
	var x1 := int(maxf(a.x, b.x) + r + 1.0 + HALF)
	var z0 := int(minf(a.z, b.z) - r - 1.0 + HALF)
	var z1 := int(maxf(a.z, b.z) + r + 1.0 + HALF)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := maxf(ab.length_squared(), 0.001)
	for j in range(maxi(z0, 0), mini(z1, N - 1) + 1):
		for i in range(maxi(x0, 0), mini(x1, N - 1) + 1):
			var pp := Vector2(i - HALF - a.x, j - HALF - a.z)
			var t := clampf(pp.dot(ab) / len2, 0.0, 1.0)
			var d := (pp - ab * t).length()
			var wv := clampf((r - d) / 1.2, 0.0, 1.0)
			if wv > road[j * N + i]:
				road[j * N + i] = wv


## Layer weights for one ground vertex: r = dirt, g = rock, b = sand, a = forest floor.
func _ground_weights(i: int, j: int, h: float, slope: float) -> Color:
	var x := i - HALF
	var z := j - HALF
	var n := noise.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5
	var pos := Vector3(x, 0, z)
	var dirt := road[j * N + i] * 0.95
	# trampled ground around the castles and villages
	for kc in Defs.KEEP_CELL:
		var c := cell_center_flat(kc)
		var d := Vector2(x - c.x, z - c.z).length()
		dirt = maxf(dirt, clampf((13.0 - d) / 6.0 + (n - 0.5) * 0.8, 0.0, 0.85))
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		var c := cell_center_flat(vc)
		var d := Vector2(x - c.x, z - c.z).length()
		dirt = maxf(dirt, clampf((6.5 - d) / 3.0 + (n - 0.5) * 0.8, 0.0, 0.9))
	# a few bare patches in the meadows
	dirt = maxf(dirt, clampf((detail.get_noise_2d(x * 0.8, z * 0.8) - 0.45) * 2.5, 0.0, 0.6))
	var forest := clampf(_in_blob(pos, _forests) * 2.5, 0.0, 1.0)
	var sand := clampf((Defs.WATER_LEVEL + 0.2 - h) * 2.5, 0.0, 1.0)
	var rock := clampf((slope - 0.55) * 2.5, 0.0, 1.0)
	rock = maxf(rock, clampf((h - 2.8) * 0.6, 0.0, 1.0))
	rock = maxf(rock, clampf(_in_blob(pos, _rocks, 1.3) * 2.6, 0.0, 0.95))
	dirt *= 1.0 - rock
	dirt *= 1.0 - sand
	sand *= 1.0 - rock
	return Color(dirt, rock, sand, forest * (1.0 - dirt))


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
			st.set_color(_ground_weights(i, j, h, slope * 4.0))
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
	for layer in ["grass", "dirt", "rock", "sand"]:
		terrain_material.set_shader_parameter(layer + "_tex", load("res://assets/textures/ground/%s_albedo.png" % layer))
		if layer != "sand":
			terrain_material.set_shader_parameter(layer + "_nrm", load("res://assets/textures/ground/%s_normal.png" % layer))
	var lk := look()
	terrain_material.set_shader_parameter("grass_tint", lk.grass)
	terrain_material.set_shader_parameter("snow_cover", lk.snow)
	terrain_material.set_shader_parameter("sand_cover", lk.sand)
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
	m.set_shader_parameter("ice", look().ice)
	_water_mat = m
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
	m.albedo_color = look().far
	_far_mat = m
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


## Loads a nature GLB and returns its mesh with game materials: leaves get the foliage
## shader, everything else a lit material tinted by the per-instance colour.
func _nature_mesh(file: String) -> Mesh:
	var ps: PackedScene = load("res://assets/models/nature/%s.glb" % file)
	var inst := ps.instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = mi.mesh.duplicate()
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as BaseMaterial3D
		var tex: Texture2D = src.albedo_texture if src else null
		if src and src.resource_name.begins_with("leaves"):
			var fm := ShaderMaterial.new()
			fm.shader = load("res://assets/shaders/foliage.gdshader")
			fm.set_shader_parameter("leaf_tex", tex)
			fm.set_shader_parameter("leaf_tint", look().leaf)
			fm.set_shader_parameter("snow_amt", look().leaf_snow)
			_leaf_mats.append(fm)
			if file.begins_with("tree_chenar"):
				_bare_mats.append(fm)
			mesh.surface_set_material(i, fm)
		else:
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.95
			if file.begins_with("tree") and not file.begins_with("tree_snow"):
				_bark_mats.append(m)
			mesh.surface_set_material(i, m)
	inst.free()
	return mesh


## Instances grouped in 20 m chunks, so the camera only draws the chunks it can see.
func _chunked(mesh: Mesh, xforms: Array, colors: Array, shadows := true) -> Array:
	var made := []
	var chunks := {}
	for i in xforms.size():
		var o: Vector3 = xforms[i].origin
		var key := Vector2i(int(floor(o.x / 20.0)), int(floor(o.z / 20.0)))
		if not chunks.has(key):
			chunks[key] = [[], []]
		chunks[key][0].append(xforms[i])
		chunks[key][1].append(colors[i])
	for key in chunks:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var xs: Array = chunks[key][0]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_color(i, chunks[key][1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		made.append(mmi)
	return made


func _near_castle_or_road(p: Vector3) -> bool:
	if road[int(clampf(p.z + HALF, 0, N - 1)) * N + int(clampf(p.x + HALF, 0, N - 1))] > 0.05:
		return true
	for kc in Defs.KEEP_CELL:
		if Vector2(p.x, p.z).distance_to(Vector2(cell_center_flat(kc).x, cell_center_flat(kc).z)) < 17.0:
			return true
	for vc in Defs.VILLAGE_CELLS + Defs.CAMP_CELLS:
		if Vector2(p.x, p.z).distance_to(Vector2(cell_center_flat(vc).x, cell_center_flat(vc).z)) < 8.0:
			return true
	return false


func _scatter_trees() -> void:
	var kinds := ["tree_chenar_a", "tree_chenar_b", "tree_cypress"]
	var xf := [[], [], []]
	var cols := [[], [], []]
	for j in G:
		for i in G:
			var t := cell_type[j * G + i]
			var base := cell_center(Vector2i(i, j))
			var lone := t == GRASS and rng.randf() < 0.012 and not _near_castle_or_road(base)
			if t != FOREST and not lone:
				continue
			if t == FOREST and rng.randf() < 0.18:
				continue   # small clearings
			var p := base + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			p.y = height_at(p.x, p.z) - 0.1
			tree_cells[j * G + i] = true
			var cy: float = look().cypress
			var k := 2 if rng.randf() < (maxf(cy, 0.45) if lone else cy) else rng.randi() % 2
			var s := rng.randf_range(0.75, 1.15) * (0.85 if k < 2 else 1.0)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
			xf[k].append(Transform3D(b, p))
			var hue := rng.randf()
			cols[k].append(Color(0.9 + hue * 0.25, 0.95 + hue * 0.15, 0.85 + hue * 0.1))
	for k in 3:
		if xf[k].size() > 0:
			var made := _chunked(_nature_mesh(kinds[k]), xf[k], cols[k])
			if k < 2:
				_chenar[k] = xf[k]
				_chenar_mmis += made
	if biome == "snow":
		_show_snow_trees(true)


## Winter: the plane trees stand bare with snow on their branches (Meshy models,
## scaled to the height of the leafy tree each one replaces). Cypresses stay green.
func _show_snow_trees(on: bool) -> void:
	if on and _snow_mmis.is_empty():
		var files := ["tree_snow_a", "tree_snow_b"]
		var height := [7.2, 6.0]
		for k in 2:
			if _chenar[k].is_empty():
				continue
			var mesh := _nature_mesh(files[k])
			var box := mesh.get_aabb()
			var s: float = height[k] / maxf(box.size.y, 0.01)
			var fit := Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(0, -box.position.y * s - 0.05, 0))
			var xs := []
			var cs := []
			for x: Transform3D in _chenar[k]:
				xs.append(x * fit)
				cs.append(Color(1.2, 1.22, 1.28))
			_snow_mmis += _chunked(mesh, xs, cs)
	for m: Node3D in _snow_mmis:
		m.visible = on
	for m: Node3D in _chenar_mmis:
		m.visible = not on


func _scatter_rocks() -> void:
	var kinds := ["rock_a", "rock_b", "rock_c"]
	var xf := [[], [], []]
	var cols := [[], [], []]
	for j in G:
		for i in G:
			var t := cell_type[j * G + i]
			var on_peak := t == MOUNTAIN and _in_blob(cell_center(Vector2i(i, j)), _peaks, 1.5) > 0.0
			if t != ROCK and not (t == MOUNTAIN and rng.randf() < (0.4 if on_peak else 0.12)):
				continue
			var base := cell_center(Vector2i(i, j))
			for _k in (2 if t == ROCK else 1):
				var p := base + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
				p.y = height_at(p.x, p.z) - 0.15
				var k := rng.randi() % 3
				var s := rng.randf_range(0.55, 1.1) * (1.6 if t == MOUNTAIN else 1.0)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
				xf[k].append(Transform3D(b.scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), p))
				var g := rng.randf_range(0.85, 1.1)
				cols[k].append(Color(g, g * 0.98, g * 0.95))
	for k in 3:
		if xf[k].size() > 0:
			_chunked(_nature_mesh(kinds[k]), xf[k], cols[k])


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
	_grass_mat = vc_material(1.0)
	_multimesh(blade, xs, cs, _grass_mat, false)


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


## Snow settling over the land: 0 = the land as built, 1 = deep winter.
func set_winter(k: float) -> void:
	var a: Dictionary = look()
	var b: Dictionary = LOOK.snow
	terrain_material.set_shader_parameter("grass_tint", a.grass.lerp(b.grass, k))
	terrain_material.set_shader_parameter("snow_cover", lerpf(a.snow, b.snow, k))
	terrain_material.set_shader_parameter("sand_cover", lerpf(a.sand, b.sand, k))
	for fm: ShaderMaterial in _leaf_mats:
		fm.set_shader_parameter("leaf_tint", a.leaf.lerp(b.leaf, k))
		fm.set_shader_parameter("snow_amt", lerpf(a.leaf_snow, b.leaf_snow, k))
	# the plane trees drop their leaves and dry up, then stand bare under the snow
	if k >= 0.55 and _snow_mmis.is_empty():
		_show_snow_trees(true)
	for fm: ShaderMaterial in _bare_mats:
		fm.set_shader_parameter("bare", 0.72 * clampf(k * 1.4, 0.0, 1.0))
		fm.set_shader_parameter("snow_amt", lerpf(a.leaf_snow, 0.75, k))
	for fm: ShaderMaterial in _leaf_mats:
		if not fm in _bare_mats:
			fm.set_shader_parameter("snow_amt", lerpf(a.leaf_snow, 0.6, k))
	for m: StandardMaterial3D in _bark_mats:
		m.albedo_color = Color.WHITE.lerp(Color(1.25, 1.28, 1.35), k)
	if _water_mat:
		_water_mat.set_shader_parameter("ice", lerpf(a.ice, 0.85, clampf(k * 1.3 - 0.3, 0.0, 1.0)))
	if _far_mat:
		_far_mat.albedo_color = a.far.lerp(b.far, k)
	if _grass_mat:
		# the grass blades vanish under the snow
		_grass_mat.albedo_color = Color.WHITE.lerp(Color(2.2, 2.3, 2.4), k)
