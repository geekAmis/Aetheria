class_name GameSession
extends Node3D
## Игровая сессия: связывает симуляцию, рендер, камеру и интерфейс.

signal back_to_menu
signal load_requested(slot)

const SPEEDS := [1.0, 2.0, 5.0, 10.0, 20.0]
const ESSENCE_MAX := 1000.0

var world: WorldModel
var sim: SimWorld
var camera_rig: CameraRig
var terrain_view: TerrainView
var nature_view: NatureView
var settlement_view: SettlementView
var creature_view: CreatureView
var fx: FXView
var sky: SkyView
var hud: HUD

var config: Dictionary = {}
var world_name := "Аэтерия"
var essence := 600.0
var sandbox := true
var paused := false
var speed := 1.0
var day_accum := 0.0
var visual_hour := 9.0
var play_seconds := 0.0

var active_tool := "inspect"
var brush_radius := 5.0
var stroke_active := false
var stroke_last := 0.0
var stroke_last_cell := Vector2i(-1, -1)
var stroke_tool := ""
var hover_cell := Vector2i(-1, -1)
var hover_timer := 0.0
var hud_timer := 0.0
var last_hud_us := 0
var sky_timer := 0.0
var autosave_timer := 180.0
var save_dirty := true

var selected_agent_id := -1
var selected_settlement_id := -1
var follow_agent := -1

var undo_stack: Array = []
var redo_stack: Array = []
var tutorial_flags := {"select": false, "mountain": false, "lightning": false, "speed": false}
var tutorial_done := false
var world_lost_shown := false
var mods_initialized := false


func new_game(p_config: Dictionary, progress: Callable = Callable()) -> void:
	config = p_config
	world_name = str(config.get("world_name", ""))
	var size := int(config.get("size", 256))
	var seed_v := int(config.get("seed", randi()))
	var preset := str(config.get("preset", "continent"))
	world = WorldModel.new(size, seed_v, preset)
	await world.generate({
		"size": size, "seed": seed_v, "preset": preset
	}, progress, self)
	if world_name.is_empty():
		world_name = world.world_name
	else:
		world.world_name = world_name
	config["seed"] = seed_v
	config["size"] = size
	config["preset"] = preset
	sandbox = bool(config.get("sandbox", true))
	essence = 600.0
	tutorial_done = _tutorial_was_done()
	await _build_views(progress)
	if progress.is_valid():
		progress.call("generating_tribes", 0.965)
	sim = SimWorld.new()
	sim.setup(world, config)
	sim.populate()
	_after_sim()
	if progress.is_valid():
		progress.call("generating_mesh", 1.0)
	await get_tree().process_frame
	_create_hud()
	_finish_start()
	_start_tutorial()


func load_game(slot: int, progress: Callable = Callable()) -> bool:
	var data := Save.load_world(slot)
	if data.is_empty():
		return false
	config = data.get("config", {})
	world_name = str(data.get("world_name", "Аэтерия"))
	essence = float(data.get("essence", 600.0))
	sandbox = bool(data.get("sandbox", true))
	tutorial_done = true
	var wd: Dictionary = data.get("world", {})
	var size := int(wd.get("size", 256))
	var seed_v := int(wd.get("seed", 1))
	var preset := str(wd.get("preset", "continent"))
	world = WorldModel.new(size, seed_v, preset)
	world.world_name = str(wd.get("name", world_name))
	world.sea_level = float(wd.get("sea_level", 0.4))
	world.heights = _dec_f32(wd.get("heights", ""))
	world.moisture = _dec_f32(wd.get("moisture", ""))
	world.temperature = _dec_f32(wd.get("temperature", ""))
	world.vegetation = _dec_f32(wd.get("vegetation", ""))
	world.water = _dec_f32(wd.get("water", ""))
	world.radiation = _dec_f32(wd.get("radiation", ""))
	world.burn = _dec_f32(wd.get("burn", ""))
	world.biome_ids = _dec_bytes(wd.get("biomes", ""))
	world.res_type = _dec_bytes(wd.get("res_type", ""))
	world.res_amount = _dec_f32(wd.get("res_amount", ""))
	world.dist_water = PackedInt32Array()
	world.dist_water.resize(world.n())
	world._recount()
	world.rebuild_fertility()
	if progress.is_valid():
		progress.call("generating_mesh", 0.3)
	await _build_views(progress)
	sim = SimWorld.new()
	sim.setup(world, config)
	sim.from_dict(data.get("sim", {}))
	_after_sim()
	if progress.is_valid():
		progress.call("generating_mesh", 0.95)
	await get_tree().process_frame
	_create_hud()
	var cam: Dictionary = data.get("camera", {})
	if not cam.is_empty():
		camera_rig.yaw = float(cam.get("yaw", camera_rig.yaw))
		camera_rig.pitch = float(cam.get("pitch", camera_rig.pitch))
		camera_rig.distance = float(cam.get("dist", camera_rig.distance))
		camera_rig.smooth_distance = camera_rig.distance
		var ct: Array = cam.get("target", [0, 0, 0])
		camera_rig.focus_cell(Vector2(float(ct[0]), float(ct[2])))
	selected_settlement_id = -1
	_finish_start()
	return true


