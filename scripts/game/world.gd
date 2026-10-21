extends Node3D
## The level: owns the terrain, every unit and building, the economy, pathfinding,
## touch input and the win / lose rules. The HUD reads from it and calls its actions.

signal message(text: String, side: int)
signal game_over(win: bool)
signal selection_changed

const G := Defs.GRID
const IRAN := Defs.IRAN
const TURAN := Defs.TURAN
const DIVS := Defs.DIVS

var stage: Dictionary = {}      # the campaign stage being played (Defs.STAGES entry)
var biome := "meadow"
var _keep_warned := -100.0    # time of the last spoken warning that the keep is under attack
var terrain: Terrain
var rig: CameraRig
var hud: Node
var ai: Node
var sun: DirectionalLight3D

var units: Array = []
var buildings: Array = []
var structures := {}            # cell index -> Building (blocking footprint)
var grids: Array = []           # AStarGrid2D per side (0, 1, 2)
var keeps := [null, null]
var villages: Array = []
var tribes: Array = []          # {b, n, units, trust: [iran, turan], send_t, tribute_t, men}

var res := [{}, {}]
var heroes_down := [0.0, 0.0]
var time := 0.0
var finished := false
var _tax_t := 0.0
var _village_t := 0.0
var _food_t := 0.0
var _capture_t := 0.0
var _starving := [false, false]

# selection & input
var selected: Array = []
var selected_building: Building = null
var mode := "normal"            # normal / build / box / power / formation
var formation_armed := ""      # formation waiting for a tap on the map
var powers: Powers
var build_type := ""
var build_cell := Vector2i(-1, -1)
var wall_start := Vector2i(-1, -1)
var wall_cells: Array = []
var ghost_ok := false
var ghost_reason := ""
var _ghosts: Array = []
var _touches := {}
var _ui_touch := {}
var _gesture_moved := false
var _gesture_multi := false
var _pinch_d := 0.0
var _last_tap_t := -1.0
var _last_tap_unit: Unit = null
var box_from := Vector2.ZERO
var box_to := Vector2.ZERO
var box_active := false

# effects read by the HUD overlay
var floats: Array = []          # {pos: Vector3, text, color, t}


func _ready() -> void:
	war_started.connect(_on_war_started)
	# 60 frames a second is smooth; 90 and 120 Hz phones would otherwise draw twice as much and heat up
	Engine.max_fps = 60
	randomize()
	stage = App.stage_def()
	biome = stage.biome
	_setup_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var map_seed := randi()
	if OS.get_cmdline_user_args().has("--pathtest") or OS.get_cmdline_user_args().has("--wavetest") or OS.get_cmdline_user_args().has("--chaintest"):
		map_seed = 4242     # same map every test run
	# the first stage keeps its hand-made map; the others get a layout of their own
	terrain.build(map_seed, biome, 0 if App.stage == 0 else int(stage.seed))
	_setup_grids()
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	Sfx.listener = rig
	powers = Powers.new()
	powers.name = "Powers"
	add_child(powers)
	powers.setup(self)
	res[IRAN] = Defs.START_RES.duplicate()
	res[TURAN] = Defs.START_RES.duplicate()
	for k in stage.bonus:
		res[IRAN][k] += stage.bonus[k]
	_setup_castles()
	_update_zones()
	ai = preload("res://scripts/game/enemy_ai.gd").new()
	ai.name = "TuranAI"
	ai.world = self
	add_child(ai)
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.name = "HUD"
	hud.world = self
	add_child(hud)
	rig.position = keeps[IRAN].position + Vector3(10, 0, -8)
	rig.zoom_by(1.0)
	if biome == "snow":
		_add_snowfall()
	say("مرحله‌ی %s: %s" % [Defs.fa(App.stage + 1), stage.n], IRAN)
	say("افراسیاب از جیحون گذشته است. دژ را استوار کن و سپاه گرد آور!" if App.stage == 0 else "دژ را استوار کن و سپاه گرد آور. افراسیاب آماده‌ی یورش است!", TURAN)


## Sky, fog and sunlight for each biome.
const SKIES := {
	"meadow": {"top": "#4f7fc4", "horizon": "#e7cfa8", "ground": "#d9c09a", "fog": "#d8c7a8", "fog_d": 0.0016, "sun": "#ffe2b8", "sun_e": 1.55, "amb": 0.6, "sat": 1.08},
	"steppe": {"top": "#5a86c0", "horizon": "#efd5a0", "ground": "#e0c590", "fog": "#e6cf9e", "fog_d": 0.0019, "sun": "#ffd9a0", "sun_e": 1.6, "amb": 0.6, "sat": 1.12},
	"forest": {"top": "#56789e", "horizon": "#c9d3bc", "ground": "#a6b096", "fog": "#b9c6ad", "fog_d": 0.0032, "sun": "#ffe9c8", "sun_e": 1.35, "amb": 0.65, "sat": 1.05},
	"snow": {"top": "#6f8fbd", "horizon": "#dce3ec", "ground": "#d5dce6", "fog": "#d3dbe6", "fog_d": 0.0026, "sun": "#e8eeff", "sun_e": 1.1, "amb": 0.62, "sat": 0.98},
	"desert": {"top": "#4a82cc", "horizon": "#f3d9a8", "ground": "#e9cc94", "fog": "#ead3a3", "fog_d": 0.0022, "sun": "#fff0cc", "sun_e": 1.75, "amb": 0.6, "sat": 1.1},
}


func _setup_environment() -> void:
	var sk: Dictionary = SKIES.get(biome, SKIES.meadow)
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(sk.top)
	psm.sky_horizon_color = Color(sk.horizon)
	psm.ground_bottom_color = Color("#5a4e3e")
	psm.ground_horizon_color = Color(sk.ground)
	psm.sun_angle_max = 20.0
	psm.sky_energy_multiplier = 1.0
	sky.sky_material = psm
	_sky_mat = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = sk.amb
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(sk.fog)
	env.fog_density = sk.fog_d
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = sk.sat
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-62), 0)
	sun.light_color = Color(sk.sun)
	sun.light_energy = sk.sun_e
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_blur = 1.2
	add_child(sun)


## Falling snow that follows the camera.
func _add_snowfall() -> void:
	var p := CPUParticles3D.new()
	p.name = "Snowfall"
	p.amount = 700
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 1, 35)
	p.direction = Vector3(0.25, -1, 0.1)
	p.spread = 12.0
	p.gravity = Vector3(0.3, -0.6, 0.1)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.mesh = Models.soft_particle(0.22, Color(1, 1, 1, 0.9), false)
	p.color = Color(1, 1, 1, 0.9)
	p.position = Vector3(0, 22, 0)
	p.local_coords = false
	rig.add_child(p)


# ---------------- pathfinding ----------------
func _setup_grids() -> void:
	grids = []
	for s in 3:
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, G, G)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		g.update()
		grids.append(g)
	for j in G:
		for i in G:
			_refresh_cell(Vector2i(i, j))


func _refresh_cell(c: Vector2i) -> void:
	var t := terrain.type_at(c)
	var walk := terrain.walkable(c)
	var s = structures.get(c.y * G + c.x)
	for side in 3:
		var g: AStarGrid2D = grids[side]
		var solid := not walk
		var w := 1.25 if t == Terrain.FOREST else 1.0
		if s != null and not s.dead:
			if not s.blocks(side):
				pass
			elif s.side == side or side == DIVS or s.side < 0:
				solid = true
			else:
				w = 7.0     # enemy structure: passable at a cost, units will attack it
		g.set_point_solid(c, solid)
		g.set_point_weight_scale(c, w)


func _nearest_open(side: int, c: Vector2i) -> Vector2i:
	var g: AStarGrid2D = grids[side]
	if not g.is_point_solid(c):
		return c
	for r in range(1, 20):
		var best := Vector2i(-1, -1)
		var bd := INF
		for j in range(c.y - r, c.y + r + 1):
			for i in range(c.x - r, c.x + r + 1):
				var p := Vector2i(i, j)
				if not Terrain.in_grid(p) or g.is_point_solid(p):
					continue
				var d := Vector2(p - c).length()
				if d < bd:
					bd = d
					best = p
		if best.x >= 0:
			return best
	return c


func find_path(side: int, from: Vector3, to: Vector3) -> Array:
	var s := clampi(side, 0, 2)
	var a := _nearest_open(s, Terrain.cell_of(from))
	var b := _nearest_open(s, Terrain.cell_of(to))
	var ids: Array[Vector2i] = grids[s].get_id_path(a, b, true)
	var pts := []
	for k in range(1, ids.size()):
		pts.append(Terrain.cell_center_flat(ids[k]))
	if pts.size() > 0 and Terrain.cell_of(to) == b:
		pts[pts.size() - 1] = Vector3(to.x, 0, to.z)
	# string-pulling: skip waypoints that can be reached in a straight, clear line
	var out := []
	var cur := Vector3(from.x, 0, from.z)
	var k := 0
	while k < pts.size():
		var far := k
		var lim := mini(pts.size() - 1, k + 12)
		for m in range(lim, k, -1):
			if clear_line(s, cur, pts[m]):
				far = m
				break
		out.append(pts[far])
		cur = pts[far]
		k = far + 1
	if out.is_empty() and Terrain.cell_of(to) == b:
		out.append(Vector3(to.x, 0, to.z))   # goal is in the same cell
	return out


