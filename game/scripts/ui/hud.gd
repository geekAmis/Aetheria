class_name HUD
extends CanvasLayer
## Игровой интерфейс Aetheria.

signal tool_selected(id: String)
signal brush_size_changed(r: float)
signal speed_requested(s: float)
signal pause_toggled
signal layer_changed(l: String)
signal jump_to(pos: Vector2, settlement_id: int)
signal save_requested(slot: int)
signal load_requested(slot: int)
signal menu_requested
signal select_settlement(id: int)
signal follow_toggled(id: int)
signal server_settings_changed

var game: GameSession
var world: WorldModel
var sim: SimWorld
var root: Control
var theme_ref: Theme

var top_bar: PanelContainer
var bottom_bar: PanelContainer
var right_panel: PanelContainer
var panel_content: VBoxContainer
var panel_scroll: ScrollContainer
var panel_minimap: MiniMap
var tab_buttons: Dictionary = {}
var panel_tab := "inspector"
var panel_collapsed := false

var date_label: Label
var world_label: Label
var pop_label: Label
var settle_label: Label
var era_label: Label
var essence_label: Label
var speed_buttons: Dictionary = {}
var pause_button: Button
var right_toggle: Button

var category_buttons: Dictionary = {}
var tool_strip: HBoxContainer
var tool_buttons: Dictionary = {}
var tool_title: Label
var tool_desc: Label
var brush_value: Label
var brush_slider: HSlider
var hover_label: Label
var active_category := "inspect"
var active_tool := "inspect"

var toast_box: VBoxContainer
var flash_rect: ColorRect
var era_banner_label: Label
var tutorial_panel: PanelContainer
var tutorial_checks: Dictionary = {}
var world_lost_panel: PanelContainer

var modal_layer: Control
var modal_panel: PanelContainer
var modal_content: VBoxContainer
var modal_title: Label
var modal_open := false
var modal_kind := ""

var inspector_sig := ""
var inspector_kind := ""
var inspector_id := -1
var inspector_cell := Vector2i(-1, -1)
var world_sig := ""
var flash_alpha := 0.0
var flash_life := 0.0
var flash_total := 0.55
var flash_color := Color.WHITE
var tech_era := 0
var codex_tab := "races"
var chronicle_filter := "all"
var chronicle_rows: VBoxContainer
var ui_scale := 1.0
var stats_refresh := 0.0


func setup(p_game: GameSession) -> void:
	game = p_game
	world = game.world
	sim = game.sim
	layer = 10
	theme_ref = ThemeBuilder.build()
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_ref
	add_child(root)
	_apply_saved_ui_scale()
	_build_flash()
	_build_top()
	_build_bottom()
	_build_right()
	_build_toasts()
	_build_tutorial()
	_build_world_lost()
	_build_modal()
	_build_era_banner()
	_set_category("terrain", true)
	_select_tool("inspect")
	_set_tab("inspector")
	stats_refresh = 0.0


# ------------------------------------------------------------------ helpers

func _lbl(text: String, variation: String = "", color: Color = Color.TRANSPARENT, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if color != Color.TRANSPARENT:
		l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l

func _vbox(sep: int = 5) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _hbox(sep: int = 7) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _icon(name: String, tint: Color = Color.WHITE, px: int = 18) -> TextureRect:
	return Icons.icon_rect(name, tint, px)

func _button(text: String, variation: String = "", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b

func _icon_button(icon_name: String, tint: Color = ThemeBuilder.MUTED, px: int = 18, min_size: Vector2 = Vector2(32, 30)) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.icon = Icons.get_icon(icon_name)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", px)
	b.modulate = tint
	return b

func _stat(icon_name: String, value: String, tooltip: String = "") -> HBoxContainer:
	var h := _hbox(5)
	h.add_child(_icon(icon_name, ThemeBuilder.GOLD, 16))
	var l := _lbl(value, "GoldLabel", Color.TRANSPARENT, 14)
	h.add_child(l)
	if tooltip != "":
		h.tooltip_text = tooltip
	h.set_meta("value_label", l)
	return h

func _hairline() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.45, 0.55, 0.55, 0.15)
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _sep_vert() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.5, 0.55, 0.5, 0.18)
	c.custom_minimum_size = Vector2(1, 0)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _bar(row_label: String, value: float, max_v: float, fill: Color, show_value: bool = true) -> HBoxContainer:
	var h := _hbox(6)
	var l := _lbl(row_label, "Small", ThemeBuilder.MUTED, 12)
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = max_v
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("fill", ThemeBuilder.style(fill, Color.TRANSPARENT, 4, 0, 0))
	bar.add_theme_stylebox_override("background", ThemeBuilder.style(Color(0.05, 0.08, 0.09, 0.9), Color(0.25, 0.35, 0.4, 0.35), 4, 1, 0))
	h.add_child(bar)
	if show_value:
		var v := _lbl(str(int(round(value))), "Small", ThemeBuilder.TEXT, 12)
		v.custom_minimum_size = Vector2(42, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(v)
		h.set_meta("value_label", v)
	h.set_meta("bar", bar)
	return h

func _chip(text: String, color: Color = ThemeBuilder.MUTED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.style(Color(color.r, color.g, color.b, 0.12), Color(color.r, color.g, color.b, 0.35), 10, 1, 7))
	var l := _lbl(text, "Small", color, 11)
	p.add_child(l)
	return p

func _info_row(icon_name: String, label: String, value: String, value_color: Color = ThemeBuilder.TEXT) -> HBoxContainer:
	var h := _hbox(6)
	h.add_child(_icon(icon_name, ThemeBuilder.MUTED, 15))
	var l := _lbl(label, "Small", ThemeBuilder.MUTED, 12)
	h.add_child(l)
	h.add_child(_spacer())
	var v := _lbl(value, "", value_color, 13)
	h.add_child(v)
	h.set_meta("value_label", v)
	return h


# ------------------------------------------------------------------ top bar

func _build_top() -> void:
	top_bar = PanelContainer.new()
	top_bar.theme_type_variation = "PanelGlass"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 58
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(top_bar)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	top_bar.add_child(m)
	var h := _hbox(12)
	m.add_child(h)

	# логотип
	var logo_box := _vbox(0)
	var logo := _lbl("AETHERIA", "H2", ThemeBuilder.GOLD_BRIGHT, 17)
	logo.add_theme_font_override("font", load("res://assets/fonts/CormorantGaramond.ttf"))
	logo.add_theme_constant_override("outline_size", 0)
	logo_box.add_child(logo)
	world_label = _lbl(world.world_name, "Small", ThemeBuilder.MUTED, 10)
	logo_box.add_child(world_label)
	h.add_child(logo_box)
	h.add_child(_sep_vert())

	var date_box := _vbox(0)
	date_label = _lbl("Год 1 · Весна", "", ThemeBuilder.TEXT, 14)
	date_box.add_child(date_label)
	var sub := _lbl("", "Small", ThemeBuilder.MUTED, 10)
	sub.name = "Sub"
	date_box.add_child(sub)
	h.add_child(date_box)
	h.add_child(_sep_vert())

	var pop := _stat("people", "0", L.t("population"))
	pop_label = pop.get_meta("value_label")
	h.add_child(pop)
	var st := _stat("map", "0", L.t("settlements"))
	settle_label = st.get_meta("value_label")
	h.add_child(st)
	var er := _stat("era", "—", L.t("era"))
	era_label = er.get_meta("value_label")
	h.add_child(er)

	h.add_child(_spacer())

	var ess := _hbox(5)
	var ess_icon := _icon("essence", ThemeBuilder.GOLD_BRIGHT, 22)
	ess.add_child(ess_icon)
	var ess_box := _vbox(0)
	var ess_cap := _lbl(L.t("essence"), "Small", ThemeBuilder.MUTED, 9)
	ess_box.add_child(ess_cap)
	essence_label = _lbl("600", "GoldLabel", ThemeBuilder.GOLD_BRIGHT, 16)
	ess_box.add_child(essence_label)
	ess.add_child(ess_box)
	h.add_child(ess)
	h.add_child(_sep_vert())

	# скорости
	var speeds := _hbox(2)
	pause_button = _button("", "SpeedButton", Vector2(34, 30))
	pause_button.icon = Icons.get_icon("pause")
	pause_button.expand_icon = true
	pause_button.add_theme_constant_override("icon_max_width", 16)
	pause_button.tooltip_text = L.t("pause") + " (Space)"
	pause_button.pressed.connect(func(): pause_toggled.emit())
	speeds.add_child(pause_button)
	for s in GameSession.SPEEDS:
		var b := _button("%d×" % int(s), "SpeedButton", Vector2(38, 30))
		b.toggle_mode = true
		b.tooltip_text = L.t("speed") + " %d×" % int(s)
		var sv: float = s
		b.pressed.connect(func(): speed_requested.emit(sv))
		speeds.add_child(b)
		speed_buttons[s] = b
	h.add_child(speeds)
	h.add_child(_sep_vert())
	var menu_b := _icon_button("settings", ThemeBuilder.TEXT, 20, Vector2(38, 32))
	menu_b.tooltip_text = L.t("settings") + " (Esc)"
	menu_b.pressed.connect(open_pause)
	h.add_child(menu_b)


# ------------------------------------------------------------------ bottom bar

func _build_bottom() -> void:
	bottom_bar = PanelContainer.new()
	bottom_bar.theme_type_variation = "PanelGlass"
	bottom_bar.anchor_left = 0.5
	bottom_bar.anchor_right = 0.5
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.offset_left = -620
	bottom_bar.offset_right = 620
	bottom_bar.offset_top = -186
	bottom_bar.offset_bottom = -8
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bottom_bar)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 7)
	m.add_theme_constant_override("margin_bottom", 6)
	bottom_bar.add_child(m)
	var v := _vbox(5)
	m.add_child(v)

	var cats := _hbox(2)
	# осмотр
	var inspect_b := _category_button("inspect", "inspect", L.t("inspector"))
	cats.add_child(inspect_b)
	for cat in ["terrain", "water", "life", "disaster", "civ", "bless"]:
		cats.add_child(_category_button(cat, _cat_icon(cat), L.t(cat)))
	cats.add_child(_spacer())
	var brush_box := _hbox(5)
	brush_box.add_child(_icon("brush", ThemeBuilder.MUTED, 16))
	brush_box.add_child(_lbl(L.t("brush_size"), "Small", ThemeBuilder.MUTED, 11))
	brush_slider = HSlider.new()
	brush_slider.min_value = 1
	brush_slider.max_value = 32
	brush_slider.step = 1
	brush_slider.value = 5
	brush_slider.custom_minimum_size = Vector2(110, 20)
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.value_changed.connect(func(val):
		brush_value.text = str(int(val))
		brush_size_changed.emit(float(val))
	)
	brush_box.add_child(brush_slider)
	brush_value = _lbl("5", "GoldLabel", ThemeBuilder.GOLD, 12)
	brush_value.custom_minimum_size = Vector2(20, 0)
	brush_box.add_child(brush_value)
	cats.add_child(brush_box)
	v.add_child(cats)
	v.add_child(_hairline())

	tool_strip = _hbox(4)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 78)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(tool_strip)
	v.add_child(scroll)
	v.add_child(_hairline())

	var footer := _hbox(10)
	tool_title = _lbl("", "GoldLabel", ThemeBuilder.GOLD_BRIGHT, 14)
	tool_title.custom_minimum_size = Vector2(130, 0)
	footer.add_child(tool_title)
	tool_desc = _lbl("", "Small", ThemeBuilder.MUTED, 11)
	tool_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(tool_desc)
	hover_label = _lbl("", "Small", ThemeBuilder.MUTED, 10)
	hover_label.custom_minimum_size = Vector2(300, 0)
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(hover_label)
	v.add_child(footer)
	_set_category("inspect", true)


