extends Node
## Aetheria — главное меню, загрузка мира и переключение сессий.

var menu_layer: CanvasLayer
var menu_root: Control
var menu_modal: Control
var menu_modal_panel: PanelContainer
var menu_modal_content: VBoxContainer
var menu_modal_title: Label
var menu_modal_open := false
var loading_layer: CanvasLayer
var loading_root: Control
var loading_phase: Label
var loading_bar: ProgressBar
var loading_tip: Label
var game: GameSession
var shot_path := ""
var shot_delay := 5.0
var shot_timer := -1.0
var auto_start := false
var auto_seed := 424242
var auto_size := 256
var shot_hour := -1.0
var shot_dist := 0.0
var shot_weather := ""
var shot_hide_ui := false
var shot_pause := false
var shot_layer := ""
var shot_hide_nature := false
var shot_hide_water := false
var sim_years := -1
var load_slot := -1
var shot_modal := ""
var shot_action := ""
var bench_seconds := 0.0
var bench_print := 0.0
var profile_frames := 0
var profile_times: Array = []
var profile_cell := Vector2i.ZERO
var profile_brush := true
var profile_warmup := 0
var profile_slow: Array = []
var menu_config: Dictionary = {}
var selected_preset := "continent"
var size_choice := 256
var diff_choice := "normal"
var tribes_choice := 6
var sandbox_choice := true
var genesis_choice := false
var codex_tab := "races"
var new_seed_text := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_window()
	_parse_args()
	_build_menu()
	_build_loading()
	_build_music()
	if load_slot >= 0:
		await get_tree().process_frame
		await _load_slot(load_slot)
		if shot_modal != "" and game != null:
			_open_game_modal()
		if shot_path != "":
			shot_timer = shot_delay
	elif auto_start:
		await get_tree().process_frame
		await _start_new({"seed": auto_seed, "size": auto_size, "preset": "continent", "difficulty": "normal", "tribes": 6, "sandbox": true, "genesis": genesis_choice})
		if shot_hour >= 0.0:
			game.visual_hour = shot_hour
			game.sky.apply(game.visual_hour, game.sim.season, game.sim.weather_mode, game.sim.nuclear_winter)
			print("[debug] visual hour=", game.visual_hour, " sun=", game.sky.sun.light_energy, " moon=", game.sky.moon.light_energy, " amb=", game.sky.env.ambient_light_energy)
		if shot_weather != "":
			game.sim.weather_mode = shot_weather
			game.sim.weather_days_left = 999
			game.sky.weather_mode = shot_weather
		if shot_dist > 0.0:
			game.camera_rig.distance = shot_dist
			game.camera_rig.smooth_distance = shot_dist
		if shot_pause:
			game.toggle_pause()
		if shot_hide_ui:
			game.hud.toggle_visible()
		if shot_layer != "":
			game.terrain_view.set_layer(shot_layer)
		if sim_years > 0:
			game.sim.bulk_mode = true
			for i in int(sim_years) * 365:
				game.sim.step_day()
			game.sim.bulk_mode = false
			game._update_hud()
			game._finish_start()
			game.settlement_view.timer = 0.0
			for ss in game.sim.settlements:
				print("[sim] %s: pop=%d era=%d stage=%s build=%d techs=%d wars=%s food=%.0f" % [ss.name, ss.population, ss.era, ss.stage, ss.buildings.size(), ss.techs.size(), str(ss.wars), float(ss.resources.get("food",0))])
		if shot_hide_nature:
			game.nature_view.visible = false
		if shot_hide_water:
			for w in game.terrain_view.water_chunks.values():
				w.visible = false
		if shot_modal != "":
			_open_game_modal()
		if shot_action != "":
			_do_action(shot_action)
		if profile_frames > 0:
			var sel = game.get_selected_settlement()
			profile_cell = sel.center if sel != null else Vector2i(game.world.size / 2, game.world.size / 2)
			print("[profile-start] frames=", profile_frames, " cell=", profile_cell)
		if bench_seconds > 0.0:
			game.set_speed(20.0)
		if shot_path != "":
			shot_timer = shot_delay
	elif shot_path != "":
		shot_timer = 2.0
	if shot_modal != "" and game == null and not auto_start and load_slot < 0:
		if shot_modal == "new":
			open_new_world()
		elif shot_modal == "codex":
			open_codex()
		elif shot_modal == "settings":
			open_settings()
		elif shot_modal == "load":
			open_load()
		if shot_path != "":
			shot_timer = maxf(shot_timer, 3.0)


