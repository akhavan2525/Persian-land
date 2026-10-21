class_name Powers
extends Node
## Iran's four war powers: arrow rain, fire, lightning and the Simorgh's healing.
## Each one charges over time, three times faster while Iran is fighting.

signal changed

var world: Node
var charge := {}            # power -> 0..1
var armed := ""             # power waiting for a tap on the ground
var _battle_t := 0.0        # seconds since Iran last dealt or took damage
var _fires: Array = []      # {pos, t, node}


func setup(w: Node) -> void:
	world = w
	for k in Defs.POWER_ORDER:
		charge[k] = 0.35


func note_battle() -> void:
	_battle_t = 0.0


func in_battle() -> bool:
	return _battle_t < 6.0


func ready_to_use(k: String) -> bool:
	return charge.get(k, 0.0) >= 1.0


## Called by the power buttons. Targeted powers wait for a tap; the Simorgh acts at once.
func press(k: String) -> void:
	if not ready_to_use(k):
		world.say("%s هنوز آماده نیست." % Defs.POWERS[k].n, Defs.TURAN)
		return
	if not Defs.POWERS[k].target:
		_use(k, Vector3.ZERO)
		return
	if armed == k:
		armed = ""
		world.mode = "normal"
	else:
		world.cancel_build()
		armed = k
		world.mode = "power"
		world.say("روی زمین بزن تا %s فرود آید." % Defs.POWERS[k].n, Defs.IRAN)
	changed.emit()


func cast_at(p: Vector3) -> void:
	if armed == "":
		return
	var k := armed
	armed = ""
	world.mode = "normal"
	_use(k, p)


func cancel() -> void:
	if armed != "":
		armed = ""
		world.mode = "normal"
		changed.emit()


func _use(k: String, p: Vector3) -> void:
	charge[k] = 0.0
	match k:
		"arrows": _arrow_rain(p)
		"fire": _fire(p)
		"lightning": _lightning(p)
		"simorgh": _simorgh()
	Sfx.play("power_" + k)
	Sfx.voice("power_" + k, true)
	changed.emit()


func _physics_process(dt: float) -> void:
	if world == null or world.finished:
		return
	_battle_t += dt
	var rate := 3.0 if in_battle() else 1.0
	for k in charge:
		var was: bool = charge[k] >= 1.0
		charge[k] = minf(1.0, charge[k] + dt * rate / Defs.POWERS[k].charge)
		if not was and charge[k] >= 1.0:
			world.say("%s آماده است!" % Defs.POWERS[k].n, Defs.IRAN)
			changed.emit()
	_tick_fires(dt)


# ---------------- helpers ----------------
func _enemies_near(p: Vector3, r: float) -> Array:
	return world.units.filter(func(u): return not u.dead and u.side != Defs.IRAN \
		and Vector2(u.position.x - p.x, u.position.z - p.z).length() < r)


func _buildings_near(p: Vector3, r: float) -> Array:
	return world.buildings.filter(func(b): return not b.dead and b.side == Defs.TURAN \
		and Vector2(b.position.x - p.x, b.position.z - p.z).length() < r + b.half_extent())


func _glow_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.terrain.height_at(p.x, p.z), p.z)


