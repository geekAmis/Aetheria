class_name SettlementData
extends RefCounted
## Поселение: экономика, здания, технологии, политика.

var id: int = 0
var race_id: String = "human"
var name: String = ""
var center: Vector2i = Vector2i.ZERO
var founded_year: int = 0
var stage: String = "camp"
var leader_id: int = -1
var resources: Dictionary = {"food": 60.0, "wood": 40.0, "stone": 20.0, "iron": 0.0, "gold": 5.0, "goods": 0.0}
var buildings: Array = []
var construction: Dictionary = {}
var techs: Array = []
var researching: String = ""
var research_progress: float = 0.0
var era: int = 0
var era_techs_done: int = 0
var faith: float = 5.0
var happiness: float = 8.0
var stability: float = 65.0
var wars: Array = []
var allies: Array = []
var relations: Dictionary = {}
var war_target: int = -1
var war_days: int = 0
var siege_days: int = 0
var army: int = 0
var plague: float = 0.0
var fire: float = 0.0
var drought: float = 0.0
var blizzard: float = 0.0
var blessed: float = 0.0
var cursed: float = 0.0
var radioactive: float = 0.0
var population: int = 0
var color: Color = Color(1, 1, 1)
var territory_radius: float = 8.0
var last_birth_day: float = 0.0
var last_event_day: float = 0.0
var destroyed: bool = false
var nuked: bool = false
var total_births: int = 0
var total_deaths: int = 0
var age_sum: float = 0.0
var prosperity: float = 1.0
var water_cell: Vector2i = Vector2i(-1, -1)
var water_day: int = -999
var known: Dictionary = {}          # id -> true
var roads: Dictionary = {}          # id -> {progress, segments, condition}

const STAGE_POPS := {"camp": 0, "village": 15, "town": 55, "city": 150, "metropolis": 350}
const STAGE_RADIUS := {"camp": 7.0, "village": 11.0, "town": 17.0, "city": 25.0, "metropolis": 34.0}
const STAGE_CAP := {"camp": 18, "village": 70, "town": 190, "city": 430, "metropolis": 900}


func setup(p_id: int, p_race: String, p_center: Vector2i, p_year: int, rng: RandomNumberGenerator) -> void:
	id = p_id
	race_id = p_race
	center = p_center
	founded_year = p_year
	var r: Dictionary = D.race(race_id)
	color = r.get("color_c", Color.WHITE)
	var nm: Dictionary = r.get("names", {})
	var towns: Array = nm.get("settlement", ["Безымянное"])
	name = str(towns[rng.randi() % towns.size()])
	resources = {"food": 50.0 + rng.randf_range(0, 40), "wood": 30.0 + rng.randf_range(0, 25), "stone": 10.0, "iron": 0.0, "gold": 3.0, "goods": 0.0}
	buildings = [{"type": "campfire", "x": center.x + rng.randf_range(-0.8, 0.8), "z": center.y + rng.randf_range(-0.8, 0.8), "rot": rng.randf() * TAU, "level": 1, "hp": 100.0, "built": p_year}]
	_update_stage(1)
	researching = ""


func _update_stage(pop: int) -> void:
	population = pop
	var s := "camp"
	if pop >= STAGE_POPS["village"]: s = "village"
	if pop >= STAGE_POPS["town"]: s = "town"
	if pop >= STAGE_POPS["city"]: s = "city"
	if pop >= STAGE_POPS["metropolis"]: s = "metropolis"
	stage = s
	territory_radius = float(STAGE_RADIUS[s])


func max_pop() -> int:
	return int(STAGE_CAP[stage])


func max_buildings() -> int:
	match stage:
		"camp": return 8
		"village": return 16
		"town": return 26
		"city": return 38
		"metropolis": return 52
	return 8


func housing() -> int:
	var h := 0
	for b in buildings:
		if b.type == "hut":
			h += 8
		elif b.type == "granary":
			h += 2
	return h


func jobs() -> int:
	var j := 0
	for b in buildings:
		j += int(D.building(str(b.type)).get("jobs", 0))
	return j