func _open_game_modal() -> void:
	if shot_modal == "pause":
		game.hud.open_pause()
	elif shot_modal == "settings":
		game.hud.open_settings()
	elif shot_modal == "codex":
		game.hud.open_codex()
	elif shot_modal == "tech":
		game.hud.open_tech()
	elif shot_modal == "save":
		game.hud.open_save()
	elif shot_modal == "load":
		game.hud.open_load()
	elif shot_modal == "help":
		game.hud.open_help()
	elif shot_modal == "chronicle":
		game.hud._set_tab("chronicle")
	elif shot_modal == "world":
		game.hud._set_tab("world")


func _do_action(action: String) -> void:
	if game == null:
		return
	var s: SettlementData = null
	for ss in game.sim.settlements:
		if not ss.destroyed:
			s = ss
			break
	if s == null:
		return
	game.camera_rig.focus_settlement(s.center)
	match action:
		"nuke":
			game.sim.nuke(s.center.x, s.center.y, 11.0)
		"meteor":
			game.sim.meteor(s.center.x + 6, s.center.y + 4, 6.0)
		"tornado":
			game.fx.play("tornado", Vector2(s.center), 5.0, {})
		"lightning":
			game.sim.lightning(s.center.x, s.center.y)
		"fire":
			game.sim.ignite_at(s.center.x, s.center.y, 5)
		"rain":
			game.sim.rain(s.center.x, s.center.y, 10.0)
		"bless":
			game.sim.bless_area(s.center.x, s.center.y, 8.0, "health")
		"earthquake":
			game.sim.earthquake(s.center.x, s.center.y, 16.0)
		"tribe":
			game.sim.spawn_tribe(s.center.x + 20, s.center.y + 10)
		"inspect_first":
			for aa in game.sim.agents:
				if aa.alive:
					game.selected_agent_id = aa.id
					game.selected_settlement_id = -1
					game.sim.selected_settlement_id = -1
					game.creature_view.set_selected(aa.id)
					game.hud.inspect_agent(aa)
					break
		"inspect_settlement":
			game.select_settlement(s.id)
		"world_tab":
			game.hud._set_tab("world")
		"monster":
			game.sim._spawn_monster("dragon", Vector2i(clampi(s.center.x + 7, 1, game.world.size - 2), s.center.y))
			game.sim._add_world_event("monster", "Дракон пробудился", 4, "monster")
		"legend":
			var best_a: AgentData = null
			for aa2 in game.sim.agents:
				if aa2.alive and (best_a == null or aa2.legend_score() < best_a.legend_score()):
					best_a = aa2
			if best_a != null:
				best_a.legend += 120.0
				best_a.add_title("Легенда " + best_a.dynasty)
				best_a.notable = true
		"save":
			game.save_to_slot(2, false)
		"banner":
			game.hud.era_banner("Железный век\nКровавая Степь")
		"peace":
			for w in s.wars.duplicate():
				var o: SettlementData = game.sim.settlement_by_id.get(w, null)
				if o != null:
					game.sim.make_peace(s, o, false)


