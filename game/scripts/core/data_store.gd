extends Node
## DataStore — все игровые данные загружаются из res://data/*.json.
## Никакой контент не зашит в логику: расы, биомы, животные, здания,
## технологии, эпохи и силы бога можно менять модом.

var races: Array = []
var biomes: Array = []
var animals: Array = []
var buildings: Array = []
var techs: Array = []
var eras: Array = []
var powers: Array = []

var races_by_id: Dictionary = {}
var biomes_by_id: Dictionary = {}
var animals_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var techs_by_id: Dictionary = {}
var powers_by_id: Dictionary = {}

var powers_by_cat: Dictionary = {}
var era_techs: Dictionary = {}
var mods_loaded: Array = []

const MOD_FILES := ["races.json", "biomes.json", "animals.json", "buildings.json", "techs.json", "eras.json", "powers.json"]

var world_presets: Array = [
	{"id": "continent", "name": "Континент", "name_en": "Continent", "land": 0.56, "freq": 2.1, "warp": 1.3, "mountain": 1.0, "desc": "Один большой материк с горами, реками и удобными бухтами.", "desc_en": "One large continent with mountains, rivers and convenient bays."},
	{"id": "archipelago", "name": "Архипелаг", "name_en": "Archipelago", "land": 0.34, "freq": 3.4, "warp": 1.1, "mountain": 0.8, "desc": "Россыпь островов. Много моря, торговли и пиратов.", "desc_en": "A scatter of islands. Much sea, trade and pirates."},
	{"id": "pangaea", "name": "Пангея", "name_en": "Pangaea", "land": 0.68, "freq": 1.5, "warp": 1.0, "mountain": 1.15, "desc": "Огромный сплошной массив суши. Империи сойдутся в центре.", "desc_en": "A huge solid landmass. Empires will meet in the center."},
	{"id": "garden", "name": "Мир-сад", "name_en": "Garden World", "land": 0.62, "freq": 2.0, "warp": 1.6, "mountain": 0.6, "desc": "Тёплый плодородный мир. Мало пустынь, много жизни.", "desc_en": "A warm fertile world. Few deserts, much life."},
	{"id": "ash", "name": "Пепел","name_en": "Ash World", "land": 0.48, "freq": 2.4, "warp": 1.8, "mountain": 1.35, "desc": "Суровый вулканический мир. Жизнь цепляется за оазисы.", "desc_en": "A harsh volcanic world. Life clings to oases."}
]

var difficulties: Array = [
	{"id": "easy", "name": "Лёгкий", "name_en": "Easy", "growth": 1.3, "death": 0.7, "aggr": 0.7, "tech": 0.8, "disaster": 0.7, "essence": 1.4},
	{"id": "normal", "name": "Обычный", "name_en": "Normal", "growth": 1.0, "death": 1.0, "aggr": 1.0, "tech": 1.0, "disaster": 1.0, "essence": 1.0},
	{"id": "hard", "name": "Сложный", "name_en": "Hard", "growth": 0.8, "death": 1.3, "aggr": 1.3, "tech": 1.2, "disaster": 1.3, "essence": 0.75},
	{"id": "hardcore", "name": "Хардкор", "name_en": "Hardcore", "growth": 0.6, "death": 1.6, "aggr": 1.6, "tech": 1.5, "disaster": 1.8, "essence": 0.55}
]


func _ready() -> void:
	load_all()


