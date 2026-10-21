extends Node
## Development helper: `godot -- --simorghshot=<dir>` calls the Simorgh and saves
## a few screenshots while it crosses the sky.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.5).timeout
	var w = get_tree().current_scene
	w.ai.set_process(false)
	w.ai.set_physics_process(false)
	w.powers.charge["simorgh"] = 1.0
	w.powers.press("simorgh")
	for i in 6:
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/simorgh_%d.png" % [out, i])
	get_tree().quit()
