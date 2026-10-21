extends Node
## Development helper: `godot -- --formtest=<dir>` tries each battle formation on a small
## army, saves a screenshot of each, then calls the first snow and shoots the white land.

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
	var army := []
	for i in 12:
		var t: String = ["spear", "archer", "cav", "immortal"][i % 4]
		army.append(w.spawn_unit(t, 0, w._open_spot(spot + Vector3((i % 4) * 1.5 - 6, 0, (i / 4) * 1.5 + 4))))
	for k in Defs.FORMATION_ORDER:
		var foes := []
		if k == "encircle":
			for i in 4:
				var f = w.spawn_unit("spear", 1, w._open_spot(spot + Vector3(i * 1.2, 0, -4)))
				f.state = Unit.State.GUARD
				f.home = f.position
				foes.append(f)
		w.select_units(army.filter(func(u): return not u.dead))
		w.arm_formation(k)
		var target: Vector3 = w._group_center(army) + (w._group_center(army) - spot).normalized() * 3.0 if k != "encircle" else spot + Vector3(0, 0, -4)
		if k == "ambush":
			target = _near_trees(w, spot)
		var ok: bool = {"encircle": w._form_encircle, "ambush": w._form_ambush, "wall": w._form_wall,
			"wedge": w._form_wedge, "ring": w._form_ring}[k].call(w.selected, target)
		w.mode = "normal"
		w.formation_armed = ""
		w.selection_changed.emit()
		print("%s placed: %s" % [k, ok])
		if k == "ambush":
			w.rig.position = Vector3(target.x, 0, target.z)
			w.rig._apply()
		await get_tree().create_timer(10.0).timeout
		if k == "ambush":
			print("hidden archers: %d" % army.filter(func(u): return u.hidden).size())
			for u in army.filter(func(u): return u.type == "archer"):
				print("  archer state=%d ambush=%s post_d=%.1f path=%d/%d" % [u.state, u.ambush, Vector2(u.post.x - u.position.x, u.post.z - u.position.z).length(), u.path_i, u.path.size()])
		var at := army.filter(func(u): return not u.dead and u.formation != "" and u.at_post()).size()
		print("%s: %d of %d at their post" % [k, at, army.filter(func(u): return not u.dead and (u.formation != "" or k == "encircle")).size()])
		await _shot("form_" + k)
		for f in foes:
			if is_instance_valid(f) and not f.dead:
				w.units.erase(f)
				f.queue_free()
		w.rig.position = Vector3(spot.x, 0, spot.z)
		w.rig._apply()
	w.select_units(army)
	await _shot("form_icons")
	w.arm_formation("encircle")
	await get_tree().create_timer(0.3).timeout
	await _shot("form_name")
	w.clear_selection()
	w._start_winter()
	for i in 3:
		await get_tree().create_timer(8.0).timeout
		w.terrain.set_winter((i + 1) / 3.0)
		await _shot("winter_%d" % i)
	get_tree().quit()


func _near_trees(w, p: Vector3) -> Vector3:
	var c0 := Terrain.cell_of(p)
	var best := p
	var bd := INF
	for dz in range(-30, 31):
		for dx in range(-30, 31):
			var c := c0 + Vector2i(dx, dz)
			if w.terrain.type_at(c) == Terrain.FOREST and not w.grids[0].is_point_solid(c):
				var d := Vector2(dx, dz).length()
				if d < bd:
					bd = d
					best = Terrain.cell_center_flat(c)
	return Vector3(best.x, 0, best.z)
