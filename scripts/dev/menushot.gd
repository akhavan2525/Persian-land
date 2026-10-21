extends Node
## Development helper: `godot -- --menushot=<dir>` saves the title screen and the stage cards.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/menu.png")
	get_tree().current_scene._show_stages()
	get_tree().current_scene._pick_stage(2)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/stages.png")
	get_tree().quit()
