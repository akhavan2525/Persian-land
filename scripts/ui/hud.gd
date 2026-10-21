extends CanvasLayer
## In-game interface, right-to-left Persian. Built in code so it is easy to restyle later.

var world: Node

var root: Control
var overlay: Control
var minimap: Control
var res_labels := {}
var pop_label: Label
var wave_label: Label
var speed_btn: Button
var build_bar: HBoxContainer
var build_buttons := {}
var sel_panel: PanelContainer
var sel_box: VBoxContainer
var build_panel: PanelContainer
var build_hint: Label
var build_ok: Button
var box_btn: Button
var toasts: VBoxContainer
var dim: ColorRect
var menu_frame: PanelContainer
var help_frame: PanelContainer
var end_frame: PanelContainer
var end_title: Label
var end_text: Label
var end_next: Button
var end_retry: Button
var _refresh_t := 0.0
var blockers: Array[Control] = []
var power_row: HBoxContainer
var power_btns := {}           # power -> {bar, ring, label}


## True when a screen point is on a panel or button, so the world ignores that touch.
func is_over_ui(p: Vector2) -> bool:
	if dim.visible:
		return true
	for c in blockers:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false

const ICONS := {"wood": "res://assets/icons/wood.svg", "stone": "res://assets/icons/stone.svg",
	"food": "res://assets/icons/food.svg", "gold": "res://assets/icons/gold.svg"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = App.theme
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL
	add_child(root)

	overlay = preload("res://scripts/ui/overlay.gd").new()
	overlay.world = world
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	_build_top_bar()
	_build_bottom_bar()
	_build_power_row()
	_build_side_tools()
	_build_selection_panel()
	_build_build_panel()
	_build_toasts()
	_build_minimap()
	_build_dialogs()

	world.message.connect(_on_message)
	world.selection_changed.connect(_on_selection)
	world.game_over.connect(_on_game_over)
	_on_selection()
	_refresh()


# ---------------- helpers ----------------
func _label(text: String, size := 18, color := App.IVORY, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _icon(path: String, size := 26) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Painted face of a unit type; Turan soldiers share one face, the two heroes have their own.
func _portrait_path(type: String, side: int) -> String:
	var key := type
	if side == Defs.TURAN:
		key = "turan_hero" if type == "hero" else "turan"
	var path := "res://assets/ui/portraits/%s.png" % key
	return path if ResourceLoader.exists(path) else ""


func _portrait(type: String, side: int, size := 96) -> Control:
	var path := _portrait_path(type, side)
	if path == "":
		return null
	return _icon(path, size)


func _button(text: String, variation := "", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if variation == "Primary":
		# the painted plaque looks right near its own shape, so do not let it stretch wide
		b.custom_minimum_size = Vector2(250, 84)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


# ---------------- top bar ----------------
## Where the four number slots sit on the painted top bar, as fractions of its width
## (printed by tools/ui/make_ui.py).
const TOP_SLOTS := [[0.0744, 0.2188], [0.2681, 0.4118], [0.5885, 0.7323], [0.7815, 0.9253]]
const TOP_SLOT_Y := [0.3365, 0.7279]
const BAR_H := 148            # height of the painted bottom bar
const TOP_H := 88.0
const TOP_W := TOP_H * 1010.0 / 150.0


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 54
	var sb := App.box(Color(App.LAPIS, 0.9), App.GOLD_SOFT, 0, 0, 10)
	sb.border_width_bottom = 2
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	bar.add_theme_stylebox_override("panel", sb)
	root.add_child(bar)
	blockers.append(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)
	var title := _label("سرزمین پارسیان", 24, App.GOLD, App.font_display)
	hb.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	var wc := HBoxContainer.new()
	wc.add_child(_icon("res://assets/icons/timer.svg"))
	wave_label = _label("", 17, Color("#ffb3a8"), App.font_bold)
	wc.add_child(wave_label)
	hb.add_child(wc)
	speed_btn = _button("سرعت ×۱", "Ghost", _toggle_speed)
	hb.add_child(speed_btn)
	hb.add_child(_button("منو", "Ghost", _open_menu))

	# the painted Persian bar in the middle, with the stores in its slots and people in the medallion
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/topbar.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_preset(Control.PRESET_CENTER_TOP)
	art.offset_left = -TOP_W / 2.0
	art.offset_right = TOP_W / 2.0
	art.offset_top = -6
	art.offset_bottom = TOP_H - 6
	art.layout_direction = Control.LAYOUT_DIRECTION_LTR
	root.add_child(art)
	blockers.append(art)
	# right to left, as Persian reads: wood, stone | people | food, gold
	var order := ["gold", "food", "stone", "wood"]
	for i in 4:
		var k: String = order[i]
		var x0: float = TOP_SLOTS[i][0] * TOP_W
		var x1: float = TOP_SLOTS[i][1] * TOP_W
		var chip := HBoxContainer.new()
		chip.layout_direction = Control.LAYOUT_DIRECTION_LTR
		chip.position = Vector2(x0 - 6, TOP_SLOT_Y[0] * TOP_H - 9)
		chip.size = Vector2(x1 - x0 + 6, (TOP_SLOT_Y[1] - TOP_SLOT_Y[0]) * TOP_H + 18)
		chip.add_theme_constant_override("separation", 2)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.tooltip_text = Defs.RES_NAMES[k]
		chip.add_child(_icon("res://assets/ui/icons/%s.png" % k, 40))
		var l := _label("۰", 19, App.IVORY, App.font_bold)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_FILL
		chip.add_child(l)
		res_labels[k] = l
		art.add_child(chip)
	pop_label = _label("", 19, Color("#fff4d6"), App.font_black)
	pop_label.add_theme_color_override("font_outline_color", Color("#0b1a3d"))
	pop_label.add_theme_constant_override("outline_size", 7)
	pop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop_label.tooltip_text = "جمعیت"
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(pop_label)
	art.add_child(mid)


func _toggle_speed() -> void:
	Engine.time_scale = 2.0 if Engine.time_scale < 1.5 else 1.0
	speed_btn.text = "سرعت ×۲" if Engine.time_scale > 1.5 else "سرعت ×۱"


# ---------------- bottom build bar ----------------
func _build_bottom_bar() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -BAR_H
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var bar := PanelContainer.new()
	# the painted lapis strip with pointed gold ends
	bar.add_theme_stylebox_override("panel", App.tex_box("res://assets/ui/bottom_bar.png", Vector4(84, 30, 84, 30), Vector4(64, 12, 64, 12)))
	holder.add_child(bar)
	blockers.append(bar)
	build_bar = HBoxContainer.new()
	build_bar.add_theme_constant_override("separation", 4)
	bar.add_child(build_bar)
	var tile := App.tex_box("res://assets/ui/build_tile.png", Vector4(10, 44, 10, 10), Vector4(6, 8, 6, 6))
	var tile_on := App.tex_box("res://assets/ui/build_tile.png", Vector4(10, 44, 10, 10), Vector4(6, 8, 6, 6), Color(1.35, 1.25, 0.9))
	var tile_dn := App.tex_box("res://assets/ui/build_tile.png", Vector4(10, 44, 10, 10), Vector4(6, 8, 6, 6), Color(0.85, 0.85, 0.9))
	for t in Defs.BUILD_MENU:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(92, 116)
		b.toggle_mode = true
		b.add_theme_stylebox_override("normal", tile)
		b.add_theme_stylebox_override("hover", tile)
		b.add_theme_stylebox_override("pressed", tile_on)
		b.add_theme_stylebox_override("hover_pressed", tile_on)
		b.add_theme_stylebox_override("disabled", tile_dn)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_top = 4
		vb.offset_bottom = -6
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", -2)
		var ip := "res://assets/ui/icons/b_%s.png" % t
		if ResourceLoader.exists(ip):
			var ic := _icon(ip, 58)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(ic)
		var n := _label(Defs.BUILDINGS[t].n, 14, App.IVORY, App.font_bold)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		n.add_theme_constant_override("outline_size", 4)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var c := _label(Defs.cost_text(Defs.BUILDINGS[t].cost), 11, Color("#e6d7a8"))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(n)
		vb.add_child(c)
		b.add_child(vb)
		b.pressed.connect(func():
			if world.mode == "build" and world.build_type == t:
				world.cancel_build()
			else:
				world.start_build(t))
		build_bar.add_child(b)
		build_buttons[t] = b


# ---------------- war powers ----------------
func _build_power_row() -> void:
	power_row = HBoxContainer.new()
	power_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	power_row.offset_top = -BAR_H - 98
	power_row.offset_bottom = -BAR_H - 6
	power_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	power_row.alignment = BoxContainer.ALIGNMENT_CENTER
	power_row.add_theme_constant_override("separation", 0)
	root.add_child(power_row)
	for k in Defs.POWER_ORDER:
		# icon button on top, its name in a label below; the VBox keeps them centred together
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(78, 76)
		cell.add_child(b)
		b.tooltip_text = Defs.POWERS[k].desc
		var icon: Texture2D = load("res://assets/ui/icons/power_%s.png" % k)
		var bar := TextureProgressBar.new()
		bar.texture_under = icon
		bar.texture_progress = icon
		bar.tint_under = Color(0.25, 0.25, 0.3, 0.9)
		bar.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		bar.nine_patch_stretch = true
		bar.max_value = 1.0
		bar.step = 0.001
		# anchored to fill the button so right-to-left mirroring cannot push it aside
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.offset_left = 3
		bar.offset_right = -3
		bar.offset_bottom = -4
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bar)
		var ring := Panel.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0, 0, 0, 0)
		rs.border_color = App.GOLD
		rs.set_border_width_all(3)
		rs.set_corner_radius_all(40)
		ring.add_theme_stylebox_override("panel", rs)
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.offset_left = -1
		ring.offset_right = 1
		ring.offset_top = -4
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.visible = false
		b.add_child(ring)
		var l := _label(Defs.POWERS[k].n, 13, App.IVORY, App.font_bold)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = 96
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(l)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			Sfx.play("click")
			world.powers.press(k))
		power_row.add_child(cell)
		blockers.append(b)
		power_btns[k] = {"bar": bar, "ring": ring, "label": l, "btn": b}


