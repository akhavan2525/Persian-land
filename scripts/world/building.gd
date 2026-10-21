class_name Building
extends Node3D
## A structure on the grid: keep, house, farm, wall, tower, village...

var world: Node
var type := "house"
var side := 0                  # -1 = nobody (free village)
var cell := Vector2i.ZERO      # top-left cell of the footprint
var size := 1
var hp := 1.0
var max_hp := 1.0
var level := 1
var dead := false
var model: Node3D
var fire: Node3D = null
var _fire_t := 0.0
var marks: Node3D               # level banners, kept outside the model so its scale does not touch them
var prod_t := 0.0
var atk_cd := 0.0
var queue: Array = []          # unit types waiting to be trained
var train_t := 0.0
var capture := {0: 0.0, 1: 0.0}
var capturing := -1
var selected := false
var _rise := 1.0
var _base_scale := Vector3.ONE
var last_hit_t := -100.0
var turn := 0                  # gate: 1 = turned a quarter
var ally := -1                 # camp: the side its tribe is pledged to
var title := ""                # camp: the tribe's name


func setup(w: Node, t: String, s: int, c: Vector2i, lvl := 1, instant := true) -> void:
	world = w
	type = t
	side = s
	cell = c
	level = lvl
	size = Defs.BUILDINGS[t].size
	max_hp = _level_hp()
	hp = max_hp
	position = center_flat()
	position.y = _ground_y()
	prod_t = randf() * 3.0
	_rebuild_model()
	if not instant:
		_rise = 0.0


func center_flat() -> Vector3:
	var a := Terrain.cell_center_flat(cell)
	var b := Terrain.cell_center_flat(cell + Vector2i(size - 1, size - 1))
	return (a + b) * 0.5


func _ground_y() -> float:
	var lo := INF
	for j in size:
		for i in size:
			var p := Terrain.cell_center_flat(cell + Vector2i(i, j))
			lo = minf(lo, world.terrain.height_at(p.x, p.z))
	var c := center_flat()
	return lerpf(lo, world.terrain.height_at(c.x, c.z), 0.5)


func cells() -> Array:
	var o := []
	for j in size:
		for i in size:
			o.append(cell + Vector2i(i, j))
	return o


func half_extent() -> float:
	return size * Defs.CELL * 0.5


func blocks(for_side: int) -> bool:
	if type in ["village", "farm", "camp"]:
		return false
	if type == "gate" and for_side == side:
		return false
	return true


func display_name() -> String:
	var n: String = Defs.BUILDINGS[type].n
	if title != "":
		return title
	if type == "keep":
		n = "دژ %s" % Defs.FACTIONS[side].n if side >= 0 else n
	return n


func _rebuild_model() -> void:
	if model:
		model.queue_free()
	model = Models.make_building(type, ally if type == "camp" else side, level)
	add_child(model)
	if marks:
		marks.queue_free()
	marks = Models.level_marks(type, side, level)
	marks.position.y = 0.05
	add_child(marks)
	if type == "tower":
		# each level raises the tower a little higher, banners and all
		_base_scale = Vector3(1.0 + (level - 1) * 0.05, 1.0 + (level - 1) * 0.13, 1.0 + (level - 1) * 0.05)
		model.scale = _base_scale
		marks.scale = _base_scale
	if type in ["wall", "gate"]:
		model.rotation.y = PI * 0.5 * turn if type == "gate" else 0.0
	elif type != "keep":
		model.rotation.y = [0.0, PI * 0.5, PI, PI * 1.5][(cell.x * 7 + cell.y * 3) % 4] if type in ["house", "woodcutter", "quarry"] else 0.0


func set_turn(t: int) -> void:
	turn = t
	_rebuild_model()


func set_ally(s: int) -> void:
	ally = s
	_rebuild_model()


func set_side(s: int) -> void:
	side = s
	capture = {0: 0.0, 1: 0.0}
	_rebuild_model()