func _ring(p: Vector3, r: float, c: Color, life := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.25
	tm.outer_radius = r
	tm.rings = 48
	tm.ring_segments = 4
	mi.mesh = tm
	var m := _glow_mat(c, 2.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.scale = Vector3(0.2, 0.2, 0.2)
	mi.position = _ground(p) + Vector3(0, 0.2, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1, 0.3, 1), life * 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, life)
	tw.tween_callback(mi.queue_free)


func _flash(p: Vector3, c: Color, energy: float, rng: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = p
	world.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(l.queue_free)


# ---------------- arrow rain ----------------
func _arrow_rain(p: Vector3) -> void:
	var r: float = Defs.POWERS.arrows.radius
	_ring(p, r, Color("#ffe18a"), 3.0)
	world.say("بارش تیر! آسمان سیاه شد.", Defs.IRAN)
	for i in 70:
		var delay := i * 0.035
		var a := randf() * TAU
		var d := sqrt(randf()) * r
		var hit := _ground(p + Vector3(cos(a) * d, 0, sin(a) * d))
		get_tree().create_timer(delay).timeout.connect(_one_arrow.bind(hit))


func _one_arrow(hit: Vector3) -> void:
	if not is_instance_valid(world):
		return
	var arrow := MeshInstance3D.new()
	arrow.mesh = Models.cyl_mesh(0.03, 0.03, 1.0, 4)
	arrow.material_override = Models.mat(Color("#2e2014"))
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var from := hit + Vector3(-6, 22, -4)
	arrow.position = from
	world.add_child(arrow)
	arrow.look_at_from_position(from, hit, Vector3.RIGHT)
	arrow.rotate_object_local(Vector3.RIGHT, PI / 2)
	var tw := arrow.create_tween()
	tw.tween_property(arrow, "position", hit + Vector3(0, 0.35, 0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		for u in _enemies_near(hit, 1.4):
			u.take_damage(9.0 * (1.0 - float(Defs.UNITS[u.type].armor) * 0.5), null)
			world.spawn_burst(u.position + Vector3(0, 1.1, 0), Color("#9c1f17"), 5, 0.1, 2.0, 0.4)
		world.spawn_burst(hit + Vector3(0, 0.2, 0), Color("#a8916c"), 3, 0.08, 1.5, 0.3))
	tw.tween_interval(1.2)
	tw.tween_callback(arrow.queue_free)


# ---------------- fire ----------------
func _fire(p: Vector3) -> void:
	var r: float = Defs.POWERS.fire.radius
	var g := _ground(p)
	_ring(g, r, Color("#ff7a1a"), 1.5)
	_flash(g + Vector3(0, 3, 0), Color("#ff8a2a"), 6.0, r * 3.0, 7.0)
	world.say("آتش! زمین زیر پای دشمن شعله‌ور شد.", Defs.IRAN)
	var node := Node3D.new()
	node.position = g
	world.add_child(node)
	node.add_child(FX.flames(Vector3(r * 0.75, 0.2, r * 0.75), 150, 1.6))
	_fires.append({"pos": g, "t": 7.0, "tick": 0.0, "node": node})


func _tick_fires(dt: float) -> void:
	for f in _fires.duplicate():
		f.t -= dt
		f.tick -= dt
		if f.tick <= 0.0:
			f.tick = 0.5
			var r: float = Defs.POWERS.fire.radius
			for u in _enemies_near(f.pos, r):
				u.take_damage(6.0, null)
			for b in _buildings_near(f.pos, r):
				b.take_damage(45.0, null)
		if f.t <= 0.0:
			_fires.erase(f)
			for c in f.node.get_children():
				if c is CPUParticles3D:
					c.emitting = false
			get_tree().create_timer(3.0).timeout.connect(f.node.queue_free)


# ---------------- lightning ----------------
func _lightning(p: Vector3) -> void:
	var r: float = Defs.POWERS.lightning.radius
	world.say("رعد و برق! آسمان بر سر دشمن خروشید.", Defs.IRAN)
	_ring(p, r, Color("#b9d8ff"), 2.0)
	for i in 5:
		var a := randf() * TAU
		var d := 0.0 if i == 0 else sqrt(randf()) * r
		var at := p + Vector3(cos(a) * d, 0, sin(a) * d)
		get_tree().create_timer(i * 0.32).timeout.connect(_bolt.bind(_ground(at)))


func _bolt(g: Vector3) -> void:
	if not is_instance_valid(world):
		return
	var root := Node3D.new()
	world.add_child(root)
	var m := _glow_mat(Color("#dfeeff"), 6.0)
	var top := g + Vector3(randf_range(-2, 2), 26, randf_range(-2, 2))
	var pts := [top]
	for i in range(1, 9):
		var t := i / 9.0
		pts.append(top.lerp(g, t) + Vector3(randf_range(-0.9, 0.9), 0, randf_range(-0.9, 0.9)))
	pts.append(g)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new()
		seg.mesh = Models.box_mesh(Vector3(0.28, 1.0, 0.28))
		seg.material_override = m
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(seg)
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		seg.look_at_from_position(mid, b, Vector3.RIGHT if absf((b - a).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP)
		seg.rotate_object_local(Vector3.RIGHT, PI / 2)
		seg.scale = Vector3(1, len, 1)
	_flash(g + Vector3(0, 4, 0), Color("#cfe3ff"), 14.0, 24.0, 0.35)
	world.spawn_burst(g + Vector3(0, 0.5, 0), Color("#cfe3ff"), 24, 0.12, 7.0, 0.5, true)
	_ring(g, 2.8, Color("#cfe3ff"), 0.6)
	var scorch := FX.flames(Vector3(0.8, 0.1, 0.8), 30, 1.0)
	scorch.position = g
	scorch.one_shot = true
	scorch.explosiveness = 0.6
	world.add_child(scorch)
	get_tree().create_timer(2.0).timeout.connect(scorch.queue_free)
	world.rig.shake(0.5)
	for u in _enemies_near(g, 2.8):
		u.take_damage(55.0, null)
	for b in _buildings_near(g, 1.5):
		b.take_damage(140.0, null)
	Sfx.play("thunder")
	var tw := root.create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func(): root.visible = false)
	tw.tween_interval(0.06)
	tw.tween_callback(func(): root.visible = true)
	tw.tween_interval(0.1)
	tw.tween_callback(root.queue_free)


# ---------------- Simorgh ----------------
func _simorgh() -> void:
	var healed := 0
	for u in world.units:
		if u.dead or u.side != Defs.IRAN:
			continue
		if u.hp < u.max_hp:
			healed += 1
		u.hp = u.max_hp
		world.spawn_burst(u.position + Vector3(0, 2.2, 0), Color("#ffd766"), 10, 0.1, 2.5, 1.2, true)
		_ring(u.position, 1.2, Color("#ffd766"), 1.2)
	world.say("سیمرغ پر گشود و زخم %s جنگجو را شفا داد!" % Defs.fa(healed), Defs.IRAN)
	_simorgh_flight()


## The Simorgh (a Meshy model) sweeps across the sky above the camera's view, beating its wings.
## Falls back to a simple glowing bird if the model is missing.
const SIMORGH_GLB := "res://assets/models/fx/simorgh.glb"
const SIMORGH_SHADER := preload("res://assets/shaders/simorgh.gdshader")


func _simorgh_flight() -> void:
	var bird := Node3D.new()
	var flap_mat: ShaderMaterial = null
	var model := _simorgh_model()
	var wings := []
	if model:
		bird.add_child(model)
		flap_mat = model.get_meta("flap_mat")
	else:
		_simple_simorgh(bird, wings)
	var trail := CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 1.6
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	trail.emission_box_extents = Vector3(7, 0.2, 1)
	trail.gravity = Vector3(0, -2.5, 0)
	trail.mesh = Models.box_mesh(Vector3(0.15, 0.02, 0.4))
	trail.material_override = _glow_mat(Color("#ffe39a"), 2.5)
	trail.local_coords = false
	bird.add_child(trail)
	world.add_child(bird)
	# cross the screen from left to right, a little above the battle, so the player sees it
	var c: Vector3 = world.rig.global_position
	var right: Vector3 = world.rig.global_transform.basis.x
	var up_screen: Vector3 = -world.rig.global_transform.basis.z
	right.y = 0.0
	up_screen.y = 0.0
	right = right.normalized()
	up_screen = up_screen.normalized()
	var from := c - right * 42.0 - up_screen * 2.0 + Vector3(0, 6, 0)
	var to := c + right * 42.0 + up_screen * 6.0 + Vector3(0, 8, 0)
	bird.position = from
	bird.look_at_from_position(from, to, Vector3.UP)
	var fly_dir := (to - from).normalized()
	var alt := [from.y]
	var tw := bird.create_tween()
	tw.tween_method(func(k: float):
		var p := from.lerp(to, k) + Vector3(0, sin(k * PI) * 3.0, 0)
		# never pass through rocks, hills or buildings: climb over whatever is below or just ahead
		var want := p.y
		for ahead in [0.0, 5.0, 10.0]:
			var q: Vector3 = p + fly_dir * ahead
			want = maxf(want, _clearance_at(q))
		alt[0] = lerpf(alt[0], want, 0.12) if want < alt[0] else maxf(alt[0], lerpf(alt[0], want, 0.35))
		p.y = alt[0]
		bird.position = p
		# a slow, mighty beat: quick down stroke, gentle glide between beats
		var beat := sin(k * 34.0)
		if flap_mat:
			flap_mat.set_shader_parameter("flap", beat * 0.55 + 0.1)
			bird.rotation.z = sin(k * 6.0) * 0.12
		for w in wings:
			w[0].rotation.z = beat * 0.45 * w[1], 0.0, 1.0, 6.5)
	tw.tween_callback(bird.queue_free)


## Lowest safe height for the Simorgh over a point: the ground (rocks, hills) and any
## building close by, with room for its wings.
func _clearance_at(q: Vector3) -> float:
	var y: float = world.terrain.height_at(q.x, q.z) + 5.0
	for b: Building in world.buildings:
		if b.dead:
			continue
		var r: float = b.half_extent() + 6.0
		if absf(b.position.x - q.x) < r and absf(b.position.z - q.z) < r:
			var h := 5.0
			if b.type == "keep":
				h = 10.5 + b.level * 1.5
			elif b.type == "tower":
				h = 8.5
			y = maxf(y, b.position.y + h + 3.5)
	return y


func _simorgh_model() -> Node3D:
	if not ResourceLoader.exists(SIMORGH_GLB):
		return null
	var ps: PackedScene = load(SIMORGH_GLB)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	var mi: MeshInstance3D = inst if inst is MeshInstance3D else inst.find_children("*", "MeshInstance3D", true, false).front()
	if mi == null or mi.mesh == null:
		return null
	var tex: Texture2D = null
	var src := mi.get_active_material(0)
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
	var aabb := mi.mesh.get_aabb()
	var m := ShaderMaterial.new()
	m.shader = SIMORGH_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("span", maxf(absf(aabb.position.x), absf(aabb.end.x)))
	m.set_shader_parameter("shoulder", aabb.size.x * 0.1)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the model stands upright facing +Z; lay it down so it flies head first along -Z, belly down
	var holder := Node3D.new()
	holder.add_child(inst)
	inst.rotation = Vector3(deg_to_rad(SIMORGH_PITCH), PI, 0)
	holder.scale = Vector3.ONE * (16.0 / aabb.size.x)   # about 16 m from wing tip to wing tip
	holder.set_meta("flap_mat", m)
	return holder


const SIMORGH_PITCH := 70.0


func _simple_simorgh(bird: Node3D, wings: Array) -> void:
	var gold := _glow_mat(Color("#ffcf5a"), 1.6)
	var body := MeshInstance3D.new()
	body.mesh = Models.sphere_mesh(0.9, 2.2, 10)
	body.material_override = gold
	body.rotation.x = PI / 2
	bird.add_child(body)
	for s in [-1.0, 1.0]:
		var w := Node3D.new()
		var wm := MeshInstance3D.new()
		wm.mesh = Models.box_mesh(Vector3(7.0, 0.12, 2.6))
		wm.material_override = gold
		wm.position = Vector3(3.6 * s, 0, 0.2)
		w.add_child(wm)
		bird.add_child(w)
		wings.append([w, s])
	var tail := MeshInstance3D.new()
	tail.mesh = Models.box_mesh(Vector3(1.8, 0.1, 4.5))
	tail.material_override = gold
	tail.position = Vector3(0, 0, 3.2)
	bird.add_child(tail)
