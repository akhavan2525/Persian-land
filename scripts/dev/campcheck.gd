extends Node
## Development helper: `godot -- --campcheck` prints where each stage's tribe camps landed.

func _ready() -> void:
	_run()


func _run() -> void:
	for st in Defs.STAGES.size():
		App.stage = st
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await get_tree().create_timer(1.2).timeout
		var w = get_tree().current_scene
		for t in w.tribes:
			print("stage %d %s cell %s (planned %s)" % [st, t.n, t.b.cell + Vector2i(1, 1), Defs.CAMP_CELLS[w.tribes.find(t)]])
	get_tree().quit()
