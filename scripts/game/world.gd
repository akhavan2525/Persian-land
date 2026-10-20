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
var mode := "normal"            # normal / build / box
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
	randomize()
	_setup_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(randi())
	_setup_grids()
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	res[IRAN] = Defs.START_RES.duplicate()
	res[TURAN] = Defs.START_RES.duplicate()
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
	say("افراسیاب از جیحون گذشته است. دژ را استوار کن و سپاه گرد آور!", TURAN)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("#4f7fc4")
	psm.sky_horizon_color = Color("#e7cfa8")
	psm.ground_bottom_color = Color("#5a4e3e")
	psm.ground_horizon_color = Color("#d9c09a")
	psm.sun_angle_max = 20.0
	psm.sky_energy_multiplier = 1.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color("#d8c7a8")
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-62), 0)
	sun.light_color = Color("#ffe2b8")
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_blur = 1.2
	add_child(sun)


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
	for r in range(1, 8):
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
	var out := []
	for k in range(1, ids.size()):
		var p := Terrain.cell_center_flat(ids[k])
		out.append(p)
	if out.size() > 0 and Terrain.cell_of(to) == b:
		out[out.size() - 1] = Vector3(to.x, 0, to.z)
	return out


func structure_at(c: Vector2i):
	return structures.get(c.y * G + c.x)


# ---------------- setup ----------------
func _setup_castles() -> void:
	keeps[IRAN] = _add_building("keep", IRAN, Defs.KEEP_CELL[IRAN] - Vector2i(2, 2))
	keeps[TURAN] = _add_building("keep", TURAN, Defs.KEEP_CELL[TURAN] - Vector2i(2, 2))
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
			_add_building("tower", TURAN, c)
	for p in [[kc + Vector2i(2, 2), "barracks"], [kc + Vector2i(-5, -5), "house"], [kc + Vector2i(-5, -2), "house"],
			[kc + Vector2i(1, -5), "house"], [kc + Vector2i(-5, 2), "barracks"]]:
		if _footprint_free(p[0], Defs.BUILDINGS[p[1]].size):
			_add_building(p[1], TURAN, p[0])
	for p in [kc + Vector2i(-12, -3), kc + Vector2i(-3, 9), kc + Vector2i(-12, 2)]:
		if _footprint_free(p, 3):
			_add_building("farm", TURAN, p)
	# villages
	for vc in Defs.VILLAGE_CELLS:
		var v := _add_building("village", -1, vc - Vector2i(1, 1))
		villages.append(v)
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
	# divs hold the middle village and one on each side
	for v: Building in villages:
		var n := 2 if v == villages[1] else 1
		for k in n:
			spawn_unit("div", DIVS, v.position + Vector3(2.5 - k * 5.0, 0, 3.0))


func _try_prebuilt(c: Vector2i, gate: bool) -> void:
	if _footprint_free(c, 1):
		_add_building("gate" if gate else "wall", TURAN, c)


func _footprint_free(c: Vector2i, size: int) -> bool:
	for j in size:
		for i in size:
			var p := c + Vector2i(i, j)
			if not Terrain.in_grid(p) or terrain.type_at(p) != Terrain.GRASS or structure_at(p) != null:
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
	var bd := radius
	for u: Unit in units:
		if u.dead or not are_enemies(src.side, u.side):
			continue
		var d := Vector2(u.position.x - c.x, u.position.z - c.z).length()
		if d < bd:
			bd = d
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
	target.take_damage(dmg, attacker)
	if target is Building and target.side == IRAN and randf() < 0.15:
		rig.shake(0.3)


func spawn_arrow(src: Node3D, target: Node3D, dmg: float) -> void:
	var from := src.position + Vector3(0, 1.5, 0)
	if src is Building:
		from.y += 5.0 if src.type == "tower" else 7.5
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
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = 28
	ps.lifetime = 1.6
	ps.explosiveness = 0.85
	ps.position = p + Vector3(0, 1.0, 0)
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = scale_m
	ps.direction = Vector3.UP
	ps.spread = 70.0
	ps.initial_velocity_min = 1.0
	ps.initial_velocity_max = 3.5
	ps.gravity = Vector3(0, -1.0, 0)
	ps.scale_amount_min = 1.0
	ps.scale_amount_max = 2.5
	var m := Models.sphere_mesh(0.5, 1.0, 6)
	ps.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#bba98a", 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ps.material_override = mat
	add_child(ps)
	get_tree().create_timer(2.0).timeout.connect(ps.queue_free)


