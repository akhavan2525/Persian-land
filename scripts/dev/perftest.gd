extends Node
## Development helper: `godot -- --stage=1 --perftest` runs a battle of 60 soldiers in the
## rain and prints how much processor time the game logic takes per second.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(1.5).timeout
	var w = get_tree().current_scene
	var mid: Vector3 = (w.keeps[0].position + w.keeps[1].position) * 0.5
	for i in (0 if OS.get_environment("NOUNITS") != "" else 30):
		var t: String = ["spear", "archer", "cav", "immortal"][i % 4]
		var a = w.spawn_unit(t, 0, w._open_spot(mid + Vector3(-12 + (i % 6) * 1.5, 0, (i / 6) * 1.5)))
		var b = w.spawn_unit(t, 1, w._open_spot(mid + Vector3((40 if OS.get_environment("NOFIGHT") != "" else 0) + 12 - (i % 6) * 1.5, 0, (i / 6) * 1.5)))
		if OS.get_environment("NOFIGHT") == "":
			a.order_move(mid, true)
			b.order_move(mid, true)
	w.rig.position = mid
	w.rig._apply()
	if OS.get_environment("NOANIM") != "":
		for u in w.units:
			if u.anim:
				u.anim.active = false
	if OS.get_environment("NOUPROC") != "":
		for u in w.units:
			u.set_process(false)
	if OS.get_environment("NOVIS") != "":
		for u in w.units:
			u.visible = false
	if OS.get_environment("NOMODEL") != "":
		for u in w.units:
			u.model.get_parent().remove_child(u.model)
	if OS.get_environment("NOHUD") != "":
		w.hud.process_mode = Node.PROCESS_MODE_DISABLED
	if OS.get_environment("LISTPROC") != "":
		var cnt := {}
		for n in get_tree().root.find_children("*", "", true, false):
			if n.is_processing() or n.is_physics_processing() or n.is_processing_internal() or n.is_physics_processing_internal():
				var k: String = n.get_class() + ":" + (n.get_script().resource_path if n.get_script() else "") + " p%d f%d i%d" % [int(n.is_processing()), int(n.is_physics_processing()), int(n.is_processing_internal())]
				cnt[k] = cnt.get(k, 0) + 1
		for k in cnt:
			print("PROC ", cnt[k], " ", k)
	if OS.get_environment("NOPROCALL") != "":
		for n in w.find_children("*", "", true, false):
			if n != w:
				n.set_process(false)
	if OS.get_environment("MICRO") != "":
		await get_tree().create_timer(3.0).timeout
		var a0 := Time.get_ticks_usec()
		for k in 30:
			for u in w.units.duplicate():
				if not u.dead:
					u.tick(0.033)
		var a1 := Time.get_ticks_usec()
		for k in 30:
			w._separate()
		var a2 := Time.get_ticks_usec()
		for k in 30:
			for u in w.units:
				if not u.dead:
					u._process(0.033)
		var a3 := Time.get_ticks_usec()
		for k in 30:
			w.enemy_ai._physics_process(0.033) if w.get("enemy_ai") else null
		var a4 := Time.get_ticks_usec()
		for k in 30:
			w.hud._process(0.033)
		var a5 := Time.get_ticks_usec()
		for k in 30:
			for b in w.buildings.duplicate():
				b.tick(0.033)
		var a6 := Time.get_ticks_usec()
		print("MICRO per second(30 calls) ms: unit.tick %.1f  separate %.1f  unit._process %.1f  ai %.1f  hud %.1f  bld.tick %.1f  units %d" % [(a1-a0)/1000.0, (a2-a1)/1000.0, (a3-a2)/1000.0, (a4-a3)/1000.0, (a5-a4)/1000.0, (a6-a5)/1000.0, w.units.size()])
		get_tree().quit()
		return
	if OS.get_environment("UNCAP") != "":
		Engine.max_fps = 0
	var proc := 0.0
	var phys := 0.0
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		frames += 1
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("PERF frames/s %.1f  logic ms per second: process %.0f, physics %.0f  (max_fps %d, ticks %d)" % [frames / secs, proc * 1000.0 / secs, phys * 1000.0 / secs, Engine.max_fps, Engine.physics_ticks_per_second])
	get_tree().quit()
