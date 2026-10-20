extends Control
## Draws health bars, floating numbers, village capture bars and the selection box on top of the 3D view.

var world: Node


func _bar(p: Vector2, w: float, frac: float, col: Color) -> void:
	var h := 6.0
	var r := Rect2(p - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(w * clampf(frac, 0.0, 1.0), h)), col)


func _hp_color(f: float) -> Color:
	return Color("#6fd28a") if f > 0.6 else (Color("#e8c45a") if f > 0.3 else Color("#e0574b"))


func _draw() -> void:
	if world == null or world.rig == null:
		return
	var cam: Camera3D = world.rig.cam
	var now := Time.get_ticks_msec() / 1000.0
	var vis := get_viewport_rect()
	var font: Font = App.font_bold
	for u: Unit in world.units:
		if u.dead:
			continue
		var show: bool = u.selected or now - u.last_hit_t < 4.0 or u.type in ["hero", "div"]
		if not show:
			continue
		var wp: Vector3 = u.position + Vector3(0, 2.3 if u.type not in ["cav", "div", "hero"] else 3.4, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		if not vis.grow(40).has_point(sp):
			continue
		var f: float = u.hp / u.max_hp
		var w := 34.0 if u.type not in ["hero", "div"] else 54.0
		_bar(sp, w, f, _hp_color(f) if u.side != Defs.TURAN else Color("#e06a5a"))
		if u.type == "hero":
			draw_string_outline(font, sp + Vector2(-60, -10), u.display_name(), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(font, sp + Vector2(-60, -10), u.display_name(), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color("#ffe18a"))
	for b: Building in world.buildings:
		if b.dead:
			continue
		if b.type == "village":
			if b.capturing >= 0:
				var wp: Vector3 = b.position + Vector3(0, 5.5, 0)
				if not cam.is_position_behind(wp):
					var sp := cam.unproject_position(wp)
					_bar(sp, 70, b.capture[b.capturing] / Defs.CAPTURE_TIME, Defs.faction_color[b.capturing].lightened(0.2))
			continue
		if not (b.selected or now - b.last_hit_t < 5.0):
			continue
		var top := 4.0 if b.type != "keep" else 13.0
		var wp: Vector3 = b.position + Vector3(0, top, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var f: float = b.hp / b.max_hp
		_bar(sp, 70.0 if b.size > 1 else 40.0, f, _hp_color(f))
	for fl in world.floats:
		var wp: Vector3 = fl.pos + Vector3(0, fl.t * 1.5, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var a := 1.0 - pow(fl.t / 1.6, 2.0)
		draw_string_outline(font, sp + Vector2(-80, 0), fl.text, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 5, Color(0.05, 0.07, 0.15, 0.85 * a))
		draw_string(font, sp + Vector2(-80, 0), fl.text, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color(fl.color, a))
	if world.box_active:
		var r := Rect2(world.box_from, Vector2.ZERO).expand(world.box_to)
		draw_rect(r, Color(1.0, 0.88, 0.54, 0.15))
		draw_rect(r, Color("#ffe18a"), false, 2.0)
