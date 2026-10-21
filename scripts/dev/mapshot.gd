extends Node
## Development helper: `godot -- --mapshot=<dir>` saves a map of cell types and a wide view
## for the stages with a river or peaks.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _run() -> void:
	App.unlocked = Defs.STAGES.size()
	for i in [3, 4]:
		App.stage = i
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await get_tree().create_timer(2.0).timeout
		var w = get_tree().current_scene
		w.ai.set_process(false)
		w.ai.set_physics_process(false)
		var img := Image.create(Defs.GRID, Defs.GRID, false, Image.FORMAT_RGB8)
		var cols := {Terrain.GRASS: Color("#7fae55"), Terrain.FOREST: Color("#2f6b2a"), Terrain.WATER: Color("#3a78c8"),
			Terrain.MOUNTAIN: Color("#8a7f75"), Terrain.ROCK: Color("#b5b0a6")}
		for j in Defs.GRID:
			for k in Defs.GRID:
				var c := Vector2i(k, j)
				var col: Color = cols.get(w.terrain.type_at(c), Color.BLACK)
				if w.structure_at(c) != null:
					col = Color.RED if w.structure_at(c).side == 1 else (Color.BLUE if w.structure_at(c).side == 0 else Color.YELLOW)
				img.set_pixel(k, j, col)
		img.resize(480, 480, Image.INTERPOLATE_NEAREST)
		img.save_png(out.path_join("map%d.png" % (i + 1)))
		# can Iran walk to the Turan keep?
		var path: Array = w.find_path(0, w.keeps[0].position + Vector3(8, 0, -8), w.keeps[1].position + Vector3(-8, 0, 8))
		print("stage %d path len %d end %s" % [i + 1, path.size(), str(path[-1] if path.size() > 0 else null)])
		w.rig.position = Vector3(0, 0, -10)
		w.rig.dist = 70.0
		w.rig.zoom_by(1.0)
		w.rig._apply()
		await get_tree().create_timer(0.8).timeout
		await _snap("view%d" % (i + 1))
		if w.terrain._peaks.size() > 0:
			var pk = w.terrain._peaks[0]
			w.rig.position = Vector3(pk.x, 0, pk.y + 14)
			w.rig.dist = 40.0
			w.rig.zoom_by(1.0)
			w.rig._apply()
			await get_tree().create_timer(0.8).timeout
			await _snap("peak%d" % (i + 1))
	get_tree().quit()
