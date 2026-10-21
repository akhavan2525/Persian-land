extends Node
## Afrasiab's war council: trains troops, defends the castle, raids villages and
## sends ever-larger attack waves at the Iranian keep.

var world: Node
var points := 20.0
var wave := 0
var next_wave := 0.0
var next_raid := 75.0
var _think := 0.0
var _rally := Vector3.ZERO
var D: Dictionary
var smart := 0                 # 0 plain waves, 1 gather and pick weak spots, 2 also flank and pull back the wounded
var _muster: Array = []        # soldiers gathering for the next push
var _muster_t := 0.0
var _muster_target := Vector3.ZERO
var _resting: Array = []       # wounded soldiers sent home to heal

const COST := {"spear": 8.0, "archer": 9.0, "cav": 14.0, "immortal": 20.0}
const CAP := 30


func _ready() -> void:
	# the chosen difficulty, scaled by the campaign stage
	var base: Dictionary = Defs.DIFFICULTY[App.difficulty]
	var st: Dictionary = App.stage_def()
	D = {"first": base.first * st.ai.first, "every": base.every * st.ai.every, "base": base.base + st.ai.base,
		"grow": base.grow * st.ai.grow, "income": base.income * st.ai.income}
	smart = int(st.smart)
	next_wave = D.first
	var k = world.keeps[Defs.TURAN]
	_rally = k.position + Vector3(-3, 0, 4)


func time_to_wave() -> float:
	return maxf(0.0, next_wave - world.time)


func on_unit_spawned(u: Unit) -> void:
	if u.type != "hero":
		u.order_move(_rally + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))


func _physics_process(dt: float) -> void:
	if world.finished:
		return
	var turan_villages := 0
	for v: Building in world.villages:
		if v.side == Defs.TURAN:
			turan_villages += 1
	points += (0.55 + turan_villages * 0.25 + world.time / 900.0) * D.income * dt
	_think -= dt
	if _think > 0.0:
		return
	_think = 1.0
	_train()
	_defend()
	if world.time >= next_wave:
		_launch_wave()
	_tick_muster()
	if smart >= 2:
		_tend_wounded()
	if world.time >= next_raid:
		next_raid = world.time + 80.0
		_raid()
	_resend_idle()


func _army() -> Array:
	return world.units.filter(func(u): return u.side == Defs.TURAN and not u.dead)


func _train() -> void:
	var army := _army()
	if army.size() >= CAP:
		return
	var barracks: Array = world.buildings.filter(func(b): return b.side == Defs.TURAN and b.type == "barracks" and not b.dead)
	if barracks.is_empty():
		return
	var iran: Array = world.units.filter(func(u): return u.side == Defs.IRAN and not u.dead)
	var cav: int = iran.filter(func(u): return u.type == "cav").size()
	var arch: int = iran.filter(func(u): return u.type == "archer").size()
	var w := {"spear": 3.0 + cav * 1.5, "archer": 2.5, "cav": 1.5 + arch, "immortal": 0.6 + wave * 0.4}
	var tot := 0.0
	for k in w:
		tot += w[k]
	var x := randf() * tot
	var choice := "spear"
	for k in w:
		x -= w[k]
		if x <= 0.0:
			choice = k
			break
	if points >= COST[choice]:
		points -= COST[choice]
		var b: Building = barracks[randi() % barracks.size()]
		world.spawn_unit(choice, Defs.TURAN, world.free_spot_near(b))


func _defend() -> void:
	var k = world.keeps[Defs.TURAN]
	if k == null or k.dead:
		return
	var intruders: Array = world.units.filter(func(u): return u.side == Defs.IRAN and not u.dead and u.position.distance_to(k.position) < 26.0)
	if intruders.is_empty():
		return
	for u in _army():
		if u.state == Unit.State.IDLE or (u.state == Unit.State.MOVE and u.position.distance_to(k.position) < 30.0 and not u.attack_move):
			var best: Unit = null
			var bd := INF
			for e in intruders:
				var d: float = u.position.distance_to(e.position)
				if d < bd:
					bd = d
					best = e
			if best and bd < 40.0:
				u.order_attack(best)


func _launch_wave() -> void:
	wave += 1
	next_wave = world.time + D.every
	_grow_castle()
	var size := int(D.base + D.grow * (wave - 1))
	var k = world.keeps[Defs.TURAN]
	var pool := _army().filter(func(u): return u.type != "hero" and u.state != Unit.State.ATTACK and not _resting.has(u))
	pool.sort_custom(func(a, b): return a.position.distance_to(k.position) < b.position.distance_to(k.position))
	var keep_home := 3
	var send := pool.slice(0, maxi(0, mini(size, pool.size() - keep_home)))
	if send.size() < 2:
		send = pool.slice(0, mini(size, pool.size()))
	if wave >= 3:
		for u in _army():
			if u.type == "hero":
				send.append(u)
	if send.is_empty():
		return
	var target := _pick_target()
	if smart >= 1:
		# gather in front of the castle first, so the whole wave strikes at once
		var front: Vector3 = k.position + (target - k.position).normalized() * 16.0
		for u in send:
			u.order_move(front + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), false)
		_muster = send
		_muster_t = 22.0
		_muster_target = target
		world.say("موج %s: سپاه توران در برابر دژش صف می‌کشد!" % Defs.fa(wave), Defs.TURAN)
	else:
		_charge(send, target)
		world.say("موج %s: سپاه توران با %s جنگجو به سوی ایران می‌تازد!" % [Defs.fa(wave), Defs.fa(send.size())], Defs.TURAN)
	Sfx.play("horn")
	Sfx.voice("turan_attack", true)


