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
	# ground, forest, rock, water, mountain colours for each land
	var pal: Array = {
		"meadow": ["#7d9a46", "#46692c", "#9a9286", "#3d7fa3", "#7d7466"],
		"steppe": ["#b5a052", "#6a7a33", "#a39579", "#4a88a8", "#8a7a60"],
		"forest": ["#5f8a3c", "#2f5422", "#8f8a7c", "#3d7fa3", "#6a6658"],
		"snow": ["#dfe6ee", "#5f7a6e", "#a7adb5", "#a9c8dc", "#c4cad2"],
		"desert": ["#d8bd84", "#7d8f45", "#b0946a", "#3f8fb0", "#a8875c"],
	}.get(world.terrain.biome, ["#7d9a46", "#46692c", "#9a9286", "#3d7fa3", "#7d7466"])
	for j in n:
		for i in n:
			var t: int = world.terrain.type_at(Vector2i(i, j))
			var c := Color(pal[0])
			match t:
				Terrain.FOREST: c = Color(pal[1])
				Terrain.ROCK: c = Color(pal[2])
				Terrain.WATER: c = Color(pal[3])
				Terrain.MOUNTAIN: c = Color(pal[4])
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
