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

const COST := {"spear": 8.0, "archer": 9.0, "cav": 14.0, "immortal": 20.0}
const CAP := 30


func _ready() -> void:
	D = Defs.DIFFICULTY[App.difficulty]
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
	var pool := _army().filter(func(u): return u.type != "hero" and u.state != Unit.State.ATTACK)
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
	var target: Vector3 = world.keeps[Defs.IRAN].position
	for u in send:
		u.order_move(target + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), true)
	world.say("موج %s: سپاه توران با %s جنگجو به سوی ایران می‌تازد!" % [Defs.fa(wave), Defs.fa(send.size())], Defs.TURAN)


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
		if u.state == Unit.State.IDLE and u.position.distance_to(k.position) < 60.0 and u.position.distance_to(world.keeps[Defs.TURAN].position) > 30.0:
			u.order_move(k.position, true)
