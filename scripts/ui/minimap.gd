extends Control
## Small overview map. Tap it to move the camera there.

var world: Node
var _bg: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_make_bg()


func _make_bg() -> void:
	var n := Defs.GRID
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var t: int = world.terrain.type_at(Vector2i(i, j))
			var c := Color("#7d9a46")
			match t:
				Terrain.FOREST: c = Color("#46692c")
				Terrain.ROCK: c = Color("#9a9286")
				Terrain.WATER: c = Color("#3d7fa3")
				Terrain.MOUNTAIN: c = Color("#7d7466")
			img.set_pixel(i, j, c)
	_bg = ImageTexture.create_from_image(img)


func _to_map(p: Vector3) -> Vector2:
	var k := size.x / (Defs.GRID * Defs.CELL)
	return Vector2((p.x + Defs.HALF) * k, (p.z + Defs.HALF) * k)


func _draw() -> void:
	if world == null:
		return
	draw_texture_rect(_bg, Rect2(Vector2.ZERO, size), false)
	for b: Building in world.buildings:
		if b.dead:
			continue
		var col := Color("#d8cdb2") if b.side < 0 else Defs.faction_color[b.side].lightened(0.15)
		var s := maxf(3.0, b.size * Defs.CELL * size.x / (Defs.GRID * Defs.CELL))
		draw_rect(Rect2(_to_map(b.position) - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	for u: Unit in world.units:
		if u.dead:
			continue
		var col: Color = Defs.faction_color[u.side].lightened(0.35) if u.side < 2 else Color("#c9a3ff")
		draw_rect(Rect2(_to_map(u.position) - Vector2(1.5, 1.5), Vector2(3, 3)), col)
	# camera footprint
	var c := _to_map(world.rig.position)
	var r: float = world.rig.dist * 0.55 * size.x / (Defs.GRID * Defs.CELL)
	var pts := PackedVector2Array()
	for k in 5:
		var a: float = world.rig.rotation.y * -1.0 + PI / 4.0 + k * PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_polyline(pts, Color(1, 1, 1, 0.8), 1.5)


func _gui_input(ev: InputEvent) -> void:
	var pos = null
	if ev is InputEventScreenTouch and ev.pressed:
		pos = ev.position
	elif ev is InputEventScreenDrag:
		pos = ev.position
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		pos = ev.position
	if pos != null:
		var k := (Defs.GRID * Defs.CELL) / size.x
		world.rig.position = Vector3(pos.x * k - Defs.HALF, 0, pos.y * k - Defs.HALF)
		world.rig.zoom_by(1.0)
		accept_event()