func _process(delta: float) -> void:
	if profile_frames > 0 and game != null:
		if profile_warmup > 0:
			profile_warmup -= 1
			return
		profile_times.append(delta)
		if delta > 0.033:
			var views := {
				"terrain": game.terrain_view.last_frame_us,
				"nature": game.nature_view.last_frame_us,
				"creature": game.creature_view.last_sync_us,
				"hud": game.last_hud_us,
				"settle_rebuild": game.settlement_view.last_rebuild_us,
				"roads": game.settlement_view.last_roads_us
			}
			profile_slow.append([profile_frames, snappedf(delta * 1000.0, 0.1), str(game.sim.last_parts), str(views)])
		if profile_frames % 6 == 0 and profile_brush:
			game.world.raise_area(profile_cell.x, profile_cell.y, 16, 0.01, "add")
		profile_frames -= 1
		if profile_frames == 0:
			var sorted := profile_times.duplicate()
			sorted.sort()
			var n := sorted.size()
			var p50: float = sorted[int(n * 0.50)]
			var p95: float = sorted[int(n * 0.95)]
			var mx: float = sorted[n - 1]
			print("[profile] frames=%d p50=%.1fms p95=%.1fms max=%.1fms fps_avg=%.1f" % [n, p50 * 1000.0, p95 * 1000.0, mx * 1000.0, 1.0 / maxf(0.0001, _avg(profile_times))])
			var ok := p95 <= 0.020 and mx <= 0.033
			print("[profile] %s p95<=20ms max<=33ms" % ["PASS" if ok else "FAIL"])
			if not profile_slow.is_empty():
				print("[profile] slow frames=", str(profile_slow))
	if bench_seconds > 0.0:
		if game != null and game.speed < 20.0:
			game.set_speed(20.0)
		bench_seconds -= delta
		bench_print -= delta
		if bench_print <= 0.0:
			bench_print = 2.0
			if game != null:
				var acts := {}
				var emos := {}
				for a in game.sim.agents:
					acts[a.action] = int(acts.get(a.action, 0)) + 1
					emos[a.emotion] = int(emos.get(a.emotion, 0)) + 1
				var steep := 0
				var roads := 0
				var vassals := 0
				for sv in game.sim.settlements:
					var s2: SettlementData = sv
					if s2.destroyed:
						continue
					if s2.overlord_id >= 0:
						vassals += 1
					for oid in s2.roads:
						if float(s2.roads[oid].get("progress", 0.0)) >= 1.0:
							roads += 1
					var h0: float = game.world.heights[game.world.idx(s2.center.x, s2.center.y)]
					var relief := 0.0
					for dz in range(-3, 4):
						for dx in range(-3, 4):
							var hh: float = game.world.heights[game.world.idx(clampi(s2.center.x + dx, 0, game.world.size - 1), clampi(s2.center.y + dz, 0, game.world.size - 1))]
							relief = maxf(relief, absf(hh - h0))
					if relief > 0.052:
						steep += 1
				var rels := {}
				for sv2 in game.sim.settlements:
					if not sv2.destroyed:
						rels[sv2.religion] = int(rels.get(sv2.religion, 0)) + 1
				print("[bench] fps=%d day=%d pop=%d agents=%d nodes=%d steep=%d roads=%d vassals=%d exp=%d monsters=%d legends=%d religions=%s actions=%s emotions=%s parts=%s" % [int(Engine.get_frames_per_second()), int(game.sim.day), game.sim.total_population, game.sim.agents.size(), get_tree().get_node_count(), steep, roads, vassals, game.sim.expeditions.size(), game.sim.monsters.size(), game.sim.top_legends(3).size(), str(rels), str(acts), str(emos), str(game.sim.last_parts)])
		if bench_seconds <= 0.0:
			get_tree().quit()
	if shot_timer > 0.0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			_take_shot()


func _setup_window() -> void:
	get_window().title = "AETHERIA — живой мир"
	get_window().min_size = Vector2i(1200, 720)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var screen := DisplayServer.screen_get_size()
	var pos := (screen - Vector2i(1600, 900)) / 2
	DisplayServer.window_set_position(pos)


func _parse_args() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--shot":
				if i + 1 < args.size():
					shot_path = args[i + 1]
					i += 1
			"--shot-delay":
				if i + 1 < args.size():
					shot_delay = float(args[i + 1])
					i += 1
			"--autostart":
				auto_start = true
			"--genesis":
				genesis_choice = true
			"--seed":
				if i + 1 < args.size():
					auto_seed = int(args[i + 1])
					i += 1
			"--size":
				if i + 1 < args.size():
					auto_size = int(args[i + 1])
					i += 1
			"--hour":
				if i + 1 < args.size():
					shot_hour = float(args[i + 1])
					i += 1
			"--dist":
				if i + 1 < args.size():
					shot_dist = float(args[i + 1])
					i += 1
			"--weather":
				if i + 1 < args.size():
					shot_weather = args[i + 1]
					i += 1
			"--hideui":
				shot_hide_ui = true
			"--pause":
				shot_pause = true
			"--layer":
				if i + 1 < args.size():
					shot_layer = args[i + 1]
					i += 1
			"--hidenature":
				shot_hide_nature = true
			"--shot-action":
				if i + 1 < args.size():
					shot_action = args[i + 1]
					i += 1
			"--hidewater":
				shot_hide_water = true
			"--sim-years":
				if i + 1 < args.size():
					sim_years = int(args[i + 1])
					i += 1
			"--load-slot":
				if i + 1 < args.size():
					load_slot = int(args[i + 1])
					i += 1
			"--modal":
				if i + 1 < args.size():
					shot_modal = args[i + 1]
					i += 1
			"--action":
				if i + 1 < args.size():
					shot_action = args[i + 1]
					i += 1
			"--bench":
				if i + 1 < args.size():
					bench_seconds = float(args[i + 1])
					i += 1
			"--profile":
				profile_frames = 180
				profile_warmup = 120
			"--profile-idle":
				profile_frames = 180
				profile_warmup = 120
				profile_brush = false
		i += 1


func _build_music() -> void:
	SFX.start_music()


func _take_shot() -> void:
	if shot_path == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := shot_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(shot_path)
	print("[shot] saved ", shot_path)
	get_tree().quit()


# ------------------------------------------------------------------ menu