func _tutorial_was_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		return bool(cfg.get_value("game", "tutorial_done", false))
	return false


func _build_views(progress: Callable = Callable()) -> void:
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.setup(world)
	if progress.is_valid():
		progress.call("generating_mesh", 0.84)
	await get_tree().process_frame
	terrain_view = TerrainView.new()
	terrain_view.name = "Terrain"
	add_child(terrain_view)
	terrain_view.setup(world)
	if progress.is_valid():
		progress.call("generating_mesh", 0.89)
	await get_tree().process_frame
	nature_view = NatureView.new()
	nature_view.name = "Nature"
	add_child(nature_view)
	nature_view.setup(world)
	if progress.is_valid():
		progress.call("generating_mesh", 0.92)
	await get_tree().process_frame
	settlement_view = SettlementView.new()
	settlement_view.name = "Settlements"
	add_child(settlement_view)
	creature_view = CreatureView.new()
	creature_view.name = "Creatures"
	add_child(creature_view)
	fx = FXView.new()
	fx.name = "FX"
	add_child(fx)
	sky = SkyView.new()
	sky.name = "Sky"
	add_child(sky)
	sky.setup(world, camera_rig)
	# при первом запуске смотрим на центр
	camera_rig.focus_cell(Vector2(world.size * 0.5, world.size * 0.5), world.size * 0.62)


func _after_sim() -> void:
	settlement_view.setup(world, sim, camera_rig)
	creature_view.setup(world, sim)
	fx.setup(world, sim, camera_rig)
	for s in sim.settlements:
		nature_view.mark_dirty_rect(_nature_rect(s.center))
	sim.settlement_founded.connect(func(s): nature_view.mark_dirty_rect(_nature_rect(s.center)))
	fx.screen_flash.connect(_on_screen_flash)
	fx.screen_shake.connect(func(a, d): camera_rig.add_shake(a, d))
	sim.chronicle_added.connect(_on_chronicle_event)
	sim.toast.connect(_on_toast)
	sim.era_changed.connect(_on_era_changed)
	sim.disaster.connect(_on_disaster)
	sim.nuclear_winter_started.connect(func(): hud_toast_later(L.t("toast_nuclear_winter"), "nuke"))
	sim.war_declared.connect(func(_a, _b): SFX.set_war(sim.war_intensity))
	sim.war_ended.connect(func(_a, _b): pass)


func _create_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)
	hud.tool_selected.connect(_on_tool_selected)
	hud.brush_size_changed.connect(func(r): brush_radius = r)
	hud.speed_requested.connect(func(s): set_speed(s))
	hud.pause_toggled.connect(toggle_pause)
	hud.layer_changed.connect(func(l): terrain_view.set_layer(l))
	hud.jump_to.connect(_on_jump_to)
	hud.save_requested.connect(func(slot): save_to_slot(slot, false))
	hud.load_requested.connect(func(slot): load_requested.emit(slot))
	hud.menu_requested.connect(func(): back_to_menu.emit())
	hud.select_settlement.connect(func(id): select_settlement(id))
	hud.follow_toggled.connect(func(id): follow_agent = id)
	hud.god_agent_action.connect(_on_god_agent_action)
	hud.favourite_toggled.connect(_on_favourite_toggled)
	hud.spawn_requested.connect(_on_spawn_requested)
	hud.server_settings_changed.connect(_on_settings_changed)
	hud.set_speed(speed)
	hud.update_essence(essence, sandbox)
	hud.set_brush(brush_radius)
	hud.update_tutorial(tutorial_flags, tutorial_done)
	if not mods_initialized:
		mods_initialized = true
		ModLoader.load_for_game(self)


func reload_hud() -> void:
	var sel_a := selected_agent_id
	var sel_s := selected_settlement_id
	if hud != null:
		hud.queue_free()
		hud = null
	_create_hud()
	if sel_s >= 0:
		var s: SettlementData = sim.settlement_by_id.get(sel_s, null)
		if s != null:
			selected_settlement_id = sel_s
			hud.inspect_settlement(s)
	elif sel_a >= 0:
		var a: AgentData = sim.agent_by_id.get(sel_a, null)
		if a != null:
			selected_agent_id = sel_a
			hud.inspect_agent(a)
	_update_hud()


