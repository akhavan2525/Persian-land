extends Node
## Development helper: `godot -- --shots=/some/dir` plays a scripted tour and saves screenshots.

var out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	await _wait(1.5)
	await _snap("01_menu")
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _wait(2.5)
	var w = get_tree().current_scene
	await _snap("02_start")
	w.rig.dist = 26.0
	w.rig.zoom_by(1.0)
	w.rig.position = w.keeps[0].position + Vector3(5, 0, -5)
	w.rig._apply()
	await _wait(0.6)
	await _snap("03_close")
	w.select_building(w.keeps[0])
	await _wait(0.5)
	await _snap("04_keep_panel")
	w.start_build("house")
	w._build_tap(w.keeps[0].position + Vector3(-10, 0, -2))
	await _wait(0.4)
	await _snap("05_build_mode")
	w.confirm_build()
	w.res[0].wood += 300
	w.res[0].stone += 300
	w.res[0].gold += 300
	w.res[0].food += 300
	w.start_build("barracks")
	w._build_tap(w.keeps[0].position + Vector3(10, 0, 4))
	w.confirm_build()
	w.start_build("farm")
	w._build_tap(w.keeps[0].position + Vector3(-4, 0, 12))
	w.confirm_build()
	w.start_build("wall")
	w._build_tap(w.keeps[0].position + Vector3(14, 0, 12))
	w._build_tap(w.keeps[0].position + Vector3(14, 0, -6))
	w.confirm_build()
	w.start_build("tower")
	w._build_tap(w.keeps[0].position + Vector3(14, 0, 14))
	w.confirm_build()
	w.cancel_build()
	w.rig.position = w.keeps[0].position + Vector3(6, 0, 2)
	w.rig.dist = 40.0
	w.rig.zoom_by(1.0)
	await _wait(2.0)
	await _snap("06_built")
	w.rig.position = w.keeps[1].position + Vector3(-4, 0, 6)
	w.rig.dist = 40.0
	w.rig.zoom_by(1.0)
	await _wait(0.6)
	await _snap("07_turan_castle")
	# march the army to the middle village
	w.select_all_army()
	w._move_selected(w.villages[1].position)
	Engine.time_scale = 3.0
	w.rig.position = w.villages[1].position
	w.rig.dist = 30.0
	w.rig.zoom_by(1.0)
	await _wait(12.0)
	await _snap("08_battle")
	await _wait(6.0)
	await _snap("09_battle2")
	Engine.time_scale = 6.0
	await _wait(40.0)
	w.rig.position = w.keeps[0].position
	w.rig.dist = 55.0
	w.rig.zoom_by(1.0)
	await _wait(0.5)
	await _snap("10_later")
	print("time ", w.time, " units ", w.units.size(), " iran res ", w.res[0])
	get_tree().quit()
