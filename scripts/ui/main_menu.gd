extends Control
## Title screen: background painting, the story, difficulty and the start button.

var diff_buttons := {}
var stage_buttons: Array = []
var story: Label


func _ready() -> void:
	theme = App.theme
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	var bg := TextureRect.new()
	bg.texture = load("res://assets/images/menu_bg.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.02, 0.02, 0.55))
	grad.set_color(1, Color(0.03, 0.02, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.62)
	gt.fill_to = Vector2(0.5, 0.05)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(shade)

	var panel := PanelContainer.new()
	panel.theme_type_variation = "Frame"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = 10
	panel.offset_bottom = 10
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(680, 0)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "سرزمین پارسیان"
	t.theme_type_variation = "Title"
	t.add_theme_font_size_override("font_size", 50)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := Label.new()
	sub.text = "نبرد ایران و توران، از روزگار شاهنامه"
	sub.theme_type_variation = "Muted"
	sub.add_theme_font_size_override("font_size", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	story = Label.new()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.add_theme_font_size_override("font_size", 15)
	story.add_theme_constant_override("line_spacing", 4)
	story.custom_minimum_size.y = 92
	vb.add_child(story)
	# campaign stages: three to a row, locked ones greyed out
	var sl := Label.new()
	sl.text = "مرحله‌ها"
	sl.theme_type_variation = "Muted"
	vb.add_child(sl)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(grid)
	for i in Defs.STAGES.size():
		var st: Dictionary = Defs.STAGES[i]
		var b := Button.new()
		var locked := i >= App.unlocked
		b.text = "%s. %s" % [Defs.fa(i + 1), st.n] if not locked else "%s. قفل" % Defs.fa(i + 1)
		b.tooltip_text = Defs.BIOMES[st.biome].n
		b.toggle_mode = true
		b.disabled = locked
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 46)
		b.add_theme_font_size_override("font_size", 15)
		b.clip_text = true
		b.pressed.connect(_pick_stage.bind(i))
		grid.add_child(b)
		stage_buttons.append(b)
	var dl := Label.new()
	dl.text = "سختی نبرد"
	dl.theme_type_variation = "Muted"
	vb.add_child(dl)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(dh)
	for k in ["easy", "normal", "hard"]:
		var b := Button.new()
		b.text = Defs.DIFFICULTY[k].n
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 42)
		b.button_pressed = k == App.difficulty
		b.pressed.connect(_pick.bind(k))
		dh.add_child(b)
		diff_buttons[k] = b
	var start := Button.new()
	start.text = "آغاز نبرد"
	start.theme_type_variation = "Primary"
	start.custom_minimum_size = Vector2(300, 96)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 24)
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(_start)
	vb.add_child(start)
	_pick_stage(clampi(App.stage, 0, App.unlocked - 1))
	Sfx.play_music("res://assets/music/menu_theme.ogg")
	var ver := Label.new()
	ver.text = "نسخه‌ی آزمایشی %s" % Defs.fa(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	ver.theme_type_variation = "Muted"
	ver.add_theme_font_size_override("font_size", 13)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)


func _pick(k: String) -> void:
	App.difficulty = k
	App.save_progress()
	for d in diff_buttons:
		diff_buttons[d].set_pressed_no_signal(d == k)


func _pick_stage(i: int) -> void:
	App.stage = i
	for k in stage_buttons.size():
		stage_buttons[k].set_pressed_no_signal(k == i)
	var st: Dictionary = Defs.STAGES[i]
	story.text = "مرحله‌ی %s، %s (%s)\n%s" % [Defs.fa(i + 1), st.n, Defs.BIOMES[st.biome].n, st.story]


func _start() -> void:
	App.save_progress()
	Sfx.stop_music(1.5)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