func storage_cap() -> float:
	var cap := 220.0
	for b in buildings:
		if b.type == "granary":
			cap += 180.0
	return cap


func tech_mods() -> Dictionary:
	var m := {"food": 0.0, "prod": 0.0, "science": 0.0, "military": 0.0, "health": 0.0, "happiness": 0.0, "growth": 0.0, "magic": 0.0}
	for tid in techs:
		var t: Dictionary = D.tech(str(tid))
		var mm: Dictionary = t.get("mods", {})
		for k in mm:
			if m.has(k):
				m[k] += float(mm[k])
	# бонус эпохи
	m["prod"] += era * 0.03
	m["science"] += era * 0.03
	if blessed > 0.0:
		m["food"] += 0.2
		m["growth"] += 0.2
		m["happiness"] += 0.15
	if cursed > 0.0:
		m["food"] -= 0.25
		m["growth"] -= 0.3
		m["happiness"] -= 0.2
	if drought > 0.0:
		m["food"] -= 0.45
	if blizzard > 0.0:
		m["food"] -= 0.55
	if plague > 0.0:
		m["growth"] -= 0.5
		m["health"] -= 0.4
	if radioactive > 0.0:
		m["growth"] -= 0.35
		m["health"] -= 0.3
	return m


func production(season: int, day: float) -> Dictionary:
	var out := {"food": 0.0, "wood": 0.0, "stone": 0.0, "iron": 0.0, "gold": 0.0, "goods": 0.0, "faith": 0.0, "science": 0.0}
	var workers_needed := 0
	var workers_avail := maxi(1, int(population * 0.72))
	for b in buildings:
		workers_needed += int(D.building(str(b.type)).get("jobs", 0))
	var staffing := clampf(float(workers_avail) / float(maxi(1, workers_needed)), 0.35, 1.15)
	var mods := tech_mods()
	var season_food: float = [0.85, 1.25, 1.0, 0.45][clampi(season, 0, 3)]
	var bless_bonus: float = 1.0 + (float(mods.get("food", 0.0)) * 0.5)
	for b in buildings:
		var bd: Dictionary = D.building(str(b.type))
		var prod: Dictionary = bd.get("prod", {})
		var lvl: float = float(b.get("level", 1))
		for k in prod:
			var v: float = float(prod[k]) * lvl * staffing * (1.0 + float(mods.get("prod", 0.0)) * 0.6)
			if k == "food":
				v *= season_food * bless_bonus
			out[k] = out.get(k, 0.0) + v
	# население тоже работает: небольшое производство вне зданий
	out["food"] += population * 0.012 * season_food * (1.0 + mods.get("food", 0.0))
	out["wood"] += population * 0.004
	out["stone"] += population * 0.0015
	# наука
	var sci_workers := float(population) * 0.035
	out["science"] += sci_workers * 0.5 * (1.0 + mods.get("science", 0.0)) * (0.6 + happiness / 100.0)
	# торговля
	out["gold"] += population * 0.004 * (1.0 + prosperity * 0.3)
	# вера
	out["faith"] += population * 0.0015
	return out


func consumption() -> Dictionary:
	var food := population * 0.115
	var goods := population * 0.018
	var gold := army * 0.05
	return {"food": food, "goods": goods, "gold": gold}


func research_cost() -> float:
	if researching.is_empty():
		return 999999.0
	return float(D.tech(researching).get("cost", 100))


func era_progress_ratio() -> float:
	var list: Array = D.era_techs.get(era, [])
	if list.is_empty():
		return 1.0
	return float(era_techs_done) / float(list.size())


func available_buildings() -> Array:
	var out: Array = []
	for b in D.buildings:
		if int(b.get("era", 0)) <= era and str(b.id) != "campfire":
			out.append(b)
	return out


func has_building(type: String) -> bool:
	for b in buildings:
		if b.type == type:
			return true
	return false


func add_building(type: String, x: float, z: float, rot: float, year: int) -> void:
	buildings.append({"type": type, "x": x, "z": z, "rot": rot, "level": 1, "hp": 100.0, "built": year})


func building_count(type: String) -> int:
	var c := 0
	for b in buildings:
		if b.type == type:
			c += 1
	return c


