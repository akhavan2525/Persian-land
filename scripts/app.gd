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

	# Gold primary button
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	var g := box(Color("#c9a34f"), Color("#6e5520"), 11, 0, 14)
	g.border_width_bottom = 3
	t.set_stylebox("normal", "Primary", g)
	var gh := g.duplicate()
	gh.bg_color = Color("#e0bb62")
	t.set_stylebox("hover", "Primary", gh)
	var gp := g.duplicate()
	gp.bg_color = Color("#b08c3c")
	gp.border_width_bottom = 1
	t.set_stylebox("pressed", "Primary", gp)
	var gd := g.duplicate()
	gd.bg_color.a = 0.5
	t.set_stylebox("disabled", "Primary", gd)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "Primary", Color("#1d1404"))
	t.set_color("font_disabled_color", "Primary", Color("#1d1404", 0.6))
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
	var fr := box(Color(LAPIS, 0.92), GOLD_SOFT, 14, 2, 22)
	fr.shadow_color = Color(0, 0, 0, 0.45)
	fr.shadow_size = 18
	t.set_stylebox("panel", "Frame", fr)

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