func _refresh_powers() -> void:
	power_row.visible = world.mode != "build"
	var t := Time.get_ticks_msec() / 1000.0
	for k in power_btns:
		var pb: Dictionary = power_btns[k]
		var c: float = world.powers.charge[k]
		pb.bar.value = c
		var ready := c >= 1.0
		pb.ring.visible = ready or world.powers.armed == k
		if world.powers.armed == k:
			pb.ring.modulate = Color(1, 1, 1, 0.6 + 0.4 * sin(t * 10.0))
		elif ready:
			pb.ring.modulate = Color(1, 1, 1, 0.55 + 0.45 * sin(t * 4.0))
		pb.bar.modulate = Color(1.15, 1.1, 1.0) if ready else Color(1, 1, 1)


# ---------------- left tools ----------------
func _build_side_tools() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	vb.offset_left = 6
	vb.offset_top = -20
	vb.add_theme_constant_override("separation", 8)
	vb.layout_direction = Control.LAYOUT_DIRECTION_RTL
	root.add_child(vb)
	blockers.append(vb)
	for item in [["همه‌ی سپاه", world.select_all_army], ["رستم", world.select_hero], ["دژ ایران", world.focus_home], ["ایست", world.stop_selected]]:
		var b := _button(item[0], "Plaque", item[1])
		b.custom_minimum_size = Vector2(140, 44)
		vb.add_child(b)
	box_btn = _button("کادر انتخاب", "Plaque", world.toggle_box_mode)
	box_btn.custom_minimum_size = Vector2(140, 44)
	box_btn.toggle_mode = true
	vb.add_child(box_btn)


