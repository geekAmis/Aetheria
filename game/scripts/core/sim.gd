class_name SimWorld
extends RefCounted
## Детерминированная симуляция мира: существа, животные, поселения,
## экономика, технологии, политика, войны, катастрофы и хроника.
## Ничего не знает о рендере; общается через сигналы.

signal chronicle_added(entry: Dictionary)
signal agent_spawned(agent: AgentData)
signal agent_died(agent: AgentData, cause: String)
signal settlement_founded(s: SettlementData)
signal settlement_structure_changed(id: int)
signal settlement_changed(id: int)
signal era_changed(id: int, era: int)
signal war_declared(a: int, b: int)
signal war_ended(a: int, b: int)
signal effect(kind: String, pos: Vector2, radius: float, data: Dictionary)
signal toast(text: String, kind: String)
signal disaster(kind: String, pos: Vector2, radius: float)
signal nuclear_winter_started()

var world: WorldModel
var agents: Array = []
var agent_by_id: Dictionary = {}
var settlements: Array = []
var settlement_by_id: Dictionary = {}
var animals: Array = []
var animal_by_id: Dictionary = {}
var chronicle: ChronicleData

var day: float = 0.0
var year: int = 1
var season: int = 0
var total_population: int = 0
var next_agent_id: int = 1
var next_settlement_id: int = 1
var next_animal_id: int = 1
var rng := RandomNumberGenerator.new()
var difficulty: Dictionary = {}
var config: Dictionary = {}
var weather_mode: String = "clear"
var weather_days_left: int = 90
var nuclear_winter: float = 0.0
var nukes_total: int = 0
var war_intensity: float = 0.0
var burning: Dictionary = {}  # cell index -> intensity
var event_cooldowns: Dictionary = {}
var last_population_record_year: int = -1
var world_age_years: int = 0
var animals_cap: int = 240
var selected_settlement_id: int = -1
var bulk_mode := false


func setup(p_world: WorldModel, p_config: Dictionary) -> void:
	world = p_world
	config = p_config
	difficulty = D.difficulty(str(config.get("difficulty", "normal")))
	rng.seed = p_world.seed * 31 + 7
	chronicle = ChronicleData.new()
	day = 0.0
	year = 1
	season = 0
	nuclear_winter = 0.0
	nukes_total = 0
	war_intensity = 0.0
	agents.clear(); agent_by_id.clear(); settlements.clear(); settlement_by_id.clear()
	animals.clear(); animal_by_id.clear()
	next_agent_id = 1; next_settlement_id = 1; next_animal_id = 1
	burning.clear()
	event_cooldowns.clear()


