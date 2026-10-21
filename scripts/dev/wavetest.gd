extends Node
## Development helper: `godot --headless -- --wavetest` marches a Turan group to the Iran keep and logs its progress.

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
	var k1: Vector3 = w.keeps[1].position
	var target: Vector3 = w.keeps[0].position
	var g := []
	for i in 8:
		var u = w.spawn_unit(["spear", "archer", "cav", "immortal"][i % 4], 1, w.free_spot_near(w.keeps[1]))
		g.append(u)
		u.order_move(target + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), true)
	for t in 24:
		await get_tree().create_timer(5.0).timeout
		var parts := []
		for u in g:
			if is_instance_valid(u) and not u.dead:
				parts.append("%s:%d:%.0f:%d" % [u.type.substr(0, 2), u.state, Vector2(u.position.x - target.x, u.position.z - target.z).length(), u._stuck_n])
		print("t=%d keep=%d %s" % [t * 5, int(w.keeps[0].hp), " ".join(parts)])
	get_tree().quit()