func _build_menu() -> void:
	if menu_layer != null:
		menu_layer.queue_free()
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 20
	add_child(menu_layer)
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = ThemeBuilder.build()
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.add_child(menu_root)
	var bg := MenuBackground.new()
	menu_root.add_child(bg)
	# верхняя панель
	var top := _hbox(8)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -420
	top.offset_right = -24
	top.offset_top = 18
	top.offset_bottom = 52
	top.alignment = BoxContainer.ALIGNMENT_END
	var lang_b := _button("RU" if L.lang != "en" else "EN", "GhostButton", Vector2(52, 28))
	lang_b.add_theme_font_size_override("font_size", 11)
	lang_b.pressed.connect(func():
		L.set_lang("en" if L.lang != "en" else "ru")
		_build_menu()
	)
	top.add_child(lang_b)
	var full_b := _button(L.t("fullscreen"), "GhostButton", Vector2(120, 28))
	full_b.add_theme_font_size_override("font_size", 11)
	full_b.pressed.connect(func():
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	top.add_child(full_b)
	menu_root.add_child(top)
	# левая колонка
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 74
	left.offset_top = 82
	left.offset_right = 520
	left.offset_bottom = 760
	left.add_theme_constant_override("separation", 6)
	menu_root.add_child(left)
	var title := _lbl("AETHERIA", "", ThemeBuilder.GOLD_BRIGHT, 100)
	title.add_theme_font_override("font", load("res://assets/fonts/CormorantGaramond.ttf"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 12)
	left.add_child(title)
	var sub := _lbl("Ж И В О Й   М И Р - А К В А Р И У М", "Small", ThemeBuilder.GOLD, 13)
	left.add_child(sub)
	var tag := _lbl(L.t("app_tagline"), "", Color(0.82, 0.88, 0.9, 0.9), 16)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(430, 0)
	left.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	left.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 7)
	buttons.custom_minimum_size = Vector2(310, 0)
	left.add_child(buttons)
	var new_b := _button(L.t("new_world"), "GoldButton", Vector2(310, 46))
	new_b.add_theme_font_size_override("font_size", 17)
	new_b.pressed.connect(open_new_world)
	buttons.add_child(new_b)
	var latest := Save.latest_slot()
	var cont := _button(L.t("continue_game"), "", Vector2(310, 42))
	cont.disabled = latest < 0
	cont.pressed.connect(func(): _load_slot(latest))
	buttons.add_child(cont)
	var load_b := _button(L.t("load_game"), "", Vector2(310, 42))
	load_b.disabled = latest < 0
	load_b.pressed.connect(open_load)
	buttons.add_child(load_b)
	var codex_b := _button(L.t("codex"), "", Vector2(310, 42))
	codex_b.pressed.connect(open_codex)
	buttons.add_child(codex_b)
	var settings_b := _button(L.t("settings"), "", Vector2(310, 42))
	settings_b.pressed.connect(open_settings)
	buttons.add_child(settings_b)
	var quit_b := _button(L.t("quit"), "GhostButton", Vector2(310, 40))
	quit_b.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit_b)
	# низ
	var ver := _lbl("v0.9.0 · Godot 4.7 · %s" % L.t("app_subtitle"), "Small", ThemeBuilder.MUTED, 10)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 74
	ver.offset_top = -42
	ver.offset_bottom = -20
	menu_root.add_child(ver)
	# карточка мира справа
	var card := PanelContainer.new()
	card.theme_type_variation = "PanelGlass"
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.offset_left = -430
	card.offset_right = -26
	card.offset_top = -330
	card.offset_bottom = -26
	menu_root.add_child(card)
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 18)
	cm.add_theme_constant_override("margin_right", 18)
	cm.add_theme_constant_override("margin_top", 16)
	cm.add_theme_constant_override("margin_bottom", 16)
	card.add_child(cm)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 7)
	cm.add_child(cv)
	cv.add_child(_lbl(L.t("tip"), "Small", ThemeBuilder.GOLD, 11))
	var tip := _lbl(_random_tip(), "", ThemeBuilder.TEXT, 13)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(tip)
	cv.add_child(_hairline())
	var latest_info := _latest_info()
	if not latest_info.is_empty():
		cv.add_child(_lbl(L.t("continue_game"), "Small", ThemeBuilder.MUTED, 10))
		cv.add_child(_lbl("%s" % latest_info.get("name", ""), "H2", ThemeBuilder.GOLD_BRIGHT, 20))
		cv.add_child(_lbl("Год %s · %s %s" % [str(latest_info.get("year", 0)), L.num(float(latest_info.get("pop", 0))), L.t("pop")], "", ThemeBuilder.TEXT, 12))
		cv.add_child(_lbl(str(latest_info.get("saved_at_text", "")), "Small", ThemeBuilder.MUTED, 10))
	else:
		cv.add_child(_lbl(L.t("no_saves"), "Small", ThemeBuilder.MUTED, 11))
	cv.add_child(_spacer())
	cv.add_child(_lbl("Совет: начните с «Мир-сад», чтобы увидеть расцвет жизни за пару минут.", "Small", ThemeBuilder.MUTED, 10))
	# эмблема
	var emblem := TextureRect.new()
	emblem.texture = Icons.get_icon("essence")
	emblem.modulate = Color(0.9, 0.7, 0.4, 0.08)
	emblem.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	emblem.offset_left = -590
	emblem.offset_right = -190
	emblem.offset_top = -320
	emblem.offset_bottom = 80
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(emblem)
	_build_menu_modal()


