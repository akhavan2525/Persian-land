extends Node
## Development helper: `godot -- --homecheck` checks that every stage lets the player
## build a quarry and a woodcutter inside the starting territory.

func _ready() -> void:
	_run()


func _run() -> void:
	App.unlocked = Defs.STAGES.size()
	for st in Defs.STAGES.size():
		App.stage = st
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await get_tree().create_timer(1.2).timeout
		var w = get_tree().current_scene
		w.res[0] = {"wood": 999, "stone": 999, "food": 999, "gold": 999}
		var found := {"quarry": 0, "woodcutter": 0}
		for j in Defs.GRID:
			for i in Defs.GRID:
				for t in found:
					if w.placement_error(t, Vector2i(i, j)) == "":
						found[t] += 1
		print("stage %d: quarry spots %d, woodcutter spots %d" % [st + 1, found.quarry, found.woodcutter])
	get_tree().quit()
