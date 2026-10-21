extends Node
## Development helper: `godot -- --panelshot=<dir>` shoots the in-game info panel
## for a small army, a building, then the army again (the panel must shrink back).

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
	var spot: Vector3 = w.keeps[0].position + Vector3(10, 0, -10)
	var army := []
	for i in 2:
		army.append(w.spawn_unit(["spear", "archer"][i], 0, w._open_spot(spot + Vector3(i * 1.5, 0, 0))))
	w.select_units(army)
	await get_tree().create_timer(1.0).timeout
	await _shot("panel_units")
	w.clear_selection()
	w.select_building(w.keeps[0])
	await get_tree().create_timer(1.0).timeout
	await _shot("panel_keep")
	w.clear_selection()
	w.res[0].food = 0
	var bk = w._add_building("barracks", 0, w.keeps[0].cell + Vector2i(6, 6))
	w.select_building(bk)
	await get_tree().create_timer(1.0).timeout
	await _shot("panel_barracks")
	w.clear_selection()
	w.select_units(army)
	await get_tree().create_timer(1.0).timeout
	await _shot("panel_units_again")
	w.clear_selection()
	var c0: Vector2i = w.keeps[0].cell + Vector2i(8, -4)
	for i in 3:
		if i != 1:
			w._add_building("wall", 0, c0 + Vector2i(0, i))
	var g = w._add_building("gate", 0, c0 + Vector2i(0, 1))
	w._orient_gate(g)
	print("gate turn: %d" % g.turn)
	w.rig.position = Vector3(g.position.x, 0, g.position.z)
	w.rig._apply()
	w.select_building(g)
	await get_tree().create_timer(1.0).timeout
	await _shot("panel_gate")
	w.clear_selection()
	w.select_building(w.structure_at(c0))
	await get_tree().create_timer(0.5).timeout
	await _shot("panel_wall")
	get_tree().quit()