# ---------------- deaths ----------------
func on_unit_killed(u: Unit, killer: Node3D) -> void:
	units.erase(u)
	selected.erase(u)
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
	_update_zones()


func _finish(win: bool) -> void:
	if finished:
		return
	finished = true
	game_over.emit(win)


# ---------------- economy ----------------
func pop_cap(side: int) -> int:
	var k = keeps[side]
	var cap: int = Defs.KEEP_LEVELS[k.level - 1].pop_cap if k and is_instance_valid(k) else 0
	for b: Building in buildings:
		if b.side == side and b.type == "house":
			cap += Defs.BUILDINGS.house.pop_cap
	return cap


func pop_used(side: int) -> int:
	var n := 0
	for b: Building in buildings:
		if b.side == side:
			n += Defs.BUILDINGS[b.type].pop
	for u: Unit in units:
		if u.side == side and u.type != "hero":
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
	_economy(dt)
	_villages_tick(dt)
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
							var push := d / l * (want - l) * 0.35
							_nudge(a, -push)
							_nudge(b, push)
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
	selection_changed.emit()


func select_units(list: Array) -> void:
	clear_selection()
	for u in list:
		if not u.dead and u.side == IRAN:
			selected.append(u)
			u.set_selected(true)
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
		u.state = Unit.State.IDLE
		u.target = null
		u.path = []


func toggle_box_mode() -> void:
	cancel_build()
	mode = "normal" if mode == "box" else "box"
	selection_changed.emit()


func start_build(type: String) -> void:
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
			if t == Terrain.FOREST:
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
	var b := _add_building(build_type, IRAN, build_cell, false)
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


func can_train(type: String) -> String:
	var ud: Dictionary = Defs.UNITS[type]
	if ud.has("keep_level") and keeps[IRAN].level < ud.keep_level:
		return "دژ باید سطح %s باشد." % Defs.fa(ud.keep_level)
	if not afford(IRAN, ud.cost):
		return "منابع کافی نیست."
	if _starving[IRAN]:
		return "مردم گرسنه‌اند. اول غذا فراهم کن."
	if pop_used(IRAN) + 1 > pop_cap(IRAN):
		return "جمعیت پر است. خانه بساز."
	return ""


func train(type: String) -> void:
	var b := selected_building
	if b == null or b.type != "barracks" or b.side != IRAN:
		return
	var err := can_train(type)
	if err != "":
		say(err, TURAN)
		return
	pay(IRAN, Defs.UNITS[type].cost)
	b.queue.append(type)
	selection_changed.emit()


func upgrade_keep() -> void:
	var k: Building = keeps[IRAN]
	if k.level >= Defs.KEEP_LEVELS.size():
		return
	var cost: Dictionary = Defs.KEEP_LEVELS[k.level].cost
	if not afford(IRAN, cost):
		say("برای ارتقای دژ منابع کافی نیست.", TURAN)
		return
	pay(IRAN, cost)
	k.upgrade()
	spawn_dust(k.position, 5.0)
	_update_zones()
	say("دژ ایران به سطح %s رسید! سرزمین و جمعیت بیشتر شد." % Defs.fa(k.level), IRAN)
	selection_changed.emit()


func demolish_selected() -> void:
	var b := selected_building
	if b == null or b.side != IRAN or b.type in ["keep", "village"]:
		return
	for k in Defs.BUILDINGS[b.type].cost:
		res[IRAN][k] += int(Defs.BUILDINGS[b.type].cost[k] / 2)
	_remove_structure(b)
	b.destroy_visual()
	selected_building = null
	_update_zones()
	selection_changed.emit()


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
	if mode == "build":
		_build_tap(ground)
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
				s.order_attack(enemy)
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
	for s in sorted:
		var row := i / cols
		var col := i % cols
		var off := Vector3((col - (cols - 1) * 0.5) * spacing, 0, (row - (ceili(float(n) / cols) - 1) * 0.5) * spacing)
		off = off.rotated(Vector3.UP, rig.rotation.y)
		s.order_move(ground + off)
		i += 1
	_ping(ground, Color("#ffe18a"))


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
