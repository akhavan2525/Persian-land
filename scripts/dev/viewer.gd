extends Node3D
## Development helper: `godot -- --view=/some/file.png` lays out every building and unit
## (procedural or GLB) on a flat field with the game's lighting and saves a screenshot.

var out := ""
var what := "all"


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("#4f7fc4")
	psm.sky_horizon_color = Color("#e7cfa8")
	psm.ground_bottom_color = Color("#5a4e3e")
	psm.ground_horizon_color = Color("#d9c09a")
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-62), 0)
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.material_override = Models.mat(Color("#7d8a4a"))
	add_child(ground)

	var x := 0.0
	if what in ["all", "buildings"]:
		for t in ["keep", "barracks", "tower", "house", "farm", "woodcutter", "quarry", "wall", "gate", "village"]:
			var sides := [0, 1] if t in ["keep", "barracks", "tower"] else [0]
			for s in sides:
				var b := Models.make_building(t, s, 1)
				add_child(b)
				var w: float = Defs.BUILDINGS[t].size * Defs.CELL
				b.position = Vector3(x + w / 2.0, 0, 0)
				x += w + 1.5
	var ux := 0.0
	if what in ["all", "units"]:
		for t in ["spear", "archer", "cav", "immortal", "hero", "div"]:
			for s in ([0, 1] if t != "div" else [2]):
				var m := Models.make_unit(t, s)
				var n: Node3D = m.root
				n.scale = Vector3.ONE * 1.25
				add_child(n)
				n.position = Vector3(ux, 0, 12 if what == "all" else 0)
				n.rotation.y = PI * 0.25
				ux += 2.6
				if m.anim:
					var names: PackedStringArray = m.anim.get_animation_list()
					for a in names:
						if String(a).to_lower().contains("walk"):
							m.anim.play(a)
	if what.begins_with("anim:"):
		# anim:<type>:<side> shows idle, two walk frames and two attack frames up close
		var bits := what.split(":")
		var shots := [["idle", 0.0], ["walk", 0.3], ["attack", 0.25], ["attack", 0.4], ["attack", 0.55]]
		for i in shots.size():
			var m := Models.make_unit(bits[1], int(bits[2]))
			var n: Node3D = m.root
			add_child(n)
			n.position = Vector3(i * 2.2, 0, 0)
			n.rotation.y = -PI * 0.3 if i % 2 == 0 else PI * 0.5
			if m.anim:
				for a in m.anim.get_animation_list():
					if String(a).to_lower().contains(shots[i][0]):
						m.anim.play(a)
						m.anim.seek(shots[i][1], true)
						m.anim.pause()
		ux = 4 * 2.2
		x = 0.0
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var span := maxf(x, ux)
	var center := Vector3(span / 2.0, 0, 6 if what == "all" else 0)
	if what.begins_with("anim:"):
		center = Vector3(ux / 2.0, 0, 0)
	var dist := span * 0.62 + 6.0
	cam.position = center + Vector3(0, dist * 0.55, dist * 0.8)
	cam.look_at(center + Vector3(0, 2, 0))
	if what.begins_with("anim:"):
		cam.position = center + Vector3(0, 2.2, 7.5)
		cam.look_at(center + Vector3(0, 1.1, 0))
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
