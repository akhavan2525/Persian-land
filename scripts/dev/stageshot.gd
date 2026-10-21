extends Node
## Development helper: `godot -- --stageshots=<dir>` opens every stage and saves an overview
## and a close shot of each, plus the title screen.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("shot ", name)


func _run() -> void:
	App.unlocked = 3
	await get_tree().create_timer(1.5).timeout
	await _snap("menu")
	for i in Defs.STAGES.size():
		App.stage = i
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await get_tree().create_timer(2.5).timeout
		var w = get_tree().current_scene
		w.rig.position = w.keeps[0].position + Vector3(14, 0, -14)
		w.rig.dist = 55.0
		w.rig.zoom_by(1.0)
		w.rig._apply()
		await get_tree().create_timer(0.8).timeout
		await _snap("stage%d_home" % (i + 1))
		w.rig.position = w.keeps[1].position + Vector3(-6, 0, 8)
		w.rig.dist = 42.0
		w.rig.zoom_by(1.0)
		w.rig._apply()
		await get_tree().create_timer(0.8).timeout
		await _snap("stage%d_turan" % (i + 1))
	get_tree().quit()