## True when a unit can walk straight from a to b without touching a blocked cell.
## Checks a little to each side as well, so units do not clip tree trunks and corners.
func clear_line(side: int, a: Vector3, b: Vector3) -> bool:
	var g: AStarGrid2D = grids[clampi(side, 0, 2)]
	var d := Vector2(b.x - a.x, b.z - a.z)
	var l := d.length()
	if l < 0.01:
		return true
	var dir := d / l
	var nrm := Vector2(-dir.y, dir.x) * 0.45
	var steps := int(ceil(l / 0.5))
	for i in range(1, steps + 1):
		var t := minf(float(i) * 0.5, l)
		var p := Vector2(a.x, a.z) + dir * t
		for o in [Vector2.ZERO, nrm, -nrm]:
			var q: Vector2 = p + o
			var c := Terrain.cell_of(Vector3(q.x, 0, q.y))
			if g.is_point_solid(c) or g.get_point_weight_scale(c) > 3.0:
				return false
	return true


func structure_at(c: Vector2i):
	return structures.get(c.y * G + c.x)


# ---------------- setup ----------------
func _setup_castles() -> void:
	keeps[IRAN] = _add_building("keep", IRAN, Defs.KEEP_CELL[IRAN] - Vector2i(2, 2))
	var tl: Dictionary = stage.turan
	keeps[TURAN] = _add_building("keep", TURAN, Defs.KEEP_CELL[TURAN] - Vector2i(2, 2), true, int(tl.keep))
	# Turan starts with a walled castle
	var kc: Vector2i = Defs.KEEP_CELL[TURAN]
	var lo := kc + Vector2i(-7, -7)
	var hi := kc + Vector2i(6, 6)
	for i in range(lo.x, hi.x + 1):
		for j in [lo.y, hi.y]:
			_try_prebuilt(Vector2i(i, j), i == kc.x and j == hi.y)
	for j in range(lo.y + 1, hi.y):
		for i in [lo.x, hi.x]:
			_try_prebuilt(Vector2i(i, j), i == lo.x and j == kc.y)
	for c in [lo, Vector2i(hi.x, lo.y), Vector2i(lo.x, hi.y), hi]:
		var s = structure_at(c)
		if s != null:
			_remove_structure(s, true)
		if _footprint_free(c, 1):
			_add_building("tower", TURAN, c, true, int(tl.tower))
	for p in [[kc + Vector2i(2, 2), "barracks"], [kc + Vector2i(-5, -5), "house"], [kc + Vector2i(-5, -2), "house"],
			[kc + Vector2i(1, -5), "house"], [kc + Vector2i(-5, 2), "barracks"]]:
		if _footprint_free(p[0], Defs.BUILDINGS[p[1]].size):
			_add_building(p[1], TURAN, p[0], true, int(tl.barracks) if p[1] == "barracks" else 1)
	for p in [kc + Vector2i(-12, -3), kc + Vector2i(-3, 9), kc + Vector2i(-12, 2)]:
		if _footprint_free(p, 3):
			_add_building("farm", TURAN, p)
	# villages
	for vc in Defs.VILLAGE_CELLS:
		var v := _add_building("village", -1, vc - Vector2i(1, 1))
		villages.append(v)
	_setup_tribes()
	# starting armies
	var ip: Vector3 = keeps[IRAN].position
	spawn_unit("hero", IRAN, ip + Vector3(6, 0, -5))
	for k in 4:
		spawn_unit("spear", IRAN, ip + Vector3(3 + k * 1.4, 0, -7))
	for k in 2:
		spawn_unit("archer", IRAN, ip + Vector3(4 + k * 1.4, 0, -9))
	var tp: Vector3 = keeps[TURAN].position
	spawn_unit("hero", TURAN, tp + Vector3(-5, 0, 5))
	for k in 4:
		spawn_unit("spear", TURAN, tp + Vector3(-2 - k * 1.4, 0, 6))
	for k in 2:
		spawn_unit("archer", TURAN, tp + Vector3(-3 - k * 1.4, 0, 8))
	# later stages: Afrasiab starts with a larger garrison
	for k in int(tl.extra):
		spawn_unit(["spear", "archer", "cav", "immortal"][k % 4], TURAN, tp + Vector3(-2 - (k % 4) * 1.5, 0, 10 + (k / 4) * 1.5))
	# divs hold the villages
	for vi in villages.size():
		var v: Building = villages[vi]
		var n: int = stage.divs[vi]
		for k in n:
			var a := TAU * k / maxf(1.0, n)
			spawn_unit("div", DIVS, v.position + Vector3(cos(a) * 3.0, 0, 3.0 + sin(a) * 1.5))


func _try_prebuilt(c: Vector2i, gate: bool) -> void:
	if _footprint_free(c, 1):
		_add_building("gate" if gate else "wall", TURAN, c)


func _footprint_free(c: Vector2i, size: int) -> bool:
	for j in size:
		for i in size:
			var p := c + Vector2i(i, j)
			if not Terrain.in_grid(p) or terrain.type_at(p) != Terrain.GRASS or terrain.has_tree(p) or structure_at(p) != null:
				return false
	return true


func _add_building(type: String, side: int, c: Vector2i, instant := true, level := 1) -> Building:
	var b := Building.new()
	b.setup(self, type, side, c, level, instant)
	add_child(b)
	buildings.append(b)
	for p in b.cells():
		structures[p.y * G + p.x] = b
		_refresh_cell(p)
	return b


func _remove_structure(b: Building, free_now := false) -> void:
	buildings.erase(b)
	for p in b.cells():
		if structures.get(p.y * G + p.x) == b:
			structures.erase(p.y * G + p.x)
	b.dead = true
	for p in b.cells():
		_refresh_cell(p)
	if free_now:
		b.queue_free()


func spawn_unit(type: String, side: int, pos: Vector3) -> Unit:
	var u := Unit.new()
	pos.y = terrain.height_at(pos.x, pos.z)
	add_child(u)
	u.setup(self, type, side, pos)
	units.append(u)
	if side == TURAN and ai:
		ai.on_unit_spawned(u)
	return u


func free_spot_near(b: Building) -> Vector3:
	var r := b.size
	var best := Vector3.ZERO
	var bd := INF
	var target: Vector3 = keeps[1 - b.side].position if b.side in [0, 1] and keeps[1 - b.side] else Vector3.ZERO
	for j in range(b.cell.y - 1, b.cell.y + r + 1):
		for i in range(b.cell.x - 1, b.cell.x + r + 1):
			var c := Vector2i(i, j)
			if not Terrain.in_grid(c) or not terrain.walkable(c) or structure_at(c) != null:
				continue
			var p := terrain.cell_center(c)
			var d := p.distance_to(target) + randf() * 3.0
			if d < bd:
				bd = d
				best = p
	if bd == INF:
		return b.position + Vector3(0, 0, b.half_extent() + 1.0)
	return best