func _latest_info() -> Dictionary:
	var slot := Save.latest_slot()
	if slot < 0:
		return {}
	for i in Save.list_slots():
		if int(i.slot) == slot:
			return i
	return {}


func _random_tip() -> String:
	var tips := [
		"Кислотный дождь убивает урожай, но почти не вредит каменным стенам.",
		"Дождь тушит пожар и ускоряет рост травы.",
		"Три ядерных удара приводят к ядерной зиме и голоду по всему миру.",
		"Поселения воюют сами — можно лишь подтолкнуть их или помирить.",
		"Лесопилка и ферма — первые постройки, которые стоит дать племени.",
		"Эссенция восстанавливается со временем; в песочнице она бесконечна.",
		"Если существо голодает, оно ест запасы поселения, затем траву.",
		"Пророк может стать лидером и ускорить развитие веры.",
		"Климат зависит от широты и высоты: горы холоднее низин.",
		"Нажмите H, чтобы убрать интерфейс и полюбоваться миром.",
		"Нажмите F12, чтобы сохранить скриншот в папку игры.",
	]
	return tips[randi() % tips.size()]


# ------------------------------------------------------------------ menu helpers

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

func _vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())

func _button(text: String, variation: String = "", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b

func _hairline() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.5, 0.55, 0.55, 0.15)
	c.custom_minimum_size = Vector2(0, 1)
	return c


# ------------------------------------------------------------------ menu modals

func _build_menu_modal() -> void:
	menu_modal = Control.new()
	menu_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_modal.visible = false
	menu_modal.z_index = 80
	menu_root.add_child(menu_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.01, 0.015, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_modal.add_child(dim)
	menu_modal_panel = PanelContainer.new()
	menu_modal_panel.theme_type_variation = "PanelGlass"
	menu_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_modal_panel.offset_left = -480
	menu_modal_panel.offset_right = 480
	menu_modal_panel.offset_top = -300
	menu_modal_panel.offset_bottom = 300
	menu_modal.add_child(menu_modal_panel)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 16)
	menu_modal_panel.add_child(m)
	var v := _vbox(8)
	m.add_child(v)
	var head := _hbox(8)
	menu_modal_title = _lbl("", "H1", ThemeBuilder.GOLD_BRIGHT, 32)
	head.add_child(menu_modal_title)
	head.add_child(_spacer())
	var close := Button.new()
	close.theme_type_variation = "IconButton"
	close.icon = Icons.get_icon("close")
	close.expand_icon = true
	close.custom_minimum_size = Vector2(34, 32)
	close.add_theme_constant_override("icon_max_width", 18)
	close.pressed.connect(func(): menu_modal.visible = false; menu_modal_open = false)
	head.add_child(close)
	v.add_child(head)
	v.add_child(_hairline())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	menu_modal_content = _vbox(8)
	menu_modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(menu_modal_content)


func _open_modal(title: String) -> void:
	menu_modal_title.text = title
	menu_modal.visible = true
	menu_modal_open = true
	for c in menu_modal_content.get_children():
		c.queue_free()
	SFX.ui_click()