func grant_specific_tech(sid: int, tid: String) -> void:
	var s: SettlementData = sim.settlement_by_id.get(sid, null)
	if s == null or s.techs.has(tid):
		return
	if not _spend(25.0):
		return
	var t := D.tech(tid)
	s.techs.append(tid)
	s.era_techs_done += 1
	if tid == s.researching:
		s.researching = ""
		s.research_progress = 0.0
	hud.toast("%s: %s" % [s.name, L.tc(t)], "tech")
	if s.era_techs_done >= 4:
		sim._advance_era(s)
	hud.update_essence(essence, sandbox)
	refresh_inspector_force()


func refresh_inspector_force() -> void:
	if hud != null:
		hud.inspector_sig = ""
		hud.refresh_inspector()


func _on_god_agent_action(kind: String) -> void:
	var a := get_selected_agent()
	if a == null or not a.alive:
		return
	var res := sim.god_agent_action(a, kind)
	if res == "":
		return
	var word := {
		"heal": "исцелён", "bless": "благословлён", "curse": "проклят",
		"scare": "напуган", "reward": "награждён", "immortal": "отмечен вечностью",
		"perk_tough": "получил перк", "perk_genius": "получил перк", "perk_swift": "получил перк"
	}.get(kind, kind)
	hud.toast("%s %s" % [a.display_name(), word], "power" if kind != "scare" else "warn")
	SFX.play("bless" if kind in ["heal", "bless", "reward", "immortal"] else "curse", -6.0)
	if kind in ["heal", "bless", "reward", "immortal"]:
		fx.play("bless", a.pos, 1.4, {"kind": "health"})
	else:
		fx.play("curse", a.pos, 1.2, {"kind": "fear"})
	refresh_inspector_force()


func _on_favourite_toggled(id: int) -> void:
	var a: AgentData = sim.agent_by_id.get(id, null)
	if a == null:
		return
	a.favourite = not a.favourite
	if a.favourite:
		hud.toast("%s добавлен в избранное" % a.display_name(), "info")
	refresh_inspector_force()


func _on_spawn_requested(kind: String, data: Dictionary) -> void:
	var cell := hud.last_hover_cell
	if cell.x < 0 or not world.in_bounds(cell.x, cell.y):
		var s0 := get_selected_settlement()
		cell = s0.center if s0 != null else Vector2i(world.size / 2, world.size / 2)
	if world.is_water_cell(cell.x, cell.y):
		var land := Vector2i(-1, -1)
		for r in range(1, 8):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					if world.is_land_cell(cell.x + dx, cell.y + dz):
						land = Vector2i(cell.x + dx, cell.y + dz)
						break
				if land.x >= 0: break
			if land.x >= 0: break
		if land.x >= 0:
			cell = land
	if kind == "creature":
		var s := sim._settlement_near(cell, 24.0)
		var sid := s.id if s != null else -1
		var a := sim.spawn_agent_custom(cell, str(data.species_id), int(data.gender), float(data.age), sid)
		selected_agent_id = a.id
		selected_settlement_id = -1
		sim.selected_settlement_id = -1
		creature_view.set_selected(a.id)
		hud.inspect_agent(a)
		hud.toast("Создан %s" % a.display_name(), "power")
	else:
		var an := sim.spawn_animal_custom(cell, str(data.species_id), int(data.gender), float(data.age))
		if not an.is_empty():
			hud.toast("Создано животное: %s" % L.tc(D.animal(str(data.species_id))), "info")
	refresh_inspector_force()


func _finish_start() -> void:
	paused = false
	speed = 1.0
	day_accum = 0.0
	visual_hour = 9.0
	if not sim.settlements.is_empty():
		var best: SettlementData = null
		for s in sim.settlements:
			if not s.destroyed and (best == null or s.population > best.population):
				best = s
		if best != null:
			select_settlement(best.id, false)
	camera_rig.focus_cell(Vector2(world.size * 0.5, world.size * 0.5), world.size * 1.05)
	SFX.start_music()
	SFX.set_war(0.0)
	sky.apply(visual_hour, sim.season, sim.weather_mode, sim.nuclear_winter)
	save_dirty = true