## Where to strike: plain waves go for the keep; a cunning Afrasiab hits whatever
## Iranian holding is guarded worst (an outlying village or building), or the keep.
func _pick_target() -> Vector3:
	var keep_pos: Vector3 = world.keeps[Defs.IRAN].position
	if smart < 1:
		return keep_pos
	var options: Array = [keep_pos]
	for v: Building in world.villages:
		if v.side == Defs.IRAN:
			options.append(v.position)
	for b: Building in world.buildings:
		if b.side == Defs.IRAN and not b.dead and b.type in ["farm", "quarry", "woodcutter", "tower"] and b.position.distance_to(keep_pos) > 14.0:
			options.append(b.position)
	var best: Vector3 = keep_pos
	var best_score := INF
	for p: Vector3 in options:
		var guards := 0
		for u: Unit in world.units:
			if u.side == Defs.IRAN and not u.dead and u.position.distance_to(p) < 16.0:
				guards += 1
		# the keep is worth more: Turan prefers it unless it is far better guarded
		var score := guards * 2.0 + p.distance_to(world.keeps[Defs.TURAN].position) * 0.05 - (6.0 if p == keep_pos else 0.0)
		if score < best_score:
			best_score = score
			best = p
	return best


func _charge(group: Array, target: Vector3) -> void:
	for u in group:
		if is_instance_valid(u) and not u.dead:
			u.order_move(target + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), true)


## Waits for the gathering wave, then sends it in: at the highest cunning a third
## of it swings wide and falls on the flank at the same time.
func _tick_muster() -> void:
	if _muster.is_empty():
		return
	_muster = _muster.filter(func(u): return is_instance_valid(u) and not u.dead)
	_muster_t -= 1.0
	var waiting := _muster.filter(func(u): return u.state == Unit.State.MOVE).size()
	if _muster_t > 0.0 and waiting > _muster.size() / 4:
		return
	var group := _muster
	_muster = []
	if group.is_empty():
		return
	var k: Vector3 = world.keeps[Defs.TURAN].position
	if smart >= 2 and group.size() >= 6:
		var n := group.size() / 3
		var flank := group.slice(0, n)
		var main := group.slice(n)
		var dir := (_muster_target - k).normalized()
		var side := Vector3(-dir.z, 0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		var bend := k.lerp(_muster_target, 0.55) + side * 26.0
		bend.x = clampf(bend.x, -Defs.HALF * 0.75, Defs.HALF * 0.75)
		bend.z = clampf(bend.z, -Defs.HALF * 0.75, Defs.HALF * 0.75)
		for u in flank:
			u.order_move(bend, true)
		_flank = flank
		_flank_t = 40.0
		_charge(main, _muster_target)
		world.say("سپاه توران از دو سو یورش می‌آورد!", Defs.TURAN)
	else:
		_charge(group, _muster_target)
		world.say("سپاه توران با %s جنگجو به سوی ایران می‌تازد!" % Defs.fa(group.size()), Defs.TURAN)


var _flank: Array = []
var _flank_t := 0.0


## Badly wounded soldiers pull back to the castle to heal and rejoin later.
func _tend_wounded() -> void:
	# the flank, once at its turning point, wheels on the target
	if not _flank.is_empty():
		_flank_t -= 1.0
		_flank = _flank.filter(func(u): return is_instance_valid(u) and not u.dead)
		if _flank_t <= 0.0 or _flank.filter(func(u): return u.state == Unit.State.MOVE).size() <= _flank.size() / 3:
			_charge(_flank.filter(func(u): return u.state != Unit.State.ATTACK), _muster_target)
			_flank = []
	var k = world.keeps[Defs.TURAN]
	if k == null or k.dead:
		return
	for u: Unit in _army():
		if u.type == "hero" or _resting.has(u):
			continue
		if u.hp < u.max_hp * 0.22 and u.position.distance_to(k.position) > 30.0:
			u.order_move(k.position + Vector3(randf_range(-6, 6), 0, randf_range(4, 9)), false)
			_resting.append(u)
	for u in _resting.duplicate():
		if not is_instance_valid(u) or u.dead:
			_resting.erase(u)
		elif u.hp >= u.max_hp * 0.85:
			_resting.erase(u)


## Turan's castle grows with the war: every other wave one building goes up a level.
func _grow_castle() -> void:
	if wave < 2 or wave % 2 != 0:
		return
	var k = world.keeps[Defs.TURAN]
	if k == null or k.dead:
		return
	var list: Array = world.buildings.filter(func(b): return b.side == Defs.TURAN and not b.dead and b.type in ["barracks", "tower"] and b.level < mini(b.max_level(), k.level))
	if list.is_empty():
		if k.level < k.max_level():
			k.upgrade()
			world._update_zones()
		return
	list.sort_custom(func(a, b): return a.level < b.level)
	list[0].upgrade()


func _raid() -> void:
	var k = world.keeps[Defs.TURAN]
	var targets: Array = world.villages.filter(func(v): return v.side != Defs.TURAN)
	if targets.is_empty():
		return
	targets.sort_custom(func(a, b): return a.position.distance_to(k.position) < b.position.distance_to(k.position))
	var v = targets[0]
	var pool := _army().filter(func(u): return u.type != "hero" and u.state == Unit.State.IDLE)
	if pool.size() < 5:
		return
	var n := 3 + wave
	for u in pool.slice(0, mini(n, pool.size() - 2)):
		u.order_move(v.position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), true)


func _resend_idle() -> void:
	# soldiers left standing deep in Iranian land keep pushing to the keep
	var k = world.keeps[Defs.IRAN]
	if k == null:
		return
	for u in _army():
		if _resting.has(u) or _muster.has(u):
			continue
		if u.state == Unit.State.IDLE and u.position.distance_to(k.position) < 60.0 and u.position.distance_to(world.keeps[Defs.TURAN].position) > 30.0:
			u.order_move(k.position, true)