func open_new_world() -> void:
	_open_modal(L.t("new_world"))
	var seed_row := _hbox(8)
	seed_row.add_child(_lbl(L.t("seed"), "", ThemeBuilder.TEXT, 13))
	seed_row.add_child(_spacer())
	var seed_edit := LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(200, 32)
	seed_edit.text = str(randi() % 999999)
	new_seed_text = seed_edit.text
	seed_edit.text_changed.connect(func(t): new_seed_text = t)
	seed_row.add_child(seed_edit)
	var dice := Button.new()
	dice.theme_type_variation = "IconButton"
	dice.icon = Icons.get_icon("luck")
	dice.expand_icon = true
	dice.custom_minimum_size = Vector2(38, 32)
	dice.add_theme_constant_override("icon_max_width", 18)
	dice.tooltip_text = L.t("random")
	dice.pressed.connect(func():
		seed_edit.text = str(randi() % 999999)
		new_seed_text = seed_edit.text
	)
	seed_row.add_child(dice)
	menu_modal_content.add_child(seed_row)
	# пресеты
	menu_modal_content.add_child(_lbl(L.t("preset"), "Small", ThemeBuilder.TEAL, 11))
	var presets := _hbox(6)
	var preset_buttons := {}
	for p in D.world_presets:
		var b := Button.new()
		b.theme_type_variation = "PanelCard"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 84)
		b.button_pressed = p.id == selected_preset
		var v := _vbox(2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 8
		v.offset_right = -8
		v.offset_top = 6
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_lbl(L.tc(p), "H2", ThemeBuilder.GOLD_BRIGHT if b.button_pressed else ThemeBuilder.TEXT, 15))
		var d := _lbl(L.dc(p), "Small", ThemeBuilder.MUTED, 9)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		b.add_child(v)
		var pid := str(p.id)
		b.pressed.connect(func():
			selected_preset = pid
			for k in preset_buttons:
				preset_buttons[k].button_pressed = (k == pid)
		)
		preset_buttons[pid] = b
		presets.add_child(b)
	menu_modal_content.add_child(presets)
	# размер/сложность/племена
	var opts := _hbox(12)
	var size_box := _vbox(3)
	size_box.add_child(_lbl(L.t("world_size"), "Small", ThemeBuilder.MUTED, 10))
	var size_opt := OptionButton.new()
	size_opt.add_item("128 × 128", 0)
	size_opt.add_item("256 × 256", 1)
	size_opt.add_item("512 × 512", 2)
	size_opt.selected = [128, 256, 512].find(size_choice)
	size_opt.custom_minimum_size = Vector2(150, 32)
	size_opt.item_selected.connect(func(idx): size_choice = [128, 256, 512][idx])
	size_box.add_child(size_opt)
	opts.add_child(size_box)
	var diff_box := _vbox(3)
	diff_box.add_child(_lbl(L.t("difficulty"), "Small", ThemeBuilder.MUTED, 10))
	var diff_opt := OptionButton.new()
	for i in D.difficulties.size():
		diff_opt.add_item(L.tc(D.difficulties[i]), i)
	diff_opt.selected = 1
	diff_opt.custom_minimum_size = Vector2(150, 32)
	diff_opt.item_selected.connect(func(idx): diff_choice = str(D.difficulties[idx].id))
	diff_box.add_child(diff_opt)
	opts.add_child(diff_box)
	var tribe_box := _vbox(3)
	var tr_lbl := _lbl(L.t("tribes") + ": " + str(tribes_choice), "Small", ThemeBuilder.MUTED, 10)
	tribe_box.add_child(tr_lbl)
	var tr := HSlider.new()
	tr.min_value = 2
	tr.max_value = 10
	tr.step = 1
	tr.value = tribes_choice
	tr.custom_minimum_size = Vector2(150, 22)
	tr.value_changed.connect(func(v): tribes_choice = int(v); tr_lbl.text = L.t("tribes") + ": " + str(tribes_choice))
	tribe_box.add_child(tr)
	opts.add_child(tribe_box)
	menu_modal_content.add_child(opts)
	var sandbox := CheckButton.new()
	sandbox.text = L.t("infinite_essence")
	sandbox.button_pressed = sandbox_choice
	sandbox.toggled.connect(func(on): sandbox_choice = on)
	menu_modal_content.add_child(sandbox)
	var genesis := CheckButton.new()
	genesis.text = "Genesis: первородные без готовых деревень"
	genesis.button_pressed = genesis_choice
	genesis.toggled.connect(func(on): genesis_choice = on)
	menu_modal_content.add_child(genesis)
	menu_modal_content.add_child(_hairline())
	var desc := _lbl("Мир генерируется процедурно: тектоника, климат, реки, биомы и племена. Один и тот же seed даёт один и тот же мир.", "Small", ThemeBuilder.MUTED, 10)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_modal_content.add_child(desc)
	var create := _button(L.t("create_world"), "GoldButton", Vector2(0, 46))
	create.add_theme_font_size_override("font_size", 17)
	create.pressed.connect(func():
		menu_modal.visible = false
		menu_modal_open = false
		var seed_v := int(new_seed_text) if new_seed_text.is_valid_int() else randi() % 999999
		_start_new({"seed": seed_v, "size": size_choice, "preset": selected_preset, "difficulty": diff_choice, "tribes": tribes_choice, "sandbox": sandbox_choice, "genesis": genesis_choice})
	)
	menu_modal_content.add_child(create)