# ---------------- selection panel ----------------
func _build_selection_panel() -> void:
	sel_panel = PanelContainer.new()
	sel_panel.theme_type_variation = "Ornate"
	sel_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sel_panel.offset_left = -400
	sel_panel.offset_right = -6
	sel_panel.offset_top = 60
	sel_panel.custom_minimum_size.x = 394
	root.add_child(sel_panel)
	blockers.append(sel_panel)
	sel_box = VBoxContainer.new()
	sel_box.add_theme_constant_override("separation", 6)
	sel_panel.add_child(sel_box)


func _on_selection() -> void:
	_last_sig = _selection_signature()
	_clear(sel_box)
	for t in build_buttons:
		build_buttons[t].set_pressed_no_signal(world.mode == "build" and world.build_type == t)
	box_btn.set_pressed_no_signal(world.mode == "box")
	build_panel.visible = world.mode == "build"
	if world.mode == "build":
		_refresh_build_hint()
	var b: Building = world.selected_building
	if world.selected.size() > 0:
		_fill_units()
	elif b != null and not b.dead:
		_fill_building(b)
	else:
		sel_panel.visible = false
		return
	sel_panel.visible = true


func _fill_units() -> void:
	var counts := {}
	var hp := 0.0
	var max_hp := 0.0
	for u: Unit in world.selected:
		counts[u.type] = counts.get(u.type, 0) + 1
		hp += u.hp
		max_hp += u.max_hp
	if world.selected.size() == 1:
		var u: Unit = world.selected[0]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		var face := _portrait(u.type, u.side, 104)
		if face:
			head.add_child(face)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_child(col)
		col.add_child(_label(u.display_name(), 24, App.GOLD, App.font_display))
		var desc: String = Defs.HEROES[0].desc if u.type == "hero" else Defs.UNITS[u.type].desc
		var d := _label(desc, 15, App.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 200
		col.add_child(d)
		sel_box.add_child(head)
		var ud: Dictionary = Defs.UNITS[u.type]
		sel_box.add_child(_label("جان %s از %s · ضربه %s · بُرد %s" % [Defs.fa(int(u.hp)), Defs.fa(int(u.max_hp)), Defs.fa(ud.dmg), Defs.fa(int(ud.range))], 15))
	else:
		sel_box.add_child(_label("سپاه برگزیده: %s جنگجو" % Defs.fa(world.selected.size()), 22, App.GOLD, App.font_display))
		var faces := HBoxContainer.new()
		faces.add_theme_constant_override("separation", 4)
		for t in counts:
			var f := _portrait(t, world.selected[0].side, 62)
			if f == null:
				continue
			var cell := Control.new()
			cell.custom_minimum_size = Vector2(62, 62)
			cell.add_child(f)
			var n := _label(Defs.fa(counts[t]), 16, App.IVORY, App.font_bold)
			n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			n.add_theme_constant_override("outline_size", 6)
			n.position = Vector2(4, 38)
			cell.add_child(n)
			faces.add_child(cell)
		if faces.get_child_count() > 0:
			sel_box.add_child(faces)
		var parts: PackedStringArray = []
		for t in counts:
			parts.append("%s %s" % [Defs.fa(counts[t]), Defs.unit_name(t, 0)])
		var l := _label("، ".join(parts), 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sel_box.add_child(l)
		sel_box.add_child(_label("جان سپاه: %s٪" % Defs.fa(int(100.0 * hp / maxf(1.0, max_hp))), 15, App.MUTED))
	var hint := _label("روی زمین بزن تا بروند، روی دشمن بزن تا بجنگند.", 14, App.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_child(_button("ایست", "", world.stop_selected))
	row.add_child(_button("لغو انتخاب", "", world.clear_selection))
	sel_box.add_child(row)


func _fill_building(b: Building) -> void:
	var title := b.display_name()
	if b.type == "village":
		title = "روستا · " + ("آزاد" if b.side < 0 else Defs.FACTIONS[b.side].n)
	sel_box.add_child(_label(title, 24, App.GOLD, App.font_display))
	var d := _label(Defs.BUILDINGS[b.type].desc, 15, App.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_box.add_child(d)
	if b.type != "village":
		sel_box.add_child(_label("جان %s از %s" % [Defs.fa(int(b.hp)), Defs.fa(int(b.max_hp))], 15))
	if b.side != Defs.IRAN:
		return
	if b.type != "village" and b.max_level() > 1:
		_fill_upgrade(b)
	match b.type:
		"keep":
			sel_box.add_child(_label("جمعیت %s" % Defs.fa(world.pop_cap(Defs.IRAN)), 16))
		"barracks":
			for t in Defs.TRAIN_MENU:
				var ud: Dictionary = Defs.UNITS[t]
				var err: String = world.can_train(t, b)
				# phones show no tooltips, so a locked soldier says on the button what it is waiting for
				var locked: bool = ud.has("barracks_level") and b.level < ud.barracks_level
				var info: String = ("نیاز به سربازخانه‌ی سطح %s" % Defs.fa(ud.barracks_level)) if locked else Defs.cost_text(ud.cost)
				var btn := _button("%s  ·  %s" % [ud.n, info], "", world.train.bind(t))
				btn.disabled = err != ""
				btn.tooltip_text = err if err != "" else ud.desc
				btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				var pp := _portrait_path(t, Defs.IRAN)
				if pp != "":
					btn.icon = load(pp)
					btn.expand_icon = true
					btn.custom_minimum_size.y = 52
					btn.add_theme_constant_override("icon_max_width", 44)
				sel_box.add_child(btn)
			if b.queue.size() > 0:
				var names: PackedStringArray = []
				for q in b.queue:
					names.append(Defs.UNITS[q].n)
				var ql := _label("در حال آموزش: " + "، ".join(names), 14, App.TURQ)
				ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sel_box.add_child(ql)
		_:
			var bd: Dictionary = Defs.BUILDINGS[b.type]
			if bd.has("res"):
				var amt := int(round(bd.amt * Defs.LEVEL_PROD[clampi(b.level - 1, 0, 2)] * world.land_yield(bd.res)))
				sel_box.add_child(_label("هر %s ثانیه %s %s" % [Defs.fa(int(bd.every)), Defs.fa(amt), Defs.RES_NAMES[bd.res]], 15, App.TURQ))
	if b.type not in ["keep", "village"]:
		sel_box.add_child(_button("تخریب (نیمی از هزینه برمی‌گردد)", "", world.demolish_selected))


## Level and the upgrade button, the same for every building.
func _fill_upgrade(b: Building) -> void:
	sel_box.add_child(_label("سطح %s از %s" % [Defs.fa(b.level), Defs.fa(b.max_level())], 16, App.GOLD))
	if b.level >= b.max_level():
		sel_box.add_child(_label("در بالاترین سطح است.", 15, App.TURQ))
		return
	var cost: Dictionary = world.upgrade_cost(b)
	var what := "سرزمین، جمعیت و جان بیشتر" if b.type == "keep" else Defs.upgrade_text(b.type, b.level + 1)
	var up := _button("ارتقا به سطح %s" % Defs.fa(b.level + 1), "Primary", world.upgrade_selected)
	var err: String = world.can_upgrade(b)
	up.disabled = err != ""
	up.custom_minimum_size = Vector2(250, 84)
	up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sel_box.add_child(up)
	var cl := _label("هزینه: " + Defs.cost_text(cost), 15, App.GOLD)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_box.add_child(cl)
	var l := _label(what if err == "" or err == "منابع کافی نیست." else err, 14, App.TURQ if err == "" else App.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_box.add_child(l)


# ---------------- build mode panel ----------------
func _build_build_panel() -> void:
	build_panel = PanelContainer.new()
	build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_panel.offset_top = -176
	build_panel.offset_bottom = -BAR_H - 10
	build_panel.offset_left = -300
	build_panel.offset_right = 300
	build_panel.add_theme_stylebox_override("panel", App.box(Color(App.LAPIS, 0.92), App.GOLD, 12, 1, 10))
	root.add_child(build_panel)
	blockers.append(build_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	build_panel.add_child(hb)
	build_hint = _label("", 16)
	build_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(build_hint)
	build_ok = _button("ساختن", "Primary", func(): world.confirm_build())
	build_ok.custom_minimum_size = Vector2(110, 46)
	hb.add_child(build_ok)
	hb.add_child(_button("لغو", "", world.cancel_build))
	build_panel.visible = false


func _refresh_build_hint() -> void:
	var t: String = world.build_type
	if t == "":
		return
	var txt := ""
	if t == "wall":
		if world.wall_cells.size() <= 1:
			txt = "سر دیوار را لمس کن، بعد ته آن را." if world.wall_start.x < 0 else "حالا ته دیوار را لمس کن."
		else:
			txt = "%s تکه دیوار · %s" % [Defs.fa(world.wall_cells.size()), Defs.cost_text({"stone": world.wall_cells.size() * Defs.BUILDINGS.wall.cost.stone})]
	elif world.build_cell.x < 0:
		txt = "جای %s را روی زمین لمس کن (درون مرز آبی)." % Defs.BUILDINGS[t].n
	else:
		txt = world.ghost_reason if world.ghost_reason != "" else "%s این‌جا ساخته می‌شود." % Defs.BUILDINGS[t].n
	build_hint.text = txt
	build_hint.add_theme_color_override("font_color", Color("#ff9d8f") if world.ghost_reason != "" and (world.build_cell.x >= 0 or world.wall_cells.size() > 1) else App.IVORY)
	build_ok.disabled = not world.ghost_ok or (t == "wall" and world.wall_cells.size() < 1)


# ---------------- toasts ----------------
func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_top = 64
	toasts.offset_left = -330
	toasts.offset_right = 330
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 4)
	root.add_child(toasts)


func _on_message(text: String, side: int) -> void:
	var p := PanelContainer.new()
	var col: Color = Defs.faction_color[clampi(side, 0, 2)]
	p.add_theme_stylebox_override("panel", App.box(Color(App.LAPIS, 0.9), col.lightened(0.2), 18, 1, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


# ---------------- minimap ----------------
func _build_minimap() -> void:
	# the painted tile frame is drawn over the map; its square hole shows the map
	const MAP := 128.0
	var fsize := Vector2(MAP * 512.0 / 309.0, MAP * 500.0 / 278.0)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	holder.offset_left = 0
	holder.offset_top = 50
	holder.custom_minimum_size = fsize
	holder.size = fsize
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	minimap = preload("res://scripts/ui/minimap.gd").new()
	minimap.world = world
	minimap.position = Vector2(102.0 / 512.0 * fsize.x, 112.0 / 500.0 * fsize.y)
	minimap.size = Vector2(MAP, MAP)
	minimap.custom_minimum_size = Vector2(MAP, MAP)
	minimap.layout_direction = Control.LAYOUT_DIRECTION_LTR
	holder.add_child(minimap)
	blockers.append(minimap)
	var fr := TextureRect.new()
	fr.texture = load("res://assets/ui/minimap_frame.png")
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.stretch_mode = TextureRect.STRETCH_SCALE
	fr.position = Vector2.ZERO
	fr.size = fsize
	fr.layout_direction = Control.LAYOUT_DIRECTION_LTR
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fr)


# ---------------- dialogs ----------------
func _frame(width := 560) -> PanelContainer:
	var f := PanelContainer.new()
	f.theme_type_variation = "Frame"
	f.set_anchors_preset(Control.PRESET_CENTER)
	f.custom_minimum_size = Vector2(width, 0)
	f.grow_horizontal = Control.GROW_DIRECTION_BOTH
	f.grow_vertical = Control.GROW_DIRECTION_BOTH
	f.visible = false
	root.add_child(f)
	return f


func _build_dialogs() -> void:
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.1, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)

	menu_frame = _frame(420)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	menu_frame.add_child(mv)
	var mt := _label("درنگ", 40, App.GOLD, App.font_display)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	mv.add_child(_button("ادامه‌ی نبرد", "Primary", _close_menu))
	mv.add_child(_button("راهنمای بازی", "", _open_help))
	mv.add_child(_button("نبرد تازه", "", _restart))
	mv.add_child(_button("منوی اصلی", "", _to_menu))

	help_frame = _frame(640)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help_frame.add_child(sc)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 8)
	sc.add_child(hv)
	var ht := _label("راهنمای نبرد", 36, App.GOLD, App.font_display)
	ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(ht)
	for para in [
		["هدف", "دژ افراسیاب را در شمال‌خاوری نقشه ویران کن. اگر دژ ایران ویران شود، شکست خورده‌ای."],
		["دوربین", "با یک انگشت نقشه را جابه‌جا کن و با دو انگشت بزرگ و کوچکش کن."],
		["سپاه", "روی سرباز بزن تا برگزیده شود؛ دو بار پشت سر هم بزن تا همه‌ی هم‌نوعانش برگزیده شوند. دکمه‌ی «کادر انتخاب» را بزن و روی نقشه بکش تا گروهی را برگزینی. بعد روی زمین بزن تا بروند یا روی دشمن تا بجنگند."],
		["ساختن", "از نوار پایین ساختمانی برگزین، جایش را درون مرز آبی لمس کن و «ساختن» را بزن. هیزم‌شکن کنار جنگل و معدن کنار صخره‌های خاکستری کار می‌کند."],
		["مردم و غذا", "هر ساختمان کارگاهی و هر سرباز یک نفر از جمعیت را می‌گیرد. خانه جمعیت را بیشتر می‌کند. همه غذا می‌خورند؛ اگر انبار خالی شود کارها کند می‌شود و سرباز نمی‌توانی بگیری."],
		["سرزمین", "روستاهای میانه را با بردن سپاه به کنارشان بگیر. دیوها نگهبان روستاها هستند؛ رستم بر دیوها چیره‌تر است. هر روستا مرز ایران را گسترش می‌دهد و طلا و غذا می‌آورد."],
		["دفاع", "توران هر چند دقیقه با سپاهی بزرگ‌تر حمله می‌کند. دیوار سنگی بکش، دروازه بگذار تا سپاهت بگذرد و برج تیرانداز بساز. دژ هم به دشمنان نزدیک تیر می‌بارد."],
	]:
		hv.add_child(_label(para[0], 22, App.GOLD, App.font_display))
		var l := _label(para[1], 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
		hv.add_child(l)
	hv.add_child(_button("فهمیدم", "Primary", _close_help))

	end_frame = _frame(520)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 12)
	end_frame.add_child(ev)
	end_title = _label("", 46, App.GOLD, App.font_display)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(end_title)
	end_text = _label("", 18, App.MUTED)
	end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(end_text)
	end_next = _button("مرحله‌ی بعد", "Primary", _next_stage)
	ev.add_child(end_next)
	end_retry = _button("دوباره این مرحله", "Primary", _restart)
	ev.add_child(end_retry)
	ev.add_child(_button("منوی اصلی", "", _to_menu))


func _open_menu() -> void:
	get_tree().paused = true
	Engine.max_fps = 30
	dim.visible = true
	menu_frame.visible = true


func _close_menu() -> void:
	get_tree().paused = false
	Engine.max_fps = 60
	dim.visible = false
	menu_frame.visible = false


func _open_help() -> void:
	menu_frame.visible = false
	help_frame.visible = true


func _close_help() -> void:
	help_frame.visible = false
	menu_frame.visible = true


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _next_stage() -> void:
	App.stage = mini(App.stage + 1, Defs.STAGES.size() - 1)
	App.save_progress()
	_restart()


func _on_game_over(win: bool) -> void:
	dim.visible = true
	end_frame.visible = true
	var mins := Defs.fa_time(world.time)
	var last := App.stage >= Defs.STAGES.size() - 1
	end_next.visible = win and not last
	end_retry.visible = not win
	if win:
		App.stage_won(world.time)
		end_title.text = "پیروزی ایران"
		end_text.text = "مرحله‌ی «%s» پس از %s گشوده شد و درفش کاویانی بر باروی توران برافراشته شد." % [world.stage.n, mins]
		if last:
			end_text.text += "\nافراسیاب شکست خورد و ایران برای همیشه آسوده شد. تو همه‌ی مرحله‌ها را گشودی!"
		else:
			end_text.text += "\nمرحله‌ی تازه گشوده شد: %s" % Defs.STAGES[App.stage + 1].n
	else:
		end_title.text = "شکست"
		end_text.text = "سپاه توران پس از %s دژ ایران را گشود. دوباره بکوش." % mins


# ---------------- per-frame ----------------
func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		_refresh()
	overlay.queue_redraw()
	# the little map does not need sixty pictures a second
	_map_t -= delta
	if _map_t <= 0.0:
		_map_t = 0.1
		minimap.queue_redraw()
	_refresh_powers()


func _refresh() -> void:
	var r: Dictionary = world.res[Defs.IRAN]
	for k in res_labels:
		res_labels[k].text = Defs.fa(int(r[k]))
	res_labels["food"].add_theme_color_override("font_color", Color("#ff8a7a") if world.starving(Defs.IRAN) else App.IVORY)
	var used: int = world.pop_used(Defs.IRAN)
	var cap: int = world.pop_cap(Defs.IRAN)
	pop_label.text = "%s/%s" % [Defs.fa(used), Defs.fa(cap)]
	pop_label.add_theme_color_override("font_color", Color("#ffcf7a") if used >= cap else App.IVORY)
	wave_label.text = "حمله‌ی توران: %s" % Defs.fa_time(world.ai.time_to_wave())
	for t in build_buttons:
		var cost: Dictionary = Defs.BUILDINGS[t].cost
		build_buttons[t].modulate = Color.WHITE if world.afford(Defs.IRAN, cost) else Color(1, 1, 1, 0.55)
	if world.mode == "build":
		_refresh_build_hint()
	# keep the panel's numbers live, but only rebuild it when something it shows has changed
	var sig := _selection_signature()
	if sig != _last_sig:
		_last_sig = sig
		_on_selection()


var _last_sig := ""
var _map_t := 0.0


func _selection_signature() -> String:
	var parts: PackedStringArray = [world.mode, world.build_type]
	for u: Unit in world.selected:
		parts.append("%d:%d" % [u.get_instance_id(), int(u.hp / 5.0)])
	var b = world.selected_building
	if b != null and is_instance_valid(b):
		parts.append("b%d:%d:%d:%d:%d" % [b.get_instance_id(), int(b.hp / 20.0), b.level, b.queue.size(), b.side])
		var r: Dictionary = world.res[Defs.IRAN]
		if b.type in ["keep", "barracks"]:
			parts.append("%d,%d,%d,%d,%d" % [r.wood / 5, r.stone / 5, r.food / 5, r.gold / 5, world.pop_used(Defs.IRAN)])
	return "|".join(parts)
