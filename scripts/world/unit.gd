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
var dmg_mult := 1.0
var _prog_pos := Vector3.ZERO     # where the unit was at the last progress check
var _prog_t := 0.0
var _stuck_n := 0                 # progress checks in a row with almost no movement
var _crowd_t := 0.0
var _retarget_t := 0.0

# battle formations (see World.apply_formation)
var formation := ""               # the formation this unit is standing in, "" for none
var hold := false                 # keep the post: fight what comes close, do not chase far
var post := Vector3.ZERO          # its place in the formation
var face_dir := Vector3.ZERO      # which way to look once there
var guard_bonus := 0.0            # less harm taken while standing at its post
var charge := false               # wedge: faster march, the first blow lands twice as hard
var ambush := false               # archers on their way to hide among the trees
var hidden := false               # hidden archers are invisible to the enemy until they shoot
var tribe := ""                # warriors lent by an allied tribe

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
		for k in ["idle", "walk"]:
			if anim_names.has(k):
				anim.get_animation(anim_names[k]).loop_mode = Animation.LOOP_LINEAR
		if anim_names.has("attack"):
			anim.get_animation(anim_names["attack"]).loop_mode = Animation.LOOP_NONE
		anim.speed_scale = randf_range(0.92, 1.08)
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


## Troops from a fully upgraded barracks.
func make_veteran() -> void:
	max_hp *= 1.0 + Defs.VETERAN_BONUS
	hp = max_hp
	dmg_mult = 1.0 + Defs.VETERAN_BONUS


func is_military() -> bool:
	return true


func set_selected(v: bool) -> void:
	selected = v
	ring.visible = v


func display_name() -> String:
	if tribe != "":
		return "%s · %s" % [Defs.unit_name(type, side), tribe]
	return Defs.unit_name(type, side)


# ---------------- formations ----------------
## Drops any formation, e.g. when the player gives a new plain order.
func clear_formation() -> void:
	formation = ""
	hold = false
	guard_bonus = 0.0
	charge = false
	ambush = false
	face_dir = Vector3.ZERO
	set_hidden(false)


func at_post() -> bool:
	return Vector2(post.x - position.x, post.z - position.z).length() < 1.6


## Harm taken is multiplied by this (shield wall and the defensive ring guard their men).
func harm_mult() -> float:
	if hold and guard_bonus > 0.0 and at_post():
		return 1.0 - guard_bonus
	return 1.0


func move_speed() -> float:
	return def.speed * (1.25 if charge and state != State.ATTACK else 1.0)


func set_hidden(v: bool) -> void:
	if hidden == v:
		return
	hidden = v
	# our own player still sees them, faded like a shadow among the trees
	for mi in model.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 0.55 if v else 0.0
	if v and target != null:
		target = null
		state = State.IDLE


## Shoots from cover: the enemy learns where the archer stands.
func reveal() -> void:
	if hidden:
		set_hidden(false)
		ambush = false
		formation = ""


# ---------------- orders ----------------
func order_move(p: Vector3, fight := false) -> void:
	if dead:
		return
	state = State.MOVE
	attack_move = fight
	target = null
	dest = p
	_reset_progress()
	_repath(p)


func order_attack(t: Node3D) -> void:
	if dead or t == null:
		return
	state = State.ATTACK
	target = t
	repath_t = 0.0
	_reset_progress()


func _reset_progress() -> void:
	_prog_pos = position
	_prog_t = 0.0
	_stuck_n = 0


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
				if hold and type != "archer":
					aggro = def.range + 2.5     # a wall waits for the enemy to come to it
				var e = world.nearest_enemy(self, aggro, false)
				if e:
					order_attack(e)
			if state != State.IDLE:
				pass
			elif ambush and not hidden and at_post():
				set_hidden(true)
			elif hold and not at_post() and not hidden:
				# pushed out of line: step back into place
				state = State.MOVE
				dest = post
				_repath(post)
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
			if _follow(dt, dest) or _arrived_in_crowd(dt):
				_arrive()
		State.ATTACK:
			_attack_tick(dt)


func _arrive() -> void:
	state = State.IDLE if type != "div" else State.GUARD
	if face_dir != Vector3.ZERO:
		rotation.y = atan2(-face_dir.x, -face_dir.z)
	if formation == "encircle":
		# the ring is closed: strike the nearest foe inside it
		var e = world.nearest_enemy(self, 16.0, false)
		if e:
			order_attack(e)
	path = []
	path_i = 0
	_stuck_n = 0


## A group sent to one spot cannot all stand on it: stop once close and touching
## a friend who has already arrived, or when pushed around near the goal for a while.
func _arrived_in_crowd(dt: float) -> bool:
	var dd := Vector2(dest.x - position.x, dest.z - position.z).length()
	if dd > 4.0:
		return _stuck_n >= 6       # hopeless: give up rather than push forever
	if _stuck_n >= 2:
		return true
	if dd > 2.4:
		return false
	_crowd_t -= dt
	if _crowd_t > 0.0:
		return false
	_crowd_t = 0.25
	for u: Unit in world.units:
		if u == self or u.dead or u.side != side or u.state == State.MOVE:
			continue
		var d := Vector2(u.position.x - position.x, u.position.z - position.z).length()
		if d < radius + u.radius + 0.4 and Vector2(dest.x - u.position.x, dest.z - u.position.z).length() < 3.0:
			return true
	return false