func open_load() -> void:
	_open_modal(L.t("load_game"))
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
		v.add_child(_lbl(str(info.get("name", "")), "H2", ThemeBuilder.GOLD_BRIGHT, 17))
		v.add_child(_lbl("Год %s · %s %s · %s" % [str(info.get("year", 0)), L.num(float(info.get("pop", 0))), L.t("pop"), str(info.get("saved_at_text", ""))], "Small", ThemeBuilder.MUTED, 10))
		h.add_child(v)
		var slot := int(info.slot)
		var lb := _button(L.t("load_game"), "GoldButton", Vector2(100, 34))
		lb.pressed.connect(func(): menu_modal.visible = false; _load_slot(slot))
		h.add_child(lb)
		var db := _button(L.t("delete"), "DangerButton", Vector2(80, 34))
		db.pressed.connect(func(): Save.delete_slot(slot); open_load())
		h.add_child(db)
		menu_modal_content.add_child(panel)
	if not any:
		menu_modal_content.add_child(_lbl(L.t("no_saves"), "Muted"))


func open_codex() -> void:
	_open_modal(L.t("screen_codex"))
	var tabs := _hbox(4)
	for t in [["races", L.t("codex_races")], ["animals", L.t("codex_animals")], ["biomes", L.t("codex_biomes")], ["tech", L.t("codex_tech")]]:
		var b := _button(str(t[1]), "Chip")
		b.toggle_mode = true
		b.button_pressed = codex_tab == t[0]
		b.add_theme_font_size_override("font_size", 11)
		var key := str(t[0])
		b.pressed.connect(func(): codex_tab = key; open_codex())
		tabs.add_child(b)
	menu_modal_content.add_child(tabs)
	var list: Array = []
	if codex_tab == "races": list = D.races
	elif codex_tab == "animals": list = D.animals
	elif codex_tab == "biomes": list = D.biomes
	else: list = D.techs
	for item in list:
		var p := PanelContainer.new()
		p.theme_type_variation = "PanelCard"
		var h := _hbox(8)
		p.add_child(h)
		var cb := ColorRect.new()
		cb.color = item.get("color_c", ThemeBuilder.GOLD)
		cb.custom_minimum_size = Vector2(4, 0)
		h.add_child(cb)
		var v := _vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_lbl(L.tc(item), "H2", ThemeBuilder.TEXT, 15))
		var d := _lbl(L.dc(item), "Small", ThemeBuilder.MUTED, 10)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
		h.add_child(v)
		menu_modal_content.add_child(p)


