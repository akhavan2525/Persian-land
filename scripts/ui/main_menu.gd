extends Control
## Title screen: the painting fills the screen, the game's name stands large on top and a
## short column of grand buttons sits below it. Stages open on their own screen of cards.

var diff_btn: Button
var music_btn: Button
var home: Control
var stages_screen: Control
var stage_cards: Array = []
var story: Label
var story_title: Label

const DIFF_ORDER := ["easy", "normal", "hard"]


func _ready() -> void:
	# the menu is still: half the frames keep the phone cool with no visible change
	Engine.max_fps = 30
	theme = App.theme
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var bg := TextureRect.new()
	bg.texture = load("res://assets/images/menu_bg.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	# darken the top for the title and the bottom for the buttons; the painting stays bright in between
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.01, 0.02, 0.7), Color(0.02, 0.01, 0.02, 0.1), Color(0.02, 0.01, 0.02, 0.15), Color(0.02, 0.01, 0.02, 0.8)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_build_home()
	_build_stages()
	_pick_stage(clampi(App.stage, 0, App.unlocked - 1))
	Sfx.play_music("res://assets/music/menu_theme.ogg")


# ---------------- title screen ----------------
func _build_home() -> void:
	home = Control.new()
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(home)
	var t := Label.new()
	t.text = "سرزمین پارسیان"
	t.add_theme_font_override("font", App.font_display)
	t.add_theme_font_size_override("font_size", 96)
	t.add_theme_color_override("font_color", Color("#f4cf6e"))
	t.add_theme_color_override("font_outline_color", Color("#2a1406"))
	t.add_theme_constant_override("outline_size", 18)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.offset_left = -500
	t.offset_right = 500
	t.offset_top = 22
	home.add_child(t)
	var sub := Label.new()
	sub.text = "نبرد ایران و توران، از روزگار شاهنامه"
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color("#f2e9d3"))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("outline_size", 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -400
	sub.offset_right = 400
	sub.offset_top = 150
	home.add_child(sub)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.offset_left = -190
	col.offset_right = 190
	col.offset_top = -330
	col.offset_bottom = -30
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 10)
	home.add_child(col)
	var start := Button.new()
	start.text = "آغاز نبرد"
	start.theme_type_variation = "Primary"
	start.custom_minimum_size = Vector2(380, 104)
	start.add_theme_font_size_override("font_size", 30)
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(_start)
	col.add_child(start)
	col.add_child(_grand("مرحله‌ها", _show_stages))
	diff_btn = _grand("", _next_difficulty)
	col.add_child(diff_btn)
	music_btn = _grand("", _toggle_music)
	col.add_child(music_btn)
	_update_labels()

	var ver := Label.new()
	ver.text = "نسخه‌ی آزمایشی %s" % Defs.fa(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 14
	ver.offset_top = -30
	home.add_child(ver)


## A wide painted plaque button for the title column.
func _grand(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "Plaque"
	b.custom_minimum_size = Vector2(330, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _update_labels() -> void:
	diff_btn.text = "سختی: %s" % Defs.DIFFICULTY[App.difficulty].n
	music_btn.text = "موسیقی: %s" % ("روشن" if App.music_on else "خاموش")


func _next_difficulty() -> void:
	App.difficulty = DIFF_ORDER[(DIFF_ORDER.find(App.difficulty) + 1) % DIFF_ORDER.size()]
	App.save_progress()
	_update_labels()


func _toggle_music() -> void:
	App.music_on = not App.music_on
	App.save_progress()
	if App.music_on:
		Sfx.play_music("res://assets/music/menu_theme.ogg")
	else:
		Sfx.stop_music(0.6)
	_update_labels()


# ---------------- stage cards ----------------
func _build_stages() -> void:
	stages_screen = Control.new()
	stages_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	stages_screen.visible = false
	add_child(stages_screen)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	stages_screen.add_child(dim)
	var head := Label.new()
	head.text = "راه نبرد"
	head.add_theme_font_override("font", App.font_display)
	head.add_theme_font_size_override("font_size", 54)
	head.add_theme_color_override("font_color", Color("#f4cf6e"))
	head.add_theme_color_override("font_outline_color", Color("#2a1406"))
	head.add_theme_constant_override("outline_size", 12)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.offset_left = -300
	head.offset_right = 300
	head.offset_top = 16
	stages_screen.add_child(head)
	# a row of cards, one per stage, scrolling sideways on narrow screens
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	scroll.offset_top = 100
	scroll.offset_bottom = 300
	scroll.offset_left = 30
	scroll.offset_right = -30
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stages_screen.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(row)
	for i in Defs.STAGES.size():
		var st: Dictionary = Defs.STAGES[i]
		var locked := i >= App.unlocked
		var b := Button.new()
		b.toggle_mode = true
		b.disabled = locked
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(158, 180)
		b.add_theme_stylebox_override("normal", App.box(Color(App.LAPIS, 0.88), App.GOLD_SOFT, 14, 2, 10))
		b.add_theme_stylebox_override("hover", App.box(Color(App.LAPIS_2, 0.92), App.GOLD, 14, 2, 10))
		b.add_theme_stylebox_override("pressed", App.box(Color(App.LAPIS_3, 0.95), Color("#ffe18a"), 14, 4, 10))
		b.add_theme_stylebox_override("disabled", App.box(Color(0.05, 0.05, 0.08, 0.75), Color(0.35, 0.35, 0.4), 14, 2, 10))
		b.pressed.connect(_pick_stage.bind(i))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(vb)
		var num := Label.new()
		num.text = Defs.fa(i + 1)
		num.add_theme_font_override("font", App.font_display)
		num.add_theme_font_size_override("font_size", 52)
		num.add_theme_color_override("font_color", App.GOLD if not locked else Color(0.5, 0.5, 0.55))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(num)
		var nm := Label.new()
		nm.text = st.n if not locked else "قفل"
		nm.add_theme_font_size_override("font_size", 17)
		nm.add_theme_color_override("font_color", App.IVORY if not locked else Color(0.6, 0.6, 0.65))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(nm)
		var bio := Label.new()
		bio.text = Defs.BIOMES[st.biome].n if not st.has("first_snow") else "پاییز تا زمستان"
		bio.add_theme_font_size_override("font_size", 14)
		bio.add_theme_color_override("font_color", App.TURQ if not locked else Color(0.45, 0.45, 0.5))
		bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(bio)
		row.add_child(b)
		stage_cards.append(b)
	# the chosen stage's story under the cards
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", App.box(Color(App.LAPIS, 0.85), App.GOLD_SOFT, 16, 2, 18))
	sp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sp.offset_left = -430
	sp.offset_right = 430
	sp.offset_top = -330
	sp.offset_bottom = -130
	stages_screen.add_child(sp)
	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 6)
	sp.add_child(svb)
	story_title = Label.new()
	story_title.add_theme_font_override("font", App.font_display)
	story_title.add_theme_font_size_override("font_size", 28)
	story_title.add_theme_color_override("font_color", App.GOLD)
	svb.add_child(story_title)
	story = Label.new()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.add_theme_font_size_override("font_size", 16)
	story.add_theme_constant_override("line_spacing", 5)
	svb.add_child(story)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -300
	bar.offset_right = 300
	bar.offset_top = -112
	bar.offset_bottom = -16
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	stages_screen.add_child(bar)
	var go := Button.new()
	go.text = "آغاز نبرد"
	go.theme_type_variation = "Primary"
	go.custom_minimum_size = Vector2(300, 92)
	go.add_theme_font_size_override("font_size", 26)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(_start)
	bar.add_child(go)
	var back := _grand("بازگشت", _hide_stages)
	back.custom_minimum_size = Vector2(200, 58)
	bar.add_child(back)


func _show_stages() -> void:
	home.visible = false
	stages_screen.visible = true


func _hide_stages() -> void:
	stages_screen.visible = false
	home.visible = true


func _pick_stage(i: int) -> void:
	App.stage = i
	for k in stage_cards.size():
		stage_cards[k].set_pressed_no_signal(k == i)
	var st: Dictionary = Defs.STAGES[i]
	story_title.text = "مرحله‌ی %s: %s" % [Defs.fa(i + 1), st.n]
	story.text = st.story


func _start() -> void:
	App.save_progress()
	Sfx.stop_music(1.5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
