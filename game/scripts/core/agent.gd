class_name AgentData
extends RefCounted
## Одно разумное существо. Данные, без ссылок на сцену.

var id: int = 0
var race_id: String = "human"
var name: String = ""
var family: String = ""
var gender: int = 0  # 0 male, 1 female
var age: float = 20.0
var level: int = 1
var xp: float = 0.0
var power: float = 50.0
var wisdom: float = 50.0
var agility: float = 50.0
var magic: float = 10.0
var charisma: float = 50.0
var health: float = 100.0
var max_health: float = 100.0
var satiety: float = 80.0
var thirst: float = 80.0
var energy: float = 80.0
var mood: float = 10.0
var sanity: float = 100.0
var skills: Dictionary = {}
var perks: Array = []
var settlement_id: int = -1
var role: String = "worker"
var state: String = "idle"
var pos: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var speed: float = 1.1
var alive: bool = true
var partner_id: int = -1
var pregnant: float = 0.0
var father_id: int = -1
var children: Array = []
var equipment: int = 0
var kills: int = 0
var born_year: int = 0
var death_cause: String = ""
var notable: bool = false
var journey_timer: float = 0.0


func setup(p_id: int, p_race: Dictionary, p_gender: int, p_age: float, rng: RandomNumberGenerator) -> void:
	id = p_id
	race_id = p_race.get("id", "human")
	gender = p_gender
	age = p_age
	var nm: Dictionary = p_race.get("names", {})
	var firsts: Array = nm.get("male" if gender == 0 else "female", ["Айна"])
	var fams: Array = nm.get("family", ["Безымянный"])
	name = str(firsts[rng.randi() % firsts.size()])
	family = str(fams[rng.randi() % fams.size()])
	var base_power: float = float(p_race.get("power", 50))
	var base_wis: float = float(p_race.get("wisdom", 50))
	var base_agi: float = float(p_race.get("agility", 50))
	var base_mag: float = float(p_race.get("magic", 10))
	var base_cha: float = float(p_race.get("charisma", 50))
	power = clampf(base_power * rng.randf_range(0.82, 1.18), 1, 100)
	wisdom = clampf(base_wis * rng.randf_range(0.82, 1.18), 1, 100)
	agility = clampf(base_agi * rng.randf_range(0.82, 1.18), 1, 100)
	magic = clampf(base_mag * rng.randf_range(0.7, 1.3), 0, 100)
	charisma = clampf(base_cha * rng.randf_range(0.82, 1.18), 1, 100)
	var maturity: float = float(p_race.get("maturity", 18))
	speed = 1.0 + agility * 0.006
	health = 1.0
	satiety = rng.randf_range(65, 95)
	thirst = rng.randf_range(65, 95)
	energy = rng.randf_range(70, 100)
	mood = rng.randf_range(-5, 15)
	sanity = rng.randf_range(88, 100)
	if age < 5:
		role = "child"
	elif age < maturity:
		role = "child"
	elif age > float(p_race.get("lifespan", 70)) * 0.78:
		role = "elder"
	else:
		role = "worker"
	for k in ["melee", "craft", "farming", "science", "leadership", "trade", "medicine", "survival"]:
		skills[k] = clampi(int((power + wisdom + agility) / 3.0 * rng.randf_range(0.4, 0.8)), 3, 70)
	var perk_pool := ["tough", "industrious", "genius", "charmer", "swift", "lucky", "brave", "curious", "frugal", "pious"]
	var nperks := rng.randi_range(0, 2)
	for k in nperks:
		var pk: String = perk_pool[rng.randi() % perk_pool.size()]
		if not perks.has(pk):
			perks.append(pk)
	max_health = compute_max_health(p_race)
	health = max_health


func compute_max_health(p_race: Dictionary = {}) -> float:
	if p_race.is_empty():
		p_race = D.race(race_id)
	var base: float = float(p_race.get("hp", 100))
	var h := (base + power * 0.5 + level * 2.5)
	var am := age_mod()
	h *= am
	if perks.has("tough"):
		h *= 1.15
	return maxf(1.0, h)


func age_mod() -> float:
	if age < 3: return 0.1
	if age < 13: return 0.4
	if age < 18: return 0.8
	if age < 56: return 1.0
	if age < 71: return 0.85
	return 0.6


