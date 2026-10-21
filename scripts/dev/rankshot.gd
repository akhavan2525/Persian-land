extends Node
## Development helper: `godot -- --rankshot=<dir>` shows soldiers at each barracks rank
## and a tower at each level.

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
	var spot: Vector3 = w.keeps[0].position + Vector3(12, 0, -12)
	var groups := []
	for r in 4:
		var g := []
		for i in 4:
			var u = w.spawn_unit(["spear", "archer", "cav", "immortal"][i], 0, w._open_spot(spot + Vector3(i * 1.8 - 3, 0, r * 2.2 - 3)))
			u.set_rank(r + 1)
			g.append(u)
		groups.append(g)
	var c0: Vector2i = Terrain.cell_of(spot) + Vector2i(5, -4)
	for l in 4:
		var t = w._add_building("tower", 0, c0 + Vector2i(l * 2, 0), true, l + 1)
	w.rig.position = Vector3(spot.x + 3, 0, spot.z - 1)
	w.rig.dist = 22.0
	w.rig.zoom_by(1.0)
	w.rig._apply()
	await get_tree().create_timer(1.0).timeout
	print("hp by rank: ", groups.map(func(g): return int(g[0].max_hp)))
	await _shot("ranks")
	var tp: Vector3 = Terrain.cell_center_flat(c0 + Vector2i(3, 0))
	w.rig.position = Vector3(tp.x, 0, tp.z + 4)
	w.rig._apply()
	await get_tree().create_timer(0.8).timeout
	await _shot("towers")
	get_tree().quit()
