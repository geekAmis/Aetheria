class_name SimWorld
extends RefCounted
## Детерминированная симуляция мира: существа, животные, поселения,
## экономика, технологии, политика, войны, катастрофы и хроника.
## Ничего не знает о рендере; общается через сигналы.

const VARIANTS_COUNT := 8
const RELIGIONS := [
	{"id": "sun", "name": "Солнечный Орден", "color": "#e8c04a"},
	{"id": "moon", "name": "Лунный Ковен", "color": "#9a8ad8"},
	{"id": "forest", "name": "Дети Леса", "color": "#4aa85a"},
	{"id": "flame", "name": "Пламенный Путь", "color": "#d85a3a"},
	{"id": "deep", "name": "Глубинные", "color": "#3a8ad8"},
	{"id": "bone", "name": "Костяной Хор", "color": "#c8c8c8"},
	{"id": "storm", "name": "Грозовой Круг", "color": "#6a8ad8"},
	{"id": "harvest", "name": "Мать Урожая", "color": "#d8a24a"}
]
const MONSTER_KINDS := ["dragon", "undead", "giant", "wyvern"]

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
var expeditions: Array = []
var next_expedition_id: int = 1
var last_step_us: int = 0
var last_parts: Dictionary = {}
var heavy_step_fresh := false
var monsters: Array = []
var next_monster_id: int = 1
var agents_cap: int = 900


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
	monsters.clear(); next_monster_id = 1
	next_agent_id = 1; next_settlement_id = 1; next_animal_id = 1
	burning.clear()
	event_cooldowns.clear()


