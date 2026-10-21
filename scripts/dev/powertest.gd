extends Node
## Development helper: `godot -- --powertest=<dir>` casts each war power on a Turan group,
## saves a screenshot in the middle of each and prints how much harm it did.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.5).timeout
	var w = get_tree().current_scene
	w.ai.set_process(false)
	w.ai.set_physics_process(false)
	var spot: Vector3 = w.keeps[0].position + Vector3(14, 0, -14)
	w.rig.position = Vector3(spot.x, 0, spot.z)
	w.rig._apply()
	for k in Defs.POWER_ORDER:
		var group := []
		for i in 10:
			var u = w.spawn_unit(["spear", "archer", "cav", "immortal"][i % 4], 1, spot + Vector3((i % 5) * 1.5 - 3, 0, (i / 5) * 1.5 - 1))
			u.state = Unit.State.GUARD
			u.home = u.position
			group.append(u)
		var mine := []
		for i in 4:
			var u = w.spawn_unit("spear", 0, spot + Vector3(-6 + i * 1.2, 0, 6))
			u.hp = u.max_hp * 0.3
			mine.append(u)
		await get_tree().create_timer(0.5).timeout
		var hp0 := 0.0
		for u in group:
			hp0 += u.hp
		w.powers.charge[k] = 1.0
		w.powers.press(k)
		if Defs.POWERS[k].target:
			w.powers.cast_at(spot)
		await get_tree().create_timer(1.2).timeout
		await _shot("power_" + k)
		await get_tree().create_timer(6.0).timeout
		var hp1 := 0.0
		var dead := 0
		for u in group:
			if is_instance_valid(u) and not u.dead:
				hp1 += u.hp
			else:
				dead += 1
		var healed := mine.filter(func(u): return is_instance_valid(u) and u.hp >= u.max_hp - 0.01).size()
		print("%s: enemy health %d -> %d, killed %d/10, friends healed %d/4" % [k, int(hp0), int(hp1), dead, healed])
		for u in group + mine:
			if is_instance_valid(u) and not u.dead:
				w.units.erase(u)
				u.queue_free()
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
