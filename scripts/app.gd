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
var smooth := false              # false = cool mode: 30 frames a second, kinder to the battery
var stage := 0                 # campaign stage being played (index into Defs.STAGES)
var unlocked := 1              # how many stages the player may choose
var best := {}                 # "stage:difficulty" -> best time in seconds

const SAVE_PATH := "user://progress.cfg"

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
	load_progress()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = clampi(int(a.substr(8)), 0, Defs.STAGES.size() - 1)
			unlocked = Defs.STAGES.size()
		if a == "--sim":
			add_child(load("res://scripts/dev/sim.gd").new())
		if a.begins_with("--powertest="):
			var pt = load("res://scripts/dev/powertest.gd").new()
			pt.out = a.substr(12)
			add_child(pt)
		if a.begins_with("--simorghshot="):
			var so = load("res://scripts/dev/simorghshot.gd").new()
			so.out = a.substr(14)
			add_child(so)
		if a.begins_with("--formtest="):
			var ft = load("res://scripts/dev/formtest.gd").new()
			ft.out = a.substr(11)
			add_child(ft)
		if a.begins_with("--wintershot="):
			var wi = load("res://scripts/dev/wintershot.gd").new()
			wi.out = a.substr(13)
			add_child(wi)
		if a.begins_with("--rankshot="):
			var rk = load("res://scripts/dev/rankshot.gd").new()
			rk.out = a.substr(11)
			add_child(rk)
		if a.begins_with("--mapshot="):
			var mp = load("res://scripts/dev/mapshot.gd").new()
			mp.out = a.substr(10)
			add_child(mp)
		if a.begins_with("--stormshot="):
			var so2 = load("res://scripts/dev/stormshot.gd").new()
			so2.out = a.substr(12)
			add_child(so2)
		if a.begins_with("--tribeshot="):
			var tr = load("res://scripts/dev/tribeshot.gd").new()
			tr.out = a.substr(12)
			add_child(tr)
		if a.begins_with("--panelshot="):
			var ps = load("res://scripts/dev/panelshot.gd").new()
			ps.out = a.substr(12)
			add_child(ps)
		if a.begins_with("--menushot="):
			var ms = load("res://scripts/dev/menushot.gd").new()
			ms.out = a.substr(11)
			add_child(ms)
		if a == "--wavetest":
			add_child(load("res://scripts/dev/wavetest.gd").new())
		if a.begins_with("--stageshots="):
			var ss = load("res://scripts/dev/stageshot.gd").new()
			ss.out = a.substr(13)
			add_child(ss)
		if a == "--chaintest":
			add_child(load("res://scripts/dev/chaintest.gd").new())
		if a == "--perftest":
			add_child(load("res://scripts/dev/perftest.gd").new())
		if a == "--homecheck":
			add_child(load("res://scripts/dev/homecheck.gd").new())
		if a == "--campcheck":
			add_child(load("res://scripts/dev/campcheck.gd").new())
		if a == "--siegetest":
			add_child(load("res://scripts/dev/siegetest.gd").new())
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


# ---------------- campaign progress ----------------
func load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	unlocked = clampi(int(cf.get_value("campaign", "unlocked", 1)), 1, Defs.STAGES.size())
	stage = clampi(int(cf.get_value("campaign", "stage", 0)), 0, unlocked - 1)
	difficulty = str(cf.get_value("campaign", "difficulty", "normal"))
	if not Defs.DIFFICULTY.has(difficulty):
		difficulty = "normal"
	best = cf.get_value("campaign", "best", {})
	smooth = bool(cf.get_value("settings", "smooth", false))


func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("campaign", "unlocked", unlocked)
	cf.set_value("campaign", "stage", stage)
	cf.set_value("campaign", "difficulty", difficulty)
	cf.set_value("campaign", "best", best)
	cf.set_value("settings", "smooth", smooth)
	cf.save(SAVE_PATH)


## Called when Afrasiab's keep falls: opens the next stage.
## Frame rate and game-logic rate for a battle. Cool mode draws and thinks 30 times a
## second, which halves the work (and the heat); smooth mode does both 60 times.
func apply_game_rate() -> void:
	Engine.max_fps = 60 if smooth else 30
	Engine.physics_ticks_per_second = 60 if smooth else 30
	Engine.max_physics_steps_per_frame = 4