func maturity() -> float:
	return float(D.race(race_id).get("maturity", 18))


func lifespan() -> float:
	return float(D.race(race_id).get("lifespan", 70))


func is_adult() -> bool:
	return age >= maturity()


func xp_to_next() -> float:
	return round(50.0 * pow(level, 1.6) + 50.0 * level)


func add_xp(amount: float) -> bool:
	xp += amount
	var leveled := false
	while xp >= xp_to_next() and level < 100:
		xp -= xp_to_next()
		level += 1
		power = minf(100.0, power + 0.55)
		wisdom = minf(100.0, wisdom + 0.25)
		agility = minf(100.0, agility + 0.2)
		max_health = compute_max_health()
		health = minf(max_health, health + max_health * 0.15)
		leveled = true
	return leveled


func attack_value() -> float:
	var w: float = [0.0, 6.0, 14.0, 24.0, 36.0, 55.0][clampi(equipment, 0, 5)]
	return (power * 0.55 + w) * (1.0 + level * 0.012)


func defense_value() -> float:
	var a: float = [0.0, 3.0, 8.0, 15.0, 25.0, 40.0][clampi(equipment, 0, 5)]
	return a + power * 0.1


func display_name() -> String:
	if family.is_empty():
		return name
	return name + " " + family


func is_warrior() -> bool:
	return role == "warrior"


func to_dict() -> Dictionary:
	return {
		"id": id, "race": race_id, "name": name, "family": family, "gender": gender,
		"age": age, "level": level, "xp": xp, "power": power, "wisdom": wisdom,
		"agility": agility, "magic": magic, "charisma": charisma, "health": health,
		"max_health": max_health, "satiety": satiety, "thirst": thirst, "energy": energy,
		"mood": mood, "sanity": sanity, "skills": skills, "perks": perks,
		"settlement_id": settlement_id, "role": role, "state": state,
		"pos": [pos.x, pos.y], "target": [target.x, target.y], "speed": speed,
		"alive": alive, "partner_id": partner_id, "pregnant": pregnant,
		"father_id": father_id, "children": children, "equipment": equipment,
		"kills": kills, "born_year": born_year, "notable": notable
	}


static func from_dict(d: Dictionary) -> AgentData:
	var a := AgentData.new()
	a.id = int(d.get("id", 0))
	a.race_id = str(d.get("race", "human"))
	a.name = str(d.get("name", "?"))
	a.family = str(d.get("family", ""))
	a.gender = int(d.get("gender", 0))
	a.age = float(d.get("age", 20))
	a.level = int(d.get("level", 1))
	a.xp = float(d.get("xp", 0))
	a.power = float(d.get("power", 50))
	a.wisdom = float(d.get("wisdom", 50))
	a.agility = float(d.get("agility", 50))
	a.magic = float(d.get("magic", 10))
	a.charisma = float(d.get("charisma", 50))
	a.health = float(d.get("health", 100))
	a.max_health = float(d.get("max_health", 100))
	a.satiety = float(d.get("satiety", 80))
	a.thirst = float(d.get("thirst", 80))
	a.energy = float(d.get("energy", 80))
	a.mood = float(d.get("mood", 0))
	a.sanity = float(d.get("sanity", 100))
	a.skills = d.get("skills", {}).duplicate()
	a.perks = d.get("perks", []).duplicate()
	a.settlement_id = int(d.get("settlement_id", -1))
	a.role = str(d.get("role", "worker"))
	a.state = str(d.get("state", "idle"))
	var p: Array = d.get("pos", [0, 0])
	a.pos = Vector2(float(p[0]), float(p[1]))
	var t: Array = d.get("target", [0, 0])
	a.target = Vector2(float(t[0]), float(t[1]))
	a.speed = float(d.get("speed", 1.1))
	a.alive = bool(d.get("alive", true))
	a.partner_id = int(d.get("partner_id", -1))
	a.pregnant = float(d.get("pregnant", 0))
	a.father_id = int(d.get("father_id", -1))
	a.children = d.get("children", [])
	a.equipment = int(d.get("equipment", 0))
	a.kills = int(d.get("kills", 0))
	a.born_year = int(d.get("born_year", 0))
	a.notable = bool(d.get("notable", false))
	return a
