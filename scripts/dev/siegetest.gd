extends Node
## Development helper: `godot --headless -- --siegetest` sends an army at Afrasiab's keep
## and counts soldiers that stop on the way (idle, far from the keep, no enemy near).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.0).timeout
	var w = get_tree().current_scene
	Engine.time_scale = 6.0
	var start: Vector3 = w.keeps[0].position + Vector3(8, 0, -8)
	var army := []
	for i in 24:
		var t: String = ["spear", "archer", "cav", "immortal", "spear", "archer"][i % 6]
		army.append(w.spawn_unit(t, 0, w._open_spot(start + Vector3((i % 6) * 1.4, 0, (i / 6) * 1.4))))
	var goal: Building = w.keeps[1]
	for u in army:
		u.order_attack(goal)
	var worst := 0
	for k in 30:
		await get_tree().create_timer(5.0).timeout
		var idle_far := 0
		for u in army:
			if not is_instance_valid(u) or u.dead:
				continue
			var far: bool = u.position.distance_to(goal.position) > 18.0
			if far and u.state == Unit.State.IDLE and w.nearest_enemy(u, 14.0, true) == null:
				idle_far += 1
		worst = maxi(worst, idle_far)
		var alive := army.filter(func(u): return is_instance_valid(u) and not u.dead).size()
		print("t=%d alive=%d stopped_on_the_way=%d keep_hp=%d" % [int(w.time), alive, idle_far, int(goal.hp)])
		if goal.dead or alive == 0:
			break
	print("SIEGE worst stopped: %d" % worst)
	get_tree().quit()