func _cat_icon(cat: String) -> String:
	return {"terrain": "mountain", "water": "water", "life": "leaf", "disaster": "lightning", "civ": "crown", "bless": "heart"}.get(cat, "dot")


func _category_button(cat: String, icon_name: String, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "CategoryButton"
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(104, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = text
	var h := _hbox(5)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(_icon(icon_name, ThemeBuilder.MUTED, 17))
	var l := _lbl(text, "", ThemeBuilder.MUTED, 12)
	h.add_child(l)
	b.add_child(h)
	b.pressed.connect(func(): _set_category(cat, false))
	category_buttons[cat] = b
	return b


func _set_category(cat: String, initial: bool = false) -> void:
	active_category = cat
	for k in category_buttons:
		var b: Button = category_buttons[k]
		b.button_pressed = (k == cat)
		for c in b.get_children():
			if c is HBoxContainer:
				for ch in c.get_children():
					if ch is Label:
						ch.add_theme_color_override("font_color", ThemeBuilder.GOLD_BRIGHT if k == cat else ThemeBuilder.MUTED)
					elif ch is TextureRect:
						ch.modulate = ThemeBuilder.GOLD if k == cat else ThemeBuilder.MUTED
	for c in tool_strip.get_children():
		c.queue_free()
	tool_buttons.clear()
	# «Осмотр» доступен из любой категории
	var inspect_p := {
		"id": "inspect", "name": L.t("inspector"), "name_en": "Inspector",
		"desc": L.t("select_hint"), "desc_en": "Click a creature, settlement or building to inspect it.",
		"cost": 0, "icon": "eye", "cat": "inspect"
	}
	tool_strip.add_child(_make_tool_button(inspect_p))
	if cat == "inspect":
		if initial:
			_select_tool("inspect")
		return
	var list: Array = D.powers_by_cat.get(cat, [])
	for p in list:
		tool_strip.add_child(_make_tool_button(p))
	if initial and list.size() > 0:
		_select_tool(str(list[0].id))


func _make_tool_button(p: Dictionary) -> Button:
	var id := str(p.get("id", "dot"))
	var b := Button.new()
	b.theme_type_variation = "ToolButton"
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(84, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = L.tc(p) + "\n" + L.dc(p) + "\n" + L.t("cost") + ": " + L.num(float(p.get("cost", 0)))
	var v := _vbox(1)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 4
	v.offset_right = -4
	v.offset_top = 5
	v.offset_bottom = -4
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := _icon(str(p.get("icon", "dot")), ThemeBuilder.TEXT, 25)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var nm := _lbl(L.tc(p), "", ThemeBuilder.TEXT, 10)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	nm.custom_minimum_size = Vector2(76, 0)
	v.add_child(nm)
	var cost := _lbl(("∞" if game.sandbox else L.num(float(p.get("cost", 0)))), "", ThemeBuilder.GOLD, 9)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cost)
	b.add_child(v)
	b.pressed.connect(func(): _select_tool(id))
	tool_buttons[id] = b
	return b


func _select_tool(id: String) -> void:
	active_tool = id
	for k in tool_buttons:
		var b: Button = tool_buttons[k]
		b.button_pressed = (k == id)
		for c in b.get_children():
			if c is VBoxContainer:
				for ch in c.get_children():
					if ch is Label and ch.get_index() == 1:
						ch.add_theme_color_override("font_color", ThemeBuilder.GOLD_BRIGHT if k == id else ThemeBuilder.TEXT)
					elif ch is TextureRect:
						ch.modulate = ThemeBuilder.GOLD_BRIGHT if k == id else ThemeBuilder.TEXT
	var p := D.power(id)
	if id == "inspect":
		tool_title.text = L.t("inspector")
		tool_desc.text = L.t("select_hint")
	else:
		tool_title.text = L.tc(p)
		tool_desc.text = L.dc(p) + "   ·   " + L.t("cost") + ": " + ("∞" if game.sandbox else L.num(float(p.get("cost", 0))))
	tool_selected.emit(id)


func set_active_tool(id: String) -> void:
	active_tool = id
	for k in tool_buttons:
		tool_buttons[k].button_pressed = (k == id)


func set_brush(r: float) -> void:
	brush_slider.value = r
	brush_value.text = str(int(r))


# ------------------------------------------------------------------ right panel

func _build_right() -> void:
	right_panel = PanelContainer.new()
	right_panel.theme_type_variation = "PanelGlass"
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -358
	right_panel.offset_right = -12
	right_panel.offset_top = 70
	right_panel.offset_bottom = -204
	right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(right_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	right_panel.add_child(m)
	var v := _vbox(6)
	m.add_child(v)

	var tabs := _hbox(3)
	for t in ["inspector", "chronicle", "world"]:
		var b := Button.new()
		b.theme_type_variation = "Chip"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var h := _hbox(4)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(_icon({"inspector": "inspect", "chronicle": "chronicle", "world": "world"}[t], ThemeBuilder.MUTED, 15))
		h.add_child(_lbl(L.t(t), "", ThemeBuilder.MUTED, 12))
		b.add_child(h)
		var tt: String = t
		b.pressed.connect(func(): _set_tab(tt))
		tabs.add_child(b)
		tab_buttons[t] = b
	v.add_child(tabs)
	v.add_child(_hairline())
	panel_scroll = ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(panel_scroll)
	panel_content = _vbox(8)
	panel_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_scroll.add_child(panel_content)
	v.add_child(_hairline())
	var foot := _hbox(4)
	var techb := _button(L.t("tech_tree"), "GhostButton")
	techb.add_theme_font_size_override("font_size", 12)
	techb.pressed.connect(open_tech)
	foot.add_child(techb)
	var codexb := _button(L.t("codex"), "GhostButton")
	codexb.add_theme_font_size_override("font_size", 12)
	codexb.pressed.connect(open_codex)
	foot.add_child(codexb)
	foot.add_child(_spacer())
	var helpb := _icon_button("info", ThemeBuilder.MUTED, 15, Vector2(28, 26))
	helpb.tooltip_text = L.t("controls") + " (F1)"
	helpb.pressed.connect(open_help)
	foot.add_child(helpb)
	v.add_child(foot)


func _set_tab(t: String) -> void:
	panel_tab = t
	for k in tab_buttons:
		var b: Button = tab_buttons[k]
		b.button_pressed = (k == t)
		for c in b.get_children():
			if c is HBoxContainer:
				for ch in c.get_children():
					if ch is Label:
						ch.add_theme_color_override("font_color", ThemeBuilder.GOLD_BRIGHT if k == t else ThemeBuilder.MUTED)
					elif ch is TextureRect:
						ch.modulate = ThemeBuilder.GOLD if k == t else ThemeBuilder.MUTED
	if t == "inspector":
		inspector_sig = ""
		refresh_inspector()
	elif t == "chronicle":
		_build_chronicle()
	else:
		_build_world_tab()
	SFX.ui_click()


func _clear_content() -> void:
	for c in panel_content.get_children():
		c.queue_free()
	panel_minimap = null
	inspector_sig = ""


func refresh_inspector() -> void:
	if panel_tab != "inspector" or game == null:
		return
	var sig := ""
	var kind := ""
	var id := -1
	var a: AgentData = game.get_selected_agent()
	var s: SettlementData = game.get_selected_settlement()
	if a != null and a.alive:
		kind = "agent"
		id = a.id
		sig = "a%d|%d|%d|%d|%d|%d|%d|%s|%d|%d" % [a.id, a.level, int(a.age), int(a.health / maxf(1.0, a.max_health) * 20), int(a.satiety / 10), int(a.thirst / 10), int(a.mood / 10), a.role, int(a.pregnant / 20), a.partner_id]
	elif s != null:
		kind = "settlement"
		id = s.id
		var cons: float = float(s.construction.get("progress", 0.0) if not s.construction.is_empty() else 0.0)
		sig = "s%d|%d|%s|%d|%d|%d|%d|%d|%d|%s|%d" % [s.id, s.population, s.stage, s.era, s.wars.size(), int(float(s.resources.get("food", 0)) / 25.0), s.buildings.size(), int(float(s.resources.get("wood", 0)) / 25.0), int(cons / 3.0), str(s.plague > 0) + str(s.drought > 0) + str(s.blizzard > 0), s.leader_id]
	else:
		kind = "cell"
		sig = "c%d_%d_%d" % [inspector_cell.x, inspector_cell.y, world.biome_id_at(inspector_cell.x, inspector_cell.y)]
	if sig == inspector_sig and kind == inspector_kind and id == inspector_id:
		return
	inspector_sig = sig
	inspector_kind = kind
	inspector_id = id
	_clear_content()
	if kind == "agent" and a != null:
		_build_agent_card(a)
	elif kind == "settlement" and s != null:
		_build_settlement_card(s)
	else:
		_build_cell_card(inspector_cell)


func inspect_agent(a: AgentData) -> void:
	inspector_sig = ""
	inspector_cell = Vector2i(-1, -1)
	panel_tab = "inspector"
	_set_tab("inspector")


func inspect_settlement(s: SettlementData) -> void:
	inspector_sig = ""
	inspector_cell = Vector2i(-1, -1)
	panel_tab = "inspector"
	_set_tab("inspector")


func inspect_cell(cell: Vector2i) -> void:
	inspector_cell = cell
	inspector_sig = ""
	panel_tab = "inspector"
	_set_tab("inspector")


func _build_agent_card(a: AgentData) -> void:
	var race := D.race(a.race_id)
	var head := _hbox(9)
	var color_bar := ColorRect.new()
	color_bar.color = race.get("color_c", ThemeBuilder.GOLD)
	color_bar.custom_minimum_size = Vector2(5, 54)
	head.add_child(color_bar)
	var names := _vbox(0)
	names.add_child(_lbl(a.display_name(), "H2", ThemeBuilder.TEXT, 21))
	names.add_child(_lbl("%s · %s · %d %s" % [L.tc(race), L.t("male" if a.gender == 0 else "female"), int(a.age), L.t("year_short")], "Small", ThemeBuilder.MUTED, 11))
	head.add_child(names)
	panel_content.add_child(head)
	var chips := _hbox(4)
	chips.add_child(_chip(L.t("role_" + a.role), race.get("color_c", ThemeBuilder.GOLD)))
	chips.add_child(_chip(L.t("level") + " " + str(a.level), ThemeBuilder.GOLD))
	var s: SettlementData = sim.settlement_by_id.get(a.settlement_id, null)
	if s != null:
		chips.add_child(_chip(s.name, s.color))
	panel_content.add_child(chips)
	panel_content.add_child(_hairline())

	var hp := _bar("HP", a.health, a.max_health, Color("#c85048"))
	hp.set_meta("bar", hp.get_meta("bar"))
	panel_content.add_child(hp)
	panel_content.add_child(_bar(L.t("food"), a.satiety, 100.0, Color("#d8a24a")))
	panel_content.add_child(_bar(L.t("thirst"), a.thirst, 100.0, Color("#4aa8d8")))
	panel_content.add_child(_bar(L.t("energy"), a.energy, 100.0, Color("#8a7ad8")))
	panel_content.add_child(_bar(L.t("sanity"), a.sanity, 100.0, Color("#66c8a8")))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for pair in [
		["power", L.t("power"), a.power], ["wisdom", L.t("wisdom"), a.wisdom],
		["agility", L.t("agility"), a.agility], ["magic", L.t("magic"), a.magic],
		["charisma", L.t("charisma"), a.charisma], ["kills", "Убийств", a.kills]
	]:
		var row := _hbox(4)
		row.add_child(_lbl(str(pair[1]), "Small", ThemeBuilder.MUTED, 11))
		row.add_child(_spacer())
		row.add_child(_lbl(str(int(pair[2])), "", ThemeBuilder.TEXT, 12))
		grid.add_child(row)
	panel_content.add_child(grid)
	panel_content.add_child(_hairline())

	var skill_names := {"melee": "Ближний бой", "craft": "Ремесло", "farming": "Земледелие", "science": "Наука", "leadership": "Лидерство", "trade": "Торговля", "medicine": "Медицина", "survival": "Выживание"}
	for k in ["melee", "craft", "science", "survival"]:
		var sv := int(a.skills.get(k, 0))
		var row := _hbox(4)
		row.add_child(_lbl(skill_names[k], "Small", ThemeBuilder.MUTED, 11))
		row.add_child(_spacer())
		row.add_child(_lbl(str(sv), "", ThemeBuilder.TEXT, 12))
		panel_content.add_child(row)
	if not a.perks.is_empty():
		var ph := _hbox(3)
		for pk in a.perks:
			ph.add_child(_chip(_perk_name(str(pk)), ThemeBuilder.TEAL))
		panel_content.add_child(ph)
	# семья
	var fam := ""
	if a.partner_id > 0:
		var p: AgentData = sim.agent_by_id.get(a.partner_id, null)
		if p != null:
			fam = L.t("family") + ": " + p.display_name()
	if not a.children.is_empty():
		fam += ("   " if fam != "" else "") + "Дети: " + str(a.children.size())
	if fam != "":
		panel_content.add_child(_lbl(fam, "Small", ThemeBuilder.MUTED, 11))
	panel_content.add_child(_hairline())
	var actions := _hbox(4)
	var center_b := _button("В центр", "GhostButton")
	center_b.add_theme_font_size_override("font_size", 12)
	center_b.pressed.connect(func(): jump_to.emit(a.pos, -1))
	actions.add_child(center_b)
	var follow_b := _button(L.t("follow"), "GhostButton")
	follow_b.add_theme_font_size_override("font_size", 12)
	follow_b.pressed.connect(func(): follow_toggled.emit(a.id))
	actions.add_child(follow_b)
	panel_content.add_child(actions)


func _perk_name(p: String) -> String:
	return {"tough": "Крепыш", "industrious": "Трудяга", "genius": "Мудрец", "charmer": "Обаятельный", "swift": "Быстрый", "lucky": "Удачливый", "brave": "Смельчак", "curious": "Любопытный", "frugal": "Бережливый", "pious": "Благочестивый"}.get(p, p)


func _build_settlement_card(s: SettlementData) -> void:
	var race := D.race(s.race_id)
	var head := _hbox(9)
	var cb := ColorRect.new()
	cb.color = s.color
	cb.custom_minimum_size = Vector2(5, 60)
	head.add_child(cb)
	var names := _vbox(0)
	names.add_child(_lbl(s.name, "H2", ThemeBuilder.TEXT, 22))
	names.add_child(_lbl("%s · %s · %s %s" % [L.tc(race), L.stage_name(s.stage), L.num(s.population), L.t("pop")], "Small", ThemeBuilder.MUTED, 11))
	head.add_child(names)
	panel_content.add_child(head)
	var chips := _hbox(3)
	chips.add_child(_chip(L.tc(D.era(s.era)), ThemeBuilder.GOLD))
	if not s.wars.is_empty():
		chips.add_child(_chip(L.t("war"), ThemeBuilder.RED))
	elif not s.allies.is_empty():
		chips.add_child(_chip(L.t("alliance"), ThemeBuilder.TEAL))
	if s.plague > 0: chips.add_child(_chip("Эпидемия", ThemeBuilder.GREEN))
	if s.drought > 0: chips.add_child(_chip("Засуха", Color("#c8a04a")))
	if s.blizzard > 0: chips.add_child(_chip("Метель", Color("#8ac8e0")))
	if s.blessed > 0: chips.add_child(_chip("Благословение", ThemeBuilder.GOLD))
	if s.cursed > 0: chips.add_child(_chip("Проклятие", Color("#a06ad8")))
	panel_content.add_child(chips)
	# лидер
	var leader: AgentData = sim.agent_by_id.get(s.leader_id, null)
	if leader != null:
		panel_content.add_child(_info_row("leader", L.t("leader"), leader.display_name(), ThemeBuilder.GOLD_BRIGHT))
	panel_content.add_child(_hairline())
	# ресурсы
	var res := GridContainer.new()
	res.columns = 2
	res.add_theme_constant_override("h_separation", 14)
	for pair in [["food", "wheat", L.t("food_res")], ["wood", "log", L.t("wood")], ["stone", "rock", L.t("stone")], ["iron", "iron", L.t("iron")], ["gold", "coin", L.t("gold")], ["goods", "crate", L.t("goods")]]:
		var row := _hbox(4)
		row.add_child(_icon(str(pair[1]), ThemeBuilder.MUTED, 14))
		row.add_child(_lbl(str(pair[2]), "Small", ThemeBuilder.MUTED, 11))
		row.add_child(_spacer())
		row.add_child(_lbl(L.num(float(s.resources.get(pair[0], 0))), "", ThemeBuilder.TEXT, 12))
		res.add_child(row)
	panel_content.add_child(res)
	panel_content.add_child(_hairline())
	# эпоха
	panel_content.add_child(_lbl(L.t("era_progress") + " · " + L.t("techs_known") + ": " + str(s.techs.size()), "Small", ThemeBuilder.MUTED, 11))
	var era_bar := ProgressBar.new()
	era_bar.max_value = 6
	era_bar.value = s.era_techs_done
	era_bar.show_percentage = false
	era_bar.custom_minimum_size = Vector2(0, 10)
	era_bar.add_theme_stylebox_override("fill", ThemeBuilder.style(ThemeBuilder.GOLD, Color.TRANSPARENT, 4, 0, 0))
	era_bar.add_theme_stylebox_override("background", ThemeBuilder.style(Color(0.05, 0.08, 0.09, 0.9), Color(0.25, 0.35, 0.4, 0.35), 4, 1, 0))
	panel_content.add_child(era_bar)
	if not s.researching.is_empty():
		var t := D.tech(s.researching)
		panel_content.add_child(_lbl(L.t("research") + ": " + L.tc(t) + "  " + str(int(100.0 * s.research_progress / maxf(1.0, s.research_cost()))) + "%", "Small", ThemeBuilder.TEAL, 11))
	if not s.construction.is_empty():
		var c := s.construction
		panel_content.add_child(_lbl(L.t("build_queue") + ": " + L.tc(D.building(str(c.get("type", "hut")))) + "  " + str(int(100.0 * float(c.get("progress", 0)) / maxf(1.0, float(c.get("days", 8))))) + "%", "Small", ThemeBuilder.MUTED, 11))
	panel_content.add_child(_hairline())
	# здания
	var counts := {}
	for b in s.buildings:
		counts[b.type] = counts.get(b.type, 0) + 1
	var bstr := ""
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		bstr += "%s ×%d   " % [L.tc(D.building(str(k))), counts[k]]
	var bl := _lbl(bstr, "Small", ThemeBuilder.MUTED, 10)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_content.add_child(bl)
	# отношения
	if not s.relations.is_empty():
		panel_content.add_child(_lbl(L.t("relations"), "Small", ThemeBuilder.TEAL, 11))
		var shown := 0
		for oid in s.relations:
			var o: SettlementData = sim.settlement_by_id.get(int(oid), null)
			if o == null or o.destroyed:
				continue
			var rel := float(s.relations[oid])
			var status := L.t("war") if s.wars.has(int(oid)) else (L.t("alliance") if s.allies.has(int(oid)) else ("%+d" % int(rel)))
			var row := _hbox(4)
			row.add_child(_lbl(o.name, "Small", ThemeBuilder.TEXT, 11))
			row.add_child(_spacer())
			row.add_child(_lbl(status, "Small", ThemeBuilder.RED if s.wars.has(int(oid)) else (ThemeBuilder.TEAL if s.allies.has(int(oid)) else ThemeBuilder.MUTED), 11))
			panel_content.add_child(row)
			shown += 1
			if shown >= 5:
				break
	panel_content.add_child(_hairline())
	var actions := _hbox(3)
	actions.add_child(_small_action("Древо", func(): open_tech()))
	actions.add_child(_small_action("Дары", func(): game._apply_tool("gift", s.center, true)))
	actions.add_child(_small_action("Чудо", func(): game._apply_tool("miracle", s.center, true)))
	actions.add_child(_small_action("Озарение", func(): game._apply_tool("tech_boon", s.center, true)))
	panel_content.add_child(actions)


func _small_action(text: String, cb: Callable) -> Button:
	var b := _button(text, "GhostButton")
	b.add_theme_font_size_override("font_size", 10)
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _build_cell_card(cell: Vector2i) -> void:
	if not world.in_bounds(cell.x, cell.y):
		panel_content.add_child(_lbl(L.t("no_selection"), "H2"))
		panel_content.add_child(_lbl(L.t("select_hint"), "Muted"))
		return
	var i := world.idx(cell.x, cell.y)
	var b := world.biome_at(cell.x, cell.y)
	panel_content.add_child(_lbl(L.tc(b), "H2", b.get("color_c", ThemeBuilder.TEXT)))
	panel_content.add_child(_lbl(L.dc(b), "Small", ThemeBuilder.MUTED, 11))
	var temp_c := -20.0 + world.temperature[i] * 55.0 - maxf(0.0, world.heights[i] - world.sea_level) * 25.0
	var rows := [
		["Высота", "%d м" % int((world.heights[i] - world.sea_level) * 90.0)],
		["Температура", "%d °C" % int(temp_c)],
		["Влажность", "%d%%" % int(world.moisture[i] * 100)],
		["Растительность", "%d%%" % int(world.vegetation[i] * 100)],
	]
	if world.res_type[i] > 0:
		rows.append(["Ресурс", world.resource_name(world.res_type[i]) + " · " + str(int(world.res_amount[i]))])
	if world.radiation[i] > 0.01:
		rows.append(["Радиация", "%d%%" % int(world.radiation[i] * 100)])
	var s := game._settlement_at(cell)
	if s != null:
		rows.append(["Поселение", s.name])
	for r in rows:
		panel_content.add_child(_info_row("dot", str(r[0]), str(r[1])))
	var btn := _button("Фокус камеры", "GhostButton")
	btn.pressed.connect(func(): jump_to.emit(Vector2(cell), -1))
	panel_content.add_child(btn)


# ------------------------------------------------------------------ chronicle

func _build_chronicle() -> void:
	_clear_content()
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 3)
	chips.add_theme_constant_override("v_separation", 3)
	for f in [["all", L.t("all")], ["war", L.t("wars")], ["disaster", L.t("disasters")], ["founded", L.t("founded")], ["tech", L.t("technology")], ["miracle", L.t("miracles")]]:
		var b := _button(str(f[1]), "Chip")
		b.toggle_mode = true
		b.button_pressed = chronicle_filter == f[0]
		b.add_theme_font_size_override("font_size", 10)
		var ff := str(f[0])
		b.pressed.connect(func():
			chronicle_filter = ff
			_build_chronicle()
		)
		chips.add_child(b)
	panel_content.add_child(chips)
	panel_content.add_child(_lbl(L.t("chronicle_hint"), "Small", ThemeBuilder.MUTED, 10))
	chronicle_rows = _vbox(3)
	panel_content.add_child(chronicle_rows)
	var evs: Array = sim.chronicle.events.duplicate()
	evs.reverse()
	var shown := 0
	for e in evs:
		if not _event_matches(e):
			continue
		chronicle_rows.add_child(_event_row(e))
		shown += 1
		if shown >= 120:
			break
	if shown == 0:
		chronicle_rows.add_child(_lbl(L.t("no_events"), "Muted"))


func _event_matches(e: Dictionary) -> bool:
	if chronicle_filter == "all":
		return true
	var t := str(e.get("type", ""))
	if chronicle_filter == "war":
		return t in ["war", "ruin", "nuke"]
	if chronicle_filter == "disaster":
		return t in ["disaster", "plague", "nuke"]
	if chronicle_filter == "founded":
		return t in ["founded", "leader", "era"]
	if chronicle_filter == "tech":
		return t in ["tech", "era"]
	if chronicle_filter == "miracle":
		return t in ["miracle", "prophet", "bless", "curse", "festival"]
	return true


func _event_row(e: Dictionary) -> Control:
	var b := Button.new()
	b.theme_type_variation = "GhostButton"
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = str(e.get("text", ""))
	b.clip_contents = true
	var h := _hbox(6)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	h.offset_right = -8
	h.offset_top = 2
	h.offset_bottom = -2
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon(str(e.get("icon", "dot")), _event_color(str(e.get("type", ""))), 14)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := _vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(240, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 11)
	rt.add_theme_color_override("default_color", ThemeBuilder.TEXT)
	rt.text = "[color=#%s]Год %s[/color]  %s" % [_event_color(str(e.get("type", ""))).to_html(false), str(e.get("year", 1)), str(e.get("text", ""))]
	v.add_child(rt)
	h.add_child(v)
	b.add_child(h)
	var sid := int(e.get("settlement_id", -1))
	var pos: Array = e.get("pos", [-1, -1])
	b.pressed.connect(func(): jump_to.emit(Vector2(float(pos[0]), float(pos[1])), sid))
	return b


func _event_color(t: String) -> Color:
	match t:
		"war", "ruin", "nuke": return ThemeBuilder.RED
		"disaster", "plague": return Color("#d8a24a")
		"founded", "people": return ThemeBuilder.GOLD
		"tech", "era": return ThemeBuilder.TEAL
		"miracle", "bless", "prophet", "festival": return Color("#e8d07a")
		"curse": return Color("#a06ad8")
		"death": return Color("#9a9a9a")
		_:
			return ThemeBuilder.MUTED


func add_event(e: Dictionary) -> void:
	if panel_tab == "chronicle" and _event_matches(e):
		_build_chronicle()


# ------------------------------------------------------------------ world tab

func _build_world_tab() -> void:
	_clear_content()
	panel_minimap = MiniMap.new()
	panel_minimap.setup(self)
	panel_minimap.custom_minimum_size = Vector2(304, 304)
	panel_content.add_child(panel_minimap)
	var layers := HFlowContainer.new()
	layers.add_theme_constant_override("h_separation", 2)
	layers.add_theme_constant_override("v_separation", 2)
	for l in [["normal", "Обычный"], ["biome", "Биомы"], ["height", "Высоты"], ["temp", "Темп."], ["moisture", "Влага"], ["resource", "Ресурсы"], ["radiation", "Радиация"]]:
		var b := _button(str(l[1]), "Chip")
		b.add_theme_font_size_override("font_size", 9)
		var ll := str(l[0])
		b.pressed.connect(func(): layer_changed.emit(ll))
		layers.add_child(b)
	panel_content.add_child(layers)
	panel_content.add_child(_hairline())
	var counts := world.biome_counts()
	var land := 0
	var ocean := 0
	var forest := 0
	var desert := 0
	var mountains := 0
	for k in counts:
		var c := int(counts[k])
		if k in ["ocean", "shallow", "reef"]:
			ocean += c
		else:
			land += c
		if k in ["forest", "taiga", "tropical"]:
			forest += c
		if k == "desert":
			desert += c
		if k in ["mountains", "snow", "volcano"]:
			mountains += c
	var total := maxi(1, world.n())
	panel_content.add_child(_info_row("map", L.t("land"), "%d%%" % int(100.0 * land / total)))
	panel_content.add_child(_info_row("forest", L.t("forest_word"), "%d%%" % int(100.0 * forest / total)))
	panel_content.add_child(_info_row("ocean", L.t("ocean_word"), "%d%%" % int(100.0 * ocean / total)))
	panel_content.add_child(_info_row("mountain", L.t("mountain_word"), "%d%%" % int(100.0 * mountains / total)))
	panel_content.add_child(_info_row("sand", L.t("desert_word"), "%d%%" % int(100.0 * desert / total)))
	panel_content.add_child(_info_row("people", L.t("animals_count"), L.num(sim.animals.size())))
	panel_content.add_child(_info_row("tree", L.t("trees_count"), L.num(game.nature_view.tree_count())))
	panel_content.add_child(_hairline())
	panel_content.add_child(_lbl(L.t("top_settlements"), "Small", ThemeBuilder.TEAL, 11))
	var sorted: Array = []
	for s in sim.settlements:
		if not s.destroyed:
			sorted.append(s)
	sorted.sort_custom(func(a, b): return a.population > b.population)
	var shown := 0
	for s in sorted:
		var btn := _button("%s  ·  %s  ·  %s" % [s.name, L.stage_name(s.stage), L.num(s.population)], "GhostButton")
		btn.add_theme_font_size_override("font_size", 11)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sid: int = s.id
		btn.pressed.connect(func(): select_settlement.emit(sid))
		panel_content.add_child(btn)
		shown += 1
		if shown >= 8:
			break
	world_sig = "%d_%d_%d" % [sim.year, sim.total_population, sim.settlements.size()]


func stats_changed() -> void:
	if panel_tab == "world":
		var sig := "%d_%d_%d_%d" % [sim.year, sim.total_population, sim.settlements.size(), sim.animals.size()]
		if sig != world_sig:
			stats_refresh += 0.22
			if stats_refresh > 1.2:
				stats_refresh = 0.0
				world_sig = sig
				_build_world_tab()


# ------------------------------------------------------------------ top updates

func update_top(date: String, season: String, pop: int, settlements: int, era: int, ess: float, sandbox_now: bool, spd: float, paused_now: bool) -> void:
	date_label.text = "%s · %s" % [date, season]
	pop_label.text = L.num(pop)
	settle_label.text = str(settlements)
	era_label.text = L.tc(D.era(era))
	if sandbox_now:
		essence_label.text = "∞"
	else:
		essence_label.text = L.num(ess)
	essence_label.add_theme_color_override("font_color", ThemeBuilder.GOLD_BRIGHT if sandbox_now or ess > 100 else ThemeBuilder.RED)
	for k in speed_buttons:
		speed_buttons[k].button_pressed = (not paused_now and absf(float(k) - spd) < 0.01)
	pause_button.icon = Icons.get_icon("play" if paused_now else "pause")


func update_essence(ess: float, sandbox_now: bool) -> void:
	essence_label.text = "∞" if sandbox_now else L.num(ess)
	for p in tool_buttons:
		var b: Button = tool_buttons[p]
		for c in b.get_children():
			if c is VBoxContainer:
				for ch in c.get_children():
					if ch is Label and ch.get_index() == 2:
						ch.text = "∞" if sandbox_now else L.num(float(D.power(str(p)).get("cost", 0)))


func update_hover(cell: Vector2i, w: WorldModel) -> void:
	if cell.x < 0 or not w.in_bounds(cell.x, cell.y):
		hover_label.text = L.t("zoom_hint")
		return
	var b := w.biome_at(cell.x, cell.y)
	var extra := ""
	if w.res_type[w.idx(cell.x, cell.y)] > 0:
		extra = " · " + w.resource_name(w.res_type[w.idx(cell.x, cell.y)])
	hover_label.text = "%s · %d м%s" % [L.tc(b), int((w.heights[w.idx(cell.x, cell.y)] - w.sea_level) * 90.0), extra]


func set_speed(s: float) -> void:
	for k in speed_buttons:
		speed_buttons[k].button_pressed = absf(float(k) - s) < 0.01


func set_paused(p: bool) -> void:
	pause_button.icon = Icons.get_icon("play" if p else "pause")


# ------------------------------------------------------------------ toasts / flash

func _build_toasts() -> void:
	toast_box = _vbox(5)
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -300
	toast_box.offset_right = 300
	toast_box.offset_top = 68
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func toast(text: String, kind: String = "info") -> void:
	if toast_box == null:
		return
	var col := ThemeBuilder.GOLD
	var icon := "info"
	match kind:
		"war", "nuke", "error": col = ThemeBuilder.RED; icon = "war" if kind == "war" else ("nuke" if kind == "nuke" else "close")
		"tech", "era": col = ThemeBuilder.TEAL; icon = "tech"
		"city", "save", "load": col = ThemeBuilder.GOLD; icon = "people" if kind == "city" else "save"
		"plague": col = ThemeBuilder.GREEN; icon = "plague"
		"prophet", "miracle": col = ThemeBuilder.GOLD_BRIGHT; icon = "miracle"
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeBuilder.style(Color(0.03, 0.05, 0.065, 0.93), Color(col.r, col.g, col.b, 0.5), 8, 1, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := _hbox(7)
	h.add_child(_icon(icon, col, 17))
	var l := _lbl(text, "", ThemeBuilder.TEXT, 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(500, 0)
	h.add_child(l)
	p.add_child(h)
	toast_box.add_child(p)
	if kind in ["era", "nuke"]:
		SFX.play("bong", -16.0, 1.0)
	else:
		SFX.ui_click()
	while toast_box.get_child_count() > 5:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var t := create_tween()
	t.tween_interval(3.6)
	t.tween_property(p, "modulate:a", 0.0, 0.5)
	t.tween_callback(p.queue_free)


func _build_flash() -> void:
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.z_index = 40
	root.add_child(flash_rect)


func flash(color: Color, alpha: float) -> void:
	flash_color = color
	flash_alpha = alpha
	flash_life = 0.55
	flash_total = 0.55
	flash_rect.color = Color(color.r, color.g, color.b, alpha)


func _process(delta: float) -> void:
	if flash_life > 0.0:
		flash_life = maxf(0.0, flash_life - delta)
		flash_rect.color = Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha * (flash_life / flash_total))


func _build_era_banner() -> void:
	era_banner_label = _lbl("", "", ThemeBuilder.GOLD_BRIGHT, 42)
	era_banner_label.add_theme_font_override("font", load("res://assets/fonts/CormorantGaramond.ttf"))
	era_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	era_banner_label.set_anchors_preset(Control.PRESET_CENTER)
	era_banner_label.offset_left = -400
	era_banner_label.offset_right = 400
	era_banner_label.offset_top = -210
	era_banner_label.offset_bottom = -80
	era_banner_label.modulate.a = 0.0
	era_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	era_banner_label.z_index = 30
	root.add_child(era_banner_label)


func era_banner(text: String) -> void:
	era_banner_label.text = text
	era_banner_label.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(era_banner_label, "modulate:a", 1.0, 0.7)
	t.chain().tween_interval(2.0)
	t.chain().tween_property(era_banner_label, "modulate:a", 0.0, 1.0)


# ------------------------------------------------------------------ tutorial

func _build_tutorial() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.theme_type_variation = "PanelWarm"
	tutorial_panel.anchor_left = 0.0
	tutorial_panel.anchor_top = 1.0
	tutorial_panel.anchor_bottom = 1.0
	tutorial_panel.offset_left = 16
	tutorial_panel.offset_right = 386
	tutorial_panel.offset_top = -420
	tutorial_panel.offset_bottom = -204
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(tutorial_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	tutorial_panel.add_child(m)
	var v := _vbox(5)
	m.add_child(v)
	var h := _hbox(5)
	h.add_child(_icon("star", ThemeBuilder.GOLD_BRIGHT, 18))
	h.add_child(_lbl(L.t("tutorial"), "H2", ThemeBuilder.GOLD_BRIGHT, 15))
	h.add_child(_spacer())
	var skip := _button(L.t("tutorial_skip"), "GhostButton")
	skip.add_theme_font_size_override("font_size", 10)
	skip.pressed.connect(func():
		game.tutorial_done = true
		game._save_tutorial_done()
		tutorial_panel.visible = false
	)
	h.add_child(skip)
	v.add_child(h)
	for i in range(1, 5):
		var key: String = ["select", "mountain", "lightning", "speed"][i - 1]
		var row := _hbox(6)
		var ic := _icon("dot", ThemeBuilder.MUTED, 12)
		row.add_child(ic)
		var l := _lbl(L.t("tutorial_%d" % i), "", ThemeBuilder.TEXT, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
		tutorial_checks[key] = [ic, l]
	tutorial_panel.visible = false


func show_tutorial() -> void:
	if tutorial_panel != null:
		tutorial_panel.visible = true
		update_tutorial(game.tutorial_flags, false)


func update_tutorial(flags: Dictionary, done: bool) -> void:
	if tutorial_panel == null:
		return
	for k in tutorial_checks:
		var pair: Array = tutorial_checks[k]
		var ic: TextureRect = pair[0]
		var l: Label = pair[1]
		var ok := bool(flags.get(k, false))
		ic.texture = Icons.get_icon("star" if ok else "dot")
		ic.modulate = ThemeBuilder.GOLD_BRIGHT if ok else ThemeBuilder.MUTED
		l.add_theme_color_override("font_color", ThemeBuilder.MUTED if ok else ThemeBuilder.TEXT)
	if done:
		tutorial_panel.visible = false


func tutorial_complete() -> void:
	if tutorial_panel != null:
		tutorial_panel.visible = false
	toast(L.t("tutorial_done"), "tech")


# ------------------------------------------------------------------ world lost

func _build_world_lost() -> void:
	world_lost_panel = PanelContainer.new()
	world_lost_panel.theme_type_variation = "PanelWarm"
	world_lost_panel.set_anchors_preset(Control.PRESET_CENTER)
	world_lost_panel.offset_left = -260
	world_lost_panel.offset_right = 260
	world_lost_panel.offset_top = -120
	world_lost_panel.offset_bottom = 120
	world_lost_panel.visible = false
	world_lost_panel.z_index = 20
	root.add_child(world_lost_panel)
	var v := _vbox(8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 18)
	m.add_child(v)
	world_lost_panel.add_child(m)
	v.add_child(_lbl(L.t("world_lost"), "H1", ThemeBuilder.GOLD_BRIGHT, 30))
	v.add_child(_lbl(L.t("world_lost_text"), "", ThemeBuilder.MUTED, 13))
	var b := _button(L.t("new_world_btn"), "GoldButton")
	b.pressed.connect(func(): menu_requested.emit())
	v.add_child(b)


func show_world_lost() -> void:
	world_lost_panel.visible = true


# ------------------------------------------------------------------ modal

func _build_modal() -> void:
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.visible = false
	modal_layer.z_index = 50
	root.add_child(modal_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dim)
	modal_panel = PanelContainer.new()
	modal_panel.theme_type_variation = "PanelGlass"
	modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	modal_panel.offset_left = -460
	modal_panel.offset_right = 460
	modal_panel.offset_top = -330
	modal_panel.offset_bottom = 330
	modal_layer.add_child(modal_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	modal_panel.add_child(m)
	var v := _vbox(8)
	m.add_child(v)
	var h := _hbox(8)
	modal_title = _lbl("", "H1", ThemeBuilder.GOLD_BRIGHT, 30)
	h.add_child(modal_title)
	h.add_child(_spacer())
	var close := _icon_button("close", ThemeBuilder.TEXT, 18, Vector2(34, 32))
	close.pressed.connect(close_modal)
	h.add_child(close)
	v.add_child(h)
	v.add_child(_hairline())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	modal_content = _vbox(8)
	modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(modal_content)


func _open_modal(title: String, kind: String) -> void:
	modal_title.text = title
	modal_kind = kind
	modal_open = true
	modal_layer.visible = true
	for c in modal_content.get_children():
		c.queue_free()
	SFX.ui_click()


func close_modal() -> void:
	modal_open = false
	modal_kind = ""
	modal_layer.visible = false
	SFX.ui_back()


func is_modal_open() -> bool:
	return modal_open


func is_typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func open_pause() -> void:
	_open_modal(L.t("pause"), "pause")
	var summary := _lbl("%s · %s · %s %s" % [world.world_name, sim.date_text(), L.num(sim.total_population), L.t("pop")], "Muted", ThemeBuilder.MUTED, 12)
	modal_content.add_child(summary)
	modal_content.add_child(_hairline())
	var defs := [
		[L.t("resume"), "GoldButton", func(): close_modal()],
		[L.t("save_game"), "", open_save],
		[L.t("load_game"), "", open_load],
		[L.t("settings"), "", open_settings],
		[L.t("tech_tree"), "", open_tech],
		[L.t("codex"), "", open_codex],
		[L.t("controls"), "", open_help],
		[L.t("main_menu"), "DangerButton", func(): close_modal(); menu_requested.emit()],
		[L.t("quit"), "GhostButton", func(): get_tree().quit()],
	]
	for d in defs:
		var b := _button(str(d[0]), str(d[1]))
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(d[2])
		modal_content.add_child(b)


func open_save() -> void:
	_open_modal(L.t("save_slots"), "save")
	var slots := Save.list_slots()
	for info in slots:
		if int(info.slot) == 0:
			continue
		var panel := PanelContainer.new()
		panel.theme_type_variation = "PanelCard"
		var h := _hbox(10)
		panel.add_child(h)
		var v := _vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(info.get("exists", false)):
			v.add_child(_lbl("%s %d · %s" % [L.t("slot"), int(info.slot), str(info.get("name", ""))], "H2", ThemeBuilder.TEXT, 15))
			v.add_child(_lbl("Год %s · %s %s · %s" % [str(info.get("year", 0)), L.num(float(info.get("pop", 0))), L.t("pop"), str(info.get("saved_at_text", ""))], "Small", ThemeBuilder.MUTED, 10))
		else:
			v.add_child(_lbl("%s %d · %s" % [L.t("slot"), int(info.slot), L.t("empty_slot")], "H2", ThemeBuilder.MUTED, 15))
		h.add_child(v)
		var saveb := _button(L.t("save"), "GoldButton")
		var slot := int(info.slot)
		saveb.pressed.connect(func(): save_requested.emit(slot); close_modal())
		h.add_child(saveb)
		modal_content.add_child(panel)
	modal_content.add_child(_lbl(L.t("overwrite_slot"), "Small", ThemeBuilder.MUTED, 10))


func open_load() -> void:
	_open_modal(L.t("load_game"), "load")
	var slots := Save.list_slots()
	var any := false
	for info in slots:
		if not bool(info.get("exists", false)):
			continue
		any = true
		var panel := PanelContainer.new()
		panel.theme_type_variation = "PanelCard"
		var h := _hbox(10)
		panel.add_child(h)
		var v := _vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_lbl("%s %d · %s" % [L.t("slot"), int(info.slot), str(info.get("name", ""))], "H2", ThemeBuilder.TEXT, 15))
		v.add_child(_lbl("Год %s · %s %s · %s" % [str(info.get("year", 0)), L.num(float(info.get("pop", 0))), L.t("pop"), str(info.get("saved_at_text", ""))], "Small", ThemeBuilder.MUTED, 10))
		h.add_child(v)
		var loadb := _button(L.t("load_game"), "GoldButton")
		var slot := int(info.slot)
		loadb.pressed.connect(func(): load_requested.emit(slot); close_modal())
		h.add_child(loadb)
		var delb := _button(L.t("delete"), "DangerButton")
		delb.pressed.connect(func(): Save.delete_slot(slot); open_load())
		h.add_child(delb)
		modal_content.add_child(panel)
	if not any:
		modal_content.add_child(_lbl(L.t("no_saves"), "Muted"))
	modal_content.add_child(_lbl(L.t("toast_no_save"), "Small", ThemeBuilder.MUTED, 10))


func open_settings() -> void:
	_open_modal(L.t("settings"), "settings")
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	# язык
	var lh := _hbox(8)
	lh.add_child(_lbl(L.t("language"), "", ThemeBuilder.TEXT, 13))
	lh.add_child(_spacer())
	var lang := OptionButton.new()
	lang.add_item("Русский", 0)
	lang.add_item("English", 1)
	lang.selected = 0 if L.lang != "en" else 1
	lang.custom_minimum_size = Vector2(160, 30)
	lang.item_selected.connect(func(idx):
		L.set_lang("en" if idx == 1 else "ru")
		game.reload_hud()
	)
	lh.add_child(lang)
	modal_content.add_child(lh)
	# масштаб
	var scale_row := _hbox(8)
	scale_row.add_child(_lbl(L.t("ui_scale"), "", ThemeBuilder.TEXT, 13))
	scale_row.add_child(_spacer())
	var scale_val := _lbl("%d%%" % int(ui_scale * 100), "GoldLabel", ThemeBuilder.GOLD, 12)
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.8
	scale_slider.max_value = 1.3
	scale_slider.step = 0.05
	scale_slider.value = ui_scale
	scale_slider.custom_minimum_size = Vector2(220, 20)
	scale_slider.value_changed.connect(func(v):
		scale_val.text = "%d%%" % int(v * 100)
		ui_scale = v
		_apply_ui_scale_now()
	)
	scale_row.add_child(scale_slider)
	scale_row.add_child(scale_val)
	modal_content.add_child(scale_row)
	# громкость
	for s in [["master", L.t("audio"), SFX.master_volume], ["music", L.t("music_volume"), SFX.music_volume], ["sfx", L.t("sfx_volume"), SFX.sfx_volume]]:
		var row := _hbox(8)
		row.add_child(_lbl(str(s[1]), "", ThemeBuilder.TEXT, 13))
		row.add_child(_spacer())
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(s[2])
		slider.custom_minimum_size = Vector2(260, 20)
		var key := str(s[0])
		slider.value_changed.connect(func(v):
			if key == "master": SFX.master_volume = v
			elif key == "music": SFX.music_volume = v
			else: SFX.sfx_volume = v
			SFX.apply_volumes(SFX.master_volume, SFX.music_volume, SFX.sfx_volume)
		)
		row.add_child(slider)
		modal_content.add_child(row)
	# чекбоксы
	var fs := CheckButton.new()
	fs.text = L.t("fullscreen")
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	modal_content.add_child(fs)
	var shadows := CheckButton.new()
	shadows.text = L.t("shadows")
	shadows.button_pressed = game.sky.sun.shadow_enabled
	shadows.toggled.connect(func(on): game.sky.sun.shadow_enabled = on)
	modal_content.add_child(shadows)
	var particles := CheckButton.new()
	particles.text = L.t("particles")
	particles.button_pressed = game.fx.visible
	particles.toggled.connect(func(on): game.fx.visible = on)
	modal_content.add_child(particles)
	modal_content.add_child(_hairline())
	var about := _lbl(L.t("credits"), "Small", ThemeBuilder.MUTED, 10)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_content.add_child(about)
	var close := _button(L.t("close"), "GoldButton")
	close.pressed.connect(close_modal)
	modal_content.add_child(close)


func open_tech(era_override: int = -1) -> void:
	_open_modal(L.t("tech_tree"), "tech")
	var s: SettlementData = game.get_selected_settlement()
	if s == null:
		for ss in sim.settlements:
			if not ss.destroyed:
				s = ss
				break
	if s == null:
		modal_content.add_child(_lbl(L.t("relations_none"), "Muted"))
		return
	tech_era = era_override if era_override >= 0 else s.era
	var head := _hbox(6)
	head.add_child(_lbl(s.name + " · " + L.tc(D.era(tech_era)), "H2", ThemeBuilder.TEXT, 18))
	head.add_child(_spacer())
	var give := _button(L.t("grant"), "GoldButton")
	give.add_theme_font_size_override("font_size", 11)
	var sid := s.id
	give.pressed.connect(func(): game._apply_tool("tech_boon", s.center, true); open_tech(tech_era))
	head.add_child(give)
	modal_content.add_child(head)
	var eras := HFlowContainer.new()
	eras.add_theme_constant_override("h_separation", 2)
	eras.add_theme_constant_override("v_separation", 2)
	for ei in D.eras.size():
		var e: Dictionary = D.eras[ei]
		var b := _button(str(e.name), "Chip")
		b.add_theme_font_size_override("font_size", 9)
		b.button_pressed = ei == tech_era
		b.toggle_mode = true
		var eidx := ei
		b.pressed.connect(func(): open_tech(eidx))
		eras.add_child(b)
	modal_content.add_child(eras)
	var prog := ProgressBar.new()
	prog.max_value = 6
	prog.value = s.era_techs_done
	prog.show_percentage = false
	prog.custom_minimum_size = Vector2(0, 10)
	prog.add_theme_stylebox_override("fill", ThemeBuilder.style(ThemeBuilder.GOLD, Color.TRANSPARENT, 4, 0, 0))
	prog.add_theme_stylebox_override("background", ThemeBuilder.style(Color(0.05, 0.08, 0.09, 0.9), Color(0.25, 0.35, 0.4, 0.35), 4, 1, 0))
	modal_content.add_child(prog)
	if not s.researching.is_empty():
		var t := D.tech(s.researching)
		modal_content.add_child(_lbl(L.t("research") + ": " + L.tc(t) + " — " + str(int(100.0 * s.research_progress / maxf(1.0, s.research_cost()))) + "%", "Small", ThemeBuilder.TEAL, 11))
	var list: Array = D.era_techs.get(tech_era, [])
	for t in list:
		var known := s.techs.has(t.id)
		var p := PanelContainer.new()
		p.theme_type_variation = "PanelCard"
		var h := _hbox(8)
		p.add_child(h)
		var ic := _icon("tech", ThemeBuilder.TEAL if known else ThemeBuilder.MUTED, 18)
		h.add_child(ic)
		var v := _vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := _lbl(L.tc(t), "H2", ThemeBuilder.GOLD_BRIGHT if known else ThemeBuilder.TEXT, 14)
		v.add_child(nm)
		var d := _lbl(L.dc(t), "Small", ThemeBuilder.MUTED, 10)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		h.add_child(v)
		h.add_child(_lbl(L.num(float(t.cost)), "Small", ThemeBuilder.GOLD, 11))
		if known:
			h.add_child(_chip("Открыто", ThemeBuilder.TEAL))
		elif t.id == s.researching:
			h.add_child(_chip("В работе", ThemeBuilder.GOLD))
		else:
			var gb := _button("Дать", "GhostButton")
			gb.add_theme_font_size_override("font_size", 10)
			gb.pressed.connect(func(): game.grant_specific_tech(sid, str(t.id)))
			h.add_child(gb)
		modal_content.add_child(p)


func open_tech_keep(sid: int) -> void:
	game.select_settlement(sid)
	open_tech()

func open_codex() -> void:
	_open_modal(L.t("screen_codex"), "codex")
	var tabs := _hbox(3)
	for t in [["races", L.t("codex_races"), "people"], ["animals", L.t("codex_animals"), "paw"], ["biomes", L.t("codex_biomes"), "world"], ["tech", L.t("codex_tech"), "tech"]]:
		var b := _button(str(t[1]), "Chip")
		b.toggle_mode = true
		b.button_pressed = codex_tab == t[0]
		b.add_theme_font_size_override("font_size", 11)
		var key := str(t[0])
		b.pressed.connect(func(): codex_tab = key; open_codex_keep())
		tabs.add_child(b)
	modal_content.add_child(tabs)
	var list: Array = []
	if codex_tab == "races":
		list = D.races
	elif codex_tab == "animals":
		list = D.animals
	elif codex_tab == "biomes":
		list = D.biomes
	else:
		list = D.techs
	for item in list:
		var p := PanelContainer.new()
		p.theme_type_variation = "PanelCard"
		var h := _hbox(8)
		p.add_child(h)
		var cb := ColorRect.new()
		cb.color = item.get("color_c", item.get("color", ThemeBuilder.GOLD))
		if item.get("color_c") == null:
			cb.color = ThemeBuilder.GOLD
		cb.custom_minimum_size = Vector2(4, 0)
		h.add_child(cb)
		var v := _vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_lbl(L.tc(item), "H2", ThemeBuilder.TEXT, 15))
		var d := _lbl(L.dc(item), "Small", ThemeBuilder.MUTED, 10)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		var extra := ""
		if codex_tab == "races":
			extra = "HP %d · сила %d · мудрость %d · жизнь %d лет" % [int(item.hp), int(item.power), int(item.wisdom), int(item.lifespan)]
		elif codex_tab == "animals":
			extra = "HP %d · сила %d · %s" % [int(item.hp), int(item.power), "хищник" if bool(item.predator) else ("домашнее" if bool(item.domestic) else "дикое")]
		elif codex_tab == "tech":
			extra = "%s · %s" % [L.tc(D.era(int(item.era))), L.num(float(item.cost))]
		if extra != "":
			v.add_child(_lbl(extra, "Small", ThemeBuilder.GOLD, 10))
		h.add_child(v)
		modal_content.add_child(p)


func open_codex_keep() -> void:
	open_codex()


func open_help() -> void:
	_open_modal(L.t("controls"), "help")
	modal_content.add_child(_lbl(L.t("zoom_hint"), "", ThemeBuilder.TEXT, 13))
	for line in [
		"WASD / стрелки — панорама; ПКМ-перетаскивание — панорама",
		"Q / E или СКМ — вращение; колесо — зум",
		"ЛКМ — применить силу; Пробел — пауза; 1–5 — скорость",
		"Tab — правая панель; H — скрыть интерфейс; F1 — помощь",
		"Ctrl+Z / Ctrl+Y — отмена / повтор изменения рельефа",
		"F12 — скриншот; F11 — полный экран",
		"Клик по существу/поселению в режиме «Осмотр» открывает инспектор",
		"Молния в лесу вызывает пожар; дождь тушит его",
		"Атомная бомба оставляет радиацию и ядерную зиму после 3 ударов",
		"Поселения сами строят, торгуют, воюют и открывают технологии",
	]:
		var h := _hbox(6)
		h.add_child(_icon("dot", ThemeBuilder.GOLD, 8))
		var l := _lbl(line, "", ThemeBuilder.MUTED, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		modal_content.add_child(h)
	modal_content.add_child(_hairline())
	var about := _lbl(L.t("credits"), "Small", ThemeBuilder.MUTED, 10)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_content.add_child(about)
	var close := _button(L.t("close"), "GoldButton")
	close.pressed.connect(close_modal)
	modal_content.add_child(close)


# ------------------------------------------------------------------ misc

func toggle_visible() -> void:
	root.visible = not root.visible


func toggle_panel() -> void:
	panel_collapsed = not panel_collapsed
	right_panel.visible = not panel_collapsed


func _apply_saved_ui_scale() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		ui_scale = float(cfg.get_value("ui", "scale", 1.0))
	_apply_ui_scale_now()


func _apply_ui_scale_now() -> void:
	get_window().content_scale_factor = clampf(ui_scale, 0.8, 1.3)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("ui", "scale", ui_scale)
	cfg.save("user://settings.cfg")


func apply_ui_scale() -> void:
	_apply_saved_ui_scale()


func update_minimap() -> void:
	if panel_minimap != null:
		panel_minimap.queue_redraw()