# ---------------- queries used by units ----------------
func are_enemies(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b:
		return false
	return true


func nearest_enemy(src: Node3D, radius: float, include_buildings: bool, center = null) -> Node3D:
	var c: Vector3 = src.position if center == null else center
	var best: Node3D = null
	var bd := INF
	# a cunning Turan picks soft targets: archers and the wounded first
	var cunning: bool = src.side == TURAN and ai != null and int(ai.smart) >= 1
	for u: Unit in units:
		if u.dead or not are_enemies(src.side, u.side) or u.hidden:
			continue
		var d := Vector2(u.position.x - c.x, u.position.z - c.z).length()
		if d >= radius:
			continue
		var score := d
		if cunning:
			score -= (3.0 if u.type == "archer" else 0.0) + (1.0 - u.hp / u.max_hp) * 4.0
		if score < bd:
			bd = score
			best = u
	if best != null or not include_buildings:
		return best
	bd = radius
	for b: Building in buildings:
		if b.dead or b.type == "village" or not are_enemies(src.side, b.side):
			continue
		var d := _rect_dist(c, b)
		if d < bd:
			bd = d
			best = b
	return best


func _rect_dist(p: Vector3, b: Building) -> float:
	var h := b.half_extent()
	var dx := maxf(absf(p.x - b.position.x) - h, 0.0)
	var dz := maxf(absf(p.z - b.position.z) - h, 0.0)
	return Vector2(dx, dz).length()


func distance_to_target(u: Unit, t: Node3D) -> float:
	if t is Unit:
		return Vector2(t.position.x - u.position.x, t.position.z - u.position.z).length() - (t as Unit).radius - u.radius * 0.5
	return _rect_dist(u.position, t) - 0.3


func approach_point(u: Unit, t: Node3D) -> Vector3:
	if t is Unit:
		return t.position
	var b := t as Building
	var h := b.half_extent() + 0.7
	var p := Vector3(clampf(u.position.x, b.position.x - h, b.position.x + h), 0, clampf(u.position.z, b.position.z - h, b.position.z + h))
	return p


func _damage_mult(atype: String, target: Node3D) -> float:
	if target is Building:
		match atype:
			"archer": return 0.2
			"hero": return 0.9
			"div": return 1.2
			_: return 0.6
	var tt: String = (target as Unit).type
	var m := 1.0
	if atype == "spear" and tt == "cav": m = 2.0
	elif atype == "cav" and tt == "archer": m = 1.5
	elif atype == "hero" and tt == "div": m = 1.5
	return m * (1.0 - float(Defs.UNITS[tt].armor))


func deal_damage(attacker: Node3D, target: Node3D, base: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	var atype: String = attacker.type if attacker is Unit else "tower"
	var dmg := base * _damage_mult(atype, target) * randf_range(0.9, 1.1)
	if target is Unit:
		dmg *= (target as Unit).harm_mult()
	target.take_damage(dmg, attacker)
	if target.side == IRAN or attacker.side == IRAN:
		powers.note_battle()
	if target is Building and target.type == "keep" and target.side == IRAN and time - _keep_warned > 25.0:
		_keep_warned = time
		Sfx.voice("keep_attacked", true)
		say("دژ زیر حمله است!", TURAN)
	if atype in ["archer", "tower"]:
		Sfx.play_at("arrow_hit", target.position, -6.0)
	elif target is Unit:
		Sfx.play_at("sword", target.position, -2.0)
	else:
		Sfx.play_at("hit", target.position, -3.0)
	if target is Unit:
		spawn_burst(target.position + Vector3(0, 1.1, 0), Color("#9c1f17"), 6, 0.1, 2.2, 0.45)
		if randf() < 0.5:
			spawn_burst(target.position + Vector3(0, 1.3, 0), Color("#ffd27a"), 4, 0.06, 3.5, 0.25, true)
	elif target is Building:
		spawn_burst(target.position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), Color("#9b9284"), 6, 0.18, 3.0, 0.7)
	if target is Building and target.side == IRAN and randf() < 0.15:
		rig.shake(0.3)


func spawn_arrow(src: Node3D, target: Node3D, dmg: float) -> void:
	var from := src.position + Vector3(0, 1.5, 0)
	if src is Building:
		from.y += 5.0 if src.type == "tower" else 7.5
	Sfx.play_at("bow", from, -8.0)
	var arrow := MeshInstance3D.new()
	arrow.mesh = Models.cyl_mesh(0.03, 0.03, 0.9, 4)
	arrow.material_override = Models.mat(Color("#3b2a1a"))
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arrow)
	var to := target.position + Vector3(0, 1.0, 0)
	var flight := clampf(from.distance_to(to) / 26.0, 0.2, 1.2)
	var arc := from.distance_to(to) * 0.18
	var tw := arrow.create_tween()
	var last := from
	tw.tween_method(func(k: float):
		if not is_instance_valid(target):
			return
		var end := target.position + Vector3(0, 1.0, 0)
		var p := from.lerp(end, k) + Vector3(0, sin(k * PI) * arc, 0)
		arrow.position = p
		var dir := p - last
		if dir.length() > 0.001:
			arrow.look_at(p + dir, Vector3.UP)
			arrow.rotate_object_local(Vector3.RIGHT, PI / 2)
		last = p, 0.0, 1.0, flight)
	tw.tween_callback(func():
		if is_instance_valid(target) and not target.dead and is_instance_valid(src):
			deal_damage(src, target, dmg)
		elif is_instance_valid(target) and not target.dead:
			target.take_damage(dmg * 0.8, null)
		arrow.queue_free())


func spawn_dust(p: Vector3, scale_m: float) -> void:
	var ps := FX.dust(scale_m, 26)
	ps.position = p + Vector3(0, 1.0, 0)
	ps.emitting = true
	add_child(ps)
	get_tree().create_timer(2.2).timeout.connect(ps.queue_free)


var _bursts := 0


## Small one-shot spray of particles: blood and sparks on hits, stone chips, gold on upgrades.
func spawn_burst(p: Vector3, col: Color, amount := 8, size := 0.12, speed := 2.5, life := 0.5, glow := false) -> void:
	if _bursts > 40:
		return     # keep phones smooth in big fights
	_bursts += 1
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = amount
	ps.lifetime = life
	ps.explosiveness = 0.95
	ps.position = p
	ps.direction = Vector3.UP
	ps.spread = 80.0
	ps.initial_velocity_min = speed * 0.5
	ps.initial_velocity_max = speed
	ps.gravity = Vector3(0, -9.0 if not glow else -1.5, 0)
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.2
	if glow:
		ps.mesh = Models.soft_particle(size * 3.0, col, true, 1.8)
	else:
		ps.mesh = Models.box_mesh(Vector3.ONE * size)
		ps.material_override = Models.mat(col)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	get_tree().create_timer(life + 0.3).timeout.connect(func():
		_bursts -= 1
		ps.queue_free())


# ---------------- deaths ----------------
func on_unit_killed(u: Unit, killer: Node3D) -> void:
	Sfx.play_at("death", u.position, -3.0)
	units.erase(u)
	selected.erase(u)
	_tribe_deed(u, killer)
	if u.type == "div":
		if killer != null and is_instance_valid(killer) and killer.side in [0, 1]:
			res[killer.side].gold += 40
			if killer.side == IRAN:
				add_float(u.position, "+۴۰ طلا", Color("#ffd766"))
				say("دیوی به دست سپاه ایران از پا درآمد! ۴۰ طلا غنیمت.", IRAN)
	elif u.type == "hero":
		heroes_down[u.side] = Defs.HERO_RESPAWN
		say("رستم از پا افتاد… سیمرغ او را بازمی‌گرداند." if u.side == IRAN else "افراسیاب گریخت و در غار پنهان شد!", u.side)
	u.die()
	selection_changed.emit()


func on_building_destroyed(b: Building, _attacker: Node3D) -> void:
	Sfx.play_at("collapse", b.position)
	_remove_structure(b)
	if selected_building == b:
		selected_building = null
		selection_changed.emit()
	b.destroy_visual()
	if b.side == IRAN:
		rig.shake(0.8)
	if b.type == "keep":
		_finish(b.side == TURAN)
	else:
		if b.side == IRAN:
			say("%s ویران شد!" % b.display_name(), TURAN)
			Sfx.voice("building_lost", true)
	_update_zones()


func _finish(win: bool) -> void:
	if finished:
		return
	finished = true
	Sfx.voice("victory" if win else "defeat", true)
	game_over.emit(win)


# ---------------- economy ----------------
## The land changes what work brings in: thin harvests in the snow, little timber in the desert.
const LAND_YIELD := {"snow": {"food": 0.7}, "desert": {"wood": 0.75, "stone": 1.2}, "forest": {"wood": 1.25}, "steppe": {"food": 1.15}}


func land_yield(res_name: String) -> float:
	return float(LAND_YIELD.get("snow" if winter_k > 0.5 else biome, {}).get(res_name, 1.0))


func pop_cap(side: int) -> int:
	var k = keeps[side]
	var cap: int = Defs.KEEP_LEVELS[k.level - 1].pop_cap if k and is_instance_valid(k) else 0
	for b: Building in buildings:
		if b.side == side and b.type == "house":
			cap += Defs.LEVEL_HOUSE[clampi(b.level - 1, 0, Defs.LEVEL_HOUSE.size() - 1)]
	return cap


func pop_used(side: int) -> int:
	var n := 0
	for b: Building in buildings:
		if b.side == side:
			n += Defs.BUILDINGS[b.type].pop
	for u: Unit in units:
		if u.side == side and u.type != "hero" and u.tribe == "":
			n += 1
	for b: Building in buildings:
		if b.side == side and b.type == "barracks":
			n += b.queue.size()
	return n


func starving(side: int) -> bool:
	return _starving[side]


func afford(side: int, cost: Dictionary) -> bool:
	for k in cost:
		if res[side][k] < cost[k]:
			return false
	return true


## What is short for a cost, e.g. "غذا کم است (۱۰ لازم)", or "" when it is affordable.
func missing(side: int, cost: Dictionary) -> String:
	var lack: PackedStringArray = []
	for k in cost:
		if res[side][k] < cost[k]:
			lack.append(Defs.RES_NAMES[k])
	if lack.is_empty():
		return ""
	return "%s کم است" % " و ".join(lack)


func pay(side: int, cost: Dictionary) -> void:
	for k in cost:
		res[side][k] -= cost[k]