func _process(delta: float) -> void:
	if sim == null or world == null:
		return
	if terrain_view != null:
		terrain_view.skip_budget = false
	if creature_view != null:
		creature_view.skip_sync = false
	play_seconds += delta
	if hud != null and hud.is_modal_open():
		pass
	if not paused:
		day_accum += delta * speed
		var steps := 0
		while day_accum >= 1.0 and steps < 40:
			day_accum -= 1.0
			sim.step_day()
			steps += 1
			save_dirty = true
		visual_hour = fposmod(visual_hour + delta * 0.34, 24.0)
		if not sandbox:
			essence = minf(ESSENCE_MAX, essence + delta * 0.65)
		_move_agents(delta)
		_move_animals(delta)
		autosave_timer -= delta
		if autosave_timer <= 0.0:
			autosave_timer = 180.0
			if save_dirty and sim.total_population > 0:
				save_to_slot(0, true)
				save_dirty = false
	# если день был тяжёлым, пропускаем тяжёлые пересборки в этом кадре
	if sim.heavy_step_fresh:
		if terrain_view != null:
			terrain_view.skip_budget = true
		if creature_view != null:
			creature_view.skip_sync = true
		sim.heavy_step_fresh = false
	# кисть
	if stroke_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _over_ui():
		stroke_last += delta
		var cell := camera_rig.pick_cell()
		if cell.x >= 0 and (stroke_last > 0.085 or cell != stroke_last_cell):
			if cell != stroke_last_cell or stroke_last > 0.12:
				stroke_last = 0.0
				stroke_last_cell = cell
				_apply_tool(stroke_tool, cell, false)
	if follow_agent >= 0:
		var a: AgentData = sim.agent_by_id.get(follow_agent, null)
		if a != null:
			var half := world.size * 0.5
			camera_rig.target = Vector3((a.pos.x - half) * WorldModel.CELL, 0, (a.pos.y - half) * WorldModel.CELL)
		else:
			follow_agent = -1
	hud_timer -= delta
	if hud_timer <= 0.0:
		hud_timer = 0.22
		_update_hud()
	sky_timer -= delta
	if sky_timer <= 0.0:
		sky_timer = 0.18
		sky.apply(visual_hour, sim.season, sim.weather_mode, sim.nuclear_winter)
		terrain_view.refresh_minimap_if_dirty()
		_update_brush_cursor()
	# проверка вымирания
	if not world_lost_shown and sim.total_population == 0 and sim.year > 2:
		world_lost_shown = true
		if hud != null:
			hud.show_world_lost()
	if sim.total_population > 0:
		world_lost_shown = false


func _update_hud() -> void:
	if hud == null:
		return
	var t0 := Time.get_ticks_usec()
	hud.update_top(sim.date_text(), sim.season_text(), sim.total_population, _alive_settlements(), _world_era(), essence, sandbox, speed, paused)
	hud.update_essence(essence, sandbox)
	hud.update_hover(hover_cell, world)
	hud.refresh_inspector()
	hud.stats_changed()
	last_hud_us = Time.get_ticks_usec() - t0


func _world_era() -> int:
	var best := 0
	for s in sim.settlements:
		if not s.destroyed:
			best = maxi(best, s.era)
	return best


func _alive_settlements() -> int:
	return sim._alive_settlement_count()


func _nature_rect(center: Vector2i, radius: int = 13) -> Rect2i:
	return Rect2i(center.x - radius, center.y - radius, radius * 2, radius * 2)


func _update_brush_cursor() -> void:
	if hud == null:
		return
	var over := _over_ui()
	var cell := camera_rig.pick_cell() if not over else Vector2i(-1, -1)
	hover_cell = cell
	if active_tool == "inspect" or over or cell.x < 0:
		fx.update_brush(cell, brush_radius, Color(1, 0.9, 0.6), false)
		return
	var p := D.power(active_tool)
	var col := Color("#e8c07a")
	if p.get("cat", "") == "disaster":
		col = Color("#e05a4e")
	elif p.get("cat", "") == "bless":
		col = Color("#88e0b0")
	elif p.get("cat", "") == "water":
		col = Color("#66c8e0")
	fx.update_brush(cell, brush_radius, col, true)


func _move_agents(delta: float) -> void:
	if sim == null:
		return
	var mult := 1.0 + speed * 0.14
	var half := world.size * 0.5
	var road_bonus := {}
	for s in sim.settlements:
		for oid in s.roads:
			if float(s.roads[oid].get("progress", 0.0)) >= 1.0:
				road_bonus[s.id] = 1.18
				break
	for av in sim.agents:
		var a: AgentData = av
		if not a.alive:
			continue
		# охота: цель — животное, при сближении — добыча
		if a.action == "hunt":
			var an: Dictionary = sim.animal_by_id.get(a.hunting_id, {})
			if an.is_empty() or not bool(an.get("alive", false)):
				a.hunting_id = -1
				a.action_time = a.action_duration
			else:
				a.target = an.pos
				if a.pos.distance_to(Vector2(an.pos)) < 1.15:
					sim.complete_hunt(a, an)
					continue
		elif a.action == "haul":
			if a.pos.distance_to(a.target) < 1.2:
				sim.complete_haul(a)
				continue
		elif a.action == "flee" and a.pos.distance_to(a.target) < 0.6:
			a.action_time = a.action_duration
		var to: Vector2 = a.target - a.pos
		var d: float = to.length()
		if d < 0.08:
			continue
		var spd := a.speed * 0.42 * mult
		if a.action == "flee" or a.action == "hunt":
			spd *= 1.35
		elif a.action == "sleep":
			spd *= 0.5
		elif a.action in ["build", "work", "eat", "drink", "pray"]:
			spd *= 0.9
		if road_bonus.has(a.settlement_id) and a.action in ["march", "haul", "work"]:
			spd *= 1.18
		var step: float = spd * delta
		var next: Vector2 = a.pos + (to / d) * minf(step, d)
		var cc := world.cell_of(next)
		if world.is_water_cell(cc.x, cc.y):
			step *= 0.45
			next = a.pos + (to / d) * minf(step, d)
		a.pos = Vector2(clampf(next.x, 0.5, world.size - 1.5), clampf(next.y, 0.5, world.size - 1.5))