func populate(progress: Callable = Callable()) -> void:
	var genesis := bool(config.get("genesis", false))
	var tribe_count := int(config.get("tribes", 6))
	var sites: Array = world.find_settlement_sites(tribe_count, 20.0)
	if sites.is_empty():
		sites = world.find_settlement_sites(1, 4.0)
	for site in sites:
		var s := SettlementData.new()
		s.setup(next_settlement_id, str(site.race), site.cell, year, rng)
		s.name = _unique_name(s.name, s.id)
		var rel: Dictionary = RELIGIONS[rng.randi() % RELIGIONS.size()]
		s.religion = str(rel.id)
		s.zeal = rng.randf_range(30.0, 65.0)
		next_settlement_id += 1
		# стартовые постройки
		if genesis:
			s.add_building("campfire", s.center.x, s.center.y, rng.randf() * TAU, year)
			s.resources["food"] = 140.0
			s.resources["wood"] = 90.0
			s.resources["stone"] = 30.0
		else:
			s.add_building("hut", s.center.x + 1.4, s.center.y + 0.8, rng.randf() * TAU, year)
			s.add_building("farm", s.center.x - 1.6, s.center.y + 1.6, rng.randf() * TAU, year)
		settlements.append(s)
		settlement_by_id[s.id] = s
		world.add_clearing(s.center, 9.0)
		if genesis:
			# первородные: мало, но сильны и заметны
			var firstborn := rng.randi_range(6, 9)
			for i in firstborn:
				var a := spawn_agent(s, a_maturity_age(str(site.race)) + rng.randf_range(0.0, 14.0), rng.randi() % 2, "worker", Vector2(s.center) + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5)))
				a.level = rng.randi_range(4, 7)
				a.power = clampf(rng.randf_range(86.0, 100.0), 1, 100)
				a.wisdom = clampf(rng.randf_range(80.0, 100.0), 1, 100)
				a.agility = clampf(rng.randf_range(80.0, 100.0), 1, 100)
				a.charisma = clampf(rng.randf_range(70.0, 100.0), 1, 100)
				a.max_health = a.compute_max_health()
				a.health = a.max_health
				a.notable = true
				a.appearance["variant"] = i % VARIANTS_COUNT
				for pk in ["industrious", "lucky", "brave"]:
					if not a.perks.has(pk):
						a.perks.append(pk)
				_add_event(s, "founded", "Первородный %s зажигает первый костёр" % a.display_name(), 2, "spark")
		else:
			var adults := rng.randi_range(9, 13)
			for i in adults:
				var gender := rng.randi() % 2
				var age := rng.randf_range(18.0, 45.0)
				spawn_agent(s, age, gender, "worker", Vector2(s.center) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
			for i in rng.randi_range(2, 4):
				spawn_agent(s, rng.randf_range(0.5, 12.0), rng.randi() % 2, "child", Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
		_assign_leader(s)
		for aa in agents:
			if aa.settlement_id == s.id:
				s.founded_by = aa.id
				break
		var ld: AgentData = agent_by_id.get(s.leader_id, null)
		if ld != null:
			s.dynasty = ld.dynasty
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
	var t0 := Time.get_ticks_usec()
	day += 1.0
	year = 1 + int(day / 365.0)
	season = int(fposmod(day, 365.0) / 91.25)
	if nuclear_winter > 0.0:
		nuclear_winter = maxf(0.0, nuclear_winter - 1.0)
	_refresh_weather()
	_time_part("world", func(): _world_daily())
	_update_settlement_counts()
	_time_part("agents", func(): _agents_daily())
	_time_part("settle", func(): _settlements_daily())
	if total_population < 30 and _active_wars_count() > 0:
		_emergency_peace()
	_time_part("vassals", func(): _vassals_daily())
	_time_part("legends", func(): _legends_daily())
	_time_part("animals", func(): _animals_daily())
	_time_part("monsters", func(): _monsters_daily())
	_time_part("diplo", func(): _diplomacy_daily())
	_time_part("roads", func(): _roads_tick())
	_time_part("exp", func(): _expeditions_daily())
	_time_part("fire", func(): _fire_daily())
	_time_part("rad", func(): _radiation_daily())
	_time_part("events", func(): _random_events_daily())
	if year != world_age_years:
		world_age_years = year
		_time_part("yearly", func(): _yearly())
	war_intensity = clampf(float(_active_wars_count()) / 2.0, 0.0, 1.0)
	last_step_us = Time.get_ticks_usec() - t0
	heavy_step_fresh = last_step_us > 5000


func _time_part(key: String, cb: Callable) -> void:
	var t := Time.get_ticks_usec()
	cb.call()
	last_parts[key] = Time.get_ticks_usec() - t


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
	# рост растительности — 1/16 карты в день
	var offset := int(day) % 16
	var n := world.n()
	var fert := world.fertility
	var veg := world.vegetation
	var water := world.water
	var moist := world.moisture
	var temp := world.temperature
	var winter := nuclear_winter > 0.0
	for i in range(offset, n, 16):
		if water[i] > 0.0004:
			continue
		var cap: float = float(fert[i]) * 1.05
		var v := veg[i]
		if v < cap:
			var temp_f := 0.3 if temp[i] < 0.12 else 1.0
			if winter:
				temp_f *= 0.35
			veg[i] = clampf(v + 0.011 * moist[i] * temp_f, 0.0, 1.0)
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
		a.update_emotion(1.0)
		a.action_time += 1.0
		if not a.immortal:
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
				a.set_emotion("happy", "food", 3.0)
				a.set_action("eat", a.pos, "food", 1.0)
			else:
				var ac := world.cell_of(a.pos)
				var ci := world.idx(ac.x, ac.y)
				if world.vegetation[ci] > 0.25:
					a.satiety = minf(100.0, a.satiety + 18.0)
					world.vegetation[ci] = maxf(0.0, world.vegetation[ci] - 0.02)
					a.set_emotion("happy", "forage", 2.0)
			if a.satiety < 20.0 and a.emotion != "hungry":
				a.set_emotion("hungry", "starving", 12.0)
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
			# эмоциональное состояние следует из потребностей и событий
			if a.emotion_timer <= 0.0:
				if a.satiety < 25.0:
					a.set_emotion("hungry", "hunger", 6.0)
				elif a.thirst < 25.0:
					a.set_emotion("sad", "thirst", 5.0)
				elif a.health < a.max_health * 0.45:
					a.set_emotion("sad", "wounded", 8.0)
				elif a.sanity < 40.0:
					a.set_emotion("afraid", "madness", 8.0)
				elif a.mood < -15.0:
					a.set_emotion("sad", "unhappy", 6.0)
				elif not s.wars.is_empty() and a.role == "warrior":
					a.set_emotion("angry", "war", 6.0)
				elif a.mood > 40.0 and rng.randf() < 0.15:
					a.set_emotion("happy", "life", 5.0)
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
		if not a.immortal and a.age >= lifespan:
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
		s.zeal = clampf(s.zeal + s.building_count("temple") * 0.06 - 0.012, 0.0, 100.0)
		if s.holy_war and s.wars.is_empty():
			s.holy_war = false
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
		if s.population < 12 and not s.wars.is_empty():
			for eid in s.wars.duplicate():
				var o: SettlementData = settlement_by_id.get(int(eid), null)
				if o != null:
					make_peace(s, o, true)
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
	var site := Vector2(float(c.get("x", s.center.x)), float(c.get("z", s.center.y)))
	var crew: Array = []
	for a in agents:
		if a.alive and a.settlement_id == s.id and a.action == "build" and a.pos.distance_to(site) < 5.0:
			crew.append(a)
	var work := 0.18 + minf(3.0, float(crew.size())) * 0.85
	c["progress"] = float(c.get("progress", 0.0)) + work
	c["builders"] = crew.size()
	c["crew_names"] = crew.slice(0, 3).map(func(x): return x.display_name())
	var days := float(c.get("days", 8.0))
	if float(c.progress) >= days:
		var type := str(c.type)
		s.add_building(type, float(c.x), float(c.z), float(c.rot), year)
		var names: Array = c.get("crew_names", [])
		s.construction = {}
		settlement_structure_changed.emit(s.id)
		for a in crew:
			a.set_emotion("proud", "built", 20.0)
			a.add_xp(6.0)
			a.skills["craft"] = mini(100, int(a.skills.get("craft", 0)) + 1)
		if type in ["temple", "library", "monument", "walls", "granary", "university", "hut", "farm", "lumber", "quarry", "market", "workshop"]:
			var who := ""
			if not names.is_empty():
				who = " (%s)" % ", ".join(PackedStringArray(names))
			var text := "%s построило %s%s" % [s.name, D.building(type).get("name", type), who]
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
		var h0 := world.heights[world.idx(cell.x, cell.y)]
		var flat := true
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var xx := clampi(cell.x + dx, 0, world.size - 1)
				var zz := clampi(cell.y + dz, 0, world.size - 1)
				if absf(world.heights[world.idx(xx, zz)] - h0) > 0.035:
					flat = false
					break
			if not flat:
				break
		if not flat:
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
	if total_population >= 420:
		return
	if s.population >= s.max_pop():
		return
	if s.resources.get("food", 0.0) < 20.0:
		return
	if s.plague > 0.0 or s.radioactive > 0.0:
		return
	var housing_mod := clampf(float(s.housing()) / maxf(1.0, s.population / 2.0), 0.3, 1.2)
	var food_mod := clampf(float(s.resources["food"]) / maxf(1.0, s.population), 0.5, 1.5)
	var mood_mod := clampf(1.0 + s.happiness / 80.0, 0.5, 1.3)
	var base := 0.0025 * float(mods.get("growth", 0.0) + 1.0) * food_mod * housing_mod * mood_mod * float(difficulty.get("growth", 1.0))
	if total_population < 40:
		base *= 1.7
	elif total_population > 340:
		base *= 0.35
	if s.population < 8:
		base *= 1.6
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
	# династия и вера наследуются
	child.dynasty = mother.dynasty
	child.generation = mother.generation + 1
	child.religion = mother.religion
	child.parent_ids = [mother.id]
	child.faith = mother.faith
	if mother.father_id > 0:
		child.parent_ids.append(mother.father_id)
		var f0: AgentData = agent_by_id.get(mother.father_id, null)
		if f0 != null:
			child.faith = (child.faith + f0.faith) * 0.5
	if s.leader_id == mother.id:
		child.heir = true
		mother.remember("birth", "Рождение наследника", child.id, child.pos, 3.0, year)
		_add_event(s, "birth", "В %s родился наследник %s" % [s.name, child.display_name()], 3, "crown")
	s.resources["food"] = maxf(0.0, float(s.resources["food"]) - 2.0)
	mother.set_emotion("happy", "birth", 2.0)
	child.bond_with(mother.id, 60.0)
	mother.bond_with(child.id, 60.0)
	for other in agents:
		if other.alive and other.settlement_id == s.id and other.pos.distance_to(mother.pos) < 8.0:
			other.set_emotion("happy", "birth", 0.5)
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
	if defenders.size() < maxi(2, attackers.size() / 5) and s.war_days > 5:
		s.siege_days += 1
		if s.siege_days >= 3:
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
				att.add_deed(3.0)
				if att.kills in [1, 5, 10, 25, 50]:
					att.add_title("Ветеран войны")
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
	var conqueror: AgentData = agent_by_id.get(att.leader_id, null)
	if conqueror != null:
		conqueror.add_title("Завоеватель " + def.name)
		conqueror.add_deed(20.0)
		conqueror.remember("war", "Взял " + def.name, def.id, Vector2(def.center), 4.0, year)
	def.resources = {"food": 0.0, "wood": 0.0, "stone": 0.0, "iron": 0.0, "gold": 0.0, "goods": 0.0}
	# гибель части населения
	var victims: Array = []
	var survivors := 0
	for a in agents:
		if a.settlement_id == def.id and a.alive:
			if rng.randf() < 0.35:
				victims.append(a)
			else:
				survivors += 1
	for a in victims:
		kill_agent(a, "battle")
	def.buildings.clear()
	settlement_structure_changed.emit(def.id)
	_add_event(def, "war", "%s разграблено армией %s" % [def.name, att.name], 4, "war")
	# сильный победитель оставляет вассала, слабый — руины
	if survivors >= 3 and att.population > def.population * 1.15 and rng.randf() < 0.65:
		_vassalize(att, def)
	else:
		_destroy_settlement(def, "sack")
	make_peace(att, def, true)


func _vassalize(att: SettlementData, def: SettlementData) -> void:
	if def.overlord_id >= 0:
		var old: SettlementData = settlement_by_id.get(def.overlord_id, null)
		if old != null:
			old.vassals.erase(def.id)
	def.overlord_id = att.id
	if not att.vassals.has(def.id):
		att.vassals.append(def.id)
	def.holy_war = false
	def.war_target = -1
	def.relations[att.id] = -25.0
	att.relations[def.id] = -15.0
	def.happiness = maxf(-100.0, def.happiness - 20.0)
	def.stability = maxf(5.0, def.stability - 25.0)
	# наследник побеждённых становится заложником/вассалом
	var ruler: AgentData = agent_by_id.get(def.leader_id, null)
	if ruler != null:
		ruler.add_title("Вассал " + att.name)
	_add_event(att, "war", "%s становится вассалом %s" % [def.name, att.name], 4, "crown")
	_add_event(def, "war", "%s признаёт власть %s" % [def.name, att.name], 4, "crown")
	toast.emit("%s — вассал %s" % [def.name, att.name], "war")


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
		if d < 90.0 and d < best_d:
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
	var parity := int(day) % 6
	for an in animals:
		if not an.alive:
			continue
		if int(an.id) % 6 != parity:
			continue
		an.age = float(an.age) + 6.0 / 365.0
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
		if an.breed_cd <= 0.0 and rng.randf() < float(an.breed) * 0.6:
			an.breed_cd = 60.0
			if animals.size() + newborns.size() < animals_cap and newborns.size() < 3:
				newborns.append(an.species)
		else:
			an.breed_cd = maxf(0.0, an.breed_cd - 1.5)
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


func _monsters_daily() -> void:
	var dead: Array = []
	for mv in monsters:
		var m: Dictionary = mv
		if not bool(m.get("alive", true)):
			continue
		m["age"] = float(m.get("age", 0.0)) + 1.0
		if float(m.age) > 900.0 or (total_population < 25 and rng.randf() < 0.02):
			m.alive = false
			dead.append(m)
			_add_world_event("monster", "%s уходит из этих земель" % str(m.get("name", "чудовище")), 2, "monster")
			continue
		var mp: Vector2 = m.pos
		var target: SettlementData = null
		var bd := 70.0
		for sv in settlements:
			var s: SettlementData = sv
			if s.destroyed:
				continue
			var d := mp.distance_to(Vector2(s.center))
			if d < bd:
				bd = d
				target = s
		if target != null:
			m.target = Vector2(target.center)
			# монстр двигается и без камеры — сессия продолжается
			var spd := float(m.get("speed", 1.0)) * 0.9
			if mp.distance_to(Vector2(target.center)) > 3.0:
				m.pos = mp.move_toward(Vector2(target.center), spd)
			# атака поселения
			if mp.distance_to(Vector2(target.center)) < float(target.territory_radius) + 1.0:
				for a in agents:
					if a.alive and a.settlement_id == target.id and a.pos.distance_to(mp) < 4.5 and rng.randf() < 0.07:
						a.health -= float(m.get("power", 40)) * rng.randf_range(0.18, 0.45)
						a.set_emotion("afraid", "monster", 20.0)
						if a.health <= 0.0:
							kill_agent(a, "monster")
				if rng.randf() < 0.18 and not target.buildings.is_empty():
					var bi := rng.randi() % target.buildings.size()
					target.buildings[bi]["hp"] = float(target.buildings[bi].get("hp", 100)) - float(m.get("power", 40)) * 0.3
					if float(target.buildings[bi].hp) <= 0.0:
						target.buildings.remove_at(bi)
						settlement_structure_changed.emit(target.id)
				if rng.randf() < 0.12:
					_ignite_cells(target.center.x, target.center.y, 3, 0.5)
		# герои и стража бьют монстра
		var hits := 0
		for av in agents:
			var a: AgentData = av
			if hits >= 4:
				break
			if not a.alive or a.pos.distance_to(mp) > 4.0:
				continue
			if a.action != "fight" and a.role not in ["warrior", "leader"] and a.personality("aggression") < 55.0:
				continue
			hits += 1
			var dmg: float = (a.attack_value() * rng.randf_range(0.25, 0.7) + a.level * 1.2)
			m.hp = float(m.get("hp", 100.0)) - dmg
			a.add_xp(3.0)
			a.remember("fight", "Бой с " + str(m.get("name", "чудовищем")), int(m.id), mp, 2.0, year)
			a.set_emotion("angry", "monster", 12.0)
			effect.emit("battle", a.pos, 1.0, {})
			# чудовище отвечает
			if rng.randf() < 0.45:
				a.health -= float(m.get("power", 40)) * rng.randf_range(0.35, 0.9)
				if a.health <= 0.0:
					kill_agent(a, "monster")
					continue
			if float(m.hp) <= 0.0:
				m.alive = false
				dead.append(m)
				a.kills += 1
				a.add_deed(12.0)
				a.add_title("Убийца " + monster_name_acc(str(m.get("kind", "giant"))))
				a.add_xp(90.0)
				a.set_emotion("proud", "victory", 40.0)
				a.notable = true
				var s2: SettlementData = settlement_by_id.get(a.settlement_id, null)
				if s2 != null:
					s2.resources["food"] = minf(s2.storage_cap(), float(s2.resources.get("food", 0.0)) + 40.0)
					s2.happiness = minf(100.0, s2.happiness + 18.0)
					_add_event(s2, "monster", "%s побеждает %s" % [a.display_name(), monster_name_acc(str(m.get("kind", "giant")))], 4, "sword")
				if a.favourite:
					toast.emit("%s побеждает %s!" % [a.display_name(), monster_name_acc(str(m.get("kind", "giant")))], "power")
				effect.emit("monster_death", mp, 2.0, {})
				break
			elif a.health <= 0.0:
				kill_agent(a, "monster")
	for m in dead:
		monsters.erase(m)
	# новые угрозы
	if year >= 3 and total_population > 70 and _alive_settlement_count() >= 4 and monsters.size() < 2 and rng.randf() < 0.0018 * float(difficulty.get("disaster", 1.0)):
		var kind: String = MONSTER_KINDS[rng.randi() % MONSTER_KINDS.size()]
		var cell := _random_wild_cell()
		if cell.x >= 0:
			_spawn_monster(kind, cell)
			_add_world_event("monster", "В мир приходит %s" % monster_name(kind), 4, "monster")


func monster_name(kind: String) -> String:
	match kind:
		"dragon": return "дракон"
		"undead": return "восставший легион"
		"giant": return "горный великан"
		"wyvern": return "виверна"
	return "чудовище"


func monster_name_acc(kind: String) -> String:
	match kind:
		"dragon": return "дракона"
		"undead": return "восставший легион"
		"giant": return "горного великана"
		"wyvern": return "виверну"
	return "чудовище"


func _random_wild_cell() -> Vector2i:
	for attempt in 40:
		var x := rng.randi_range(6, world.size - 7)
		var z := rng.randi_range(6, world.size - 7)
		if not world.is_land_cell(x, z):
			continue
		var ok := true
		for s in settlements:
			if not s.destroyed and Vector2(s.center).distance_to(Vector2(x, z)) < 18.0:
				ok = false
				break
		if ok:
			return Vector2i(x, z)
	return Vector2i(-1, -1)


func _spawn_monster(kind: String, cell: Vector2i) -> Dictionary:
	var stats := {
		"dragon": {"hp": 1600.0, "power": 100.0, "speed": 1.4, "size": 2.6, "color": Color("#b83a2a")},
		"undead": {"hp": 900.0, "power": 60.0, "speed": 0.9, "size": 1.8, "color": Color("#7aa87a")},
		"giant": {"hp": 1200.0, "power": 80.0, "speed": 0.8, "size": 2.2, "color": Color("#8a6a4a")},
		"wyvern": {"hp": 1000.0, "power": 70.0, "speed": 1.8, "size": 2.0, "color": Color("#6a5a8a")}
	}
	var st: Dictionary = stats.get(kind, stats["giant"])
	var m: Dictionary = {
		"id": next_monster_id, "kind": kind, "name": monster_name(kind),
		"pos": Vector2(cell), "target": Vector2(cell), "hp": float(st.hp),
		"max_hp": float(st.hp), "power": float(st.power), "speed": float(st.speed),
		"size": float(st.size), "color": st.color, "alive": true, "age": 0.0
	}
	next_monster_id += 1
	monsters.append(m)
	effect.emit("monster_spawn", Vector2(cell), 3.0, {"kind": kind})
	return m


func _diplomacy_daily() -> void:
	# раз в день — небольшая проверка, основные решения в _yearly
	for sv in settlements:
		var s: SettlementData = sv
		if s.destroyed:
			continue
		for ov in settlements:
			var other: SettlementData = ov
			if other.id <= s.id or other.destroyed:
				continue
			var dist := Vector2(s.center).distance_to(Vector2(other.center))
			if dist < 55.0:
				s.known[other.id] = true
				other.known[s.id] = true
			var rel := float(s.relations.get(other.id, 0.0))
			var same_faith: bool = s.religion == other.religion
			# вера сближает или разделяет
			if same_faith:
				rel += 0.012
			else:
				rel -= 0.018
			# миссионерство: сильная вера переубеждает соседа
			if same_faith and rel > 40.0 and s.zeal > 55.0 and rng.randf() < 0.00025:
				other.religion = s.religion
				other.zeal = clampf(other.zeal + 8.0, 0.0, 100.0)
				for av in agents:
					if av.alive and av.settlement_id == other.id and rng.randf() < 0.35:
						av.religion = s.religion
				_add_event(other, "faith", "%s принимает веру %s" % [other.name, religion_name(s.religion)], 2, "faith")
			# торговля по дороге
			var road: Dictionary = s.roads.get(other.id, {})
			if not road.is_empty() and float(road.get("progress", 0.0)) >= 1.0:
				rel += 0.01
				s.resources["gold"] = minf(float(s.resources.get("gold", 0.0)) + 0.35, s.storage_cap())
				other.resources["gold"] = minf(float(other.resources.get("gold", 0.0)) + 0.35, other.storage_cap())
			# дрейф и торговля
			if s.wars.has(other.id):
				continue
			if dist < 46.0:
				rel += rng.randf_range(-0.04, 0.035)
			else:
				rel += rng.randf_range(-0.015, 0.02)
			s.relations[other.id] = clampf(rel, -100.0, 100.0)
			other.relations[s.id] = s.relations[other.id]
			# война
			if rel < -22.0 and rng.randf() < 0.00035 * float(difficulty.get("aggr", 1.0)) * (1.0 + maxf(0.0, -rel) / 100.0):
				declare_war(s, other, "tension")
			elif not same_faith and s.zeal > 68.0 and not s.wars.has(other.id) and rng.randf() < 0.00012 * (s.zeal / 100.0):
				s.holy_war = true
				declare_war(s, other, "faith")
				_add_event(s, "faith", "%s объявляет священную войну против %s" % [s.name, other.name], 3, "faith")
			elif rel > 55.0 and not s.allies.has(other.id) and rng.randf() < 0.00015:
				s.allies.append(other.id)
				other.allies.append(s.id)
				_add_event(s, "diplomacy", L.tf("alliance_made", [s.name, other.name]), 2, "peace")


func _roads_tick() -> void:
	for s in settlements:
		if s.destroyed:
			continue
		for other in settlements:
			if other.id <= s.id or other.destroyed:
				continue
			if not s.known.has(other.id):
				continue
			if s.wars.has(other.id):
				continue
			var dist := Vector2(s.center).distance_to(Vector2(other.center))
			if dist > 55.0:
				continue
			var road: Dictionary = s.roads.get(other.id, {})
			if road.is_empty():
				road = {"progress": 0.0, "segments": [], "condition": 1.0, "to": other.id}
				s.roads[other.id] = road
				other.roads[s.id] = road
			var prog := float(road.get("progress", 0.0))
			if prog >= 1.0:
				road["condition"] = clampf(float(road.get("condition", 1.0)) - rng.randf_range(0.0, 0.0015), 0.4, 1.0)
				continue
			var wood := float(s.resources.get("wood", 0.0))
			if wood < 1.0:
				continue
			prog = minf(1.0, prog + 0.055)
			road["progress"] = prog
			s.resources["wood"] = wood - 0.6
			var total := maxi(3, int(dist * 1.6))
			var target_count := int(prog * total)
			var segs: Array = road.get("segments", [])
			while segs.size() < target_count:
				var t := float(segs.size()) / float(total)
				var px := float(s.center.x) + (float(other.center.x) - float(s.center.x)) * t
				var pz := float(s.center.y) + (float(other.center.y) - float(s.center.y)) * t
				var nx := -(float(other.center.y) - float(s.center.y))
				var nz := float(other.center.x) - float(s.center.x)
				var nl := sqrt(nx * nx + nz * nz)
				if nl > 0.01:
					nx /= nl
					nz /= nl
				var wob := sin(t * 11.0 + float(s.id)) * 1.2
				segs.append([px + nx * wob, pz + nz * wob])
			road["segments"] = segs
			if prog >= 1.0:
				_add_event(s, "road", "Дорога %s — %s завершена" % [s.name, other.name], 2, "road")
				_add_event(other, "road", "Дорога %s — %s завершена" % [other.name, s.name], 2, "road")


func road_between(a: SettlementData, b_id: int) -> Dictionary:
	if a == null:
		return {}
	return a.roads.get(b_id, {})


func on_road(pos: Vector2, s: SettlementData) -> bool:
	if s == null:
		return false
	for other_id in s.roads:
		var road: Dictionary = s.roads[other_id]
		if float(road.get("progress", 0.0)) < 1.0:
			continue
		for seg in road.get("segments", []):
			if pos.distance_squared_to(Vector2(float(seg[0]), float(seg[1]))) < 2.25:
				return true
	return false


func _expeditions_daily() -> void:
	# завершение/возврат существующих групп
	var done: Array = []
	for e in expeditions:
		var home: SettlementData = settlement_by_id.get(int(e.home), null)
		if home == null or home.destroyed:
			done.append(e)
			continue
		var members_alive := 0
		for mid in e.members:
			var m: AgentData = agent_by_id.get(int(mid), null)
			if m != null and m.alive:
				members_alive += 1
		if members_alive == 0:
			done.append(e)
			_add_event(home, "scout", "Экспедиция из %s не вернулась" % home.name, 2, "skull")
			continue
		e.timer = float(e.timer) - 1.0
		if e.phase == "out":
			var target := Vector2(e.target)
			var lead: AgentData = agent_by_id.get(int(e.members[0]), null)
			if lead != null and lead.pos.distance_to(target) < 2.5:
				# разведка: открываем ближайшие поселения
				for other in settlements:
					if other.id == home.id or other.destroyed:
						continue
					if Vector2(other.center).distance_to(target) < 28.0:
						home.known[other.id] = true
						other.known[home.id] = true
						_add_event(home, "scout", "Экспедиция из %s достигла %s" % [home.name, other.name], 2, "eye")
				# если место свободно — экспедиция основывает колонию
				var near_settle: SettlementData = _settlement_near(Vector2i(target), 24.0)
				if near_settle == null and home.population > 20 and _alive_settlement_count() < 18 and rng.randf() < 0.6:
					if _found_colony_from_expedition(home, Vector2i(target), e.members):
						done.append(e)
						continue
				e.phase = "return"
				e.timer = 60.0
				for mid in e.members:
					var m2: AgentData = agent_by_id.get(int(mid), null)
					if m2 != null and m2.alive:
						m2.set_action("patrol", Vector2(home.center), "return", 30.0)
						m2.carrying = ""
		elif e.phase == "return":
			var lead2: AgentData = agent_by_id.get(int(e.members[0]), null)
			if lead2 != null and lead2.pos.distance_to(Vector2(home.center)) < 3.0:
				done.append(e)
				_add_event(home, "scout", "Экспедиция вернулась в %s" % home.name, 1, "flag")
				for mid in e.members:
					var m3: AgentData = agent_by_id.get(int(mid), null)
					if m3 != null and m3.alive:
						m3.set_action("idle", Vector2(home.center), "returned", 1.0)
						m3.set_emotion("proud", "expedition", 10.0)
		elif float(e.timer) <= 0.0:
			e.phase = "return"
			for mid in e.members:
				var m4: AgentData = agent_by_id.get(int(mid), null)
				if m4 != null and m4.alive:
					m4.set_action("patrol", Vector2(home.center), "return", 40.0)
	for e in done:
		expeditions.erase(e)
	# запуск новой группы
	for s in settlements:
		if s.destroyed or s.population < 10:
			continue
		var already := false
		for e2 in expeditions:
			if int(e2.home) == s.id:
				already = true
				break
		if already or rng.randf() > 0.004:
			continue
		var pool: Array = []
		for a in agents:
			if a.alive and a.settlement_id == s.id and a.is_adult() and a.role not in ["leader", "warrior", "child"]:
				pool.append(a)
		if pool.size() < 2:
			continue
		pool.shuffle()
		var n := mini(rng.randi_range(2, 4), pool.size())
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(26.0, 46.0)
		var target2 := Vector2(s.center) + Vector2(cos(ang), sin(ang)) * dist
		target2.x = clampf(target2.x, 2.0, float(world.size - 2))
		target2.y = clampf(target2.y, 2.0, float(world.size - 2))
		var members: Array = []
		for i in n:
			var m: AgentData = pool[i]
			members.append(m.id)
			m.set_action("explore", target2 + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), "expedition", 60.0)
			m.set_emotion("proud", "expedition", 12.0)
			if i == 0:
				m.carrying = "flag"
				m.carry_amount = 1.0
		expeditions.append({
			"id": next_expedition_id, "home": s.id, "target": target2,
			"members": members, "phase": "out", "timer": 90.0
		})
		next_expedition_id += 1
		_add_event(s, "scout", "Экспедиция из %s отправилась на разведку" % s.name, 2, "flag")


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
	var offset := int(day) % 32
	var rad := world.radiation
	var n := world.n()
	for i in range(offset, n, 32):
		var r := rad[i]
		if r > 0.0:
			rad[i] = maxf(0.0, r - 0.0007)


func _emergency_peace() -> void:
	for sv in settlements:
		var s: SettlementData = sv
		if s.destroyed:
			continue
		for eid in s.wars.duplicate():
			var o: SettlementData = settlement_by_id.get(int(eid), null)
			if o != null:
				make_peace(s, o, true)


func _vassals_daily() -> void:	for sv in settlements:
		var s: SettlementData = sv
		if s.destroyed or s.overlord_id < 0:
			continue
		var ov: SettlementData = settlement_by_id.get(s.overlord_id, null)
		if ov == null or ov.destroyed:
			s.overlord_id = -1
			continue
		# дань
		var tribute_gold: float = float(s.resources.get("gold", 0.0)) * s.tribute_rate * 0.06
		var tribute_food: float = float(s.resources.get("food", 0.0)) * s.tribute_rate * 0.04
		s.resources["gold"] = maxf(0.0, float(s.resources.get("gold", 0.0)) - tribute_gold)
		s.resources["food"] = maxf(0.0, float(s.resources.get("food", 0.0)) - tribute_food)
		ov.resources["gold"] = minf(ov.storage_cap(), float(ov.resources.get("gold", 0.0)) + tribute_gold)
		ov.resources["food"] = minf(ov.storage_cap(), float(ov.resources.get("food", 0.0)) + tribute_food)
		# вассал вступает в войны сюзерена
		for eid in ov.wars:
			if int(eid) != s.id and not s.wars.has(int(eid)):
				s.wars.append(int(eid))
				if s.war_target < 0:
					s.war_target = int(eid)
		# восстание
		var rel := float(s.relations.get(ov.id, -20.0))
		var loyalty: float = 55.0 + rel * 0.35 + float(ov.army - s.army) * 1.5 - s.zeal * 0.08
		if (s.stability < 30.0 or loyalty < 18.0) and rng.randf() < 0.004:
			s.overlord_id = -1
			ov.vassals.erase(s.id)
			if not s.wars.has(ov.id):
				s.wars.append(ov.id)
			s.war_target = ov.id
			s.happiness = minf(100.0, s.happiness + 10.0)
			_add_event(s, "war", "%s восстаёт против %s" % [s.name, ov.name], 3, "revolt")
			_add_event(ov, "war", "%s восстаёт против %s" % [s.name, ov.name], 3, "revolt")
			toast.emit("Восстание: %s против %s" % [s.name, ov.name], "war")


func _legends_daily() -> void:
	if int(day) % 3 != 0:
		return
	for av in agents:
		var a: AgentData = av
		if not a.alive:
			continue
		var sc := a.legend_score()
		if sc > 140.0 and a.titles.size() < 3 and rng.randf() < 0.01:
			if a.add_title("Легенда " + str(a.dynasty)):
				var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
				if s != null:
					_add_event(s, "legend", "Легенда: %s" % a.display_name(), 3, "star")
				if a.favourite:
					toast.emit("%s становится легендой" % a.display_name(), "crown")
		elif sc > 55.0 and a.titles.is_empty() and rng.randf() < 0.004:
			if a.add_title("Ветеран"):
				if a.favourite:
					toast.emit("%s получает титул «Ветеран»" % a.display_name(), "info")
	# вражда внутри поселения
	for sv in settlements:
		var s: SettlementData = sv
		if s.destroyed or s.population < 4:
			continue
		if rng.randf() > 0.02:
			continue
		var local: Array = []
		for av2 in agents:
			var a2: AgentData = av2
			if a2.alive and a2.settlement_id == s.id:
				local.append(a2)
		if local.size() < 2:
			continue
		var x: AgentData = local[rng.randi() % local.size()]
		var y: AgentData = local[rng.randi() % local.size()]
		if x.id == y.id:
			continue
		if x.rival_id != y.id and float(x.bonds.get(y.id, 0.0)) < -25.0:
			x.rival_id = y.id
			y.rival_id = x.id
			x.set_emotion("angry", "rival", 20.0)
			y.set_emotion("angry", "rival", 20.0)
			x.remember("feud", "Вражда с " + y.display_name(), y.id, y.pos, 2.0, year)
			_add_event(s, "feud", "%s и %s стали врагами" % [x.display_name(), y.display_name()], 1, "sword")


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
					if o != null and rng.randf() < 0.5:
						make_peace(s, o, false)
		# объявление войны
		if s.wars.is_empty() and s.army > 6 and rng.randf() < 0.006 * float(difficulty.get("aggr", 1.0)) * (1.0 + maxf(0.0, -s.happiness) / 100.0):
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
	s.religion = parent.religion
	s.zeal = parent.zeal
	s.dynasty = parent.dynasty
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
	var ld2: AgentData = agent_by_id.get(s.leader_id, null)
	if ld2 != null:
		s.dynasty = ld2.dynasty
		s.founded_by = ld2.id
	_add_event(parent, "founded", "%s основало колонию %s" % [parent.name, s.name], 3, "people")
	toast.emit(L.tf("toast_city", [s.name]), "city")
	settlement_founded.emit(s)


func _found_colony_from_expedition(home: SettlementData, cell: Vector2i, members: Array) -> bool:
	if not world.is_land_cell(cell.x, cell.y):
		return false
	var h0 := world.heights[world.idx(cell.x, cell.y)]
	var flat := true
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var hh := world.heights[world.idx(clampi(cell.x + dx, 0, world.size - 1), clampi(cell.y + dz, 0, world.size - 1))]
			if absf(hh - h0) > 0.05:
				flat = false
				break
		if not flat:
			break
	if not flat:
		return false
	var s := SettlementData.new()
	s.setup(next_settlement_id, home.race_id, cell, year, rng)
	s.name = _unique_name(s.name, s.id)
	next_settlement_id += 1
	s.resources = {"food": 60.0, "wood": 40.0, "stone": 15.0, "iron": 0.0, "gold": 5.0, "goods": 0.0}
	s.religion = home.religion
	s.zeal = home.zeal
	s.known[home.id] = true
	home.known[s.id] = true
	s.relations[home.id] = 70.0
	home.relations[s.id] = 70.0
	s.dynasty = home.dynasty
	settlements.append(s)
	settlement_by_id[s.id] = s
	world.add_clearing(s.center, 8.0)
	s.add_building("campfire", s.center.x, s.center.y, rng.randf() * TAU, year)
	var settlers := 0
	for mid in members:
		var a: AgentData = agent_by_id.get(int(mid), null)
		if a == null or not a.alive:
			continue
		a.settlement_id = s.id
		a.pos = Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		a.target = a.pos
		a.home_pos = a.pos
		a.set_action("work", a.pos, "settled", 5.0)
		a.carrying = ""
		a.set_emotion("proud", "settled", 30.0)
		a.remember("colony", "Основал " + s.name, s.id, a.pos, 5.0, year)
		a.add_title("Первопроходец " + s.name)
		settlers += 1
	_assign_leader(s)
	var ld3: AgentData = agent_by_id.get(s.leader_id, null)
	if ld3 != null:
		s.dynasty = ld3.dynasty
		s.founded_by = ld3.id
	_add_event(home, "founded", "Экспедиция из %s основала %s" % [home.name, s.name], 3, "flag")
	_add_event(s, "founded", "%s основано первопроходцами из %s" % [s.name, home.name], 3, "people")
	toast.emit("Новая колония: %s" % s.name, "city")
	settlement_founded.emit(s)
	return true


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
		var h0 := world.heights[world.idx(c.x, c.y)]
		var flat := true
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var hh := world.heights[world.idx(clampi(c.x + dx, 0, world.size - 1), clampi(c.y + dz, 0, world.size - 1))]
				if absf(hh - h0) > 0.05:
					flat = false
					break
			if not flat:
				break
		if not flat:
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
	var race_id := s.race_id if s != null else "human"
	a.setup(next_agent_id, D.race(race_id), gender, age, rng)
	next_agent_id += 1
	a.settlement_id = s.id if s != null else -1
	a.religion = s.religion if s != null else str(RELIGIONS[rng.randi() % RELIGIONS.size()].id)
	a.faith = rng.randf_range(35.0, 75.0)
	a.role = role if role != "worker" else a.role
	a.pos = pos
	a.target = pos
	a.home_pos = pos
	a.born_year = year - int(age)
	a.equipment = clampi((s.era if s != null else 0) / 2, 0, 5)
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


func _spawn_animal(species: String, cell: Vector2i) -> Dictionary:
	if cell.x < 0 or animals.size() >= animals_cap:
		return {}
	var sp: Dictionary = D.animal(species)
	if sp.is_empty():
		return {}
	var an: Dictionary = {
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
	return an


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
			for other in agents:
				if other.alive and other.settlement_id == s.id:
					other.set_emotion("grieving", "leader_died", 60.0)
					other.bond_with(a.id, -10.0)
			_assign_leader(s)
		elif a.notable or a.level >= 20:
			_add_event(s, "death", "Умер %s из %s (%s)" % [a.display_name(), s.name, L.t("cause_" + cause)], 2, "skull")
		if cause == "war" or cause == "beast":
			for other in agents:
				if other.alive and other.settlement_id == s.id and other.pos.distance_to(a.pos) < 9.0:
					other.set_emotion("afraid", cause, 20.0)
					other.bond_with(a.id, -6.0)
					other.remember("death", "Смерть " + a.display_name(), a.id, a.pos, 1.0, year)
		if a.favourite:
			toast.emit("Ваш избранник %s погиб (%s)" % [a.display_name(), L.t("cause_" + cause)], "death")
		if a.legend_score() > 70.0:
			_add_world_event("legend", "Легенда угасла: %s" % a.display_name(), 3, "skull")
	if a.partner_id > 0:
		var p: AgentData = agent_by_id.get(a.partner_id, null)
		if p != null:
			p.partner_id = -1


func _assign_targets(s: SettlementData, local: Array) -> void:
	# решения принимаются раз в 3 дня на поселение — так поведение стабильнее и дешевле
	if int(day) % 3 != s.id % 3:
		return
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
	var has_site := not s.construction.is_empty()
	var site := Vector2.ZERO
	if has_site:
		site = Vector2(float(s.construction.get("x", center.x)), float(s.construction.get("z", center.y)))
	# бригада: до 3 взрослых с лучшим ремеслом
	var builder_ids: Dictionary = {}
	if has_site:
		var cand: Array = []
		for a0v in local:
			var a0: AgentData = a0v
			if a0.alive and a0.is_adult() and a0.role not in ["leader", "warrior", "child"]:
				cand.append(a0)
		cand.sort_custom(func(x, y): return float(x.skills.get("craft", 0)) > float(y.skills.get("craft", 0)))
		for i in mini(3, cand.size()):
			builder_ids[cand[i].id] = true
			cand[i].role = "builder"
	for av in local:
		var a: AgentData = av
		if not a.alive:
			continue
		if a.action == "explore":
			continue
		if a.age >= a.maturity() and a.role == "child":
			a.role = "worker"
		if a.role == "worker" and a.is_adult() and not has_site:
			var fr: float = float(s.resources.get("food", 0.0)) / maxf(1.0, float(s.population) * 0.7)
			if a.id % 6 == 0 and fr < 1.5:
				a.role = "hunter"
			elif a.id % 5 == 0 and s.has_building("farm"):
				a.role = "farmer"
			elif a.id % 7 == 0 and (s.has_building("lumber") or s.has_building("quarry")):
				a.role = "hunter"
			elif a.id % 11 == 0 and s.has_building("library"):
				a.role = "scholar"
		if a.role == "warrior" and enemy != null and not enemy.destroyed:
			var phase := "march"
			var wt := Vector2(enemy.center)
			if s.war_days < 2:
				phase = "gather"
				wt = center + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			elif s.war_days < 5:
				phase = "march"
			else:
				phase = "siege"
				wt = Vector2(enemy.center) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			a.war_phase = phase
			a.set_action(phase, wt, "war", 2.0)
			if phase == "siege":
				a.set_emotion("angry", "war", 12.0)
			continue
		if builder_ids.has(a.id):
			var bt := site + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
			a.set_action("build", bt, "construction", 3.0)
			a.action_progress = float(s.construction.get("progress", 0.0)) / maxf(1.0, float(s.construction.get("days", 8.0)))
			continue
		if a.role == "child":
			if a.age >= 12.0:
				var b3: Dictionary = s.buildings[rng.randi() % maxi(1, s.buildings.size())] if not s.buildings.is_empty() else {}
				var wt3 := center + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
				if not b3.is_empty():
					wt3 = Vector2(float(b3.x), float(b3.z)) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				a.set_action("work", wt3, "help", 3.0)
			else:
				var ct := center + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
				a.set_action("play", ct, "child", rng.randf_range(2.0, 4.0))
			continue
		if a.role == "leader":
			if has_site and rng.randf() < 0.6:
				a.set_action("build", site + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)), "supervise", 2.0)
			else:
				a.set_action("idle", center + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), "leader", 2.0)
			continue
		# устойчивость действия: не дёргаем цель каждый день
		var urgent: bool = a.satiety < 18.0 or a.thirst < 18.0 or a.energy < 10.0 or a.health < a.max_health * 0.35
		if not urgent and a.action_time < a.action_duration and a.action in ["sleep", "work", "socialize", "pray", "hunt", "haul", "patrol", "play", "idle"]:
			continue
		var food_ratio: float = float(s.resources.get("food", 0.0)) / maxf(1.0, float(s.population) * 0.7)
		var u_sleep := clampf((55.0 - a.energy) / 55.0, 0.0, 1.0) * 1.35
		var u_eat := clampf((60.0 - a.satiety) / 60.0, 0.0, 1.0) * 1.5
		var u_drink := clampf((60.0 - a.thirst) / 60.0, 0.0, 1.0) * 1.6
		var u_build := 0.0
		var u_hunt := 0.0
		if a.role == "hunter":
			u_hunt = 0.72 + maxf(0.0, 1.1 - clampf(food_ratio, 0.0, 1.5)) * 0.9
		elif float(a.skills.get("survival", 0)) > 42.0 and food_ratio < 1.0:
			u_hunt = (1.05 - clampf(food_ratio, 0.0, 1.0)) * 1.1
		u_hunt += a.personality("aggression") / 320.0
		var u_work: float = 0.5 + float(a.skills.get("craft", 0)) / 320.0 + a.personality("ambition") / 360.0
		var u_social: float = clampf((18.0 - a.mood) / 36.0, 0.0, 1.0) * 0.55 + a.personality("sociability") / 340.0
		var u_pray: float = clampf(maxf(0.0, -s.happiness) / 60.0, 0.0, 1.0) * 0.5 + a.personality("piety") / 360.0
		var u_patrol: float = a.personality("curiosity") / 420.0
		var monster: Dictionary = _nearest_monster(a.pos, 16.0)
		var u_fight := 0.0
		var u_flee := 0.0
		if not monster.is_empty():
			u_fight = 0.8 + a.personality("aggression") / 180.0
			if a.role == "warrior" or a.role == "leader":
				u_fight += 0.5
			if a.personality("loyalty") > 65.0:
				u_fight += 0.3
			if a.personality("aggression") < 50.0 or a.health < a.max_health * 0.5:
				u_flee = 1.0
				u_fight *= 0.4
		var best := "work"
		var best_u := u_work
		if u_sleep > best_u: best = "sleep"; best_u = u_sleep
		if u_eat > best_u: best = "eat"; best_u = u_eat
		if u_drink > best_u: best = "drink"; best_u = u_drink
		if u_build > best_u: best = "build"; best_u = u_build
		if u_hunt > best_u: best = "hunt"; best_u = u_hunt
		if u_social > best_u: best = "socialize"; best_u = u_social
		if u_pray > best_u: best = "pray"; best_u = u_pray
		if u_fight > best_u: best = "fight"; best_u = u_fight
		if u_flee > best_u: best = "flee"; best_u = u_flee
		if u_patrol > best_u: best = "patrol"; best_u = u_patrol
		match best:
			"sleep":
				var st := center
				if not hut.is_empty():
					st = Vector2(hut.x, hut.z) + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
				a.set_action("sleep", st, "tired", 4.0)
			"eat":
				var et := center
				if not farm.is_empty():
					et = Vector2(farm.x, farm.z) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
				a.set_action("eat", et, "hungry", 1.0)
			"drink":
				var dt := center
				if water_target.x >= 0:
					dt = Vector2(water_target.x, water_target.y)
				a.set_action("drink", dt, "thirsty", 1.0)
			"hunt":
				var prey := _nearest_animal(a.pos, 30.0)
				if not prey.is_empty():
					a.hunting_id = int(prey.id)
					a.set_action("hunt", prey.pos, "food", 6.0)
				else:
					var b2: Dictionary = s.buildings[rng.randi() % maxi(1, s.buildings.size())] if not s.buildings.is_empty() else {}
					var wt2 := center + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
					if not b2.is_empty():
						wt2 = Vector2(float(b2.x), float(b2.z))
					a.set_action("work", wt2, "no_prey", 3.0)
			"socialize":
				var friend := _friend_of(a, local)
				var st2 := center + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
				if friend != null:
					st2 = friend.pos
					var same_faith2: bool = a.religion == friend.religion
					var delta: float = 1.5 * (0.5 + a.personality("sociability") / 100.0)
					if friend.rival_id == a.id or not same_faith2:
						delta = -2.2
						a.set_emotion("angry", "rival", 10.0)
						friend.set_emotion("angry", "rival", 10.0)
					a.bond_with(friend.id, delta)
					friend.bond_with(a.id, delta)
					if delta > 0.0:
						a.set_emotion("happy", "friends", 8.0)
						a.remember("social", "Разговор с " + friend.display_name(), friend.id, friend.pos, 0.5, year)
				a.set_action("socialize", st2, "social", 3.0)
			"pray":
				var temple := _building_of_type(s, "temple")
				var pt := center
				if not temple.is_empty():
					pt = Vector2(temple.x, temple.z)
				a.set_action("pray", pt, "faith", 2.0)
			"fight":
				a.hunting_id = int(monster.id)
				a.set_action("fight", Vector2(monster.pos), "monster", 4.0)
				a.set_emotion("angry", "monster", 10.0)
			"flee":
				var away2 := a.pos - Vector2(monster.pos)
				if away2.length() < 0.1:
					away2 = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				a.set_action("flee", a.pos + away2.normalized() * 9.0, "fear", 3.0)
				a.set_emotion("afraid", "monster", 15.0)
			"patrol":
				var pang := rng.randf() * TAU
				a.set_action("patrol", center + Vector2(cos(pang), sin(pang)) * radius, "curiosity", 5.0)
			_:
				if not s.buildings.is_empty():
					var b: Dictionary = s.buildings[rng.randi() % s.buildings.size()]
					a.set_action("work", Vector2(float(b.x), float(b.z)) + Vector2(rng.randf_range(-1.1, 1.1), rng.randf_range(-1.1, 1.1)), "job", 4.0)
				else:
					var ang := rng.randf() * TAU
					var rr := rng.randf_range(1.0, radius)
					a.set_action("wander", center + Vector2(cos(ang), sin(ang)) * rr, "idle", 2.0)
		a.action_utility = best_u


