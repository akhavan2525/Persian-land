extends Node
## Development helper: `godot --headless -- --chaintest` sends one group from spot to spot,
## as a player does, and prints how many soldiers were left behind on each leg.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.0).timeout
	var w = get_tree().current_scene
	w.ai.set_process(false)
	w.ai.set_physics_process(false)
	for u in w.units.duplicate():
		if u.side != 0:
			w.units.erase(u)
			u.queue_free()
	Engine.time_scale = 6.0
	# one group sent from spot to spot without resetting, as a player does: who is left behind?
	var chain := []
	var ip: Vector3 = w.keeps[0].position
	for i in 18:
		var t: String = ["spear", "archer", "cav", "immortal", "spear", "archer"][i % 6]
		chain.append(w.spawn_unit(t, 0, w.free_spot_near(w.keeps[0])))
	var legs := [Vector3(-20, 0, 40), Vector3(-44, 0, 10), Vector3(-10, 0, -12), Vector3(20, 0, 20), Vector3(-30, 0, 50), ip + Vector3(8, 0, -8), Vector3(-56, 0, -50), Vector3(0, 0, 30)]
	var left_total := 0
	for li in legs.size():
		w.selected = chain.filter(func(u): return is_instance_valid(u) and not u.dead)
		w._move_selected(legs[li])
		var t0: float = w.time
		while w.time - t0 < 80.0:
			await get_tree().create_timer(1.0).timeout
			if chain.filter(func(u): return u.state == Unit.State.MOVE).size() == 0:
				break
		var left := 0
		var far := 0.0
		for u in chain:
			var d := Vector2(u.position.x - legs[li].x, u.position.z - legs[li].z).length()
			far = maxf(far, d)
			if d > 10.0:
				left += 1
				if OS.get_cmdline_user_args().has("--verbose"):
					print("  behind: %s at %s dest %s (%.1fm from its slot) state %d stuck %d path %d/%d" % [u.type, u.position.snapped(Vector3.ONE * 0.1), u.dest.snapped(Vector3.ONE * 0.1), Vector2(u.position.x - u.dest.x, u.position.z - u.dest.z).length(), u.state, u._stuck_n, u.path_i, u.path.size()])
		left_total += left
		print("leg %d %s: left behind %d/18, farthest %.1fm, %ds" % [li, legs[li], left, far, int(w.time - t0)])
	print("CHAIN LEFT BEHIND %d" % left_total)
	for u in chain:
		w.units.erase(u)
		u.queue_free()
	w.selected = []
	get_tree().quit()