func _move_animals(delta: float) -> void:
	var mult := 1.0 + speed * 0.10
	for an in sim.animals:
		var p: Vector2 = an.pos
		var t: Vector2 = an.target
		var to := t - p
		var d := to.length()
		if d < 0.1:
			continue
		var sp: Dictionary = D.animal(str(an.species))
		var step: float = float(sp.get("speed", 1.5)) * 0.10 * mult * delta
		var nxt := p + (to / d) * minf(step, d)
		var cc := world.cell_of(nxt)
		if world.is_water_cell(cc.x, cc.y) != world.is_water_cell(int(p.x), int(p.y)):
			continue
		an.pos = nxt


func _over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.is_typing():
		return
	if event.is_action_pressed("pause"):
		if hud != null and hud.is_modal_open():
			hud.close_modal()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("hide_ui"):
		if hud != null:
			hud.toggle_visible()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help"):
		if hud != null:
			hud.open_help()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if hud != null and hud.is_modal_open():
				hud.close_modal()
			else:
				hud.open_pause()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F12:
			_screenshot()
			return
		if event.keycode == KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if event.keycode == KEY_TAB:
			if hud != null:
				hud.toggle_panel()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo()
			return
		if event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_5 and not event.ctrl_pressed:
			set_speed(SPEEDS[event.keycode - KEY_1])
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _over_ui():
			return
		if event.pressed:
			var cell := camera_rig.pick_cell()
			if cell.x < 0:
				return
			if active_tool == "inspect":
				_select_at(cell)
			elif active_tool == "tribe_spawn":
				pass
			else:
				stroke_tool = active_tool
				stroke_active = _is_brush_tool(active_tool)
				stroke_last = 0.0
				stroke_last_cell = cell
				if _is_brush_tool(active_tool):
					_push_undo(cell, brush_radius + 3.0)
				_apply_tool(active_tool, cell, true)
		else:
			stroke_active = false
			stroke_tool = ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		stroke_active = false


func _is_brush_tool(id: String) -> bool:
	var p := D.power(id)
	return p.get("kind", "instant") == "brush"


func _on_tool_selected(id: String) -> void:
	active_tool = id
	stroke_active = false
	SFX.ui_click()
	if hud != null:
		hud.set_active_tool(id)


func set_speed(s: float) -> void:
	speed = clampf(s, 0.0, 20.0)
	paused = speed <= 0.0
	if hud != null:
		hud.set_speed(speed)
	if speed >= 5.0:
		tutorial_flags["speed"] = true
		_tutorial_check()


func toggle_pause() -> void:
	paused = not paused
	if hud != null:
		hud.set_paused(paused)


func _on_settings_changed() -> void:
	if hud != null:
		hud.apply_ui_scale()
	if sky != null and terrain_view != null:
		pass


# ------------------------------------------------------------------ selection

func _select_at(cell: Vector2i) -> void:
	var best: AgentData = null
	var bestd := 2.2
	for av in sim.agents:
		var a: AgentData = av
		if not a.alive:
			continue
		var d: float = a.pos.distance_to(Vector2(cell))
		if d < bestd:
			bestd = d
			best = a
	if best != null:
		selected_agent_id = best.id
		selected_settlement_id = -1
		sim.selected_settlement_id = -1
		creature_view.set_selected(best.id)
		settlement_view.select(-1)
		hud.inspect_agent(best)
		tutorial_flags["select"] = true
		_tutorial_check()
		return
	var s := _settlement_at(cell)
	if s != null:
		select_settlement(s.id)
		return
	selected_agent_id = -1
	selected_settlement_id = -1
	creature_view.set_selected(-1)
	settlement_view.select(-1)
	hud.inspect_cell(cell)


func _settlement_at(cell: Vector2i) -> SettlementData:
	var best: SettlementData = null
	var bd := 9999.0
	for s in sim.settlements:
		if s.destroyed:
			continue
		var d := Vector2(s.center).distance_to(Vector2(cell))
		if d < maxf(4.0, s.territory_radius * 0.7) and d < bd:
			bd = d
			best = s
	return best


func select_settlement(id: int, mark_tutorial: bool = true) -> void:
	var s: SettlementData = sim.settlement_by_id.get(id, null)
	if s == null:
		return
	selected_settlement_id = id
	selected_agent_id = -1
	sim.selected_settlement_id = id
	settlement_view.select(id)
	creature_view.set_selected(-1)
	hud.inspect_settlement(s)
	if mark_tutorial:
		tutorial_flags["select"] = true
		_tutorial_check()