func _level_hp() -> float:
	if type == "keep":
		return Defs.KEEP_LEVELS[level - 1].hp
	return float(Defs.BUILDINGS[type].hp) * Defs.LEVEL_HP[clampi(level - 1, 0, Defs.LEVEL_HP.size() - 1)]


func max_level() -> int:
	if type == "keep":
		return Defs.KEEP_LEVELS.size()
	return Defs.MAX_LEVEL.get(type, 1)


func upgrade() -> void:
	level += 1
	var frac := hp / max_hp
	max_hp = _level_hp()
	hp = max_hp * maxf(frac, 0.6)
	_rebuild_model()
	_rise = 0.3


## Seconds to train one unit here.
func train_time(t: String) -> float:
	return Defs.UNITS[t].time * Defs.LEVEL_TRAIN[clampi(level - 1, 0, Defs.LEVEL_TRAIN.size() - 1)]


func set_selected(v: bool) -> void:
	selected = v


func take_damage(amount: float, attacker: Node3D) -> void:
	if dead or type in ["village", "camp"]:
		return
	hp -= amount
	last_hit_t = Time.get_ticks_msec() / 1000.0
	if hp <= 0.0:
		hp = 0.0
		world.on_building_destroyed(self, attacker)


func destroy_visual() -> void:
	dead = true
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 4.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "rotation:z", randf_range(-0.15, 0.15), 1.6)
	tw.tween_callback(queue_free)
	world.spawn_dust(global_position, size * 1.4)


# ---------------- logic ----------------
func tick(dt: float) -> void:
	if dead:
		return
	var bd: Dictionary = Defs.BUILDINGS[type]
	if bd.has("res") and side >= 0:
		var rate := 0.5 if world.starving(side) else 1.0
		prod_t += dt * rate
		if prod_t >= bd.every:
			prod_t -= bd.every
			world.add_resource(side, bd.res, int(round(bd.amt * Defs.LEVEL_PROD[clampi(level - 1, 0, 2)] * world.land_yield(bd.res))), self)
	if type == "barracks" and queue.size() > 0:
		train_t += dt
		if train_t >= train_time(queue[0]):
			var t: String = queue.pop_front()
			train_t = 0.0
			var u: Unit = world.spawn_unit(t, side, world.free_spot_near(self))
			if level >= 4 and side != Defs.IRAN:
				u.make_veteran()    # Iran's soldiers grow stronger through their rank instead
			if side == Defs.IRAN:
				Sfx.voice("trained")
	var arrow = null
	if type == "tower":
		arrow = Defs.BUILDINGS.tower
	elif type == "keep":
		arrow = Defs.KEEP_ARROW
	if arrow != null:
		atk_cd -= dt
		if atk_cd <= 0.0:
			var e = world.nearest_enemy(self, arrow.range + (level - 1) * 2.0, false)
			if e and e is Unit:
				atk_cd = arrow.cd
				world.spawn_arrow(self, e, arrow.dmg * (1.0 + (level - 1) * 0.35))
			else:
				atk_cd = 0.4


## Fire and smoke on a badly damaged building.
func _update_fire() -> void:
	var want := not dead and type not in ["village", "camp"] and hp < max_hp * 0.45
	if want == (fire != null):
		return
	if not want:
		fire.queue_free()
		fire = null
		return
	fire = Node3D.new()
	add_child(fire)
	var e := half_extent() * 0.55
	var flames := FX.flames(Vector3(e, 0.3, e), 28, 1.3)
	flames.position = Vector3(0, 1.4, 0)
	fire.add_child(flames)
	var smoke := FX.smoke(Vector3(e * 0.6, 0.3, e * 0.6), 12, 2.6)
	smoke.position = Vector3(0, 2.6, 0)
	fire.add_child(smoke)


func _process(delta: float) -> void:
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = 0.5
		_update_fire()
	if _rise < 1.0:
		_rise = minf(1.0, _rise + delta / 1.4)
		var k := ease(_rise, 0.4)
		model.scale = _base_scale * Vector3(1.0, maxf(0.02, k), 1.0)
