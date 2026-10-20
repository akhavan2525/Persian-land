class_name Unit
extends Node3D
## One soldier (or hero, or div). Logic runs in tick() called by the World; visuals animate in _process.

enum State { IDLE, MOVE, ATTACK, GUARD }

var world: Node
var type := "spear"
var side := 0
var def: Dictionary
var hp := 1.0
var max_hp := 1.0
var dead := false
var state := State.IDLE
var target: Node3D = null
var attack_move := false          # AI waves fight whatever they meet on the way
var home := Vector3.ZERO          # divs guard this spot
var path: Array = []
var path_i := 0
var dest := Vector3.ZERO
var cd := 0.0
var repath_t := 0.0
var scan_t := 0.0
var idle_t := 0.0
var radius := 0.45
var selected := false
var last_hit_t := -100.0

var model: Node3D
var rig := {}
var anim: AnimationPlayer
var anim_names := {}
var walk_phase := 0.0
var swing_t := 0.0
var moving := false
var ring: MeshInstance3D
var _fall := 0.0


func setup(w: Node, t: String, o: int, pos: Vector3) -> void:
	world = w
	type = t
	side = o
	def = Defs.UNITS[t]
	max_hp = def.hp
	hp = max_hp
	position = pos
	home = pos
	radius = 1.0 if t in ["cav", "div", "hero"] else 0.55
	var m := Models.make_unit(t, o)
	model = m.root
	model.scale = Vector3.ONE * 1.25
	rig = m.rig
	anim = m.anim
	add_child(model)
	if anim:
		for a in anim.get_animation_list():
			var l := String(a).to_lower()
			for k in ["idle", "walk", "run", "attack"]:
				if l.contains(k) and not anim_names.has(k):
					anim_names[k] = a
		if anim_names.has("run") and not anim_names.has("walk"):
			anim_names["walk"] = anim_names["run"]
	# selection ring
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius + 0.25
	tm.outer_radius = radius + 0.42
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("#ffe18a")
	ring.material_override = rm
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.08
	ring.visible = false
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if t == "div":
		state = State.GUARD


func is_military() -> bool:
	return true


func set_selected(v: bool) -> void:
	selected = v
	ring.visible = v


func display_name() -> String:
	return Defs.unit_name(type, side)


# ---------------- orders ----------------
func order_move(p: Vector3, fight := false) -> void:
	if dead:
		return
	state = State.MOVE
	attack_move = fight
	target = null
	dest = p
	_repath(p)


func order_attack(t: Node3D) -> void:
	if dead or t == null:
		return
	state = State.ATTACK
	target = t
	repath_t = 0.0


func _repath(p: Vector3) -> void:
	path = world.find_path(side, position, p)
	path_i = 0
	repath_t = 1.0


# ---------------- logic ----------------
func tick(dt: float) -> void:
	if dead:
		return
	cd = maxf(0.0, cd - dt)
	scan_t -= dt
	repath_t -= dt
	moving = false
	# slow regeneration when resting (faster for heroes)
	if state == State.IDLE or state == State.GUARD:
		idle_t += dt
		if idle_t > 5.0 and hp < max_hp:
			hp = minf(max_hp, hp + max_hp * (0.03 if type in ["hero", "div"] else 0.015) * dt)
	else:
		idle_t = 0.0
	match state:
		State.IDLE:
			if scan_t <= 0.0:
				scan_t = 0.5
				var aggro := maxf(def.range + 3.0, 10.0)
				var e = world.nearest_enemy(self, aggro, false)
				if e:
					order_attack(e)
		State.GUARD:
			if scan_t <= 0.0:
				scan_t = 0.5
				var e = world.nearest_enemy(self, 9.0, false, home)
				if e:
					state = State.ATTACK
					target = e
			if state == State.GUARD and position.distance_to(home) > 1.5:
				_follow(dt, home)
		State.MOVE:
			if attack_move and scan_t <= 0.0:
				scan_t = 0.5
				var e = world.nearest_enemy(self, 11.0, true)
				if e:
					order_attack(e)
					attack_move = true
					return
			if _follow(dt, dest):
				state = State.IDLE if type != "div" else State.GUARD
		State.ATTACK:
			_attack_tick(dt)


func _target_alive() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		return not (target as Unit).dead
	return not target.dead