func _on_jump_to(pos: Vector2, settlement_id: int) -> void:
	if settlement_id >= 0:
		select_settlement(settlement_id)
		var s: SettlementData = sim.settlement_by_id.get(settlement_id, null)
		if s != null:
			camera_rig.focus_settlement(s.center)
	elif pos.x >= 0:
		camera_rig.focus_cell(pos)


# ------------------------------------------------------------------ god tools

func _apply_tool(tool_id: String, cell: Vector2i, first: bool) -> bool:
	var p: Dictionary = D.power(tool_id)
	if p.is_empty():
		return false
	var cost := float(p.get("cost", 1))
	var radius := brush_radius
	if first and not _spend(cost):
		return false
	var s := _settlement_at(cell)
	match tool_id:
		"raise", "lower", "smooth", "mountain", "hill":
			var mode := "add"
			var strength := 0.05
			match tool_id:
				"lower": mode = "sub"
				"smooth": mode = "smooth"; strength = 0.75
				"mountain": strength = 0.055
				"hill": strength = 0.028
			world.raise_area(cell.x, cell.y, radius, strength, mode)
			if tool_id == "mountain":
				world.paint_biome(cell.x, cell.y, radius * 0.6, "mountains")
				tutorial_flags["mountain"] = true
				_tutorial_check()
			SFX.play("brush", -12.0, randf_range(0.9, 1.1))
		"sand":
			world.paint_biome(cell.x, cell.y, radius, "beach")
			SFX.play("brush", -12.0, 1.05)
		"grass":
			world.paint_biome(cell.x, cell.y, radius, "meadow")
			SFX.play("brush", -12.0, 0.95)
		"forest":
			world.paint_biome(cell.x, cell.y, radius, "forest")
			SFX.play("brush", -12.0, 0.9)
		"lava":
			world.water_area(cell.x, cell.y, radius, "lava")
			sim.ignite_at(cell.x, cell.y, int(radius))
			SFX.play("explosion", -8.0, 0.7)
		"water_shallow":
			world.water_area(cell.x, cell.y, radius, "shallow")
		"water_river":
			world.water_area(cell.x, cell.y, radius, "river")
		"water_lake":
			world.water_area(cell.x, cell.y, radius, "lake")
		"water_ocean":
			world.water_area(cell.x, cell.y, radius, "ocean")
		"dry":
			world.water_area(cell.x, cell.y, radius, "dry")
		"tree":
			world.paint_biome(cell.x, cell.y, 1.1, "forest")
			SFX.play("brush", -12.0, 0.8)
		"bush":
			world.paint_biome(cell.x, cell.y, 0.8, "meadow")
		"animal":
			sim.spawn_animal_at(cell.x, cell.y)
		"tribe":
			if sim.spawn_tribe(cell.x, cell.y) == null:
				if hud != null:
					hud.toast(L.t("target_settlement"), "error")
				return false
			tutorial_flags["select"] = true
		"lightning":
			sim.lightning(cell.x, cell.y)
			tutorial_flags["lightning"] = true
			_tutorial_check()
		"tornado":
			fx.play("tornado", Vector2(cell), radius, {})
			SFX.play("horn", -8.0, 0.7)
		"meteor":
			sim.meteor(cell.x, cell.y, maxf(4.0, radius * 0.55))
		"bomb":
			sim.bomb(cell.x, cell.y, maxf(2.0, radius * 0.35))
		"nuke":
			sim.nuke(cell.x, cell.y, maxf(7.0, radius * 0.9))
		"earthquake":
			sim.earthquake(cell.x, cell.y, maxf(10.0, radius * 1.4))
		"rain":
			sim.rain(cell.x, cell.y, radius * 1.6)
		"acid_rain":
			sim.acid_rain(cell.x, cell.y, radius * 1.4)
		"fire":
			sim.ignite_at(cell.x, cell.y, int(radius))
		"plague":
			if s != null:
				sim.plague_settlement(s)
			else:
				if hud != null: hud.toast(L.t("target_settlement"), "error")
				return false
		"drought":
			sim.drought(cell.x, cell.y, radius * 1.8)
		"flood":
			sim.flood(cell.x, cell.y, radius * 1.4)
		"volcano":
			sim.volcano_eruption(cell.x, cell.y, maxf(4.0, radius * 0.75))
		"blizzard":
			sim.blizzard(cell.x, cell.y, radius * 1.8)
		"bless_health":
			sim.bless_area(cell.x, cell.y, radius, "health")
		"bless_fertility":
			sim.bless_area(cell.x, cell.y, radius, "fertility")
		"bless_wisdom":
			sim.bless_area(cell.x, cell.y, radius, "wisdom")
		"bless_luck":
			sim.bless_area(cell.x, cell.y, radius, "luck")
		"curse_disease":
			sim.curse_area(cell.x, cell.y, radius, "disease")
		"curse_madness":
			sim.curse_area(cell.x, cell.y, radius, "madness")
		"curse_undeath":
			sim.curse_area(cell.x, cell.y, radius, "undeath")
		"gift":
			if s != null: sim.gift_settlement(s)
			else: _need_settlement(); return false
		"tech_boon":
			if s != null: sim.grant_tech(s)
			else: _need_settlement(); return false
		"leader":
			if s != null: sim.god_new_leader(s)
			else: _need_settlement(); return false
		"war":
			if s != null:
				var other := sim._nearest_other(s, 80.0)
				if other != null:
					sim.declare_war(s, other, "god")
				else:
					if hud != null: hud.toast(L.t("relations_none"), "error")
			else: _need_settlement(); return false
		"peace":
			if s != null:
				for other_id in s.wars.duplicate():
					var o: SettlementData = sim.settlement_by_id.get(other_id, null)
					if o != null:
						sim.make_peace(s, o, false)
			else: _need_settlement(); return false
		"prophet":
			if s != null: sim.prophet(s)
			else: _need_settlement(); return false
		"miracle":
			if s != null: sim.miracle(s)
			else: _need_settlement(); return false
		_:
			pass
	if hud != null:
		hud.update_essence(essence, sandbox)
	return true