func populate(progress: Callable = Callable()) -> void:
	var tribe_count := int(config.get("tribes", 6))
	var sites: Array = world.find_settlement_sites(tribe_count, 20.0)
	if sites.is_empty():
		sites = world.find_settlement_sites(1, 4.0)
	for site in sites:
		var s := SettlementData.new()
		s.setup(next_settlement_id, str(site.race), site.cell, year, rng)
		s.name = _unique_name(s.name, s.id)
		next_settlement_id += 1
		# стартовые постройки
		s.add_building("hut", s.center.x + 1.4, s.center.y + 0.8, rng.randf() * TAU, year)
		s.add_building("farm", s.center.x - 1.6, s.center.y + 1.6, rng.randf() * TAU, year)
		settlements.append(s)
		settlement_by_id[s.id] = s
		world.add_clearing(s.center, 9.0)
		var adults := rng.randi_range(9, 13)
		for i in adults:
			var gender := rng.randi() % 2
			var age := rng.randf_range(18.0, 45.0)
			spawn_agent(s, age, gender, "worker", Vector2(s.center) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
		for i in rng.randi_range(2, 4):
			spawn_agent(s, rng.randf_range(0.5, 12.0), rng.randi() % 2, "child", Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
		_assign_leader(s)
		# отношения
		for other in settlements:
			if other.id != s.id:
				s.relations[other.id] = rng.randi_range(-8, 12)
				other.relations[s.id] = s.relations[other.id]
		var e := {
			"year": year, "day": int(day), "type": "founded", "importance": 2,
			"text": L.tf("city_founded", [s.name]), "settlement_id": s.id,
			"pos": [s.center.x, s.center.y], "icon": "people"
		}
		chronicle.add(year, int(day), "founded", e.text, 2, s.id, Vector2(s.center), "people")
		chronicle_added.emit(e)
		settlement_founded.emit(s)
	_spawn_initial_animals()
	_update_settlement_counts()
	_record_population()
	if progress.is_valid():
		progress.call(0.98)
	chronicle.add(year, 0, "world", "%s: мир пробуждается. %d племён зажигают первые костры." % [world.world_name, settlements.size()], 3, -1, Vector2.ZERO, "spark")


# ------------------------------------------------------------------ main tick

func step_day() -> void:
	day += 1.0
	year = 1 + int(day / 365.0)
	season = int(fposmod(day, 365.0) / 91.25)
	if nuclear_winter > 0.0:
		nuclear_winter = maxf(0.0, nuclear_winter - 1.0)
	_refresh_weather()
	_world_daily()
	_update_settlement_counts()
	_agents_daily()
	_settlements_daily()
	_animals_daily()
	_diplomacy_daily()
	_fire_daily()
	_radiation_daily()
	_random_events_daily()
	if year != world_age_years:
		world_age_years = year
		_yearly()
	war_intensity = clampf(float(_active_wars_count()) / 2.0, 0.0, 1.0)


func _refresh_weather() -> void:
	if weather_days_left > 0:
		weather_days_left -= 1
		return
	var roll := rng.randf()
	if nuclear_winter > 0.0:
		weather_mode = "ash" if roll < 0.5 else "snow"
	elif season == 3 and roll < 0.45:
		weather_mode = "snow"
	elif roll < 0.16:
		weather_mode = "rain"
	elif roll < 0.17:
		weather_mode = "fog"
	else:
		weather_mode = "clear"
	weather_days_left = rng.randi_range(60, 200)


func _active_wars_count() -> int:
	var c := 0
	for s in settlements:
		if not s.destroyed:
			c += s.wars.size()
	return int(c / 2)


func _world_daily() -> void:
	# рост растительности — 1/8 карты в день
	var offset := int(day) % 8
	var n := world.n()
	var fert := world.fertility
	for i in range(offset, n, 8):
		if world.water[i] > 0.0004:
			continue
		var cap: float = float(fert[i]) * 1.05
		var v := world.vegetation[i]
		if v < cap:
			var temp_f := 1.0
			if world.temperature[i] < 0.12:
				temp_f = 0.3
			if nuclear_winter > 0.0:
				temp_f *= 0.35
			world.vegetation[i] = clampf(v + 0.006 * world.moisture[i] * temp_f, 0.0, 1.0)
	# тушение пожара дождём
	if weather_mode == "rain" and burning.size() > 0:
		var keys := burning.keys()
		for k in keys:
			burning[k] = maxf(0.0, float(burning[k]) - 0.35)
			world.burn[k] = burning[k]
			if burning[k] <= 0.01:
				burning.erase(k)


func _update_settlement_counts() -> void:
	for s in settlements:
		s.population = 0
		s.age_sum = 0.0
	for a in agents:
		if not a.alive:
			continue
		var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
		if s != null and not s.destroyed:
			s.population += 1
			s.age_sum += a.age
	total_population = 0
	for s in settlements:
		if not s.destroyed:
			total_population += s.population
			s._update_stage(s.population)


func _agents_daily() -> void:
	var to_kill: Array = []
	var lifespan_mult: float = 1.0
	for a in agents:
		if not a.alive:
			continue
		a.age += 1.0 / 365.0
		var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
		# потребности
		a.satiety -= 9.0
		a.thirst -= 15.0
		a.energy -= 17.0
		if a.satiety < 32.0:
			if s != null and s.resources.get("food", 0.0) > 0.3 and not s.destroyed:
				s.resources["food"] = float(s.resources["food"]) - 0.35
				a.satiety = minf(100.0, a.satiety + 42.0)
			else:
				var ac := world.cell_of(a.pos)
				var ci := world.idx(ac.x, ac.y)
				if world.vegetation[ci] > 0.25:
					a.satiety = minf(100.0, a.satiety + 18.0)
					world.vegetation[ci] = maxf(0.0, world.vegetation[ci] - 0.02)
		if a.thirst < 30.0:
			var has_water := false
			if s != null and s.water_cell.x >= 0:
				has_water = a.pos.distance_squared_to(Vector2(s.water_cell)) < 144.0
			if has_water or _near_water(a.pos, 6):
				a.thirst = minf(100.0, a.thirst + 55.0)
		if a.energy < 18.0:
			a.energy = minf(100.0, a.energy + 55.0)
		a.energy = minf(100.0, a.energy + 4.0)
		# здоровье
		if a.satiety <= 0.0:
			a.health -= a.max_health * 0.09
			a.satiety = 0.0
		if a.thirst <= 0.0:
			a.health -= a.max_health * 0.12
			a.thirst = 0.0
		if a.satiety > 45.0 and a.thirst > 40.0 and a.health < a.max_health:
			a.health = minf(a.max_health, a.health + a.max_health * 0.03)
		if s != null:
			a.mood = move_toward(a.mood, s.happiness * 0.6, 0.8)
			if s.plague > 0.0:
				if rng.randf() < 0.0018:
					a.health -= a.max_health * 0.5
			if s.radioactive > 0.0:
				a.health -= a.max_health * 0.002
			if s.cursed > 0.0:
				a.sanity = maxf(0.0, a.sanity - 0.5)
				a.mood -= 0.4
		if a.pregnant > 0.0:
			a.pregnant -= 1.0
			if a.pregnant <= 0.0:
				_give_birth(a)
		# старость
		var lifespan: float = a.lifespan() * lifespan_mult
		if a.age >= lifespan:
			if rng.randf() < 0.12:
				to_kill.append([a, "old_age"])
		# болезни/голод
		if a.health <= 0.0:
			var cause := "hunger" if a.satiety <= 0.0 else ("thirst" if a.thirst <= 0.0 else ("plague" if s != null and s.plague > 0.0 else "health"))
			to_kill.append([a, cause])
		# безумие
		if a.sanity < 15.0 and rng.randf() < 0.002 and s != null:
			s.stability = maxf(0.0, s.stability - 1.0)
	for pair in to_kill:
		kill_agent(pair[0], pair[1])


func _settlements_daily() -> void:
	var groups: Dictionary = {}
	for a in agents:
		if not a.alive:
			continue
		var gid: int = a.settlement_id
		if not groups.has(gid):
			groups[gid] = []
		groups[gid].append(a)
	for s in settlements:
		if s.destroyed:
			continue
		var local: Array = groups.get(s.id, [])
		var mods: Dictionary = s.tech_mods()
		var prod: Dictionary = s.production(season, day)
		var cons: Dictionary = s.consumption()
		# производство
		for k in prod:
			s.resources[k] = float(s.resources.get(k, 0.0)) + float(prod[k])
		# потребление
		s.resources["food"] = float(s.resources.get("food", 0.0)) - float(cons["food"])
		s.resources["goods"] = maxf(0.0, float(s.resources.get("goods", 0.0)) - float(cons["goods"]))
		s.resources["gold"] = maxf(0.0, float(s.resources.get("gold", 0.0)) - float(cons["gold"]))
		# порча еды
		if s.resources["food"] > 0.0:
			s.resources["food"] = float(s.resources["food"]) * 0.9995
		var cap: float = s.storage_cap()
		for k in ["food", "wood", "stone", "iron", "gold", "goods"]:
			s.resources[k] = clampf(float(s.resources.get(k, 0.0)), 0.0, cap)
		if s.resources["food"] <= 0.0:
			s.happiness -= 0.35
			s.stability = maxf(0.0, s.stability - 0.15)
		# счастье
		var temple: float = s.building_count("temple") * 3.0
		var target_h: float = 8.0 + temple + s.faith * 0.05 - float(s.wars.size()) * 10.0 + s.blessed * 0.05
		if s.resources["food"] < s.population * 0.2:
			target_h -= 18.0
		if s.population > s.max_pop():
			target_h -= 10.0
		target_h += (s.prosperity - 1.0) * 12.0
		s.happiness = move_toward(s.happiness, target_h, 0.35)
		s.happiness = clampf(s.happiness, -100.0, 100.0)
		# стабильность
		var target_st: float = 68.0 + s.happiness * 0.15 - float(s.wars.size()) * 8.0
		if s.plague > 0.0: target_st -= 20.0
		if s.radioactive > 0.0: target_st -= 15.0
		s.stability = move_toward(s.stability, clampf(target_st, 0.0, 100.0), 0.2)
		# процветание
		s.prosperity = clampf(0.65 + (float(s.resources["food"]) + float(s.resources["wood"]) + float(s.resources["gold"]) * 3.0) / maxf(30.0, s.population * 8.0), 0.5, 1.6)
		# флаги
		if s.plague > 0.0: s.plague = maxf(0.0, s.plague - 1.0)
		if s.fire > 0.0: s.fire = maxf(0.0, s.fire - 1.0)
		if s.drought > 0.0: s.drought = maxf(0.0, s.drought - 1.0)
		if s.blizzard > 0.0: s.blizzard = maxf(0.0, s.blizzard - 1.0)
		if s.blessed > 0.0: s.blessed = maxf(0.0, s.blessed - 0.25)
		if s.cursed > 0.0: s.cursed = maxf(0.0, s.cursed - 0.2)
		if s.radioactive > 0.0: s.radioactive = maxf(0.0, s.radioactive - 0.002)
		if s.war_days > 0: s.war_days += 1
		# армия
		var warriors := 0
		for a in local:
			if a.role == "warrior":
				warriors += 1
		s.army = warriors
		_construction_tick(s)
		_research_tick(s, prod)
		_reproduction_tick(s, mods, local)
		_siege_tick(s, local, groups)
		_assign_targets(s, local)
		if s.population <= 0 and not s.destroyed:
			_destroy_settlement(s, "empty")
	for s in settlements:
		if s.destroyed:
			s.resources["food"] = 0.0
			s.resources["wood"] = 0.0


func _construction_tick(s: SettlementData) -> void:
	if s.construction.is_empty():
		_choose_construction(s)
		return
	var c := s.construction
	c["progress"] = float(c.get("progress", 0.0)) + 1.0
	var days := float(c.get("days", 8.0))
	if float(c.progress) >= days:
		var type := str(c.type)
		s.add_building(type, float(c.x), float(c.z), float(c.rot), year)
		s.construction = {}
		settlement_structure_changed.emit(s.id)
		if type in ["temple", "library", "monument", "walls", "granary", "university"]:
			var text := "%s построило %s" % [s.name, D.building(type).get("name", type)]
			_add_event(s, "build", text, 2, "build")
		if s.population >= 12 and s.stage == "camp":
			s._update_stage(s.population)


func _choose_construction(s: SettlementData) -> void:
	if s.buildings.size() >= s.max_buildings():
		return
	if s.resources.get("wood", 0.0) < 5.0:
		return
	var need: String = ""
	if s.population > s.housing() - 2:
		need = "hut"
	elif s.resources.get("food", 0.0) < s.population * 0.6:
		need = "farm"
	elif s.resources.get("wood", 0.0) < 25.0:
		need = "lumber"
	elif s.era >= 1 and s.resources.get("stone", 0.0) < 25.0:
		need = "quarry"
	elif s.era >= 2 and not s.has_building("mine"):
		need = "mine"
	elif s.era >= 1 and s.building_count("granary") < 1:
		need = "granary"
	elif s.era >= 1 and s.happiness < 5.0 and not s.has_building("temple"):
		need = "temple"
	elif s.era >= 3 and not s.has_building("library"):
		need = "library"
	elif s.era >= 2 and s.resources.get("gold", 0.0) > 30.0 and not s.has_building("market"):
		need = "market"
	elif s.resources.get("iron", 0.0) > 20.0 and not s.has_building("workshop"):
		need = "workshop"
	elif s.era >= 2 and s.building_count("barracks") < 1:
		need = "barracks"
	elif s.era >= 3 and s.building_count("monument") < 1:
		need = "monument"
	elif s.era >= 4 and s.building_count("university") < 1:
		need = "university"
	elif s.era >= 5 and s.building_count("factory") < 1:
		need = "factory"
	elif s.era >= 6 and s.building_count("power") < 1:
		need = "power"
	elif s.era >= 6 and s.building_count("lab") < 1:
		need = "lab"
	elif s.era >= 7 and s.building_count("silo") < 1:
		need = "silo"
	elif s.era >= 7 and s.building_count("spaceport") < 1:
		need = "spaceport"
	else:
		var pool := s.available_buildings()
		if pool.is_empty():
			return
		need = str(pool[rng.randi() % pool.size()].id)
	var bd: Dictionary = D.building(need)
	var cost_wood := float(bd.get("wood", 0))
	var cost_stone := float(bd.get("stone", 0))
	var cost_iron := float(bd.get("iron", 0))
	if s.resources.get("wood", 0.0) < cost_wood or s.resources.get("stone", 0.0) < cost_stone or s.resources.get("iron", 0.0) < cost_iron:
		return
	s.resources["wood"] = float(s.resources["wood"]) - cost_wood
	s.resources["stone"] = float(s.resources["stone"]) - cost_stone
	s.resources["iron"] = float(s.resources["iron"]) - cost_iron
	var spot := _find_building_spot(s)
	if spot.x < 0:
		# вернуть ресурсы
		s.resources["wood"] = float(s.resources["wood"]) + cost_wood
		s.resources["stone"] = float(s.resources["stone"]) + cost_stone
		s.resources["iron"] = float(s.resources["iron"]) + cost_iron
		return
	s.construction = {"type": need, "progress": 0.0, "x": spot.x, "z": spot.y, "rot": rng.randf() * TAU, "days": clampf(5.0 + (cost_wood + cost_stone) / 14.0, 6.0, 30.0)}


func _find_building_spot(s: SettlementData) -> Vector2:
	var best := Vector2(-1, -1)
	var radius := maxf(3.0, minf(9.0, s.territory_radius * 0.55))
	for attempt in 26:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(1.8, radius)
		var p := Vector2(s.center) + Vector2(cos(ang), sin(ang)) * r
		var cell := world.cell_of(p)
		if not world.is_land_cell(cell.x, cell.y):
			continue
		if world.water[world.idx(cell.x, cell.y)] > 0.0004:
			continue
		var b := world.biome_name_at(cell.x, cell.y)
		if b in ["ocean", "shallow", "reef", "river", "lake", "swamp"]:
			continue
		var ok := true
		for bd in s.buildings:
			if Vector2(float(bd.x), float(bd.z)).distance_to(p) < 1.35:
				ok = false
				break
		if s.construction.size() > 0:
			if Vector2(float(s.construction.get("x", 0)), float(s.construction.get("z", 0))).distance_to(p) < 1.35:
				ok = false
		if ok:
			return p
	return best


func _research_tick(s: SettlementData, prod: Dictionary) -> void:
	if s.era >= D.eras.size():
		return
	if s.researching.is_empty():
		var pool: Array = []
		for t in D.era_techs.get(s.era, []):
			if not s.techs.has(t.id):
				pool.append(t)
		if pool.is_empty():
			_advance_era(s)
			return
		pool.sort_custom(func(a, b): return int(a.cost) < int(b.cost))
		s.researching = str(pool[0].id)
		s.research_progress = 0.0
	var sci := float(prod.get("science", 0.0)) * (1.0 + float(s.tech_mods().get("science", 0.0))) * float(difficulty.get("tech", 1.0))
	# реальное время: наука идёт медленнее, чтобы эпохи длились
	s.research_progress += sci * 0.65
	var cost := s.research_cost()
	if s.research_progress >= cost:
		var t: Dictionary = D.tech(s.researching)
		s.techs.append(s.researching)
		s.era_techs_done += 1
		s.research_progress = 0.0
		var tid := s.researching
		s.researching = ""
		_add_event(s, "tech", L.tf("tech_discovered_ev", [s.name, L.tc(t)]), 2, "tech")
		if s.id == selected_settlement_id:
			toast.emit("%s: %s" % [s.name, L.tc(t)], "tech")
		if s.era_techs_done >= 4:
			_advance_era(s)


func _advance_era(s: SettlementData) -> void:
	if s.era >= D.eras.size() - 1:
		if s.researching.is_empty():
			s.era_techs_done = 0
		return
	s.era += 1
	s.era_techs_done = 0
	s.researching = ""
	s.research_progress = 0.0
	s.happiness = minf(100.0, s.happiness + 12.0)
	var er: Dictionary = D.era(s.era)
	_add_event(s, "era", L.tf("era_advanced_ev", [s.name, L.tc(er)]), 3, "era")
	era_changed.emit(s.id, s.era)
	_mark_troops_equipment(s)


func _reproduction_tick(s: SettlementData, mods: Dictionary, local: Array) -> void:
	if s.population >= s.max_pop():
		return
	if s.resources.get("food", 0.0) < 20.0:
		return
	if s.plague > 0.0 or s.radioactive > 0.0:
		return
	var housing_mod := clampf(float(s.housing()) / maxf(1.0, s.population / 2.0), 0.3, 1.2)
	var food_mod := clampf(float(s.resources["food"]) / maxf(1.0, s.population), 0.5, 1.5)
	var mood_mod := clampf(1.0 + s.happiness / 80.0, 0.5, 1.3)
	var base := 0.00042 * float(mods.get("growth", 0.0) + 1.0) * food_mod * housing_mod * mood_mod * float(difficulty.get("growth", 1.0))
	var women: Array = []
	for a in local:
		if a.alive and a.gender == 1 and a.is_adult() and a.pregnant <= 0.0 and a.age < 48.0 and a.health > a.max_health * 0.4:
			women.append(a)
	if women.is_empty():
		return
	var chance := base * women.size()
	if rng.randf() < chance:
		var mother: AgentData = women[rng.randi() % women.size()]
		var father: AgentData = null
		if mother.partner_id > 0:
			father = agent_by_id.get(mother.partner_id, null)
		if father == null:
			var men: Array = []
			for a in local:
				if a.alive and a.gender == 0 and a.is_adult() and a.age < 60.0 and a.health > a.max_health * 0.4:
					men.append(a)
					if men.size() >= 8:
						break
			if men.size() > 0:
				father = men[rng.randi() % men.size()]
		mother.pregnant = 150.0
		if father != null:
			mother.father_id = father.id
			mother.partner_id = father.id
			father.partner_id = mother.id
		for a in local:
			if a.alive and a.is_adult() and a.gender == 0 and a.partner_id < 0 and rng.randf() < 0.08:
				a.partner_id = mother.id
				break


func _give_birth(mother: AgentData) -> void:
	var s: SettlementData = settlement_by_id.get(mother.settlement_id, null)
	if s == null or s.destroyed:
		return
	var child := spawn_agent(s, 0.0, rng.randi() % 2, "child", Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
	child.level = 1
	child.health = child.max_health
	child.power = clampf(mother.power * 0.55 + 10.0, 5, 100)
	child.wisdom = clampf(mother.wisdom * 0.55 + 10.0, 5, 100)
	child.agility = clampf(mother.agility * 0.55 + 10.0, 5, 100)
	child.magic = clampf(mother.magic * 0.6, 0, 100)
	child.max_health = child.compute_max_health()
	child.health = child.max_health
	if mother.father_id > 0:
		child.father_id = mother.father_id
		var f: AgentData = agent_by_id.get(mother.father_id, null)
		if f != null:
			f.children.append(child.id)
			child.power = clampf((child.power + f.power) * 0.5, 5, 100)
	mother.children.append(child.id)
	s.total_births += 1
	s.resources["food"] = maxf(0.0, float(s.resources["food"]) - 2.0)
	if s.total_births in [1, 10, 50, 100, 250, 500] or (mother.notable):
		_add_event(s, "birth", "В %s родился %s" % [s.name, child.display_name()], 1, "birth")


func _siege_tick(s: SettlementData, local: Array, groups: Dictionary) -> void:
	if s.war_target < 0 or s.wars.is_empty():
		return
	var enemy: SettlementData = settlement_by_id.get(s.war_target, null)
	if enemy == null or enemy.destroyed:
		s.war_target = -1
		s.wars.clear()
		return
	var attackers: Array = []
	var defenders: Array = []
	for a in local:
		if a.alive and a.role == "warrior":
			if a.pos.distance_to(Vector2(enemy.center)) < 20.0:
				attackers.append(a)
	var enemy_list: Array = groups.get(enemy.id, [])
	for a in enemy_list:
		if a.alive:
			if a.pos.distance_to(Vector2(enemy.center)) < 16.0:
				defenders.append(a)
	if attackers.is_empty():
		return
	if defenders.is_empty() and s.war_days > 4:
		s.siege_days += 1
		if s.siege_days >= 4:
			_sack_settlement(s, enemy)
		return
	var rounds := mini(18, attackers.size())
	for i in rounds:
		if defenders.is_empty():
			break
		var att: AgentData = attackers[rng.randi() % attackers.size()]
		var def: AgentData = defenders[rng.randi() % defenders.size()]
		var hit := rng.randf() < clampf(0.75 + (att.agility - def.agility) * 0.005, 0.25, 0.95)
		if hit:
			var dmg := att.attack_value() * rng.randf_range(0.6, 1.25)
			dmg *= (1.0 - def.defense_value() / (def.defense_value() + 100.0))
			def.health -= dmg
			att.add_xp(4.0)
			effect.emit("hit", def.pos, 1.0, {})
			if def.health <= 0.0:
				att.kills += 1
				att.add_xp(35.0)
				kill_agent(def, "battle")
				defenders.erase(def)
				if att.level >= 8 and rng.randf() < 0.1:
					att.notable = true
	# урон по зданиям
	for i in 3:
		if enemy.buildings.is_empty():
			break
		var idxb := rng.randi() % enemy.buildings.size()
		var bd: Dictionary = enemy.buildings[idxb]
		bd["hp"] = float(bd.get("hp", 100.0)) - rng.randf_range(8.0, 22.0)
		if float(bd.hp) <= 0.0:
			enemy.buildings.remove_at(idxb)
			settlement_structure_changed.emit(enemy.id)
	# если защитников мало — сжечь
	if defenders.size() < attackers.size() / 4 and rng.randf() < 0.3:
		_ignite_cells(enemy.center.x, enemy.center.y, 4, 0.6)


func _sack_settlement(att: SettlementData, def: SettlementData) -> void:
	var loot := def.resources.duplicate()
	for k in ["food", "wood", "stone", "iron", "gold"]:
		att.resources[k] = minf(att.storage_cap(), float(att.resources.get(k, 0.0)) + float(loot.get(k, 0.0)) * 0.5)
	def.resources = {"food": 0.0, "wood": 0.0, "stone": 0.0, "iron": 0.0, "gold": 0.0, "goods": 0.0}
	# гибель части населения
	var victims: Array = []
	for a in agents:
		if a.settlement_id == def.id and a.alive:
			if rng.randf() < 0.35:
				victims.append(a)
	for a in victims:
		kill_agent(a, "battle")
	def.buildings.clear()
	settlement_structure_changed.emit(def.id)
	_add_event(def, "war", "%s разграблено армией %s" % [def.name, att.name], 4, "war")
	_destroy_settlement(def, "sack")
	make_peace(att, def, true)


func _destroy_settlement(s: SettlementData, reason: String) -> void:
	if s.destroyed:
		return
	s.destroyed = true
	s.stage = "ruins"
	s.wars.clear()
	s.war_target = -1
	s.researching = ""
	s.buildings.clear()
	_add_event(s, "war", L.tf("city_destroyed", [s.name]), 4, "ruin")
	var refuge: SettlementData = null
	var best_d := 9999.0
	for other in settlements:
		if other.id == s.id or other.destroyed:
			continue
		var d := Vector2(other.center).distance_to(Vector2(s.center))
		if d < 55.0 and d < best_d:
			best_d = d
			refuge = other
	var refugees: Array = []
	for a in agents:
		if a.settlement_id == s.id and a.alive:
			refugees.append(a)
	for a in refugees:
		if refuge != null:
			a.settlement_id = refuge.id
			a.role = "worker"
			a.target = Vector2(refuge.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		else:
			kill_agent(a, "war")
	if reason == "empty":
		_add_event(s, "death", "%s опустело" % s.name, 2, "ruin")


func _animals_daily() -> void:
	var newborns: Array = []
	var dead: Array = []
	var parity := int(day) % 2
	for an in animals:
		if not an.alive:
			continue
		if int(an.id) % 2 != parity:
			continue
		an.age = float(an.age) + 1.0 / 365.0
		var lifespan := 18.0
		if an.age > lifespan or rng.randf() < 0.000024:
			an.alive = false
			dead.append(an)
			continue
		# бродяжничество
		if rng.randf() < 0.45:
			var c := world.cell_of(an.pos)
			for attempt in 3:
				var p := Vector2(c) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
				var cc := world.cell_of(p)
				if world.is_land_cell(cc.x, cc.y):
					an.target = p
					break
		# размножение
		if an.breed_cd <= 0.0 and rng.randf() < float(an.breed) * 0.12:
			an.breed_cd = 60.0
			if animals.size() + newborns.size() < animals_cap:
				newborns.append(an.species)
		else:
			an.breed_cd = maxf(0.0, an.breed_cd - 0.5)
		# хищники
		if bool(an.predator) and rng.randf() < 0.03:
			var victim: AgentData = _agent_near(an.pos, 1.6)
			if victim != null:
				victim.health -= float(an.power) * rng.randf_range(0.5, 1.4)
				effect.emit("battle", victim.pos, 1.0, {})
				if victim.health <= 0.0:
					kill_agent(victim, "beast")
		# охота поселений
		if rng.randf() < 0.03:
			var sc := world.cell_of(an.pos)
			var owner := _settlement_near(sc, 12)
			if owner != null and owner.resources.get("food", 0.0) < owner.population * 0.35:
				owner.resources["food"] = float(owner.resources["food"]) + float(an.size) * 40.0
				an.alive = false
				dead.append(an)
				effect.emit("hunt", an.pos, 1.0, {})
	for sp2 in newborns:
		var c2 := _random_cell_for_species(str(sp2))
		if c2.x >= 0:
			_spawn_animal(str(sp2), c2)
	for an2 in dead:
		animals.erase(an2)
		animal_by_id.erase(an2.id)


func _diplomacy_daily() -> void:
	# раз в день — небольшая проверка, основные решения в _yearly
	for s in settlements:
		if s.destroyed:
			continue
		for other in settlements:
			if other.id <= s.id or other.destroyed:
				continue
			var rel := float(s.relations.get(other.id, 0.0))
			# дрейф и торговля
			if s.wars.has(other.id):
				continue
			var dist := Vector2(s.center).distance_to(Vector2(other.center))
			if dist < 46.0:
				rel += rng.randf_range(-0.04, 0.035)
			else:
				rel += rng.randf_range(-0.015, 0.02)
			s.relations[other.id] = clampf(rel, -100.0, 100.0)
			other.relations[s.id] = s.relations[other.id]
			# война
			if rel < -22.0 and rng.randf() < 0.00035 * float(difficulty.get("aggr", 1.0)) * (1.0 + maxf(0.0, -rel) / 100.0):
				declare_war(s, other, "tension")
			elif rel > 55.0 and not s.allies.has(other.id) and rng.randf() < 0.00015:
				s.allies.append(other.id)
				other.allies.append(s.id)
				_add_event(s, "diplomacy", L.tf("alliance_made", [s.name, other.name]), 2, "peace")


func _fire_daily() -> void:
	if burning.is_empty():
		return
	var keys := burning.keys()
	for k in keys:
		var intensity := float(burning.get(k, 0.0)) - 0.28
		if intensity <= 0.01:
			burning.erase(k)
			world.burn[k] = 0.0
			continue
		burning[k] = intensity
		world.burn[k] = intensity
		var x: int = k % world.size
		var z: int = k / world.size
		world.vegetation[k] = maxf(0.0, world.vegetation[k] - 0.12)
		# распространение
		if rng.randf() < 0.22:
			var dx := rng.randi_range(-1, 1)
			var dz := rng.randi_range(-1, 1)
			var xx := x + dx
			var zz := z + dz
			if world.in_bounds(xx, zz):
				var j := world.idx(xx, zz)
				if world.water[j] <= 0.0004 and world.vegetation[j] > 0.15 and not burning.has(j):
					burning[j] = 0.7
					world.burn[j] = 0.7
		# огонь у поселения
		if (x + z) % 3 == 0:
			var s := _settlement_near(Vector2i(x, z), 7)
			if s != null and rng.randf() < 0.1:
				s.fire = maxf(s.fire, 3.0)
				s.happiness -= 0.2
				if rng.randf() < 0.02 and not s.buildings.is_empty():
					var bi := rng.randi() % s.buildings.size()
					s.buildings[bi]["hp"] = float(s.buildings[bi].get("hp", 100)) - 12.0
					if float(s.buildings[bi].hp) <= 0:
						s.buildings.remove_at(bi)
						settlement_structure_changed.emit(s.id)


func _radiation_daily() -> void:
	var offset := int(day) % 12
	for i in range(offset, world.n(), 12):
		if world.radiation[i] > 0.0:
			world.radiation[i] = maxf(0.0, world.radiation[i] - 0.00035)


func _random_events_daily() -> void:
	if rng.randf() > 0.0022 * float(difficulty.get("disaster", 1.0)):
		return
	var alive: Array = []
	for s in settlements:
		if not s.destroyed and s.population > 20:
			alive.append(s)
	if alive.is_empty():
		return
	var s: SettlementData = alive[rng.randi() % alive.size()]
	var roll := rng.randf()
	if roll < 0.28 and s.fire <= 0.0:
		s.fire = 5.0
		_ignite_cells(s.center.x, s.center.y, 3, 0.5)
		_add_event(s, "disaster", L.tf("fire_ev", [s.name]), 2, "fire")
		effect.emit("fire", Vector2(s.center), 5.0, {})
	elif roll < 0.48 and s.plague <= 0.0 and s.population > 50:
		s.plague = rng.randf_range(30, 90)
		_add_event(s, "disaster", L.tf("plague_started", [s.name]), 3, "plague")
		effect.emit("plague", Vector2(s.center), 6.0, {})
	elif roll < 0.66 and s.happiness > 20.0:
		s.happiness = minf(100.0, s.happiness + 15.0)
		s.resources["food"] = minf(s.storage_cap(), float(s.resources["food"]) + 20.0)
		_add_event(s, "festival", L.tf("festival", [s.name]), 1, "star")
		effect.emit("festival", Vector2(s.center), 5.0, {})
	elif roll < 0.80 and s.stability < 35.0:
		s.stability = 60.0
		if not s.buildings.is_empty():
			s.buildings.remove_at(rng.randi() % s.buildings.size())
			settlement_structure_changed.emit(s.id)
		_add_event(s, "revolt", L.tf("revolt", [s.name]), 3, "revolt")
	elif roll < 0.92 and s.faith > 30.0:
		s.faith = minf(200.0, s.faith + 25.0)
		s.blessed = minf(40.0, s.blessed + 10.0)
		_add_event(s, "miracle", L.tf("miracle", [s.name]), 2, "miracle")
		effect.emit("bless", Vector2(s.center), 6.0, {})
	else:
		s.drought = rng.randf_range(20, 80)
		_add_event(s, "disaster", L.tf("drought_ev", [s.name]), 2, "drought")
		effect.emit("drought", Vector2(s.center), 8.0, {})


func _yearly() -> void:
	# дипломатия, войны, экспансия, налоги, события
	for s in settlements:
		if s.destroyed:
			continue
		# налоги/торговля
		s.resources["gold"] = minf(s.storage_cap(), float(s.resources["gold"]) + s.population * 0.002 * (1.0 + s.prosperity))
		# войны
		if s.wars.size() > 0:
			if s.war_days > rng.randi_range(240, 900):
				for other_id in s.wars.duplicate():
					var o: SettlementData = settlement_by_id.get(other_id, null)
					if o != null and rng.randf() < 0.3:
						make_peace(s, o, false)
		# объявление войны
		if s.wars.is_empty() and s.army > 6 and rng.randf() < 0.012 * float(difficulty.get("aggr", 1.0)) * (1.0 + maxf(0.0, -s.happiness) / 100.0):
			var target := _nearest_other(s, 55.0)
			if target != null and not s.allies.has(target.id):
				declare_war(s, target, "ambition")
		# экспансия
		if s.population > 70 and s.stage in ["town", "city", "metropolis"] and s.wars.is_empty() and rng.randf() < 0.16 and _alive_settlement_count() < 18:
			_expand_colony(s)
		# эпидемия
		if s.population > 100 and s.plague <= 0.0 and rng.randf() < 0.012 * float(difficulty.get("disaster", 1.0)):
			s.plague = rng.randf_range(40, 120)
			_add_event(s, "disaster", L.tf("plague_started", [s.name]), 3, "plague")
			effect.emit("plague", Vector2(s.center), 6.0, {})
		# ядерная война
		if s.era >= 7 and s.has_building("silo") and s.wars.size() > 0 and rng.randf() < 0.04 * float(difficulty.get("aggr", 1.0)):
			var enemy: SettlementData = settlement_by_id.get(s.wars[0], null)
			if enemy != null and not enemy.destroyed and not enemy.nuked:
				nuke(enemy.center.x, enemy.center.y, 10, s.id, false)
		# обновление экипировки
		_mark_troops_equipment(s)
		# подбор пар
		_pair_adults(s)
	# летопись населения
	_record_population()


func _pair_adults(s: SettlementData) -> void:
	var singles_m: Array = []
	var singles_f: Array = []
	for a in agents:
		if a.settlement_id != s.id or not a.alive or not a.is_adult():
			continue
		if a.partner_id > 0:
			var p: AgentData = agent_by_id.get(a.partner_id, null)
			if p != null and p.alive:
				continue
			a.partner_id = -1
		if a.gender == 0:
			singles_m.append(a)
		else:
			singles_f.append(a)
	for f in singles_f:
		if singles_m.is_empty():
			break
		if f.partner_id > 0:
			continue
		var m: AgentData = singles_m[rng.randi() % singles_m.size()]
		f.partner_id = m.id
		m.partner_id = f.id
		singles_m.erase(m)


func _mark_troops_equipment(s: SettlementData) -> void:
	var tier := clampi(s.era / 2, 0, 5)
	for a in agents:
		if a.settlement_id == s.id and a.alive:
			a.equipment = maxi(a.equipment, tier)


func _expand_colony(parent: SettlementData) -> void:
	var spot := _find_colony_spot(parent)
	if spot.x < 0:
		return
	var s := SettlementData.new()
	s.setup(next_settlement_id, parent.race_id, spot, year, rng)
	s.name = _unique_name(s.name, s.id)
	next_settlement_id += 1
	s.resources = parent.resources.duplicate()
	for k in s.resources:
		s.resources[k] = float(s.resources[k]) * 0.25
	parent.resources["wood"] = maxf(0.0, float(parent.resources["wood"]) * 0.6)
	parent.resources["food"] = maxf(0.0, float(parent.resources["food"]) * 0.75)
	settlements.append(s)
	settlement_by_id[s.id] = s
	world.add_clearing(s.center, 9.0)
	s.relations[parent.id] = 75.0
	parent.relations[s.id] = 75.0
	var migrants: Array = []
	for a in agents:
		if a.settlement_id == parent.id and a.alive and a.is_adult() and not a.is_warrior() and rng.randf() < 0.16:
			migrants.append(a)
			if migrants.size() >= 10:
				break
	for a in migrants:
		a.settlement_id = s.id
		a.pos = Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		a.target = a.pos
	_assign_leader(s)
	_add_event(parent, "founded", "%s основало колонию %s" % [parent.name, s.name], 3, "people")
	toast.emit(L.tf("toast_city", [s.name]), "city")
	settlement_founded.emit(s)


func _find_colony_spot(parent: SettlementData) -> Vector2i:
	for attempt in 60:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(22.0, 55.0)
		var p := Vector2(parent.center) + Vector2(cos(ang), sin(ang)) * r
		var c := world.cell_of(p)
		if c.x < 5 or c.y < 5 or c.x >= world.size - 5 or c.y >= world.size - 5:
			continue
		if not world.is_land_cell(c.x, c.y):
			continue
		var b := world.biome_name_at(c.x, c.y)
		if b in ["ocean", "shallow", "reef", "river", "lake", "swamp", "snow", "glacier", "volcano", "ashland"]:
			continue
		var ok := true
		for s in settlements:
			if not s.destroyed and Vector2(s.center).distance_to(Vector2(c)) < 18.0:
				ok = false
				break
		if ok:
			return c
	return Vector2i(-1, -1)


func _record_population() -> void:
	if last_population_record_year == year:
		return
	last_population_record_year = year
	chronicle.record_population(year, total_population, _alive_settlement_count())


func _alive_settlement_count() -> int:
	var c := 0
	for s in settlements:
		if not s.destroyed:
			c += 1
	return c


func _unique_name(nm: String, self_id: int = -1) -> String:
	var candidate := nm
	var suffix := 2
	while true:
		var taken := false
		for s in settlements:
			if s.id != self_id and s.name == candidate:
				taken = true
				break
		if not taken:
			return candidate
		candidate = nm + " " + ["II", "III", "IV", "V"][mini(suffix - 2, 3)]
		suffix += 1
	return candidate


# ------------------------------------------------------------------ spawning

func spawn_agent(s: SettlementData, age: float, gender: int, role: String, pos: Vector2) -> AgentData:
	var a := AgentData.new()
	a.setup(next_agent_id, D.race(s.race_id), gender, age, rng)
	next_agent_id += 1
	a.settlement_id = s.id
	a.role = role if role != "worker" else a.role
	a.pos = pos
	a.target = pos
	a.born_year = year - int(age)
	a.equipment = clampi(s.era / 2, 0, 5)
	agents.append(a)
	agent_by_id[a.id] = a
	agent_spawned.emit(a)
	return a


func spawn_initial_animals() -> void:
	_spawn_initial_animals()


func _spawn_initial_animals() -> void:
	var land_animals: Array = []
	for a in D.animals:
		var biomes: Array = a.get("biomes", [])
		var water_only := true
		for b in biomes:
			if b not in ["ocean", "shallow", "reef"]:
				water_only = false
		if not water_only:
			land_animals.append(a)
	if land_animals.is_empty():
		return
	for i in 130:
		var cell := Vector2i(rng.randi_range(2, world.size - 3), rng.randi_range(2, world.size - 3))
		var b := world.biome_name_at(cell.x, cell.y)
		var candidates: Array = []
		for a in land_animals:
			if b in a.get("biomes", []):
				candidates.append(a)
		if candidates.is_empty():
			continue
		var sp: Dictionary = candidates[rng.randi() % candidates.size()]
		_spawn_animal(str(sp.id), cell)


func _random_cell_for_species(species: String) -> Vector2i:
	var sp: Dictionary = D.animal(species)
	for attempt in 40:
		var cell := Vector2i(rng.randi_range(2, world.size - 3), rng.randi_range(2, world.size - 3))
		if world.biome_name_at(cell.x, cell.y) in sp.get("biomes", []):
			return cell
	return Vector2i(-1, -1)


func _spawn_animal(species: String, cell: Vector2i) -> void:
	if cell.x < 0 or animals.size() >= animals_cap:
		return
	var sp: Dictionary = D.animal(species)
	if sp.is_empty():
		return
	var an := {
		"id": next_animal_id, "species": species,
		"pos": Vector2(cell), "target": Vector2(cell),
		"age": rng.randf_range(0.5, 8.0), "alive": true, "breed_cd": 0.0,
		"hp": float(sp.get("hp", 20)),
		"size": float(sp.get("size", 0.7)), "speed": float(sp.get("speed", 1.5)),
		"power": float(sp.get("power", 5)), "predator": bool(sp.get("predator", false)),
		"breed": float(sp.get("breed", 0.05))
	}
	next_animal_id += 1
	animals.append(an)
	animal_by_id[an.id] = an
	effect.emit("animal_spawn", an.pos, 0.5, {"species": species})


# ------------------------------------------------------------------ deaths & helpers

func kill_agent(a: AgentData, cause: String) -> void:
	if not a.alive:
		return
	a.alive = false
	a.health = 0.0
	a.death_cause = cause
	agent_died.emit(a, cause)
	agent_by_id.erase(a.id)
	agents.erase(a)
	var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
	if s != null and not s.destroyed:
		s.total_deaths += 1
		if a.id == s.leader_id:
			_add_event(s, "death", L.tf("leader_died", [a.display_name(), s.name]), 3, "skull")
			_assign_leader(s)
		elif a.notable or a.level >= 20:
			_add_event(s, "death", "Умер %s из %s (%s)" % [a.display_name(), s.name, L.t("cause_" + cause)], 2, "skull")
	if a.partner_id > 0:
		var p: AgentData = agent_by_id.get(a.partner_id, null)
		if p != null:
			p.partner_id = -1


func _assign_targets(s: SettlementData, local: Array) -> void:
	var center := Vector2(s.center)
	var enemy: SettlementData = settlement_by_id.get(s.war_target, null) if s.war_target >= 0 else null
	var radius := minf(s.territory_radius * 0.75, 9.0)
	var hut := _building_of_type(s, "hut")
	var farm := _building_of_type(s, "farm")
	if farm.is_empty():
		farm = _building_of_type(s, "campfire")
	if s.water_day < 0 or int(day) - s.water_day > 30:
		s.water_cell = _nearest_water_cell(s.center, 14)
		s.water_day = int(day)
	var water_target := s.water_cell
	for a in local:
		if not a.alive:
			continue
		if a.age >= a.maturity() and a.role == "child":
			a.role = "worker"
		if a.role == "worker" and a.is_adult():
			if a.id % 5 == 0 and s.has_building("farm"):
				a.role = "farmer"
			elif a.id % 7 == 0 and (s.has_building("lumber") or s.has_building("quarry")):
				a.role = "hunter"
			elif a.id % 11 == 0 and s.has_building("library"):
				a.role = "scholar"
			elif not s.construction.is_empty() and a.id % 4 == 0:
				a.role = "builder"
		if a.role == "warrior" and enemy != null and not enemy.destroyed:
			a.target = Vector2(enemy.center) + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
			a.state = "march"
			continue
		if a.role == "child":
			if rng.randf() < 0.55:
				a.target = center + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			a.state = "play"
			continue
		if a.role == "leader":
			if rng.randf() < 0.6:
				a.target = center + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			a.state = "idle"
			continue
		# сон
		if a.energy < 28.0 or rng.randf() < 0.07:
			if not hut.is_empty():
				a.target = Vector2(hut.x, hut.z) + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			else:
				a.target = center + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			a.state = "sleep"
			continue
		if a.satiety < 36.0:
			if not farm.is_empty():
				a.target = Vector2(farm.x, farm.z) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			a.state = "seekFood"
			continue
		if a.thirst < 34.0:
			if water_target.x >= 0:
				a.target = Vector2(water_target.x, water_target.y) + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
			a.state = "seekWater"
			continue
		if rng.randf() < 0.62 and not s.buildings.is_empty():
			var b: Dictionary = s.buildings[rng.randi() % s.buildings.size()]
			a.target = Vector2(float(b.x), float(b.z)) + Vector2(rng.randf_range(-1.1, 1.1), rng.randf_range(-1.1, 1.1))
			a.state = "work"
		else:
			var ang := rng.randf() * TAU
			var rr := rng.randf_range(1.0, radius)
			a.target = center + Vector2(cos(ang), sin(ang)) * rr
			a.state = "wander"


func _building_of_type(s: SettlementData, type: String) -> Dictionary:
	for b in s.buildings:
		if b.type == type:
			return b
	return {}


func _nearest_water_cell(cell: Vector2i, max_r: int) -> Vector2i:
	for r in range(1, max_r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := cell.x + dx
				var z := cell.y + dz
				if world.in_bounds(x, z) and world.water[world.idx(x, z)] > 0.0004:
					return Vector2i(x, z)
	return Vector2i(-1, -1)


func _assign_leader(s: SettlementData) -> void:
	var best: AgentData = null
	var best_score := -1.0
	for a in agents:
		if a.settlement_id == s.id and a.alive and a.is_adult():
			var score: float = a.charisma + float(a.skills.get("leadership", 20)) + a.level * 2.0
			if score > best_score:
				best_score = score
				best = a
	if best != null:
		s.leader_id = best.id
		best.role = "leader"
		best.notable = true
		if rng.randf() < 0.6:
			_add_event(s, "leader", L.tf("new_leader", [best.display_name(), s.name]), 1, "crown")


func _agent_near(p: Vector2, radius: float) -> AgentData:
	for a in agents:
		if a.alive and a.pos.distance_to(p) < radius:
			return a
	return null


func _settlement_near(cell: Vector2i, radius: float) -> SettlementData:
	var best: SettlementData = null
	var bd := 99999.0
	for s in settlements:
		if s.destroyed:
			continue
		var d := Vector2(s.center).distance_to(Vector2(cell))
		if d < radius and d < bd:
			bd = d
			best = s
	return best


func _nearest_other(s: SettlementData, max_dist: float = 60.0) -> SettlementData:
	var best: SettlementData = null
	var bd := max_dist
	for o in settlements:
		if o.id == s.id or o.destroyed:
			continue
		var d := Vector2(s.center).distance_to(Vector2(o.center))
		if d < bd:
			bd = d
			best = o
	return best


func _near_water(p: Vector2, radius: int) -> bool:
	var c := world.cell_of(p)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var x := c.x + dx
			var z := c.y + dz
			if world.in_bounds(x, z) and world.water[world.idx(x, z)] > 0.0004:
				return true
	return false


# ------------------------------------------------------------------ god actions

func land_point(cell: Vector2i) -> bool:
	return world.is_land_cell(cell.x, cell.y)


func declare_war(a: SettlementData, b: SettlementData, reason: String = "tension") -> void:
	if a.id == b.id or a.destroyed or b.destroyed:
		return
	if a.wars.has(b.id):
		return
	a.wars.append(b.id)
	b.wars.append(a.id)
	a.war_target = b.id
	b.war_target = a.id
	a.war_days = 0
	b.war_days = 0
	a.siege_days = 0
	b.siege_days = 0
	a.relations[b.id] = minf(float(a.relations.get(b.id, 0.0)), -60.0)
	b.relations[a.id] = a.relations[b.id]
	for a2 in agents:
		if a2.settlement_id == a.id and a2.alive and a2.is_adult() and a2.role != "leader" and rng.randf() < 0.42:
			a2.role = "warrior"
			a2.state = "march"
			a2.target = Vector2(b.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		elif a2.settlement_id == b.id and a2.alive and a2.is_adult() and a2.role != "leader" and rng.randf() < 0.22:
			a2.role = "warrior"
	var text := L.tf("war_started", [a.name, b.name])
	_add_event(a, "war", text, 3, "war")
	toast.emit(L.tf("toast_war", [a.name, b.name]), "war")
	war_declared.emit(a.id, b.id)
	effect.emit("war_horn", Vector2(a.center), 6.0, {})


func make_peace(a: SettlementData, b: SettlementData, silent: bool = false) -> void:
	a.wars.erase(b.id)
	b.wars.erase(a.id)
	if a.war_target == b.id:
		a.war_target = -1
	if b.war_target == a.id:
		b.war_target = -1
	a.relations[b.id] = maxf(float(a.relations.get(b.id, 0.0)), 5.0)
	b.relations[a.id] = a.relations[b.id]
	for a2 in agents:
		if a2.settlement_id == a.id and a2.role == "warrior":
			a2.role = "worker"
			a2.state = "idle"
			a2.target = Vector2(a.center)
		elif a2.settlement_id == b.id and a2.role == "warrior":
			a2.role = "worker"
			a2.state = "idle"
			a2.target = Vector2(b.center)
	if not silent:
		_add_event(a, "diplomacy", L.tf("peace_made", [a.name, b.name]), 2, "peace")
		toast.emit(L.tf("toast_peace", [a.name, b.name]), "peace")
	war_ended.emit(a.id, b.id)


func _mark_warriors_to_target(s: SettlementData) -> void:
	if s.war_target < 0:
		return
	var enemy: SettlementData = settlement_by_id.get(s.war_target, null)
	if enemy == null:
		return
	for a in agents:
		if a.settlement_id == s.id and a.alive and a.role == "warrior":
			a.target = Vector2(enemy.center) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			a.state = "march"


func damage_area(center: Vector2, radius: float, damage: float, source: String = "disaster") -> void:
	var dead: Array = []
	for a in agents:
		if not a.alive:
			continue
		var d: float = a.pos.distance_to(center)
		if d <= radius:
			var dmg: float = damage * (1.0 - d / maxf(radius, 0.1)) * rng.randf_range(0.7, 1.2)
			a.health -= dmg
			if a.health <= 0.0:
				dead.append(a)
	for a in dead:
		var cause := "disaster" if source != "battle" else "battle"
		kill_agent(a, cause)
	var cell := world.cell_of(center)
	for s in settlements:
		if s.destroyed:
			continue
		var d: float = Vector2(s.center).distance_to(center)
		if d <= radius + 3.0:
			s.happiness -= damage * 0.01
			if not s.buildings.is_empty():
				for i in 2:
					if s.buildings.is_empty():
						break
					var bi: int = rng.randi() % s.buildings.size()
					s.buildings[bi]["hp"] = float(s.buildings[bi].get("hp", 100.0)) - damage * 0.5
					if float(s.buildings[bi].hp) <= 0.0:
						s.buildings.remove_at(bi)
				settlement_structure_changed.emit(s.id)


func lightning(cx: int, cz: int) -> void:
	var pos := Vector2(cx, cz)
	damage_area(pos, 2.0, 130.0, "lightning")
	_ignite_cells(cx, cz, 2, 0.5)
	effect.emit("lightning", pos, 2.0, {})
	var s := _settlement_near(Vector2i(cx, cz), 5.0)
	if s != null:
		_add_event(s, "disaster", "%s: удар молнии" % s.name, 1, "lightning")


func bomb(cx: int, cz: int, radius: float = 3.0) -> void:
	var pos := Vector2(cx, cz)
	damage_area(pos, radius, 280.0, "bomb")
	_ignite_cells(cx, cz, int(maxf(1.0, radius)), 0.7)
	world.raise_area(cx, cz, radius * 0.7, 0.06, "sub")
	effect.emit("bomb", pos, radius, {})
	disaster.emit("bomb", pos, radius)


func meteor(cx: int, cz: int, radius: float = 6.0) -> void:
	var pos := Vector2(cx, cz)
	damage_area(pos, radius, 620.0, "meteor")
	_ignite_cells(cx, cz, int(radius), 0.9)
	world.raise_area(cx, cz, radius, 0.10, "sub")
	world.add_radiation(cx, cz, int(radius * 0.6), 0.15)
	world.paint_biome(cx, cz, radius * 0.7, "ashland")
	effect.emit("meteor", pos, radius, {})
	var s := _settlement_near(Vector2i(cx, cz), radius + 4.0)
	if s != null:
		_add_event(s, "disaster", L.tf("meteor_ev", [s.name]), 4, "meteor")
	disaster.emit("meteor", pos, radius)


func nuke(cx: int, cz: int, radius: float = 10.0, source_id: int = -1, by_god: bool = true) -> void:
	var pos := Vector2(cx, cz)
	damage_area(pos, radius, 1600.0, "nuke")
	world.raise_area(cx, cz, radius * 0.5, 0.16, "sub")
	world.add_radiation(cx, cz, int(radius), 0.85)
	world.paint_biome(cx, cz, radius * 0.8, "ashland")
	_ignite_cells(cx, cz, int(radius * 0.45), 0.55)
	nukes_total += 1
	var s := _settlement_near(Vector2i(cx, cz), radius + 2.0)
	if s != null:
		s.nuked = true
		s.radioactive = 900.0
		s.happiness = -100.0
		s.resources = {"food": 0.0, "wood": 0.0, "stone": 0.0, "iron": 0.0, "gold": 0.0, "goods": 0.0}
		_add_event(s, "nuke", L.tf("nuke_ev", [s.name]), 4, "nuke")
		toast.emit(L.t("toast_nuke") + ": " + s.name, "nuke")
		if s.population < 12:
			_destroy_settlement(s, "nuke")
	effect.emit("nuke", pos, radius, {})
	disaster.emit("nuke", pos, radius)
	if nukes_total >= 3 and nuclear_winter <= 0.0:
		nuclear_winter = 900.0
		_add_event(s if s != null else null, "nuke", L.t("nuclear_winter_ev"), 4, "snow")
		toast.emit(L.t("toast_nuclear_winter"), "nuke")
		nuclear_winter_started.emit()


func earthquake(cx: int, cz: int, radius: float = 16.0) -> void:
	damage_area(Vector2(cx, cz), radius, 110.0, "quake")
	for i in 14:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(1.0, radius)
		var x := clampi(cx + int(cos(ang) * r), 1, world.size - 2)
		var z := clampi(cz + int(sin(ang) * r), 1, world.size - 2)
		world.raise_area(x, z, 2.5, rng.randf_range(-0.05, 0.05), "add")
	effect.emit("quake", Vector2(cx, cz), radius, {})
	var s := _settlement_near(Vector2i(cx, cz), radius)
	if s != null:
		_add_event(s, "disaster", L.tf("quake_ev", [s.name]), 3, "quake")
	disaster.emit("quake", Vector2(cx, cz), radius)


func tornado_strike(cx: int, cz: int, radius: float = 4.0) -> void:
	damage_area(Vector2(cx, cz), radius, 45.0, "tornado")
	var s := _settlement_near(Vector2i(cx, cz), radius + 2.0)
	if s != null:
		s.happiness -= 1.0
		s.stability = maxf(0.0, s.stability - 0.5)


func flood(cx: int, cz: int, radius: float = 10.0) -> void:
	world.water_area(cx, cz, radius, "shallow")
	damage_area(Vector2(cx, cz), radius, 55.0, "flood")
	effect.emit("flood", Vector2(cx, cz), radius, {})
	var s := _settlement_near(Vector2i(cx, cz), radius)
	if s != null:
		_add_event(s, "disaster", L.tf("flood_ev", [s.name]), 3, "flood")


func volcano_eruption(cx: int, cz: int, radius: float = 6.0) -> void:
	world.water_area(cx, cz, radius * 0.55, "lava")
	world.paint_biome(cx, cz, radius * 1.2, "ashland")
	damage_area(Vector2(cx, cz), radius * 1.4, 300.0, "lava")
	_ignite_cells(cx, cz, int(radius * 1.3), 0.8)
	effect.emit("volcano", Vector2(cx, cz), radius, {})
	var s := _settlement_near(Vector2i(cx, cz), radius * 1.4)
	if s != null:
		_add_event(s, "disaster", L.tf("volcano_ev", [s.name]), 4, "volcano")
	disaster.emit("volcano", Vector2(cx, cz), radius)


func rain(cx: int, cz: int, radius: float = 10.0) -> void:
	for z in range(maxi(0, cz - int(radius)), mini(world.size, cz + int(radius) + 1)):
		for x in range(maxi(0, cx - int(radius)), mini(world.size, cx + int(radius) + 1)):
			if Vector2(x - cx, z - cz).length() <= radius:
				var i := world.idx(x, z)
				if world.water[i] <= 0.0004:
					world.vegetation[i] = minf(1.0, world.vegetation[i] + 0.18)
					world.moisture[i] = minf(1.0, world.moisture[i] + 0.08)
					if burning.has(i):
						burning[i] = 0.0
						world.burn[i] = 0.0
						burning.erase(i)
	effect.emit("rain", Vector2(cx, cz), radius, {})


func acid_rain(cx: int, cz: int, radius: float = 9.0) -> void:
	for z in range(maxi(0, cz - int(radius)), mini(world.size, cz + int(radius) + 1)):
		for x in range(maxi(0, cx - int(radius)), mini(world.size, cx + int(radius) + 1)):
			if Vector2(x - cx, z - cz).length() <= radius:
				var i := world.idx(x, z)
				world.vegetation[i] = maxf(0.0, world.vegetation[i] - 0.25)
	damage_area(Vector2(cx, cz), radius, 35.0, "acid")
	effect.emit("acid_rain", Vector2(cx, cz), radius, {})
	var s := _settlement_near(Vector2i(cx, cz), radius)
	if s != null:
		s.happiness -= 8.0
		_add_event(s, "disaster", "Кислотный дождь над %s" % s.name, 2, "acid")


func drought(cx: int, cz: int, radius: float = 14.0) -> void:
	for z in range(maxi(0, cz - int(radius)), mini(world.size, cz + int(radius) + 1)):
		for x in range(maxi(0, cx - int(radius)), mini(world.size, cx + int(radius) + 1)):
			if Vector2(x - cx, z - cz).length() <= radius:
				var i := world.idx(x, z)
				if world.water[i] <= 0.0004:
					world.vegetation[i] = maxf(0.0, world.vegetation[i] - 0.2)
					world.moisture[i] = maxf(0.0, world.moisture[i] - 0.12)
	for s in settlements:
		if not s.destroyed and Vector2(s.center).distance_to(Vector2(cx, cz)) < radius:
			s.drought = 60.0
	effect.emit("drought", Vector2(cx, cz), radius, {})


func blizzard(cx: int, cz: int, radius: float = 14.0) -> void:
	for s in settlements:
		if not s.destroyed and Vector2(s.center).distance_to(Vector2(cx, cz)) < radius:
			s.blizzard = 50.0
			s.happiness -= 5.0
	effect.emit("blizzard", Vector2(cx, cz), radius, {})
	var near := _settlement_near(Vector2i(cx, cz), radius)
	if near != null:
		_add_event(near, "disaster", L.tf("blizzard_ev", [near.name]), 2, "snow")


func plague_settlement(s: SettlementData) -> void:
	if s == null or s.destroyed:
		return
	s.plague = 80.0
	_add_event(s, "disaster", L.tf("plague_started", [s.name]), 3, "plague")
	effect.emit("plague", Vector2(s.center), 7.0, {})
	toast.emit(L.tf("plague_started", [s.name]), "plague")


func bless_area(cx: int, cz: int, radius: float = 6.0, kind: String = "health") -> void:
	for a in agents:
		if a.alive and a.pos.distance_to(Vector2(cx, cz)) <= radius:
			match kind:
				"health":
					a.health = a.max_health
					a.satiety = minf(100.0, a.satiety + 25.0)
					a.sanity = minf(100.0, a.sanity + 20.0)
				"fertility":
					a.mood += 15.0
					if a.gender == 1:
						a.pregnant = maxf(a.pregnant, 30.0)
				"wisdom":
					a.add_xp(45.0)
					a.wisdom = minf(100.0, a.wisdom + 3.0)
				"luck":
					a.mood = minf(100.0, a.mood + 25.0)
	for z in range(maxi(0, cz - int(radius)), mini(world.size, cz + int(radius) + 1)):
		for x in range(maxi(0, cx - int(radius)), mini(world.size, cx + int(radius) + 1)):
			if Vector2(x - cx, z - cz).length() <= radius:
				var i := world.idx(x, z)
				if world.water[i] <= 0.0004:
					world.vegetation[i] = minf(1.0, world.vegetation[i] + 0.22)
	effect.emit("bless", Vector2(cx, cz), radius, {"kind": kind})
	var s := _settlement_near(Vector2i(cx, cz), radius + 3.0)
	if s != null:
		s.blessed = minf(90.0, s.blessed + 25.0)
		s.happiness += 10.0
		_add_event(s, "bless", L.tf("bless_ev", [s.name]), 2, "bless")


func curse_area(cx: int, cz: int, radius: float = 6.0, kind: String = "disease") -> void:
	for a in agents:
		if a.alive and a.pos.distance_to(Vector2(cx, cz)) <= radius:
			match kind:
				"disease":
					a.health -= a.max_health * rng.randf_range(0.2, 0.45)
					if a.health <= 0.0:
						kill_agent(a, "plague")
				"madness":
					a.sanity = maxf(0.0, a.sanity - 45.0)
					a.mood -= 30.0
				"undeath":
					a.health -= a.max_health * rng.randf_range(0.35, 0.6)
					a.sanity = 0.0
					if a.health <= 0.0:
						kill_agent(a, "curse")
	effect.emit("curse", Vector2(cx, cz), radius, {"kind": kind})
	var s := _settlement_near(Vector2i(cx, cz), radius + 3.0)
	if s != null:
		s.cursed = minf(90.0, s.cursed + 30.0)
		s.stability = maxf(0.0, s.stability - 15.0)
		_add_event(s, "curse", L.tf("curse_ev", [s.name]), 2, "curse")


func spawn_tribe(cx: int, cz: int) -> SettlementData:
	var cell := Vector2i(cx, cz)
	if not world.is_land_cell(cx, cz):
		var found := world.find_settlement_sites(1, 3.0)
		if found.is_empty():
			return null
		cell = found[0].cell
	if _settlement_near(cell, 12.0) != null:
		return null
	var race := "human"
	var b := world.biome_at(cell.x, cell.y)
	var races: Array = b.get("races", [])
	if races.size() > 0:
		race = races[rng.randi() % races.size()]
	var s := SettlementData.new()
	s.setup(next_settlement_id, race, cell, year, rng)
	s.name = _unique_name(s.name, s.id)
	next_settlement_id += 1
	s.add_building("hut", s.center.x + 1.2, s.center.y + 0.5, rng.randf() * TAU, year)
	s.add_building("farm", s.center.x - 1.3, s.center.y + 1.2, rng.randf() * TAU, year)
	settlements.append(s)
	settlement_by_id[s.id] = s
	world.add_clearing(s.center, 9.0)
	var count := rng.randi_range(8, 12)
	for i in count:
		var a := spawn_agent(s, rng.randf_range(18, 40), rng.randi() % 2, "worker", Vector2(cell) + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5)))
		a.satiety = 90
	# отношения с соседями
	for other in settlements:
		if other.id != s.id:
			s.relations[other.id] = rng.randi_range(-5, 15)
			other.relations[s.id] = s.relations[other.id]
	_assign_leader(s)
	_add_event(s, "founded", L.tf("city_founded", [s.name]), 2, "people")
	toast.emit(L.tf("toast_city", [s.name]), "city")
	settlement_founded.emit(s)
	effect.emit("spawn_tribe", Vector2(cell), 5.0, {})
	return s


func spawn_animal_at(cx: int, cz: int) -> void:
	var b := world.biome_name_at(cx, cz)
	var candidates: Array = []
	for a in D.animals:
		if b in a.get("biomes", []):
			candidates.append(a)
	if candidates.is_empty():
		return
	var sp: Dictionary = candidates[rng.randi() % candidates.size()]
	_spawn_animal(str(sp.id), Vector2i(cx, cz))
	effect.emit("animal_spawn", Vector2(cx, cz), 1.0, {"species": sp.id})


func gift_settlement(s: SettlementData) -> void:
	if s == null:
		return
	s.resources["food"] = minf(s.storage_cap(), float(s.resources.get("food", 0.0)) + 150.0)
	s.resources["wood"] = minf(s.storage_cap(), float(s.resources.get("wood", 0.0)) + 100.0)
	s.resources["stone"] = minf(s.storage_cap(), float(s.resources.get("stone", 0.0)) + 80.0)
	s.resources["gold"] = minf(s.storage_cap(), float(s.resources.get("gold", 0.0)) + 40.0)
	s.happiness += 8.0
	_add_event(s, "bless", "Боги одарили %s" % s.name, 1, "gift")
	effect.emit("bless", Vector2(s.center), 6.0, {"kind": "gift"})


func grant_tech(s: SettlementData) -> void:
	if s == null:
		return
	var pool: Array = []
	for t in D.era_techs.get(s.era, []):
		if not s.techs.has(t.id):
			pool.append(t)
	if pool.is_empty():
		_advance_era(s)
		return
	pool.sort_custom(func(a, b): return int(a.cost) < int(b.cost))
	var t: Dictionary = pool[0]
	s.techs.append(t.id)
	s.era_techs_done += 1
	s.research_progress = 0.0
	_add_event(s, "tech", L.tf("tech_discovered_ev", [s.name, L.tc(t)]), 2, "tech")
	toast.emit("%s: %s" % [s.name, L.tc(t)], "tech")
	effect.emit("tech", Vector2(s.center), 4.0, {})
	if s.era_techs_done >= 4:
		_advance_era(s)


func god_new_leader(s: SettlementData) -> void:
	if s == null:
		return
	var old: AgentData = agent_by_id.get(s.leader_id, null)
	if old != null:
		old.role = "worker"
		old.notable = false
	_assign_leader(s)
	effect.emit("crown", Vector2(s.center), 4.0, {})


func prophet(s: SettlementData) -> void:
	if s == null:
		return
	s.faith = minf(200.0, s.faith + 40.0)
	s.happiness += 15.0
	var p := spawn_agent(s, rng.randf_range(25, 40), rng.randi() % 2, "worker", Vector2(s.center))
	p.magic = minf(100.0, p.magic + 40.0)
	p.charisma = minf(100.0, p.charisma + 30.0)
	p.wisdom = minf(100.0, p.wisdom + 20.0)
	p.notable = true
	p.role = "leader"
	s.leader_id = p.id
	_add_event(s, "prophet", L.tf("prophet", [s.name]), 3, "prophet")
	toast.emit(L.tf("toast_prophet", [s.name]), "prophet")
	effect.emit("prophet", Vector2(s.center), 7.0, {})


func miracle(s: SettlementData) -> void:
	if s == null:
		return
	s.blessed = 120.0
	s.happiness = minf(100.0, s.happiness + 30.0)
	s.faith = minf(250.0, s.faith + 60.0)
	s.resources["food"] = minf(s.storage_cap(), float(s.resources["food"]) + 250.0)
	for a in agents:
		if a.settlement_id == s.id and a.alive:
			a.health = a.max_health
			a.mood = minf(100.0, a.mood + 30.0)
	_add_event(s, "miracle", L.tf("miracle", [s.name]), 4, "miracle")
	effect.emit("miracle", Vector2(s.center), 10.0, {})
	toast.emit(L.tf("miracle", [s.name]), "miracle")


func ignite_at(cx: int, cz: int, radius: int = 4, intensity: float = 0.8) -> void:
	_ignite_cells(cx, cz, radius, intensity)
	effect.emit("fire", Vector2(cx, cz), float(radius), {})


func _ignite_cells(cx: int, cz: int, radius: int, intensity: float) -> void:
	for z in range(maxi(0, cz - radius), mini(world.size, cz + radius + 1)):
		for x in range(maxi(0, cx - radius), mini(world.size, cx + radius + 1)):
			if Vector2(x - cx, z - cz).length() <= float(radius):
				var i := world.idx(x, z)
				if world.water[i] > 0.0004:
					continue
				if world.vegetation[i] > 0.08 or rng.randf() < 0.2:
					world.burn[i] = maxf(world.burn[i], intensity)
					burning[i] = maxf(float(burning.get(i, 0.0)), intensity)


func _add_event(s: SettlementData, type: String, text: String, importance: int = 1, icon: String = "dot") -> void:
	var sid := -1
	var pos := Vector2.ZERO
	if s != null:
		sid = s.id
		pos = Vector2(s.center)
	chronicle.add(year, int(fposmod(day, 365.0)), type, text, importance, sid, pos, icon)
	chronicle_added.emit(chronicle.events.back())
	if importance >= 3 and type not in ["era", "build"]:
		toast.emit(text, type)


func _add_world_event(type: String, text: String, importance: int = 1, icon: String = "dot") -> void:
	chronicle.add(year, int(fposmod(day, 365.0)), type, text, importance, -1, Vector2.ZERO, icon)
	chronicle_added.emit(chronicle.events.back())


func selected_agent() -> AgentData:
	return null


func date_text() -> String:
	var d := int(fposmod(day, 365.0))
	var season_day := (d % 91) + 1
	return "%s %d · %d %s" % [L.t("year"), year, season_day, L.t("day")]


func season_text() -> String:
	return L.season_name(season)


func to_dict() -> Dictionary:
	var ag: Array = []
	for a in agents:
		ag.append(a.to_dict())
	var an: Array = []
	for a2 in animals:
		an.append({
			"id": a2.id, "species": a2.species, "pos": [a2.pos.x, a2.pos.y],
			"target": [a2.target.x, a2.target.y], "age": a2.age, "alive": a2.alive,
			"breed_cd": a2.breed_cd, "hp": a2.hp
		})
	var st: Array = []
	for s in settlements:
		st.append(s.to_dict())
	return {
		"day": day, "year": year, "season": season, "total_population": total_population,
		"next_agent_id": next_agent_id, "next_settlement_id": next_settlement_id,
		"next_animal_id": next_animal_id, "agents": ag, "animals": an,
		"settlements": st, "chronicle": chronicle.to_dict(),
		"weather": weather_mode, "weather_days_left": weather_days_left, "nuclear_winter": nuclear_winter,
		"nukes_total": nukes_total, "world_age_years": world_age_years,
		"burning": burning.keys()
	}


func from_dict(d: Dictionary) -> void:
	day = float(d.get("day", 0))
	year = int(d.get("year", 1))
	season = int(d.get("season", 0))
	total_population = int(d.get("total_population", 0))
	next_agent_id = int(d.get("next_agent_id", 1))
	next_settlement_id = int(d.get("next_settlement_id", 1))
	next_animal_id = int(d.get("next_animal_id", 1))
	weather_mode = str(d.get("weather", "clear"))
	weather_days_left = int(d.get("weather_days_left", 90))
	nuclear_winter = float(d.get("nuclear_winter", 0))
	nukes_total = int(d.get("nukes_total", 0))
	world_age_years = int(d.get("world_age_years", 0))
	agents.clear(); agent_by_id.clear()
	for ad in d.get("agents", []):
		var a := AgentData.from_dict(ad)
		agents.append(a)
		agent_by_id[a.id] = a
	animals.clear(); animal_by_id.clear()
	for ad2 in d.get("animals", []):
		var p: Array = ad2.get("pos", [0, 0])
		var t: Array = ad2.get("target", [0, 0])
		var an := {
			"id": int(ad2.get("id", 0)), "species": str(ad2.get("species", "rabbit")),
			"pos": Vector2(float(p[0]), float(p[1])), "target": Vector2(float(t[0]), float(t[1])),
			"age": float(ad2.get("age", 1)), "alive": bool(ad2.get("alive", true)),
			"breed_cd": float(ad2.get("breed_cd", 0)), "hp": float(ad2.get("hp", 20)),
			"size": float(ad2.get("size", D.animal(str(ad2.get("species", "rabbit"))).get("size", 0.7))),
			"speed": float(ad2.get("speed", D.animal(str(ad2.get("species", "rabbit"))).get("speed", 1.5))),
			"power": float(ad2.get("power", D.animal(str(ad2.get("species", "rabbit"))).get("power", 5))),
			"predator": bool(ad2.get("predator", D.animal(str(ad2.get("species", "rabbit"))).get("predator", false))),
			"breed": float(ad2.get("breed", D.animal(str(ad2.get("species", "rabbit"))).get("breed", 0.05)))
		}
		animals.append(an)
		animal_by_id[an.id] = an
	settlements.clear(); settlement_by_id.clear()
	for sd in d.get("settlements", []):
		var s := SettlementData.from_dict(sd)
		settlements.append(s)
		settlement_by_id[s.id] = s
		if not s.destroyed:
			world.add_clearing(s.center, 9.0)
	chronicle = ChronicleData.from_dict(d.get("chronicle", {}))
	burning.clear()
	for k in d.get("burning", []):
		burning[int(k)] = world.burn[int(k)] if int(k) < world.n() else 0.0
	_update_settlement_counts()