func _attack_tick(dt: float) -> void:
	if not _target_alive():
		target = null
		if type == "div":
			state = State.GUARD
		elif attack_move:
			state = State.MOVE
			_repath(dest)
		else:
			state = State.IDLE
		return
	# divs never wander far from their village
	if type == "div" and target.global_position.distance_to(home) > 14.0:
		target = null
		state = State.GUARD
		return
	var d: float = world.distance_to_target(self, target)
	if d <= def.range:
		_face(target.global_position)
		if cd <= 0.0:
			cd = def.cd * randf_range(0.9, 1.1)
			swing_t = 0.35
			if type == "archer":
				world.spawn_arrow(self, target, def.dmg)
			else:
				world.deal_damage(self, target, def.dmg)
		return
	# chase
	if repath_t <= 0.0 or path_i >= path.size():
		_repath(world.approach_point(self, target))
	_follow(dt, world.approach_point(self, target))


## Walks along the current path. Returns true when the destination is reached.
func _follow(dt: float, goal: Vector3) -> bool:
	if path_i >= path.size():
		if path.is_empty() and repath_t <= 0.0:
			_repath(goal)
		var flat := Vector2(goal.x - position.x, goal.z - position.z)
		if flat.length() < 0.6 or path.is_empty():
			return true
		path = [goal]
		path_i = 0
	var wp: Vector3 = path[path_i]
	var to := Vector2(wp.x - position.x, wp.z - position.z)
	var step: float = def.speed * dt
	# blocked by an enemy structure? knock it down
	var nc := Terrain.cell_of(wp)
	var s = world.structure_at(nc)
	if s != null and s.side != side and not s.dead and s.blocks(side) and to.length() < 2.6:
		order_attack(s)
		attack_move = attack_move or side != Defs.IRAN
		return false
	if to.length() <= step:
		position.x = wp.x
		position.z = wp.z
		path_i += 1
	else:
		var dir := to.normalized()
		position.x += dir.x * step
		position.z += dir.y * step
	position.y = world.terrain.height_at(position.x, position.z)
	_face(Vector3(wp.x, position.y, wp.z))
	moving = true
	return false


func _face(p: Vector3) -> void:
	var dir := Vector2(p.x - position.x, p.z - position.z)
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.y)
	rotation.y = lerp_angle(rotation.y, want, 0.25)


func take_damage(amount: float, attacker: Node3D) -> void:
	if dead:
		return
	hp -= amount
	last_hit_t = Time.get_ticks_msec() / 1000.0
	if hp <= 0.0:
		hp = 0.0
		world.on_unit_killed(self, attacker)
		return
	# fight back when idle or guarding
	if attacker != null and is_instance_valid(attacker) and (state == State.IDLE or state == State.GUARD) and attacker.side != side:
		order_attack(attacker)


func die() -> void:
	dead = true
	set_selected(false)
	_fall = 0.001


# ---------------- visuals ----------------
func _process(delta: float) -> void:
	if _fall > 0.0:
		_fall += delta
		model.rotation.x = minf(PI / 2.0, _fall * 4.0) * -1.0
		if _fall > 1.2:
			model.position.y -= delta * 0.6
		if _fall > 3.0:
			queue_free()
		return
	if anim:
		var want = anim_names.get("attack") if swing_t > 0.0 else (anim_names.get("walk") if moving else anim_names.get("idle"))
		if want != null and anim.current_animation != want:
			anim.play(want, 0.15)
		swing_t = maxf(0.0, swing_t - delta)
		return
	if moving:
		walk_phase += delta * (9.0 if type != "cav" else 11.0)
	else:
		walk_phase = lerpf(walk_phase, roundf(walk_phase / PI) * PI, 0.2)
	var s := sin(walk_phase)
	if rig.has("leg_l"):
		rig.leg_l.rotation.x = s * 0.55
		rig.leg_r.rotation.x = -s * 0.55
	if rig.has("hleg0"):
		rig.hleg0.rotation.x = s * 0.5
		rig.hleg3.rotation.x = s * 0.5
		rig.hleg1.rotation.x = -s * 0.5
		rig.hleg2.rotation.x = -s * 0.5
	if rig.has("body"):
		rig.body.position.y = absf(s) * 0.06 if moving else sin(Time.get_ticks_msec() / 600.0 + get_instance_id()) * 0.01
	if rig.has("arm_l"):
		rig.arm_l.rotation.x = -s * 0.3 if moving else 0.0
	if rig.has("arm_r"):
		if swing_t > 0.0:
			swing_t = maxf(0.0, swing_t - delta)
			var k := swing_t / 0.35
			rig.arm_r.rotation.x = -sin(k * PI) * (1.6 if type != "archer" else 0.6)
		else:
			rig.arm_r.rotation.x = s * 0.3 if moving else lerpf(rig.arm_r.rotation.x, 0.0, 0.2)
	if ring.visible:
		ring.rotation.y += delta * 1.5