func _need_settlement() -> void:
	if hud != null:
		hud.toast(L.t("target_settlement"), "error")
	SFX.ui_error()


func _spend(cost: float) -> bool:
	if sandbox:
		return true
	if essence < cost:
		if hud != null:
			hud.toast(L.t("toast_no_essence"), "error")
		SFX.ui_error()
		return false
	essence -= cost
	return true


# ------------------------------------------------------------------ undo

func _snapshot_cell(cell: Vector2i, radius: float) -> Dictionary:
	var r := int(ceil(radius)) + 1
	var x0 := maxi(0, cell.x - r)
	var z0 := maxi(0, cell.y - r)
	var x1 := mini(world.size - 1, cell.x + r)
	var z1 := mini(world.size - 1, cell.y + r)
	var w := x1 - x0 + 1
	var h := z1 - z0 + 1
	var hh := PackedFloat32Array(); hh.resize(w * h)
	var ww := PackedFloat32Array(); ww.resize(w * h)
	var vv := PackedFloat32Array(); vv.resize(w * h)
	var tt := PackedFloat32Array(); tt.resize(w * h)
	var mm := PackedFloat32Array(); mm.resize(w * h)
	var bi := PackedByteArray(); bi.resize(w * h)
	var rt := PackedByteArray(); rt.resize(w * h)
	var ra := PackedFloat32Array(); ra.resize(w * h)
	var k := 0
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := world.idx(x, z)
			hh[k] = world.heights[i]
			ww[k] = world.water[i]
			vv[k] = world.vegetation[i]
			tt[k] = world.temperature[i]
			mm[k] = world.moisture[i]
			bi[k] = world.biome_ids[i]
			rt[k] = world.res_type[i]
			ra[k] = world.res_amount[i]
			k += 1
	return {"rect": Rect2i(x0, z0, w, h), "heights": hh, "water": ww, "vegetation": vv, "temperature": tt, "moisture": mm, "biomes": bi, "res_type": rt, "res_amount": ra}


func _push_undo(cell: Vector2i, radius: float) -> void:
	undo_stack.append(_snapshot_cell(cell, radius))
	if undo_stack.size() > 16:
		undo_stack.pop_front()
	redo_stack.clear()


func _apply_snapshot(snap: Dictionary) -> void:
	var rect: Rect2i = snap.rect
	var k := 0
	for z in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var i := world.idx(x, z)
			world.heights[i] = snap.heights[k]
			world.water[i] = snap.water[k]
			world.vegetation[i] = snap.vegetation[k]
			world.temperature[i] = snap.temperature[k]
			world.moisture[i] = snap.moisture[k]
			world.biome_ids[i] = snap.biomes[k]
			world.res_type[i] = snap.res_type[k]
			world.res_amount[i] = snap.res_amount[k]
			k += 1
	world._recount()
	terrain_view.rebuild_rect(rect)
	nature_view.mark_dirty_rect(rect)
	terrain_view.minimap_dirty = true


func _undo() -> void:
	if undo_stack.is_empty():
		SFX.ui_error()
		return
	var snap: Dictionary = undo_stack.pop_back()
	redo_stack.append(_snapshot_cell(snap.rect.position + snap.rect.size / 2, maxf(snap.rect.size.x, snap.rect.size.y) * 0.5))
	_apply_snapshot(snap)
	SFX.ui_back()