func add_resource(side: int, kind: String, amt: int, src: Node3D) -> void:
	res[side][kind] += amt
	if side == IRAN and src != null:
		add_float(src.position + Vector3(0, 3, 0), "+%s %s" % [Defs.fa(amt), Defs.RES_NAMES[kind]], Color("#fff2c4"))


func add_float(p: Vector3, text: String, col: Color) -> void:
	floats.append({"pos": p, "text": text, "color": col, "t": 0.0})


func say(text: String, side: int) -> void:
	message.emit(text, side)


func _economy(dt: float) -> void:
	_tax_t += dt
	if _tax_t >= Defs.TAX_EVERY:
		_tax_t -= Defs.TAX_EVERY
		for s in [IRAN, TURAN]:
			if keeps[s] and not keeps[s].dead:
				res[s].gold += Defs.TAX_GOLD * keeps[s].level
	_village_t += dt
	if _village_t >= Defs.VILLAGE_EVERY:
		_village_t -= Defs.VILLAGE_EVERY
		for v: Building in villages:
			if v.side in [IRAN, TURAN]:
				for k in Defs.VILLAGE_INCOME:
					res[v.side][k] += Defs.VILLAGE_INCOME[k]
				if v.side == IRAN:
					add_float(v.position + Vector3(0, 4, 0), "+۳ طلا  +۳ غذا", Color("#fff2c4"))
	_food_t += dt
	if _food_t >= Defs.FOOD_EVERY:
		_food_t -= Defs.FOOD_EVERY
		for s in [IRAN, TURAN]:
			var eat := ceili(pop_used(s) * Defs.FOOD_PER_10)
			res[s].food -= eat
			var was: bool = _starving[s]
			_starving[s] = res[s].food <= 0
			if res[s].food < 0:
				res[s].food = 0
			if s == IRAN and _starving[s] and not was:
				say("انبار غذا خالی است! مزرعه بساز تا مردم گرسنه نمانند.", TURAN)


func _villages_tick(dt: float) -> void:
	_capture_t += dt
	if _capture_t < 0.25:
		return
	var step := _capture_t
	_capture_t = 0.0
	for v: Building in villages:
		var present := [0, 0]
		var divs_near := false
		for u: Unit in units:
			if u.dead:
				continue
			var d := Vector2(u.position.x - v.position.x, u.position.z - v.position.z).length()
			if u.side == DIVS and d < 12.0:
				divs_near = true
			elif u.side in [IRAN, TURAN] and d < 7.0:
				present[u.side] += 1
		v.capturing = -1
		if divs_near:
			continue
		for s in [IRAN, TURAN]:
			if present[s] > 0 and present[1 - s] == 0 and v.side != s:
				v.capturing = s
				v.capture[s] += step
				v.capture[1 - s] = maxf(0.0, v.capture[1 - s] - step)
				if v.capture[s] >= Defs.CAPTURE_TIME:
					var prev: int = v.side
					v.set_side(s)
					_update_zones()
					Sfx.voice("village_won" if s == IRAN else "village_lost", true)
					for t: Dictionary in tribes:
						if prev == -1 and _flat(t.b.position, v.position) < 45.0:
							_tribe_trust(t, s, Defs.TRIBE_FREE_TRUST, "روستای همسایه آزاد شد")
					if s == IRAN:
						say("روستا به دست ایران افتاد. سرزمین ایران بزرگ‌تر شد!" if prev == -1 else "روستا را از توران پس گرفتیم!", IRAN)
					else:
						say("توران روستایی را گرفت!", TURAN)
		if present[0] == 0 and present[1] == 0:
			for s in [IRAN, TURAN]:
				v.capture[s] = maxf(0.0, v.capture[s] - step * 0.5)


func _update_zones() -> void:
	var zones := []
	for s in [IRAN, TURAN]:
		var k = keeps[s]
		if k and not k.dead:
			zones.append(Vector4(k.position.x, k.position.z, Defs.KEEP_LEVELS[k.level - 1].radius, s))
	for v: Building in villages:
		if v.side in [IRAN, TURAN]:
			zones.append(Vector4(v.position.x, v.position.z, Defs.VILLAGE_RADIUS, v.side))
	terrain.set_zones(zones)


func in_territory(side: int, p: Vector3) -> bool:
	var mine := false
	for s in [IRAN, TURAN]:
		var inside := false
		var k = keeps[s]
		if k and not k.dead and Vector2(p.x - k.position.x, p.z - k.position.z).length() < Defs.KEEP_LEVELS[k.level - 1].radius:
			inside = true
		for v: Building in villages:
			if v.side == s and Vector2(p.x - v.position.x, p.z - v.position.z).length() < Defs.VILLAGE_RADIUS:
				inside = true
		if s == side:
			mine = inside
		elif inside:
			return false
	return mine


# ---------------- main loop ----------------
func _physics_process(dt: float) -> void:
	if finished:
		return
	time += dt
	if stage.has("first_snow") and winter_k == 0.0 and time >= float(stage.first_snow):
		_start_winter()
	_economy(dt)
	_villages_tick(dt)
	_tribes_tick(dt)
	for b: Building in buildings.duplicate():
		b.tick(dt)
	for u: Unit in units.duplicate():
		if not u.dead:
			u.tick(dt)
	_separate()
	for s in [IRAN, TURAN]:
		if heroes_down[s] > 0.0:
			heroes_down[s] -= dt
			if heroes_down[s] <= 0.0:
				heroes_down[s] = 0.0
				if keeps[s] and not keeps[s].dead:
					var h := spawn_unit("hero", s, free_spot_near(keeps[s]))
					say("سیمرغ پر گشود و رستم را به دژ بازگرداند!" if s == IRAN else "افراسیاب از غار پنهانش بیرون آمد!", s)
					if s == IRAN:
						add_float(h.position + Vector3(0, 3, 0), "سیمرغ!", Color("#ffd766"))


func _separate() -> void:
	var buckets := {}
	for u: Unit in units:
		if u.dead:
			continue
		var key := Vector2i(int(floor(u.position.x / 2.0)), int(floor(u.position.z / 2.0)))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(u)
	for key in buckets:
		var list: Array = buckets[key]
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var other = buckets.get(key + Vector2i(dx, dz))
				if other == null:
					continue
				for a in list:
					for b in other:
						if a == b or a.get_instance_id() > b.get_instance_id():
							continue
						var d := Vector2(b.position.x - a.position.x, b.position.z - a.position.z)
						var want: float = (a.radius + b.radius) * 0.85
						var l := d.length()
						if l < want and l > 0.0001:
							# the unit that is standing still makes way for the one on the move
							var push := d / l * (want - l) * 0.7
							var wa := 0.5
							if a.moving != b.moving:
								wa = 0.2 if a.moving else 0.8
							_nudge(a, -push * wa)
							_nudge(b, push * (1.0 - wa))
						elif l <= 0.0001:
							_nudge(a, Vector2(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05)))


func _nudge(u: Unit, v: Vector2) -> void:
	if u.type == "div" and u.state == Unit.State.GUARD:
		v *= 0.3
	var np := Vector3(u.position.x + v.x, 0, u.position.z + v.y)
	var c := Terrain.cell_of(np)
	if grids[clampi(u.side, 0, 2)].is_point_solid(c):
		return
	u.position.x = np.x
	u.position.z = np.z
	u.position.y = terrain.height_at(np.x, np.z)


func _process(dt: float) -> void:
	_music_t -= dt
	if _music_t <= 0.0:
		_music_t = 1.0
		_update_music()
	for f in floats:
		f.t += dt
	floats = floats.filter(func(f): return f.t < 1.6)


# ---------------- player actions (called by the HUD) ----------------
func clear_selection() -> void:
	for u: Unit in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected.clear()
	if selected_building:
		selected_building.set_selected(false)
	selected_building = null
	if mode == "formation":
		mode = "normal"
		formation_armed = ""
	selection_changed.emit()


func select_units(list: Array) -> void:
	clear_selection()
	for u in list:
		if not u.dead and u.side == IRAN:
			selected.append(u)
			u.set_selected(true)
	_chatter("select")
	selection_changed.emit()


func select_building(b: Building) -> void:
	clear_selection()
	selected_building = b
	b.set_selected(true)
	selection_changed.emit()


func select_all_army() -> void:
	select_units(units.filter(func(u): return u.side == IRAN and not u.dead))


func select_hero() -> void:
	for u: Unit in units:
		if u.side == IRAN and u.type == "hero" and not u.dead:
			select_units([u])
			rig.focus(u.position)
			return
	say("رستم هنوز بازنگشته است.", IRAN)


func focus_home() -> void:
	if keeps[IRAN]:
		rig.focus(keeps[IRAN].position)


func stop_selected() -> void:
	for u: Unit in selected:
		u.clear_formation()
		u.state = Unit.State.IDLE
		u.target = null
		u.path = []


func toggle_box_mode() -> void:
	cancel_build()
	mode = "normal" if mode == "box" else "box"
	selection_changed.emit()


