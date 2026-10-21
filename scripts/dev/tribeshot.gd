extends Node
## Development helper: `godot -- --tribeshot=<dir>` visits a tribe camp, gives gifts until
## the pact, waits for its warriors, then lets Afrasiab win the other camp.

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
	var t: Dictionary = w.tribes[1]
	var b: Building = t.b
	w.rig.position = Vector3(b.position.x, 0, b.position.z)
	w.rig._apply()
	w.select_building(b)
	await get_tree().create_timer(1.0).timeout
	await _shot("camp_free")
	w.res[0].gold = 500
	w.res[0].food = 500
	for i in 2:
		w.gift_tribe(b)
	await get_tree().create_timer(1.0).timeout
	await _shot("camp_gifts")
	for i in 2:
		w.gift_tribe(b)
	await get_tree().create_timer(2.0).timeout
	print("ally after gifts: %d trust %s" % [b.ally, str(t.trust)])
	await get_tree().create_timer(6.0).timeout
	print("men: %d pop_used %d" % [t.men.size(), w.pop_used(0)])
	await _shot("camp_pact")
	# Afrasiab courts the other tribe
	var t2: Dictionary = w.tribes[0]
	w.time = 200.0
	t2.trust[1] = 99.0
	await get_tree().create_timer(2.5).timeout
	print("tribe0 ally: %d" % t2.b.ally)
	w.rig.position = Vector3(t2.b.position.x, 0, t2.b.position.z)
	w.rig._apply()
	w.select_building(t2.b)
	await get_tree().create_timer(1.0).timeout
	await _shot("camp_turan")
	get_tree().quit()