func _redo() -> void:
	if redo_stack.is_empty():
		SFX.ui_error()
		return
	var snap: Dictionary = redo_stack.pop_back()
	undo_stack.append(_snapshot_cell(snap.rect.position + snap.rect.size / 2, maxf(snap.rect.size.x, snap.rect.size.y) * 0.5))
	_apply_snapshot(snap)
	SFX.ui_confirm()


# ------------------------------------------------------------------ events

func _on_screen_flash(color: Color, alpha: float) -> void:
	if hud != null:
		hud.flash(color, alpha)


func _on_chronicle_event(e: Dictionary) -> void:
	if hud != null:
		hud.add_event(e)


func _on_toast(text: String, kind: String) -> void:
	if hud != null:
		hud.toast(text, kind)


func hud_toast_later(text: String, kind: String) -> void:
	if hud != null:
		hud.toast(text, kind)


func _on_era_changed(id: int, era: int) -> void:
	if hud != null and (selected_settlement_id < 0 or id == selected_settlement_id):
		var s: SettlementData = sim.settlement_by_id.get(id, null)
		if s != null:
			hud.era_banner(L.tc(D.era(era)) + "\n" + s.name)


func _on_disaster(kind: String, pos: Vector2, radius: float) -> void:
	if hud != null and kind in ["nuke", "meteor", "volcano"]:
		hud.flash(Color(1, 0.8, 0.5) if kind != "nuke" else Color(1, 1, 1), 0.3)


func _tutorial_check() -> void:
	if hud == null or tutorial_done:
		return
	hud.update_tutorial(tutorial_flags, false)
	if tutorial_flags.select and tutorial_flags.mountain and tutorial_flags.lightning and tutorial_flags.speed:
		tutorial_done = true
		_save_tutorial_done()
		hud.tutorial_complete()


func _start_tutorial() -> void:
	if tutorial_done:
		return
	tutorial_flags = {"select": false, "mountain": false, "lightning": false, "speed": false}
	if hud != null:
		hud.show_tutorial()


func _save_tutorial_done() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("game", "tutorial_done", true)
	cfg.save("user://settings.cfg")


# ------------------------------------------------------------------ save / load

func _enc_f32(arr: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(arr.to_byte_array())


func _enc_bytes(arr: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(arr)


func _dec_f32(s: String) -> PackedFloat32Array:
	if s.is_empty():
		return PackedFloat32Array()
	var raw := Marshalls.base64_to_raw(s)
	return raw.to_float32_array()


func _dec_bytes(s: String) -> PackedByteArray:
	if s.is_empty():
		return PackedByteArray()
	return Marshalls.base64_to_raw(s)


func _world_dict() -> Dictionary:
	return {
		"size": world.size, "seed": world.seed, "preset": world.preset_id,
		"name": world.world_name, "sea_level": world.sea_level,
		"heights": _enc_f32(world.heights),
		"moisture": _enc_f32(world.moisture),
		"temperature": _enc_f32(world.temperature),
		"vegetation": _enc_f32(world.vegetation),
		"water": _enc_f32(world.water),
		"radiation": _enc_f32(world.radiation),
		"burn": _enc_f32(world.burn),
		"biomes": _enc_bytes(world.biome_ids),
		"res_type": _enc_bytes(world.res_type),
		"res_amount": _enc_f32(world.res_amount)
	}


func to_save_dict() -> Dictionary:
	return {
		"world_name": world_name,
		"seed": world.seed,
		"year": sim.year,
		"population": sim.total_population,
		"essence": essence,
		"sandbox": sandbox,
		"config": config,
		"world": _world_dict(),
		"sim": sim.to_dict(),
		"camera": {
			"target": [camera_rig.smooth_target.x, camera_rig.smooth_target.y, camera_rig.smooth_target.z],
			"yaw": camera_rig.yaw, "pitch": camera_rig.pitch, "dist": camera_rig.distance
		},
		"play_seconds": play_seconds
	}


func save_to_slot(slot: int, silent: bool = false) -> bool:
	var ok := Save.save_world(slot, to_save_dict())
	if ok:
		save_dirty = false
		if hud != null:
			hud.toast(L.t("toast_autosave") if silent else L.t("toast_saved"), "save")
	else:
		if hud != null:
			hud.toast("Save error", "error")
	return ok


func _screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var img := get_viewport().get_texture().get_image()
	var name := "aetheria_%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	img.save_png("user://screenshots/" + name)
	if hud != null:
		hud.toast("Screenshot: " + name, "save")
	SFX.ui_confirm()


func exit_game() -> void:
	back_to_menu.emit()


func get_selected_settlement() -> SettlementData:
	return sim.settlement_by_id.get(selected_settlement_id, null) if sim != null else null

func get_selected_agent() -> AgentData:
	return sim.agent_by_id.get(selected_agent_id, null) if sim != null else null