func start_build(type: String) -> void:
	powers.cancel()
	clear_selection()
	mode = "build"
	build_type = type
	build_cell = Vector2i(-1, -1)
	wall_start = Vector2i(-1, -1)
	wall_cells = []
	terrain.set_grid_visible(true)
	_update_ghost()
	selection_changed.emit()


func cancel_build() -> void:
	if mode == "build":
		mode = "normal"
	build_type = ""
	build_cell = Vector2i(-1, -1)
	wall_start = Vector2i(-1, -1)
	wall_cells = []
	terrain.set_grid_visible(false)
	_update_ghost()
	selection_changed.emit()


func placement_error(type: String, c: Vector2i) -> String:
	var bd: Dictionary = Defs.BUILDINGS[type]
	var size: int = bd.size
	for j in size:
		for i in size:
			var p := c + Vector2i(i, j)
			if not Terrain.in_grid(p):
				return "بیرون از نقشه است."
			if structure_at(p) != null:
				return "این‌جا ساختمان دیگری هست."
			var t := terrain.type_at(p)
			if t == Terrain.WATER:
				return "روی آب نمی‌شود ساخت."
			if t == Terrain.MOUNTAIN or t == Terrain.ROCK:
				return "زمین سنگلاخ است."
			if t == Terrain.FOREST or terrain.has_tree(p):
				return "این‌جا جنگل است."
			for u: Unit in units:
				if not u.dead and Terrain.cell_of(u.position) == p:
					return "سربازی این‌جا ایستاده است."
	var center := Terrain.cell_center_flat(c) + Vector3((size - 1) * Defs.CELL * 0.5, 0, (size - 1) * Defs.CELL * 0.5)
	if not in_territory(IRAN, center):
		return "بیرون از سرزمین توست. روستاها را بگیر یا دژ را ارتقا بده."
	if bd.get("need") == "trees" and _count_near(c, size, Terrain.FOREST, 5) < 4:
		return "هیزم‌شکن باید نزدیک جنگل باشد."
	if bd.get("need") == "rocks" and _count_near(c, size, Terrain.ROCK, 3) < 2:
		return "معدن باید کنار صخره‌های سنگی باشد."
	if not afford(IRAN, bd.cost):
		return "منابع کافی نیست."
	if bd.pop > 0 and pop_used(IRAN) + bd.pop > pop_cap(IRAN):
		return "کارگر کافی نیست. خانه بساز."
	return ""


func _count_near(c: Vector2i, size: int, type: int, r: int) -> int:
	var n := 0
	for j in range(c.y - r, c.y + size + r):
		for i in range(c.x - r, c.x + size + r):
			if terrain.type_at(Vector2i(i, j)) == type:
				n += 1
	return n


func _wall_line(a: Vector2i, b: Vector2i) -> Array:
	var out := []
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	n = mini(n, 24)
	for k in n + 1:
		var t := 0.0 if n == 0 else float(k) / n
		var p := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


func _build_tap(ground: Vector3) -> void:
	var size: int = Defs.BUILDINGS[build_type].size
	var c := Terrain.cell_of(ground + Vector3(-(size - 1) * Defs.CELL * 0.5, 0, -(size - 1) * Defs.CELL * 0.5))
	# tapping one of your own walls or gates while drawing walls picks it (to remove or turn it)
	var hit = structure_at(Terrain.cell_of(ground))
	if build_type in ["wall", "gate"] and hit != null and hit.side == IRAN and hit.type in ["wall", "gate"] \
			and wall_start.x < 0:
		cancel_build()
		select_building(hit)
		return
	if build_type == "wall":
		if wall_start.x < 0 or wall_cells.size() > 0:
			wall_start = c
			wall_cells = [c]
		else:
			wall_cells = _wall_line(wall_start, c)
	else:
		build_cell = c
	_update_ghost()
	selection_changed.emit()


func confirm_build() -> void:
	if mode != "build":
		return
	if build_type == "wall":
		var placed := 0
		for c in wall_cells:
			if placement_error("wall", c) == "":
				pay(IRAN, Defs.BUILDINGS.wall.cost)
				_add_building("wall", IRAN, c, false)
				_orient_gates_near(c)
				placed += 1
		if placed == 0:
			say("این‌جا دیوار نمی‌شود کشید.", TURAN)
		wall_start = Vector2i(-1, -1)
		wall_cells = []
		_update_ghost()
		selection_changed.emit()
		return
	if build_cell.x < 0:
		return
	var err := placement_error(build_type, build_cell)
	if err != "":
		say(err, TURAN)
		return
	pay(IRAN, Defs.BUILDINGS[build_type].cost)
	Sfx.play("build")
	var b := _add_building(build_type, IRAN, build_cell, false)
	if b.type == "gate":
		_orient_gate(b)
	spawn_dust(b.position, b.size * 0.8)
	var t := build_type
	cancel_build()
	if t in ["wall", "tower", "gate"]:
		start_build(t)


func _update_ghost() -> void:
	for g in _ghosts:
		g.queue_free()
	_ghosts.clear()
	terrain.terrain_material.set_shader_parameter("ghost", Vector4(0, 0, 0, 0))
	ghost_ok = false
	ghost_reason = ""
	if mode != "build":
		return
	var cells_list := []
	if build_type == "wall":
		cells_list = wall_cells
	elif build_cell.x >= 0:
		cells_list = [build_cell]
	var size: int = Defs.BUILDINGS[build_type].size
	var any_ok := false
	for c in cells_list:
		var err := placement_error(build_type, c)
		if err == "":
			any_ok = true
		elif ghost_reason == "":
			ghost_reason = err
		var g := MeshInstance3D.new()
		g.mesh = Models.box_mesh(Vector3(size * Defs.CELL - 0.1, 0.4 if build_type != "wall" else 2.6, size * Defs.CELL - 0.1))
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 1.0, 0.4, 0.4) if err == "" else Color(1.0, 0.25, 0.2, 0.45)
		g.material_override = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := Terrain.cell_center_flat(c) + Vector3((size - 1) * Defs.CELL * 0.5, 0, (size - 1) * Defs.CELL * 0.5)
		center.y = terrain.height_at(center.x, center.z) + (0.2 if build_type != "wall" else 1.3)
		g.position = center
		add_child(g)
		_ghosts.append(g)
	ghost_ok = any_ok
	if any_ok:
		ghost_reason = ""


func can_train(type: String, b: Building = null) -> String:
	var ud: Dictionary = Defs.UNITS[type]
	if b == null:
		b = selected_building
	if ud.has("barracks_level") and (b == null or b.level < ud.barracks_level):
		return "سربازخانه باید سطح %s باشد." % Defs.fa(ud.barracks_level)
	var short := missing(IRAN, ud.cost)
	if short != "":
		return short
	if _starving[IRAN]:
		return "مردم گرسنه‌اند. اول غذا فراهم کن."
	if pop_used(IRAN) + 1 > pop_cap(IRAN):
		return "جمعیت پر است. خانه بساز."
	return ""


func train(type: String) -> void:
	var b := selected_building
	if b == null or b.type != "barracks" or b.side != IRAN:
		return
	var err := can_train(type, b)
	if err != "":
		say(err, TURAN)
		return
	pay(IRAN, Defs.UNITS[type].cost)
	b.queue.append(type)
	selection_changed.emit()


func upgrade_cost(b: Building) -> Dictionary:
	if b.type == "keep":
		return Defs.KEEP_LEVELS[b.level].cost
	return Defs.upgrade_cost(b.type, b.level + 1)


## Empty string when the building can be raised one level, otherwise the reason it cannot.
func can_upgrade(b: Building) -> String:
	if b.level >= b.max_level():
		return "در بالاترین سطح است."
	if b.type != "keep" and b.level >= keeps[b.side].level:
		return "اول دژ را به سطح %s برسان." % Defs.fa(b.level + 1)
	if not afford(b.side, upgrade_cost(b)):
		return "منابع کافی نیست."
	return ""


func upgrade_building(b: Building) -> void:
	if b == null or b.dead or b.side != IRAN:
		return
	var err := can_upgrade(b)
	if err != "":
		say(err, TURAN)
		return
	pay(IRAN, upgrade_cost(b))
	Sfx.play("upgrade")
	Sfx.voice("upgrade")
	b.upgrade()
	spawn_dust(b.position, b.size * 1.3)
	spawn_burst(b.position + Vector3(0, 3.0, 0), Color("#ffd766"), 30, 0.14, 5.0, 1.4, true)
	if b.type == "keep":
		_update_zones()
		say("دژ ایران به سطح %s رسید! سرزمین و جمعیت بیشتر شد و ساختمان‌ها می‌توانند بالاتر بروند." % Defs.fa(b.level), IRAN)
	else:
		say("%s به سطح %s رسید." % [b.display_name(), Defs.fa(b.level)], IRAN)
	selection_changed.emit()


func upgrade_keep() -> void:
	upgrade_building(keeps[IRAN])


func upgrade_selected() -> void:
	upgrade_building(selected_building)


