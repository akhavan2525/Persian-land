extends Node
## Development helper: `godot -- --stage=1 --stormshot=<dir>` shoots the storm and a far bolt.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(2.0).timeout
	var w = get_tree().current_scene
	w._storm_t = 0.3
	for i in 6:
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/storm_%d.png" % [out, i])
	get_tree().quit()