func _friend_of(a: AgentData, local: Array) -> AgentData:
	if a.partner_id > 0:
		var p: AgentData = agent_by_id.get(a.partner_id, null)
		if p != null and p.alive:
			return p
	var best: AgentData = null
	var best_v := 0.0
	for o in local:
		if o.id == a.id or not o.alive:
			continue
		var v := float(a.bonds.get(o.id, 0.0))
		if v > best_v:
			best_v = v
			best = o
	return best


func _nearest_animal(p: Vector2, max_dist: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_dist
	for an in animals:
		if not an.alive or bool(an.get("predator", false)):
			continue
		var d: float = Vector2(an.pos).distance_to(p)
		if d < bd:
			bd = d
			best = an
	return best


func _nearest_monster(p: Vector2, max_dist: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_dist
	for m in monsters:
		if not bool(m.get("alive", true)):
			continue
		var d: float = Vector2(m.pos).distance_to(p)
		if d < bd:
			bd = d
			best = m
	return best


# ------------------------------------------------------------------ hunting / hauling

func complete_hunt(a: AgentData, an: Dictionary) -> void:
	if an.is_empty() or not bool(an.get("alive", false)):
		return
	an.alive = false
	animal_by_id.erase(int(an.id))
	animals.erase(an)
	a.kills += 1
	a.hunting_id = -1
	a.carrying = "carcass"
	a.carry_amount = maxf(0.25, float(an.get("size", 0.7)))
	a.add_xp(5.0)
	a.set_emotion("proud", "hunt", 18.0)
	var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
	var home := a.home_pos
	if s != null and not s.destroyed:
		home = Vector2(s.center)
	a.set_action("haul", home, "carry_carcass", 10.0)
	effect.emit("hunt", a.pos, 1.0, {"species": str(an.get("species", "animal"))})
	if s != null and not s.destroyed:
		_add_event(s, "hunt", "%s добыл %s" % [a.display_name(), L.t("animal_" + str(an.get("species", "animal")))], 1, "hunt")


func complete_haul(a: AgentData) -> void:
	if a.carrying.is_empty():
		return
	var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
	var gained := a.carry_amount * 55.0
	if s != null and not s.destroyed:
		s.resources["food"] = float(s.resources.get("food", 0.0)) + gained
		s.resources["food"] = minf(float(s.resources["food"]), s.storage_cap())
	a.carrying = ""
	a.carry_amount = 0.0
	a.set_action("eat", a.pos, "food", 1.0)
	a.set_emotion("happy", "food", 10.0)


# ------------------------------------------------------------------ god actions on one agent

func god_agent_action(a: AgentData, kind: String) -> String:
	if a == null or not a.alive:
		return ""
	match kind:
		"heal":
			a.health = a.max_health
			a.set_emotion("happy", "healed", 20.0)
			a.sanity = minf(100.0, a.sanity + 20.0)
			return "+HP"
		"bless":
			a.health = a.max_health
			a.mood += 12.0
			a.sanity = minf(100.0, a.sanity + 15.0)
			if not a.perks.has("lucky"):
				a.perks.append("lucky")
			a.set_emotion("happy", "blessed", 40.0)
			return "perk: lucky"
		"curse":
			a.mood -= 18.0
			a.sanity = maxf(0.0, a.sanity - 20.0)
			a.set_emotion("afraid", "cursed", 40.0)
			return "-mood"
		"scare":
			a.set_emotion("afraid", "god", 18.0)
			var s: SettlementData = settlement_by_id.get(a.settlement_id, null)
			if s != null:
				var away: Vector2 = a.pos - Vector2(s.center)
				if away.length() < 0.1:
					away = Vector2(1, 0)
				a.set_action("flee", a.pos + away.normalized() * 8.0, "fear", 2.0)
			return "fear"
		"reward":
			a.add_xp(15.0)
			a.mood += 10.0
			a.set_emotion("proud", "rewarded", 30.0)
			var st: SettlementData = settlement_by_id.get(a.settlement_id, null)
			if st != null:
				st.resources["gold"] = float(st.resources.get("gold", 0.0)) + 5.0
			return "+XP"
		"immortal":
			a.immortal = not a.immortal
			if a.immortal:
				a.unkillable = false
			a.set_emotion("proud", "immortal", 60.0)
			return "immortal" if a.immortal else "mortal"
		"perk_tough":
			_toggle_perk(a, "tough")
			return "tough"
		"perk_genius":
			_toggle_perk(a, "genius")
			return "genius"
		"perk_swift":
			_toggle_perk(a, "swift")
			return "swift"
	return ""


func _toggle_perk(a: AgentData, pk: String) -> void:
	if a.perks.has(pk):
		a.perks.erase(pk)
	else:
		a.perks.append(pk)
	a.max_health = a.compute_max_health()
	a.health = minf(a.health, a.max_health)
	a.set_emotion("happy", "perk", 20.0)


func rename_agent(a: AgentData, new_name: String) -> void:
	var parts := new_name.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	a.name = parts[0]
	if parts.size() > 1:
		a.family = " ".join(parts.slice(1))
	a.notable = true


func spawn_agent_custom(cell: Vector2i, race_id: String, gender: int, age: float, settlement_id: int, perks: Array = []) -> AgentData:
	var s: SettlementData = settlement_by_id.get(settlement_id, null)
	var race := D.race(race_id)
	var pos := Vector2(cell) if s == null else Vector2(s.center) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
	var a := AgentData.new()
	a.setup(next_agent_id, race, gender, age, rng)
	next_agent_id += 1
	a.race_id = race_id
	a.settlement_id = settlement_id
	a.religion = s.religion if s != null else str(RELIGIONS[rng.randi() % RELIGIONS.size()].id)
	a.faith = rng.randf_range(35.0, 80.0)
	a.dynasty = a.family
	a.role = "worker" if age >= 18 else "child"
	a.pos = pos
	a.target = pos
	a.home_pos = pos
	a.born_year = year - int(age)
	a.equipment = clampi((s.era if s != null else 0) / 2, 0, 5)
	for pk in perks:
		if not a.perks.has(str(pk)):
			a.perks.append(str(pk))
	a.max_health = a.compute_max_health(race)
	a.health = a.max_health
	agents.append(a)
	agent_by_id[a.id] = a
	agent_spawned.emit(a)
	return a


func spawn_animal_custom(cell: Vector2i, species: String, gender: int, age: float) -> Dictionary:
	var an := _spawn_animal(species, cell)
	if an.is_empty():
		return an
	an["gender"] = gender
	an["age"] = age
	an["domestic"] = false
	return an


func a_maturity_age(race_id: String) -> float:
	return float(D.race(race_id).get("maturity", 18)) + 1.0


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
	var prev_id := s.leader_id
	var best: AgentData = null
	var best_score := -1.0
	for a in agents:
		if a.settlement_id == s.id and a.alive and a.is_adult():
			var score: float = a.charisma + float(a.skills.get("leadership", 20)) + a.level * 2.0 + a.legend_score() * 0.15
			if a.heir:
				score += 55.0
			if a.parent_ids.has(prev_id):
				score += 45.0
			if not s.dynasty.is_empty() and a.dynasty == s.dynasty:
				score += 25.0
			if score > best_score:
				best_score = score
				best = a
	if best != null:
		for a in agents:
			if a.settlement_id == s.id and a.alive:
				a.heir = false
		s.leader_id = best.id
		s.dynasty = best.dynasty
		best.role = "leader"
		best.notable = true
		best.add_title("Правитель " + s.name)
		best.remember("leader", "Избран правителем " + s.name, s.id, best.pos, 3.0, year)
		_add_event(s, "leader", L.tf("new_leader", [best.display_name(), s.name]), 1, "crown")
		if best.favourite:
			toast.emit("%s избран правителем %s" % [best.display_name(), s.name], "crown")


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
			a.set_emotion("afraid", source, 18.0)
			var away: Vector2 = a.pos - center
			if away.length() < 0.2:
				away = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if a.health > 0.0 and a.action != "flee":
				a.set_action("flee", a.pos + away.normalized() * rng.randf_range(4.0, 9.0), "fear", 2.0)
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
			a.set_emotion("happy", "blessed", 30.0)
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
	var rel: Dictionary = RELIGIONS[rng.randi() % RELIGIONS.size()]
	s.religion = str(rel.id)
	s.zeal = rng.randf_range(30.0, 70.0)
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
	var ld: AgentData = agent_by_id.get(s.leader_id, null)
	if ld != null:
		s.dynasty = ld.dynasty
		s.founded_by = ld.id
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
	if rng.randf() < 0.45:
		var rel: Dictionary = RELIGIONS[rng.randi() % RELIGIONS.size()]
		s.religion = str(rel.id)
	s.zeal = 100.0
	var p := spawn_agent(s, rng.randf_range(25, 40), rng.randi() % 2, "worker", Vector2(s.center))
	p.magic = minf(100.0, p.magic + 40.0)
	p.charisma = minf(100.0, p.charisma + 30.0)
	p.wisdom = minf(100.0, p.wisdom + 20.0)
	p.notable = true
	p.religion = s.religion
	p.faith = 100.0
	p.role = "leader"
	p.add_title("Пророк " + religion_name(s.religion))
	p.remember("faith", "Основал веру " + religion_name(s.religion), s.id, p.pos, 5.0, year)
	s.leader_id = p.id
	s.dynasty = p.dynasty
	for a in agents:
		if a.alive and a.settlement_id == s.id:
			a.religion = s.religion
			a.faith = maxf(a.faith, 70.0)
	_add_event(s, "prophet", L.tf("prophet", [s.name]), 3, "prophet")
	_add_event(s, "faith", "%s: новая эра веры — %s" % [s.name, religion_name(s.religion)], 3, "faith")
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


func religion_info(id: String) -> Dictionary:
	for r in RELIGIONS:
		if str(r.id) == id:
			return r
	return {"id": id, "name": id, "color": "#c8c8c8"}


func religion_name(id: String) -> String:
	return str(religion_info(id).get("name", id))


func religion_color(id: String) -> Color:
	return Color(str(religion_info(id).get("color", "#c8c8c8")))


func top_legends(count: int = 8) -> Array:
	var arr: Array = []
	for a in agents:
		if a.alive and a.legend_score() > 8.0:
			arr.append(a)
	arr.sort_custom(func(x, y): return x.legend_score() > y.legend_score())
	return arr.slice(0, count)


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
	var mo: Array = []
	for m in monsters:
		mo.append({
			"id": int(m.id), "kind": str(m.kind), "name": str(m.name),
			"pos": [m.pos.x, m.pos.y], "target": [m.target.x, m.target.y],
			"hp": float(m.hp), "max_hp": float(m.max_hp), "power": float(m.power),
			"speed": float(m.speed), "size": float(m.size), "alive": bool(m.alive), "age": float(m.get("age", 0.0))
		})
	return {
		"day": day, "year": year, "season": season, "total_population": total_population,
		"next_agent_id": next_agent_id, "next_settlement_id": next_settlement_id,
		"next_animal_id": next_animal_id, "agents": ag, "animals": an,
		"settlements": st, "chronicle": chronicle.to_dict(),
		"weather": weather_mode, "weather_days_left": weather_days_left, "nuclear_winter": nuclear_winter,
		"nukes_total": nukes_total, "world_age_years": world_age_years,
		"burning": burning.keys(), "monsters": mo, "next_monster_id": next_monster_id
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
		if s.religion.is_empty():
			s.religion = str(RELIGIONS[rng.randi() % RELIGIONS.size()].id)
		settlements.append(s)
		settlement_by_id[s.id] = s
		if not s.destroyed:
			world.add_clearing(s.center, 9.0)
	for a in agents:
		if a.religion.is_empty():
			var sa: SettlementData = settlement_by_id.get(a.settlement_id, null)
			a.religion = sa.religion if sa != null else str(RELIGIONS[rng.randi() % RELIGIONS.size()].id)
		if a.dynasty.is_empty():
			a.dynasty = a.family
	chronicle = ChronicleData.from_dict(d.get("chronicle", {}))
	monsters.clear()
	for md in d.get("monsters", []):
		var mp: Array = md.get("pos", [0, 0])
		var mt: Array = md.get("target", [0, 0])
		monsters.append({
			"id": int(md.get("id", 0)), "kind": str(md.get("kind", "giant")),
			"name": str(md.get("name", "чудовище")),
			"pos": Vector2(float(mp[0]), float(mp[1])),
			"target": Vector2(float(mt[0]), float(mt[1])),
			"hp": float(md.get("hp", 100)), "max_hp": float(md.get("max_hp", 100)),
			"power": float(md.get("power", 40)), "speed": float(md.get("speed", 1.0)),
			"size": float(md.get("size", 2.0)), "alive": bool(md.get("alive", true)),
			"age": float(md.get("age", 0.0))
		})
	next_monster_id = int(d.get("next_monster_id", monsters.size() + 1))
	burning.clear()
	for k in d.get("burning", []):
		burning[int(k)] = world.burn[int(k)] if int(k) < world.n() else 0.0
	_update_settlement_counts()