func demolish_selected() -> void:
	var b := selected_building
	if b == null or b.side != IRAN or b.type in ["keep", "village", "camp"]:
		return
	for k in Defs.BUILDINGS[b.type].cost:
		res[IRAN][k] += int(Defs.BUILDINGS[b.type].cost[k] / 2)
	_remove_structure(b)
	b.destroy_visual()
	selected_building = null
	_update_zones()
	selection_changed.emit()


## A gate faces across the wall it sits in: walls east and west of it -> the road runs
## north-south, walls north and south -> it turns a quarter.
func _orient_gate(g: Building) -> void:
	var ew := 0
	var ns := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
		var o = structure_at(g.cell + d)
		if o != null and o.type in ["wall", "gate"]:
			ew += 1
	for d in [Vector2i(0, 1), Vector2i(0, -1)]:
		var o = structure_at(g.cell + d)
		if o != null and o.type in ["wall", "gate"]:
			ns += 1
	if ew != ns:
		g.set_turn(0 if ew > ns else 1)


func _orient_gates_near(c: Vector2i) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var o = structure_at(c + d)
		if o != null and o.type == "gate" and o.side == IRAN:
			_orient_gate(o)


func rotate_selected_gate() -> void:
	var b := selected_building
	if b != null and b.type == "gate" and b.side == IRAN:
		b.set_turn(1 - b.turn)
		Sfx.play("build")