func load_all() -> void:
	races = _load("res://data/races.json")
	biomes = _load("res://data/biomes.json")
	animals = _load("res://data/animals.json")
	buildings = _load("res://data/buildings.json")
	techs = _load("res://data/techs.json")
	eras = _load("res://data/eras.json")
	powers = _load("res://data/powers.json")

	_apply_mods()

	races_by_id.clear(); biomes_by_id.clear(); animals_by_id.clear()
	buildings_by_id.clear(); techs_by_id.clear(); powers_by_id.clear()
	powers_by_cat.clear(); era_techs.clear()

	for r in races:
		r["color_hex"] = r.get("color", "#ffffff")
		r["color_c"] = Color(r.get("color", "#ffffff"))
		r["accent_c"] = Color(r.get("accent", "#ffffff"))
		races_by_id[r["id"]] = r
	for b in biomes:
		b["color_c"] = Color(b.get("color", "#777777"))
		b["accent_c"] = Color(b.get("accent", "#999999"))
		biomes_by_id[b["id"]] = b
	for a in animals:
		a["color_c"] = Color(a.get("color", "#aaaaaa"))
		animals_by_id[a["id"]] = a
	for b in buildings:
		b["color_c"] = Color(b.get("color", "#8a7a5a"))
		b["roof_c"] = Color(b.get("roof", "#6a5a3a"))
		buildings_by_id[b["id"]] = b
	for t in techs:
		t["era"] = int(t.get("era", 0))
		techs_by_id[t["id"]] = t
		var eidx: int = t["era"]
		if not era_techs.has(eidx):
			era_techs[eidx] = []
		era_techs[eidx].append(t)
	for e in eras:
		pass
	for p in powers:
		p["color_c"] = Color(p.get("color", "#e8c07a"))
		powers_by_id[p["id"]] = p
		if not powers_by_cat.has(p["cat"]):
			powers_by_cat[p["cat"]] = []
		powers_by_cat[p["cat"]].append(p)

	print("[D] loaded: %d races, %d biomes, %d animals, %d buildings, %d techs, %d powers" % [races.size(), biomes.size(), animals.size(), buildings.size(), techs.size(), powers.size()])


func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Data file missing: " + path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		push_error("JSON parse failed: " + path)
		return []
	if parsed is Array:
		return parsed
	return []


# ------------------------------------------------------------------ mods

func mod_roots() -> Array:
	return _mod_roots()


func _mod_roots() -> Array:
	var roots: Array = ["res://mods", "user://mods"]
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir != "":
		roots.append(exe_dir.path_join("mods"))
	var out: Array = []
	for r in roots:
		if not out.has(r) and DirAccess.dir_exists_absolute(r):
			out.append(r)
	return out


func _apply_mods() -> void:
	mods_loaded.clear()
	var roots := _mod_roots()
	for root in roots:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		for mod_name in dir.get_directories():
			var data_dir: String = str(root).path_join(mod_name).path_join("data")
			if not DirAccess.dir_exists_absolute(data_dir):
				continue
			var used := false
			for fname in MOD_FILES:
				var p: String = data_dir.path_join(fname)
				if not FileAccess.file_exists(p):
					continue
				var overlay = _load_mod_file(p)
				if overlay == null:
					continue
				var target: Array = _base_for(fname)
				if target == null:
					continue
				_merge_by_id(target, overlay)
				used = true
			if used:
				mods_loaded.append(str(mod_name))
	if not mods_loaded.is_empty():
		print("[D] mods: ", ", ".join(mods_loaded))


func _base_for(fname: String) -> Array:
	match fname:
		"races.json": return races
		"biomes.json": return biomes
		"animals.json": return animals
		"buildings.json": return buildings
		"techs.json": return techs
		"eras.json": return eras
		"powers.json": return powers
	return []


func _load_mod_file(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Mod file unreadable: " + path)
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not parsed is Array:
		push_warning("Mod file is not a JSON array: " + path)
		return []
	return parsed


func _merge_by_id(base: Array, overlay: Array) -> void:
	for item in overlay:
		if not item is Dictionary:
			continue
		var key := str(item.get("id", item.get("name", "")))
		var found := false
		for i in base.size():
			var b = base[i]
			if b is Dictionary and str(b.get("id", b.get("name", ""))) == key:
				for k in item:
					b[k] = item[k]
				found = true
				break
		if not found:
			base.append(item)


func race(id: String) -> Dictionary:
	return races_by_id.get(id, races[0] if races.size() > 0 else {})

func biome(id: String) -> Dictionary:
	return biomes_by_id.get(id, biomes_by_id.get("meadow", {}))

func animal(id: String) -> Dictionary:
	return animals_by_id.get(id, {})

func building(id: String) -> Dictionary:
	return buildings_by_id.get(id, {})

func tech(id: String) -> Dictionary:
	return techs_by_id.get(id, {})

func era(i: int) -> Dictionary:
	return eras[clampi(i, 0, eras.size() - 1)]

func power(id: String) -> Dictionary:
	return powers_by_id.get(id, {})

func preset(id: String) -> Dictionary:
	for p in world_presets:
		if p.id == id:
			return p
	return world_presets[0]

func difficulty(id: String) -> Dictionary:
	for d in difficulties:
		if d.id == id:
			return d
	return difficulties[1]


func name_of(item: Dictionary) -> String:
	return item.get("name", item.get("id", "?"))

func desc_of(item: Dictionary) -> String:
	return item.get("desc", "")
