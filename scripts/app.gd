extends Node
## Global app state (autoload "App"): chosen difficulty, save file, shared UI theme and colours.

const LAPIS := Color("#0d1833")
const LAPIS_2 := Color("#15254a")
const LAPIS_3 := Color("#1e3361")
const LINE := Color("#2c4479")
const GOLD := Color("#dcb65e")
const GOLD_SOFT := Color("#a98a43")
const IVORY := Color("#f2e9d3")
const MUTED := Color("#a8b2c8")
const TURQ := Color("#43b8a9")
const CRIMSON := Color("#d0574b")

var difficulty := "normal"
var music_on := true

var font_regular: Font
var font_bold: Font
var font_black: Font
var font_display: Font
var theme: Theme


func _ready() -> void:
	font_regular = load("res://assets/fonts/Vazirmatn-UI-FD-Regular.ttf")
	font_bold = load("res://assets/fonts/Vazirmatn-UI-FD-Bold.ttf")
	font_black = load("res://assets/fonts/Vazirmatn-UI-FD-Black.ttf")
	var lalezar: FontFile = load("res://assets/fonts/Lalezar-Regular.ttf")
	# Lalezar for titles, Vazirmatn for anything it is missing.
	font_display = lalezar.duplicate()
	font_display.fallbacks = [font_black]
	theme = _make_theme()
	for a in OS.get_cmdline_user_args():
		if a == "--sim":
			add_child(load("res://scripts/dev/sim.gd").new())
		if a.begins_with("--powertest="):
			var pt = load("res://scripts/dev/powertest.gd").new()
			pt.out = a.substr(12)
			add_child(pt)
		if a == "--wavetest":
			add_child(load("res://scripts/dev/wavetest.gd").new())
		if a == "--pathtest":
			add_child(load("res://scripts/dev/pathtest.gd").new())
		if a.begins_with("--shots="):
			var shot = load("res://scripts/dev/autoshot.gd").new()
			shot.out = a.substr(8)
			add_child(shot)
		if a.begins_with("--view="):
			# --view=<png>[:units|buildings]
			var parts := a.substr(7).split(":")
			var v = load("res://scripts/dev/viewer.gd").new()
			v.out = parts[0]
			if parts.size() > 1:
				v.what = ":".join(parts.slice(1))
			get_tree().root.add_child.call_deferred(v)
			get_tree().current_scene.queue_free.call_deferred()


# ---------------- UI theme ----------------
static func box(bg: Color, border: Color, radius := 10, bw := 1, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	return s


## A 9-slice style from one of the painted UI textures.
static func tex_box(path: String, margin: Vector4, content: Vector4, mod := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.texture_margin_left = margin.x
	s.texture_margin_top = margin.y
	s.texture_margin_right = margin.z
	s.texture_margin_bottom = margin.w
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	s.modulate_color = mod
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 18
	t.set_color("font_color", "Label", IVORY)

	t.set_stylebox("normal", "Button", box(LAPIS_3, LINE, 9))
	t.set_stylebox("hover", "Button", box(LAPIS_3.lightened(0.08), GOLD_SOFT, 9))
	t.set_stylebox("pressed", "Button", box(LAPIS_2, GOLD, 9))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 9, 2))
	var dis := box(LAPIS_3, LINE, 9)
	dis.bg_color.a = 0.45
	dis.border_color.a = 0.45
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", IVORY)
	t.set_color("font_hover_color", "Button", IVORY)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", IVORY)
	t.set_color("font_disabled_color", "Button", Color(IVORY, 0.4))

	# Primary button: the painted red-and-turquoise plaque
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	var bm := Vector4(66, 40, 66, 40)
	var bc := Vector4(54, 18, 54, 20)
	t.set_stylebox("normal", "Primary", tex_box("res://assets/ui/button.png", bm, bc))
	t.set_stylebox("hover", "Primary", tex_box("res://assets/ui/button.png", bm, bc, Color(1.15, 1.1, 1.05)))
	t.set_stylebox("pressed", "Primary", tex_box("res://assets/ui/button.png", bm, bc, Color(0.82, 0.8, 0.8)))
	t.set_stylebox("disabled", "Primary", tex_box("res://assets/ui/button.png", bm, bc, Color(0.55, 0.55, 0.6, 0.75)))
	t.set_stylebox("focus", "Primary", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Primary", Color("#fff4d6"))
	t.set_color("font_disabled_color", "Primary", Color("#fff4d6", 0.55))
	t.set_color("font_outline_color", "Primary", Color("#3a0a06"))
	t.set_constant("outline_size", "Primary", 6)
	t.set_font("font", "Primary", font_black)
	t.set_font_size("font_size", "Primary", 20)

	# Ghost button for the top bar
	t.add_type("Ghost")
	t.set_type_variation("Ghost", "Button")
	t.set_stylebox("normal", "Ghost", box(Color(0, 0, 0, 0.25), GOLD_SOFT, 8, 1, 10))
	t.set_stylebox("hover", "Ghost", box(Color(GOLD, 0.12), GOLD, 8, 1, 10))
	t.set_stylebox("pressed", "Ghost", box(Color(GOLD, 0.2), GOLD, 8, 1, 10))
	t.set_color("font_color", "Ghost", GOLD)
	t.set_color("font_hover_color", "Ghost", GOLD)
	t.set_font_size("font_size", "Ghost", 16)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(Color(LAPIS_2, 0.94), LINE, 12, 1, 12))
	t.add_type("Frame")
	t.set_type_variation("Frame", "PanelContainer")
	t.set_stylebox("panel", "Frame", tex_box("res://assets/ui/panel.png", Vector4(47, 47, 47, 47), Vector4(64, 58, 64, 58)))
	# the same frame, a little tighter, for the in-game info panel
	t.add_type("Ornate")
	t.set_type_variation("Ornate", "PanelContainer")
	t.set_stylebox("panel", "Ornate", tex_box("res://assets/ui/panel.png", Vector4(47, 47, 47, 47), Vector4(56, 52, 56, 50)))

	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font_display)
	t.set_font_size("font_size", "Title", 30)
	t.set_color("font_color", "Title", GOLD)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_y", "Title", 2)

	t.add_type("Muted")
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 15)

	t.set_stylebox("panel", "PopupPanel", box(LAPIS_2, GOLD_SOFT, 12))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(GOLD_SOFT, 0.5), Color(0, 0, 0, 0), 4, 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD_SOFT, Color(0, 0, 0, 0), 4, 0, 2))
	return t