func to_dict() -> Dictionary:
	return {
		"id": id, "race": race_id, "name": name, "center": [center.x, center.y],
		"founded_year": founded_year, "stage": stage, "leader_id": leader_id,
		"resources": resources, "buildings": buildings, "construction": construction,
		"techs": techs, "researching": researching, "research_progress": research_progress,
		"era": era, "era_techs_done": era_techs_done, "faith": faith, "happiness": happiness,
		"stability": stability, "wars": wars, "allies": allies, "relations": relations,
		"war_target": war_target, "war_days": war_days, "siege_days": siege_days, "army": army,
		"plague": plague, "fire": fire, "drought": drought, "blizzard": blizzard,
		"blessed": blessed, "cursed": cursed, "radioactive": radioactive,
		"population": population, "territory_radius": territory_radius,
		"destroyed": destroyed, "nuked": nuked, "total_births": total_births,
		"total_deaths": total_deaths, "prosperity": prosperity,
		"water_cell": [water_cell.x, water_cell.y], "water_day": water_day,
		"known": known, "roads": roads
	}


static func from_dict(d: Dictionary) -> SettlementData:
	var s := SettlementData.new()
	s.id = int(d.get("id", 0))
	s.race_id = str(d.get("race", "human"))
	s.name = str(d.get("name", "?"))
	var c: Array = d.get("center", [0, 0])
	s.center = Vector2i(int(c[0]), int(c[1]))
	s.founded_year = int(d.get("founded_year", 0))
	s.stage = str(d.get("stage", "camp"))
	s.leader_id = int(d.get("leader_id", -1))
	s.resources = d.get("resources", {}).duplicate()
	s.buildings = d.get("buildings", []).duplicate(true)
	s.construction = d.get("construction", {}).duplicate(true)
	s.techs = d.get("techs", []).duplicate()
	s.researching = str(d.get("researching", ""))
	s.research_progress = float(d.get("research_progress", 0))
	s.era = int(d.get("era", 0))
	s.era_techs_done = int(d.get("era_techs_done", 0))
	s.faith = float(d.get("faith", 5))
	s.happiness = float(d.get("happiness", 8))
	s.stability = float(d.get("stability", 65))
	s.wars = []
	for w in d.get("wars", []):
		s.wars.append(int(w))
	s.allies = []
	for al in d.get("allies", []):
		s.allies.append(int(al))
	s.relations = {}
	var rels: Dictionary = d.get("relations", {})
	for k in rels:
		s.relations[int(k)] = float(rels[k])
	s.war_target = int(d.get("war_target", -1))
	s.war_days = int(d.get("war_days", 0))
	s.siege_days = int(d.get("siege_days", 0))
	s.army = int(d.get("army", 0))
	s.plague = float(d.get("plague", 0))
	s.fire = float(d.get("fire", 0))
	s.drought = float(d.get("drought", 0))
	s.blizzard = float(d.get("blizzard", 0))
	s.blessed = float(d.get("blessed", 0))
	s.cursed = float(d.get("cursed", 0))
	s.radioactive = float(d.get("radioactive", 0))
	s.population = int(d.get("population", 0))
	s.territory_radius = float(d.get("territory_radius", 8))
	s.destroyed = bool(d.get("destroyed", false))
	s.nuked = bool(d.get("nuked", false))
	s.total_births = int(d.get("total_births", 0))
	s.total_deaths = int(d.get("total_deaths", 0))
	s.prosperity = float(d.get("prosperity", 1))
	var wc: Array = d.get("water_cell", [-1, -1])
	s.water_cell = Vector2i(int(wc[0]), int(wc[1]))
	s.water_day = int(d.get("water_day", -999))
	s.known = {}
	var kn: Dictionary = d.get("known", {})
	for k in kn:
		s.known[int(k)] = bool(kn[k])
	s.roads = {}
	var rd: Dictionary = d.get("roads", {})
	for k in rd:
		var rr: Dictionary = rd[k]
		rr["to"] = int(rr.get("to", k))
		s.roads[int(k)] = rr
	s.color = D.race(s.race_id).get("color_c", Color.WHITE)
	return s