func open_settings() -> void:
	_open_modal(L.t("settings"))
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var lang_row := _hbox(8)
	lang_row.add_child(_lbl(L.t("language"), "", ThemeBuilder.TEXT, 13))
	lang_row.add_child(_spacer())
	var lang := OptionButton.new()
	lang.add_item("Русский", 0)
	lang.add_item("English", 1)
	lang.selected = 0 if L.lang != "en" else 1
	lang.custom_minimum_size = Vector2(160, 30)
	lang.item_selected.connect(func(idx):
		L.set_lang("en" if idx == 1 else "ru")
		_build_menu()
		open_settings()
	)
	lang_row.add_child(lang)
	menu_modal_content.add_child(lang_row)
	for s in [["master", L.t("audio"), SFX.master_volume], ["music", L.t("music_volume"), SFX.music_volume], ["sfx", L.t("sfx_volume"), SFX.sfx_volume]]:
		var row := _hbox(8)
		row.add_child(_lbl(str(s[1]), "", ThemeBuilder.TEXT, 13))
		row.add_child(_spacer())
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 1
		sl.step = 0.05
		sl.value = float(s[2])
		sl.custom_minimum_size = Vector2(240, 20)
		var val := _lbl("%d%%" % int(float(s[2]) * 100), "Small", ThemeBuilder.GOLD, 11)
		val.custom_minimum_size = Vector2(42, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var key := str(s[0])
		sl.value_changed.connect(func(v):
			val.text = "%d%%" % int(v * 100)
			if key == "master": SFX.master_volume = v
			elif key == "music": SFX.music_volume = v
			else: SFX.sfx_volume = v
			SFX.apply_volumes(SFX.master_volume, SFX.music_volume, SFX.sfx_volume)
		)
		row.add_child(sl)
		row.add_child(val)
		menu_modal_content.add_child(row)
	# масштаб интерфейса
	var ui_row := _hbox(8)
	ui_row.add_child(_lbl(L.t("ui_scale"), "", ThemeBuilder.TEXT, 13))
	ui_row.add_child(_spacer())
	var ui_val := _lbl("100%", "Small", ThemeBuilder.GOLD, 11)
	var ui_sl := HSlider.new()
	ui_sl.min_value = 0.8
	ui_sl.max_value = 1.3
	ui_sl.step = 0.05
	var cfg_ui := ConfigFile.new()
	cfg_ui.load("user://settings.cfg")
	ui_sl.value = float(cfg_ui.get_value("ui", "scale", 1.0))
	ui_sl.custom_minimum_size = Vector2(240, 20)
	ui_sl.value_changed.connect(func(v):
		ui_val.text = "%d%%" % int(v * 100)
		get_window().content_scale_factor = v
		var cc := ConfigFile.new()
		cc.load("user://settings.cfg")
		cc.set_value("ui", "scale", v)
		cc.save("user://settings.cfg")
	)
	ui_row.add_child(ui_sl)
	ui_row.add_child(ui_val)
	menu_modal_content.add_child(ui_row)
	var fs := CheckButton.new()
	fs.text = L.t("fullscreen")
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(func(on): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	menu_modal_content.add_child(fs)
	menu_modal_content.add_child(_hairline())
	var about := _lbl(L.t("credits"), "Small", ThemeBuilder.MUTED, 10)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_modal_content.add_child(about)
	var close := _button(L.t("close"), "GoldButton")
	close.pressed.connect(func(): menu_modal.visible = false; menu_modal_open = false)
	menu_modal_content.add_child(close)


# ------------------------------------------------------------------ loading

func _build_loading() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 100
	add_child(loading_layer)
	loading_root = Control.new()
	loading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.theme = ThemeBuilder.build()
	loading_root.visible = false
	loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_layer.add_child(loading_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.add_child(bg)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -330
	center.offset_right = 330
	center.offset_top = -190
	center.offset_bottom = 190
	center.add_theme_constant_override("separation", 12)
	loading_root.add_child(center)
	var t := _lbl("AETHERIA", "", ThemeBuilder.GOLD_BRIGHT, 54)
	t.add_theme_font_override("font", load("res://assets/fonts/CormorantGaramond.ttf"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(t)
	var sub := _lbl(L.t("generating").to_upper(), "Small", ThemeBuilder.GOLD, 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)
	loading_phase = _lbl(L.t("generating_terrain"), "", ThemeBuilder.TEXT, 15)
	loading_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(loading_phase)
	loading_bar = ProgressBar.new()
	loading_bar.min_value = 0
	loading_bar.max_value = 100
	loading_bar.value = 0
	loading_bar.show_percentage = false
	loading_bar.custom_minimum_size = Vector2(460, 10)
	loading_bar.add_theme_stylebox_override("fill", ThemeBuilder.style(ThemeBuilder.GOLD, Color.TRANSPARENT, 5, 0, 0))
	loading_bar.add_theme_stylebox_override("background", ThemeBuilder.style(Color(0.06, 0.08, 0.1, 1), Color(0.3, 0.4, 0.4, 0.4), 5, 1, 0))
	center.add_child(loading_bar)
	loading_tip = _lbl("", "Small", ThemeBuilder.MUTED, 11)
	loading_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(loading_tip)


func _progress(phase: String, frac: float) -> void:
	if loading_phase != null:
		loading_phase.text = L.t(phase)
	if loading_bar != null:
		loading_bar.value = clampf(frac * 100.0, 0.0, 100.0)
	if loading_tip != null and loading_tip.text == "":
		loading_tip.text = _random_tip()


# ------------------------------------------------------------------ sessions

func _start_new(config: Dictionary) -> void:
	menu_layer.visible = false
	loading_root.visible = true
	loading_root.modulate.a = 1.0
	if game != null:
		game.queue_free()
		game = null
	await get_tree().process_frame
	game = GameSession.new()
	game.name = "Game"
	add_child(game)
	game.back_to_menu.connect(_on_back_to_menu)
	game.load_requested.connect(_on_game_load)
	await game.new_game(config, _progress)
	await get_tree().process_frame
	loading_root.visible = false
	menu_layer.visible = false
	SFX.set_war(0.0)


func _load_slot(slot: int) -> void:
	if slot < 0:
		return
	menu_layer.visible = false
	loading_root.visible = true
	loading_root.modulate.a = 1.0
	loading_phase.text = L.t("loading")
	loading_bar.value = 10
	if game != null:
		game.queue_free()
		game = null
	await get_tree().process_frame
	game = GameSession.new()
	game.name = "Game"
	add_child(game)
	game.back_to_menu.connect(_on_back_to_menu)
	game.load_requested.connect(_on_game_load)
	var ok: bool = await game.load_game(slot, _progress)
	if not ok:
		game.queue_free()
		game = null
		loading_root.visible = false
		menu_layer.visible = true
		return
	await get_tree().process_frame
	loading_root.visible = false


func _on_back_to_menu() -> void:
	if game != null:
		game.queue_free()
		game = null
	loading_root.visible = false
	_build_menu()
	menu_layer.visible = true
	SFX.set_war(0.0)


func _on_game_load(slot: int) -> void:
	call_deferred("_load_slot", slot)
