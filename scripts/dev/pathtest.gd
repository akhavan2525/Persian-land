extends Node
## Development helper: `godot --headless -- --pathtest` sends groups of soldiers across the map
## and into a fight, then prints how many got where they were sent and how many got stuck.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.0).timeout
	var w = get_tree().current_scene
	w.ai.set_process(false)
	w.ai.set_physics_process(false)
	Engine.time_scale = 8.0
	var start: Vector3 = w.keeps[0].position + Vector3(8, 0, -8)
	# targets on the far side of forests, lakes and rocks
	var goals := [Vector3(-20, 0, 66), Vector3(0, 0, 0), Vector3(30, 0, -30), Vector3(-70, 0, -20), Vector3(25, 0, 40), Vector3(-62, 0, 22), Vector3(-38, 0, -36), Vector3(-60, 0, 56)]
	var total_ok := 0
	var total := 0
	for gi in goals.size():
		var goal: Vector3 = goals[gi]
		var group := []
		for i in 16:
			var t: String = ["spear", "archer", "cav", "immortal"][i % 4]
			group.append(w.spawn_unit(t, 0, start + Vector3((i % 4) * 1.4, 0, (i / 4) * 1.4)))
		w.selected = group
		w._move_selected(goal)
		var t0: float = w.time
		var last := {}
		var stuck_s := 0
		while w.time - t0 < 90.0:
			await get_tree().create_timer(1.0).timeout
			var moving := 0
			for u in group:
				if is_instance_valid(u) and u.state == Unit.State.MOVE:
					moving += 1
					var lp = last.get(u.get_instance_id(), null)
					if lp != null and lp.distance_to(u.position) < 0.4:
						stuck_s += 1
				last[u.get_instance_id()] = u.position
			if moving == 0:
				break
		var ok := 0
		var never := 0
		var dead := 0
		var worst := 0.0
		var in_solid := 0
		var still := 0
		group = group.filter(func(u):
			if not is_instance_valid(u) or u.dead:
				dead += 1
				return false
			return true)
		for u in group:
			if Vector2(u.position.x - u.home.x, u.position.z - u.home.z).length() < 3.0:
				never += 1
			var d := Vector2(u.position.x - goal.x, u.position.z - goal.z).length()
			worst = maxf(worst, d)
			if d < 9.0:
				ok += 1
			if u.state == Unit.State.MOVE:
				still += 1
			if w.grids[0].is_point_solid(Terrain.cell_of(u.position)):
				in_solid += 1
		print("goal %d %s: %d/16 arrived in %ds, farthest %.1fm, still walking %d, inside obstacles %d, slow-moving checks %d, never left %d, died %d" % [gi, goal, ok, int(w.time - t0), worst, still, in_solid, stuck_s, never, dead])
		total_ok += ok
		total += 16
		w.selected = []
		for u in group:
			w.units.erase(u)
			u.queue_free()
		await get_tree().process_frame
	print("PATH TOTAL %d/%d" % [total_ok, total])
	# a fight in open ground
	var mid := Vector3(-10, 0, 10)
	var ir := []
	var tu := []
	for i in 12:
		var t: String = ["spear", "archer", "cav", "immortal"][i % 4]
		ir.append(w.spawn_unit(t, 0, mid + Vector3(-14 + (i % 4) * 1.4, 0, (i / 4) * 1.4)))
		tu.append(w.spawn_unit(t, 1, mid + Vector3(14 + (i % 4) * 1.4, 0, (i / 4) * 1.4)))
	for u in ir:
		u.order_move(mid + Vector3(20, 0, 0), true)
	for u in tu:
		u.order_move(mid - Vector3(20, 0, 0), true)
	var t1: float = w.time
	var fought := {}
	while w.time - t1 < 60.0:
		await get_tree().create_timer(0.5).timeout
		for u in ir + tu:
			if is_instance_valid(u) and not u.dead and u.cd > 0.0:
				fought[u.get_instance_id()] = true
		var a := ir.filter(func(u): return is_instance_valid(u) and not u.dead).size()
		var b := tu.filter(func(u): return is_instance_valid(u) and not u.dead).size()
		if a == 0 or b == 0:
			break
	var ai := ir.filter(func(u): return is_instance_valid(u) and not u.dead).size()
	var bi := tu.filter(func(u): return is_instance_valid(u) and not u.dead).size()
	print("FIGHT %ds: iran left %d, turan left %d, soldiers that struck at least once %d/24" % [int(w.time - t1), ai, bi, fought.size()])
	get_tree().quit()
