extends Node
## Development helper: `godot --headless -- --sim` lets Turan play against an idle Iran and prints a timeline.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.0).timeout
	var w = get_tree().current_scene
	Engine.time_scale = 10.0
	Engine.physics_ticks_per_second = 30
	w.message.connect(func(t, _s): print("[%4d] %s" % [int(w.time), t]))
	w.game_over.connect(func(win): print("GAME OVER win=", win, " t=", int(w.time)))
	for i in 90:
		await get_tree().create_timer(10.0).timeout
		var n := [0, 0, 0]
		for u in w.units:
			n[u.side] += 1
		print("t=%d units iran=%d turan=%d divs=%d keepHP=%d/%d wave=%d" % [int(w.time), n[0], n[1], n[2], int(w.keeps[0].hp), int(w.keeps[1].hp), w.ai.wave])
		if w.finished:
			break
	get_tree().quit()