## The 3D world is drawn a little smaller and sharpened back up (FSR); menus and text stay
## at full resolution. Phone screens are so dense that the difference is hard to see.
func apply_render_scale(vp: Viewport) -> void:
	var px := DisplayServer.screen_get_size().x
	var scale := 1.0
	if OS.has_feature("mobile") and px > 1600:
		scale = clampf(1600.0 / px, 0.6, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.25


func stage_won(seconds: float) -> void:
	var key := "%d:%s" % [stage, difficulty]
	if not best.has(key) or seconds < float(best[key]):
		best[key] = seconds
	unlocked = maxi(unlocked, mini(stage + 2, Defs.STAGES.size()))
	save_progress()


func stage_def() -> Dictionary:
	return Defs.STAGES[clampi(stage, 0, Defs.STAGES.size() - 1)]


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
## Gold inner line and the four tile corners of the "Ornate" panel; connect a panel's
## draw signal to this (bound with the panel) so the corners never stretch.
static func draw_ornate_corners(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	var gold := Color("#dcb65e")
	c.draw_rect(r.grow(-1.5), gold, false, 2.0)
	c.draw_rect(r.grow(-9.5), Color(gold, 0.85), false, 2.0)
	var tex: Texture2D = load("res://assets/ui/panel.png")
	var k := 46.0
	var src := Rect2(0, 0, 58, 58)
	c.draw_texture_rect_region(tex, Rect2(-6, -6, k, k), src)
	c.draw_texture_rect_region(tex, Rect2(r.size.x + 6 - k, -6, k, k), Rect2(240 - 58, 0, 58, 58))
	c.draw_texture_rect_region(tex, Rect2(-6, r.size.y + 6 - k, k, k), Rect2(0, 240 - 58, 58, 58))
	c.draw_texture_rect_region(tex, Rect2(r.size.x + 6 - k, r.size.y + 6 - k, k, k), Rect2(240 - 58, 240 - 58, 58, 58))


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

	# Plaque: the painted wood-and-lapis side button
	t.add_type("Plaque")
	t.set_type_variation("Plaque", "Button")
	var pm := Vector4(34, 10, 34, 10)
	var pc := Vector4(30, 6, 30, 8)
	t.set_stylebox("normal", "Plaque", tex_box("res://assets/ui/side_button.png", pm, pc))
	t.set_stylebox("hover", "Plaque", tex_box("res://assets/ui/side_button.png", pm, pc, Color(1.12, 1.08, 1.0)))
	t.set_stylebox("pressed", "Plaque", tex_box("res://assets/ui/side_button.png", pm, pc, Color(1.35, 1.2, 0.85)))
	t.set_stylebox("focus", "Plaque", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Plaque", Color("#f6e7bf"))
	t.set_color("font_pressed_color", "Plaque", Color("#ffe18a"))
	t.set_color("font_outline_color", "Plaque", Color(0, 0, 0, 0.75))
	t.set_constant("outline_size", "Plaque", 4)
	t.set_font("font", "Plaque", font_bold)
	t.set_font_size("font_size", "Plaque", 15)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(Color(LAPIS_2, 0.94), LINE, 12, 1, 12))
	t.add_type("Frame")
	t.set_type_variation("Frame", "PanelContainer")
	t.set_stylebox("panel", "Frame", tex_box("res://assets/ui/panel.png", Vector4(47, 47, 47, 47), Vector4(64, 58, 64, 58)))
	# the same frame, a little tighter, for the in-game info panel
	t.add_type("Ornate")
	t.set_type_variation("Ornate", "PanelContainer")
	# The in-game info panel changes height all the time, so its frame is flat
	# (it never stretches); the four tile corners are drawn on top by draw_ornate_corners.
	var ornate := box(Color(0.16, 0.09, 0.05, 0.95), LAPIS_3, 14, 7, 44)
	ornate.content_margin_top = 34
	ornate.content_margin_bottom = 30
	ornate.shadow_color = Color(0, 0, 0, 0.35)
	ornate.shadow_size = 6
	t.set_stylebox("panel", "Ornate", ornate)

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
