extends Node
## Development helper: `godot -- --wintershot=<dir>` looks at a wood before and after the first snow.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _run() -> void:
	App.stage = 2
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.5).timeout
	var w = get_tree().current_scene
	w.ai.set_process(false)
	var ft = load("res://scripts/dev/formtest.gd").new()
	var spot: Vector3 = ft._near_trees(w, w.keeps[0].position + Vector3(14, 0, -14))
	ft.free()
	w.rig.position = Vector3(spot.x, 0, spot.z)
	w.rig._apply()
	await get_tree().create_timer(1.0).timeout
	await _shot("trees_summer")
	Engine.time_scale = 20.0
	w._start_winter()
	await get_tree().create_timer(64.0).timeout
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.5).timeout
	await _shot("trees_winter")
	get_tree().quit()