# ---------------- touch input ----------------
func _unhandled_input(ev: InputEvent) -> void:
	if finished:
		return
	if ev is InputEventScreenTouch:
		if ev.pressed and hud.is_over_ui(ev.position):
			_ui_touch[ev.index] = true
			return
		if not ev.pressed and _ui_touch.has(ev.index):
			_ui_touch.erase(ev.index)
			return
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_gesture_moved = false
				_gesture_multi = false
				if mode == "box":
					box_from = ev.position
					box_to = ev.position
					box_active = true
			else:
				_gesture_multi = true
				box_active = false
				_pinch_d = _pinch_distance()
		else:
			_touches.erase(ev.index)
			if _touches.is_empty():
				if box_active:
					box_active = false
					if box_from.distance_to(box_to) > 20.0:
						_box_select()
					else:
						_tap(ev.position)
				elif not _gesture_moved and not _gesture_multi:
					_tap(ev.position)
			_pinch_d = _pinch_distance()
	elif ev is InputEventScreenDrag:
		if _ui_touch.has(ev.index):
			return
		var prev: Vector2 = _touches.get(ev.index, ev.position)
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var d := _pinch_distance()
			if _pinch_d > 0.0 and d > 0.0:
				rig.zoom_by(_pinch_d / d)
			_pinch_d = d
			rig.pan_pixels((ev.position - prev) * 0.5)
			_gesture_moved = true
		elif box_active:
			box_to = ev.position
		else:
			if _gesture_moved or ev.position.distance_to(prev) > 0.0:
				var total: Vector2 = ev.position - prev
				if not _gesture_moved and total.length() < 3.0:
					return
				_gesture_moved = true
				rig.pan_pixels(ev.position - prev)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom_by(0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom_by(1.1)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			cancel_build()
			clear_selection()


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var k := _touches.values()
	return (k[0] as Vector2).distance_to(k[1])


func _pick_unit(screen: Vector2) -> Unit:
	var best: Unit = null
	var bd := 38.0 * get_viewport().get_visible_rect().size.y / 720.0
	for u: Unit in units:
		if u.dead:
			continue
		var wp: Vector3 = u.position + Vector3(0, 1.0, 0)
		if rig.cam.is_position_behind(wp):
			continue
		var sp := rig.cam.unproject_position(wp)
		var d := sp.distance_to(screen)
		if d < bd:
			bd = d
			best = u
	return best


func _pick_building(ground: Vector3) -> Building:
	for b: Building in buildings:
		if b.dead:
			continue
		var h := b.half_extent() + 0.3
		if absf(ground.x - b.position.x) < h and absf(ground.z - b.position.z) < h:
			return b
	return null


func _tap(screen: Vector2) -> void:
	var ground := rig.ground_point(screen, terrain)
	if mode == "power":
		powers.cast_at(ground)
		return
	if mode == "build":
		_build_tap(ground)
		return
	if mode == "formation":
		_formation_tap(screen, ground)
		return
	var u := _pick_unit(screen)
	var b := _pick_building(ground)
	var now := Time.get_ticks_msec() / 1000.0
	if u != null and u.side == IRAN:
		if _last_tap_unit == u and now - _last_tap_t < 0.4:
			# double tap: everyone of this type on screen
			var same := units.filter(func(o): return o.side == IRAN and o.type == u.type and not o.dead \
				and not rig.cam.is_position_behind(o.position) and get_viewport().get_visible_rect().has_point(rig.cam.unproject_position(o.position)))
			select_units(same)
		elif selected.size() > 0 and selected.has(u) and selected.size() > 1:
			select_units([u])
		else:
			select_units([u])
		_last_tap_unit = u
		_last_tap_t = now
		return
	_last_tap_unit = null
	var enemy: Node3D = null
	if u != null and u.side != IRAN:
		enemy = u
	elif b != null and b.side in [TURAN] and b.type != "village":
		enemy = b
	if selected.size() > 0:
		if enemy != null:
			for s in selected:
				s.clear_formation()
				s.order_attack(enemy)
			_chatter("attack")
			_ping(enemy.position, Color("#ff5a4a"))
			return
		_move_selected(ground)
		return
	if b != null:
		select_building(b)
		return
	if enemy != null:
		selection_changed.emit()
		return
	clear_selection()


func _move_selected(ground: Vector3) -> void:
	var n := selected.size()
	var cols := ceili(sqrt(n))
	var spacing := 1.7
	var i := 0
	var sorted := selected.duplicate()
	sorted.sort_custom(func(a, b): return a.position.distance_to(ground) < b.position.distance_to(ground))
	# only hand out spots that join up with the goal: a spot behind a tree line or across
	# water would leave that soldier stranded at the edge while the rest march on
	var region := _reachable_cells(IRAN, Terrain.cell_of(ground), 9)
	var used := {}
	for s in sorted:
		s.clear_formation()
		var row := i / cols
		var col := i % cols
		var off := Vector3((col - (cols - 1) * 0.5) * spacing, 0, (row - (ceili(float(n) / cols) - 1) * 0.5) * spacing)
		off = off.rotated(Vector3.UP, rig.rotation.y)
		var spot := ground + off
		var c := Terrain.cell_of(spot)
		if not region.is_empty() and (not region.has(c) or used.get(c, 0) >= 2):
			var best := c
			var bd := INF
			for rc: Vector2i in region:
				if used.get(rc, 0) >= 2:
					continue
				var d := Vector2(rc - c).length_squared()
				if d < bd:
					bd = d
					best = rc
			if bd < INF:
				var cc := Terrain.cell_center_flat(best)
				spot = Vector3(cc.x + randf_range(-0.4, 0.4), 0, cc.z + randf_range(-0.4, 0.4))
				c = best
		used[c] = used.get(c, 0) + 1
		s.order_move(spot)
		i += 1
	_chatter("move")
	_ping(ground, Color("#ffe18a"))


## Open cells joined to `start` (or the nearest open cell to it), up to `max_r` cells away.
func _reachable_cells(side: int, start: Vector2i, max_r: int) -> Dictionary:
	var g: AStarGrid2D = grids[side]
	var s0 := _nearest_open(side, start)
	var out := {}
	if g.is_point_solid(s0):
		return out
	out[s0] = true
	var queue: Array[Vector2i] = [s0]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + d
			if out.has(nc) or not Terrain.in_grid(nc) or g.is_point_solid(nc):
				continue
			if absi(nc.x - s0.x) > max_r or absi(nc.y - s0.y) > max_r:
				continue
			out[nc] = true
			queue.append(nc)
	return out


## A spoken answer to an order: Rostam answers for himself, otherwise a soldier does.
func _chatter(kind: String) -> void:
	if selected.is_empty():
		return
	var hero_only: bool = selected.size() == 1 and selected[0].type == "hero"
	Sfx.voice(("hero_" + kind) if hero_only else kind)


func _ping(p: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.8
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = Vector3(p.x, terrain.height_at(p.x, p.z) + 0.15, p.z)
	mi.scale = Vector3(1, 0.1, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(2.2, 0.1, 2.2), 0.5)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(mi.queue_free)


func _box_select() -> void:
	var r := Rect2(box_from, Vector2.ZERO).expand(box_to)
	var list := []
	for u: Unit in units:
		if u.side != IRAN or u.dead:
			continue
		var sp := rig.cam.unproject_position(u.position + Vector3(0, 1.0, 0))
		if r.has_point(sp):
			list.append(u)
	select_units(list)
	mode = "normal"
	selection_changed.emit()


# ---------------- battle formations ----------------
signal formation_named(text: String, hint: String)
signal war_started


## Called by the formation icons. Tapping the armed icon again puts it away.
func arm_formation(k: String) -> void:
	if selected.is_empty():
		say("اول سربازانی را انتخاب کن.", TURAN)
		return
	if mode == "formation" and formation_armed == k:
		mode = "normal"
		formation_armed = ""
	else:
		cancel_build()
		mode = "formation"
		formation_armed = k
		formation_named.emit(Defs.FORMATIONS[k].n, Defs.FORMATIONS[k].hint)
	selection_changed.emit()


func _formation_tap(screen: Vector2, ground: Vector3) -> void:
	var k := formation_armed
	var troops: Array = selected.filter(func(u): return is_instance_valid(u) and not u.dead)
	var ok := false
	if not troops.is_empty():
		match k:
			"encircle":
				var picked := _pick_unit(screen)
				ok = _form_encircle(troops, picked.position if picked != null and picked.side != IRAN else ground)
			"ambush":
				ok = _form_ambush(troops, ground)
			"wall":
				ok = _form_wall(troops, ground)
			"wedge":
				ok = _form_wedge(troops, ground)
			"ring":
				ok = _form_ring(troops, ground)
	if ok:
		mode = "normal"
		formation_armed = ""
		_chatter("attack" if k in ["encircle", "wedge"] else "move")
		_ping(ground, Color("#7fe0d0"))
		selection_changed.emit()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Nearest open spot for Iran's soldiers.
func _open_spot(p: Vector3) -> Vector3:
	var c := _nearest_open(IRAN, Terrain.cell_of(p))
	if c == Terrain.cell_of(p):
		return Vector3(p.x, 0, p.z)
	var cc := Terrain.cell_center_flat(c)
	return Vector3(cc.x, 0, cc.z)


func _group_center(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.position
	c /= maxf(1.0, list.size())
	c.y = 0.0
	return c


## Facing from the group towards the tap (or along the camera when tapped in the middle of them).
func _march_dir(troops: Array, ground: Vector3) -> Vector3:
	var d := ground - _group_center(troops)
	d.y = 0.0
	if d.length() < 2.0:
		d = -rig.global_transform.basis.z
		d.y = 0.0
	return d.normalized()


func _place(u: Unit, spot: Vector3, kind: String, face: Vector3, fight := false) -> void:
	u.clear_formation()
	u.order_move(spot, fight)
	u.formation = kind
	u.post = spot
	u.face_dir = face


func _form_encircle(troops: Array, ground: Vector3) -> bool:
	var foes: Array = units.filter(func(u): return not u.dead and u.side != IRAN and not u.hidden and _flat(u.position, ground) < 12.0)
	if foes.is_empty():
		say("برای محاصره روی گروهی از دشمن بزن.", TURAN)
		return false
	var c := _group_center(foes)
	var spread := 0.0
	for f in foes:
		spread = maxf(spread, _flat(f.position, c))
	var r := clampf(spread + 4.0, 5.0, 11.0)
	# keep each soldier on its own side of the ring so the lines do not cross
	var by_angle := troops.duplicate()
	by_angle.sort_custom(func(a, b): return atan2(a.position.z - c.z, a.position.x - c.x) < atan2(b.position.z - c.z, b.position.x - c.x))
	var a0 := atan2(by_angle[0].position.z - c.z, by_angle[0].position.x - c.x)
	var n := by_angle.size()
	for i in n:
		var a := a0 + TAU * i / n
		var spot := _open_spot(c + Vector3(cos(a), 0, sin(a)) * r)
		_place(by_angle[i], spot, "encircle", (c - spot).normalized())
	return true


func _form_ambush(troops: Array, ground: Vector3) -> bool:
	var archers: Array = troops.filter(func(u): return u.type == "archer")
	if archers.is_empty():
		say("فقط کمانداران می‌توانند کمین کنند.", TURAN)
		return false
	var g0 := Terrain.cell_of(ground)
	var spots: Array = []
	for dz in range(-7, 8):
		for dx in range(-7, 8):
			var c := g0 + Vector2i(dx, dz)
			if not Terrain.in_grid(c) or grids[IRAN].is_point_solid(c):
				continue
			if terrain.type_at(c) == Terrain.FOREST or terrain.has_tree(c) or _count_near(c, 1, Terrain.FOREST, 1) >= 3:
				spots.append(c)
	if spots.is_empty():
		say("این‌جا درختی برای کمین نیست. نزدیک درختان بزن.", TURAN)
		return false
	spots.sort_custom(func(a, b): return Vector2(a - g0).length_squared() < Vector2(b - g0).length_squared())
	var face := _march_dir(archers, ground)
	for i in archers.size():
		var cc := Terrain.cell_center_flat(spots[i % spots.size()])
		var jitter := Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)) if i >= spots.size() else Vector3.ZERO
		var spot := Vector3(cc.x, 0, cc.z) + jitter
		_place(archers[i], spot, "ambush", face)
		archers[i].ambush = true
	say("کمانداران به کمین می‌روند. تا تیر نزنند، دشمن آن‌ها را نمی‌بیند.", IRAN)
	return true


func _form_wall(troops: Array, ground: Vector3) -> bool:
	var dir := _march_dir(troops, ground)
	var right := Vector3(-dir.z, 0, dir.x)
	var front: Array = troops.filter(func(u): return u.type != "archer")
	var back: Array = troops.filter(func(u): return u.type == "archer")
	if front.is_empty():
		front = back
		back = []
	_rows(front, ground, dir, right, 0.0, 0.35)
	_rows(back, ground, dir, right, -2.6 - 1.6 * floorf((front.size() - 1) / 8.0), 0.15)
	return true


func _rows(list: Array, origin: Vector3, dir: Vector3, right: Vector3, back_off: float, bonus: float) -> void:
	var per_row := 8
	for i in list.size():
		var row := i / per_row
		var in_row: int = mini(per_row, list.size() - row * per_row)
		var col := i % per_row
		var off := right * (col - (in_row - 1) * 0.5) * 1.5 + dir * (back_off - row * 1.6)
		var spot := _open_spot(origin + off)
		_place(list[i], spot, "wall", dir)
		list[i].hold = true
		list[i].guard_bonus = bonus


func _form_wedge(troops: Array, ground: Vector3) -> bool:
	var dir := _march_dir(troops, ground)
	var right := Vector3(-dir.z, 0, dir.x)
	var rank := {"cav": 0, "hero": 1, "immortal": 2, "spear": 3, "archer": 4}
	var list := troops.duplicate()
	list.sort_custom(func(a, b): return rank.get(a.type, 3) < rank.get(b.type, 3))
	for i in list.size():
		var row := (i + 1) / 2
		var s := 0.0 if i == 0 else (1.0 if i % 2 == 1 else -1.0)
		var spot := _open_spot(ground - dir * row * 1.7 + right * s * row * 1.4)
		_place(list[i], spot, "wedge", dir, true)
		list[i].charge = list[i].type != "archer"
	return true


func _form_ring(troops: Array, ground: Vector3) -> bool:
	var outer: Array = troops.filter(func(u): return u.type != "archer")
	var inner: Array = troops.filter(func(u): return u.type == "archer")
	if outer.is_empty():
		outer = inner
		inner = []
	var r := maxf(2.6, outer.size() * 1.6 / TAU)
	for i in outer.size():
		var a := TAU * i / outer.size()
		var out := Vector3(cos(a), 0, sin(a))
		var spot := _open_spot(ground + out * r)
		_place(outer[i], spot, "ring", out)
		outer[i].hold = true
		outer[i].guard_bonus = 0.25
	for i in inner.size():
		var a := TAU * i / maxf(1, inner.size())
		var out := Vector3(cos(a), 0, sin(a))
		var spot := _open_spot(ground + out * minf(r * 0.45, 1.6))
		_place(inner[i], spot, "ring", out)
		inner[i].hold = true
		inner[i].guard_bonus = 0.25
	return true


func on_ambush_revealed(u: Unit) -> void:
	if time - _ambush_said > 8.0:
		_ambush_said = time
		say("کمانداران از کمین تیر گشودند! دشمن جایشان را یافت.", IRAN)


var _ambush_said := -100.0


# ---------------- the first snow ----------------
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var winter_k := 0.0       # 0 before the snow, 1 when the land is white


## Stages with "first_snow" start in autumn; at that second the sky greys, snow starts
## falling and over a minute it settles on the ground, the trees and the lakes.
func _start_winter() -> void:
	winter_k = 0.0001
	say("آسمان تیره شد... نخستین برف زمستان می‌بارد!", IRAN)
	say("برف کشتزارها را کم‌بار می‌کند. پیش از سرما انبار غذا را پر کن.", TURAN)
	_add_snowfall()
	var a: Dictionary = SKIES.get(biome, SKIES.meadow)
	var b: Dictionary = SKIES.snow
	var tw := create_tween()
	tw.tween_method(func(k: float):
		winter_k = maxf(k, 0.0001)
		terrain.set_winter(k)
		_sky_mat.sky_top_color = Color(a.top).lerp(Color(b.top), k)
		_sky_mat.sky_horizon_color = Color(a.horizon).lerp(Color(b.horizon), k)
		_sky_mat.ground_horizon_color = Color(a.ground).lerp(Color(b.ground), k)
		_env.fog_light_color = Color(a.fog).lerp(Color(b.fog), k)
		_env.fog_density = lerpf(a.fog_d, b.fog_d, k)
		_env.adjustment_saturation = lerpf(a.sat, b.sat, k)
		sun.light_color = Color(a.sun).lerp(Color(b.sun), k)
		sun.light_energy = lerpf(a.sun_e, b.sun_e, k), 0.0, 1.0, 60.0)


# ---------------- music ----------------
var _music_t := 0.0
var _war_music := false
var _calm_t := 0.0
var _wave_t := -100.0


func _on_war_started() -> void:
	_wave_t = time


## Calm music while building up, the war march while fighting; back to calm after a quiet spell.
func _update_music() -> void:
	var fighting: bool = powers.in_battle() or time - _wave_t < 40.0
	if fighting:
		_calm_t = 0.0
	else:
		_calm_t += 1.0
	var want := fighting or (_war_music and _calm_t < 20.0)
	if want == _war_music and Sfx._music.playing:
		return
	_war_music = want
	Sfx.play_music("res://assets/music/war_theme.ogg" if want else "res://assets/music/peace_theme.ogg", -7.0 if want else -6.0)


# ---------------- tribes and pacts ----------------
## Free tribes camp off the road. Gifts and good deeds near their camp win their trust;
## Afrasiab courts them too. At full trust they swear a pact, send warriors now and
## then, and ask a little gold in return.
func _setup_tribes() -> void:
	for i in Defs.CAMP_CELLS.size():
		var td: Dictionary = Defs.TRIBES[i % Defs.TRIBES.size()]
		var c: Vector2i = Defs.CAMP_CELLS[i] - Vector2i(1, 1)
		if not _footprint_free(c, 3):
			# a lake or a wood on this map: pitch the tents on the nearest dry clearing
			var best := c
			var bd := INF
			for dj in range(-10, 11):
				for di in range(-10, 11):
					var o := c + Vector2i(di, dj)
					if Vector2(di, dj).length() < bd and _footprint_free(o, 3):
						bd = Vector2(di, dj).length()
						best = o
			c = best
		var b := _add_building("camp", -1, c)
		b.title = td.n
		tribes.append({"b": b, "n": td.n, "units": td.units, "trust": [0.0, 0.0],
			"send_t": Defs.TRIBE_SEND_EVERY * 0.6, "tribute_t": 0.0, "men": []})


func tribe_of(b: Building) -> Dictionary:
	for t: Dictionary in tribes:
		if t.b == b:
			return t
	return {}


func _rival_rate() -> float:
	return float(Defs.DIFFICULTY[App.difficulty].get("rival", 0.2))


func _tribe_trust(t: Dictionary, side: int, amt: float, why := "") -> void:
	var before: float = t.trust[side]
	var cap := 100.0 if t.b.ally in [-1, side] else Defs.TRIBE_PACT - 1.0
	t.trust[side] = clampf(before + amt, 0.0, cap)
	if side == IRAN and amt > 0.0 and why != "":
		add_float(t.b.position + Vector3(0, 4.5, 0), "+%s اعتماد · %s" % [Defs.fa(int(round(amt))), why], Color("#9fe8c8"))


func gift_tribe(b: Building) -> void:
	var t := tribe_of(b)
	if t.is_empty() or not afford(IRAN, Defs.TRIBE_GIFT):
		return
	pay(IRAN, Defs.TRIBE_GIFT)
	Sfx.play("build")
	# a gift also cools their friendship with Afrasiab
	_tribe_trust(t, TURAN, -25.0 if b.ally == TURAN else -10.0)
	_tribe_trust(t, IRAN, Defs.TRIBE_GIFT_TRUST, "هدیه")
	say("هدیه‌ی ایران به %s رسید." % t.n, IRAN)


func _tribe_deed(u: Unit, killer: Node3D) -> void:
	if killer == null or not is_instance_valid(killer) or not ("side" in killer):
		return
	for t: Dictionary in tribes:
		if _flat(t.b.position, u.position) > Defs.TRIBE_DEED_RADIUS:
			continue
		if killer.side == IRAN and u.side in [TURAN, DIVS] and u.tribe == "":
			_tribe_trust(t, IRAN, Defs.TRIBE_DEED_TRUST, "دلاوری")
		elif killer.side == TURAN and u.side == IRAN and u.tribe == "":
			_tribe_trust(t, TURAN, Defs.TRIBE_DEED_TRUST * 0.6)


var _tribe_tick := 0.0


func _tribes_tick(dt: float) -> void:
	_tribe_tick += dt
	if _tribe_tick < 1.0:
		return
	var step := _tribe_tick
	_tribe_tick = 0.0
	for t: Dictionary in tribes:
		var b: Building = t.b
		t.men = t.men.filter(func(m): return is_instance_valid(m) and not m.dead)
		# Afrasiab's envoys
		if time > Defs.TRIBE_RIVAL_START and b.ally != IRAN:
			_tribe_trust(t, TURAN, _rival_rate() * step)
		elif b.ally == IRAN:
			_tribe_trust(t, TURAN, _rival_rate() * 0.3 * step)
		match b.ally:
			-1:
				for s in [IRAN, TURAN]:
					if t.trust[s] >= Defs.TRIBE_PACT:
						_make_pact(t, s)
						break
			IRAN:
				t.tribute_t += step
				if t.tribute_t >= Defs.TRIBE_TRIBUTE_EVERY:
					t.tribute_t = 0.0
					if res[IRAN].gold >= Defs.TRIBE_TRIBUTE:
						res[IRAN].gold -= Defs.TRIBE_TRIBUTE
						add_float(b.position + Vector3(0, 4.5, 0), "−%s طلا · سهم پیمان" % Defs.fa(Defs.TRIBE_TRIBUTE), Color("#ffd766"))
					else:
						_tribe_trust(t, IRAN, -35.0)
						say("%s سهم پیمان را نگرفتند و دلخورند!" % t.n, TURAN)
				# Afrasiab can lure them away when their trust in Iran runs low
				if t.trust[IRAN] < Defs.TRIBE_BREAK or t.trust[TURAN] > t.trust[IRAN] + 30.0:
					_break_pact(t)
			TURAN:
				if t.trust[TURAN] < Defs.TRIBE_BREAK:
					_break_pact(t)
		# allied warriors
		if b.ally >= 0:
			t.send_t += step
			if t.send_t >= Defs.TRIBE_SEND_EVERY and t.men.size() < Defs.TRIBE_MAX_MEN:
				t.send_t = 0.0
				_send_warriors(t)


func _make_pact(t: Dictionary, s: int) -> void:
	var b: Building = t.b
	b.set_ally(s)
	t.trust[1 - s] = minf(t.trust[1 - s], 40.0)
	t.send_t = Defs.TRIBE_SEND_EVERY - 4.0
	t.tribute_t = 0.0
	if s == IRAN:
		say("%s با ایران پیمان بستند! به‌زودی جنگجو می‌فرستند." % t.n, IRAN)
	else:
		say("%s با افراسیاب پیمان بستند! با هدیه دلشان را برگردان." % t.n, TURAN)
	_ping(b.position, Defs.faction_color[s])
	Sfx.play("horn", -4.0)
	if selected_building == b:
		selection_changed.emit()


func _break_pact(t: Dictionary) -> void:
	var b: Building = t.b
	var was: int = b.ally
	b.set_ally(-1)
	# their warriors go home
	for m: Unit in t.men:
		if is_instance_valid(m) and not m.dead:
			spawn_dust(m.position, 1.0)
			units.erase(m)
			selected.erase(m)
			m.queue_free()
	t.men = []
	if was == IRAN:
		say("%s پیمان با ایران را شکستند!" % t.n, TURAN)
	else:
		say("%s پیمان با توران را شکستند!" % t.n, IRAN)
	if selected_building == b:
		selection_changed.emit()
	selection_changed.emit()


func _send_warriors(t: Dictionary) -> void:
	var b: Building = t.b
	var s: int = b.ally
	for k in Defs.TRIBE_SEND:
		var kind: String = t.units[(t.men.size() + k) % t.units.size()]
		var u := spawn_unit(kind, s, free_spot_near(b))
		u.tribe = t.n
		t.men.append(u)
		if s == IRAN and keeps[IRAN]:
			u.order_move(_open_spot(keeps[IRAN].position + Vector3(randf_range(5, 9), 0, randf_range(-9, -5))))
	if s == IRAN:
		say("%s %s جنگجو به یاری ایران فرستادند." % [t.n, Defs.fa(Defs.TRIBE_SEND)], IRAN)
