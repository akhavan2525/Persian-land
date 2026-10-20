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
var prod_t := 0.0
var atk_cd := 0.0
var queue: Array = []          # unit types waiting to be trained
var train_t := 0.0
var capture := {0: 0.0, 1: 0.0}
var capturing := -1
var selected := false
var _rise := 1.0
var last_hit_t := -100.0


func setup(w: Node, t: String, s: int, c: Vector2i, lvl := 1, instant := true) -> void:
	world = w
	type = t
	side = s
	cell = c
	level = lvl
	size = Defs.BUILDINGS[t].size
	max_hp = Defs.KEEP_LEVELS[level - 1].hp if t == "keep" else float(Defs.BUILDINGS[t].hp)
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
	if type == "village" or type == "farm":
		return false
	if type == "gate" and for_side == side:
		return false
	return true


func display_name() -> String:
	var n: String = Defs.BUILDINGS[type].n
	if type == "keep":
		n = "دژ %s" % Defs.FACTIONS[side].n if side >= 0 else n
	return n


func _rebuild_model() -> void:
	if model:
		model.queue_free()
	model = Models.make_building(type, side, level)
	add_child(model)
	if type in ["wall", "gate"]:
		model.rotation.y = 0.0
	elif type != "keep":
		model.rotation.y = [0.0, PI * 0.5, PI, PI * 1.5][(cell.x * 7 + cell.y * 3) % 4] if type in ["house", "woodcutter", "quarry"] else 0.0


func set_side(s: int) -> void:
	side = s
	capture = {0: 0.0, 1: 0.0}
	_rebuild_model()


func upgrade() -> void:
	level += 1
	var frac := hp / max_hp
	max_hp = Defs.KEEP_LEVELS[level - 1].hp
	hp = max_hp * maxf(frac, 0.6)
	_rebuild_model()
	_rise = 0.3


func set_selected(v: bool) -> void:
	selected = v


func take_damage(amount: float, attacker: Node3D) -> void:
	if dead or type == "village":
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
			world.add_resource(side, bd.res, bd.amt, self)
	if type == "barracks" and queue.size() > 0:
		train_t += dt
		if train_t >= Defs.UNITS[queue[0]].time:
			var t: String = queue.pop_front()
			train_t = 0.0
			world.spawn_unit(t, side, world.free_spot_near(self))
	var arrow = null
	if type == "tower":
		arrow = Defs.BUILDINGS.tower
	elif type == "keep":
		arrow = Defs.KEEP_ARROW
	if arrow != null:
		atk_cd -= dt
		if atk_cd <= 0.0:
			var e = world.nearest_enemy(self, arrow.range, false)
			if e and e is Unit:
				atk_cd = arrow.cd
				world.spawn_arrow(self, e, arrow.dmg * (1.0 + (level - 1) * 0.35))
			else:
				atk_cd = 0.4


func _process(delta: float) -> void:
	if _rise < 1.0:
		_rise = minf(1.0, _rise + delta / 1.4)
		var k := ease(_rise, 0.4)
		model.scale = Vector3(1.0, maxf(0.02, k), 1.0)