func _target_alive() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is Unit:
		if (target as Unit).hidden and (target as Unit).side != side:
			return false
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
	if hold and d > def.range and position.distance_to(post) > 3.0:
		# do not chase far from the line: go back to the post
		target = null
		state = State.MOVE
		dest = post
		_repath(post)
		return
	if d > def.range:
		_retarget_t -= dt
		if _retarget_t <= 0.0:
			_retarget_t = 0.6
			# someone else already in reach (or an enemy soldier while we walk to a building)? fight them instead
			var near = world.nearest_enemy(self, maxf(def.range + 0.6, 6.0 if target is Building else 0.0), false)
			if near != null and near != target and (target is Building or world.distance_to_target(self, near) <= def.range + 0.3):
				target = near
				_reset_progress()
				d = world.distance_to_target(self, target)
			elif _stuck_n >= 4:
				# cannot reach this target: look for another, or give up
				var other = world.nearest_enemy(self, maxf(def.range + 3.0, 10.0), attack_move)
				_reset_progress()
				if other != null and other != target:
					target = other
				else:
					target = null
					state = State.IDLE if type != "div" else State.GUARD
					return
	if d <= def.range:
		_face(target.global_position)
		if cd <= 0.0:
			cd = def.cd * randf_range(0.9, 1.1)
			swing_t = 0.35
			if anim and anim_names.has("attack"):
				swing_t = anim.get_animation(anim_names["attack"]).length / anim.speed_scale
				anim.play(anim_names["attack"], 0.08)
				anim.seek(0.0, true)
			if type == "archer":
				if hidden:
					reveal()
					world.on_ambush_revealed(self)
				world.spawn_arrow(self, target, def.dmg * dmg_mult)
			else:
				var blow: float = def.dmg * dmg_mult
				if charge:
					# the wedge strikes: horsemen hit twice as hard, foot soldiers half again
					blow *= 2.0 if type == "cav" else 1.5
					charge = false
					formation = ""
				world.deal_damage(self, target, blow)
		return
	# chase: close in directly when the way is clear, otherwise follow a fresh path
	var goal: Vector3 = world.approach_point(self, target)
	if target is Unit and position.distance_to(goal) < 9.0 and world.clear_line(side, position, goal):
		path = [Vector3(goal.x, 0, goal.z)]
		path_i = 0
		repath_t = 0.3
	elif repath_t <= 0.0 or path_i >= path.size():
		_repath(goal)
	_follow(dt, goal)


## Walks along the current path. Returns true when the destination is reached.
func _follow(dt: float, goal: Vector3) -> bool:
	if path_i >= path.size():
		if path.is_empty() and repath_t <= 0.0:
			_repath(goal)
		if path_i >= path.size():
			return true     # at the goal, or as close as the map allows
	_check_progress(dt, goal)
	var wp: Vector3 = path[path_i]
	var to := Vector2(wp.x - position.x, wp.z - position.z)
	var step: float = move_speed() * dt
	# corners do not need to be hit exactly; this keeps groups flowing through them
	if path_i < path.size() - 1 and to.length() < 0.6:
		path_i += 1
		wp = path[path_i]
		to = Vector2(wp.x - position.x, wp.z - position.z)
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


## Notices when the unit has barely moved for a while (pushed by friends, wedged on a
## corner) and finds a new way; the callers decide when to give up.
func _check_progress(dt: float, goal: Vector3) -> void:
	_prog_t += dt
	if _prog_t < 1.2:
		return
	var moved := Vector2(position.x - _prog_pos.x, position.z - _prog_pos.z).length()
	if moved < move_speed() * 0.3:
		_stuck_n += 1
		var g := goal
		if _stuck_n >= 2:
			# step around whatever is in the way
			var side_dir := Vector3(goal.z - position.z, 0, position.x - goal.x).normalized() * (1.5 if _stuck_n % 2 == 0 else -1.5)
			g = position + side_dir
			path = world.find_path(side, position, g) + world.find_path(side, g, goal)
			path_i = 0
			repath_t = 1.5
		else:
			_repath(g)
	else:
		_stuck_n = 0
	_prog_t = 0.0
	_prog_pos = position


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
		if hold and type != "archer" and position.distance_to(attacker.position) > def.range + 3.0:
			return     # arrows from afar do not break the line
		if hidden:
			return     # still unseen: keep waiting for a clear shot
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
		elif want == null and not moving and anim.is_playing() and swing_t <= 0.0:
			# model has no idle clip: hold the first frame of the walk instead of walking on the spot
			anim.seek(0.0, true)
			anim.pause()
		if swing_t > 0.0 and not anim_names.has("attack"):
			# model has no attack clip: lunge forward and back
			var k := swing_t / 0.35
			model.position.z = -sin(k * PI) * 0.35
			model.rotation.x = -sin(k * PI) * 0.12
		elif not anim_names.has("attack"):
			model.position.z = 0.0
			model.rotation.x = 0.0 if _fall <= 0.0 else model.rotation.x
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
