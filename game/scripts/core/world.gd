class_name WorldModel
extends RefCounted
## Мир: высоты, климат, биомы, вода, растительность, ресурсы, радиация.
## Детерминирован seed'ом; не знает ничего о рендере.

signal terrain_changed(rect: Rect2i)
signal biomes_changed(rect: Rect2i)
signal water_changed(rect: Rect2i)

const CELL := 2.0
const HEIGHT_SCALE := 86.0
const SEA_DEFAULT := 0.40
const DAYS_PER_YEAR := 365

const RES_NAMES := ["none", "iron", "coal", "gold", "stone", "clay", "salt", "oil", "uranium", "crystal"]

var size: int = 256
var seed: int = 1
var preset_id: String = "continent"
var world_name: String = "Аэтерия"
var sea_level: float = SEA_DEFAULT

var heights: PackedFloat32Array
var moisture: PackedFloat32Array
var temperature: PackedFloat32Array
var vegetation: PackedFloat32Array
var fertility: PackedFloat32Array
var water: PackedFloat32Array
var radiation: PackedFloat32Array
var burn: PackedFloat32Array
var biome_ids: PackedByteArray
var res_type: PackedByteArray
var res_amount: PackedFloat32Array
var dist_water: PackedInt32Array

var biome_keys: Array = []
var biome_index: Dictionary = {}
var land_cells: int = 0
var water_cells: int = 0
var clearings: Array = []

var rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _noise3 := FastNoiseLite.new()
var _warp := FastNoiseLite.new()


func _init(p_size: int = 256, p_seed: int = 1, p_preset: String = "continent") -> void:
	size = clampi(p_size, 64, 512)
	seed = p_seed
	preset_id = p_preset
	biome_keys.clear()
	biome_index.clear()
	var i := 0
	for b in D.biomes:
		biome_keys.append(b["id"])
		biome_index[b["id"]] = i
		i += 1


func n() -> int:
	return size * size


func idx(x: int, z: int) -> int:
	return z * size + x


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < size and z < size


func cell_of(v: Vector2) -> Vector2i:
	return Vector2i(clampi(int(round(v.x)), 0, size - 1), clampi(int(round(v.y)), 0, size - 1))


func biome_id_at(x: int, z: int) -> int:
	if not in_bounds(x, z):
		return 0
	return biome_ids[idx(x, z)]


func biome_at(x: int, z: int) -> Dictionary:
	return D.biomes[clampi(biome_id_at(x, z), 0, D.biomes.size() - 1)]


func biome_name_at(x: int, z: int) -> String:
	return biome_at(x, z).get("id", "ocean")


func height_at(x: int, z: int) -> float:
	return heights[idx(clampi(x, 0, size - 1), clampi(z, 0, size - 1))]


func height_at_f(fx: float, fz: float) -> float:
	var x0 := clampi(int(floor(fx)), 0, size - 1)
	var z0 := clampi(int(floor(fz)), 0, size - 1)
	var x1 := mini(x0 + 1, size - 1)
	var z1 := mini(z0 + 1, size - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var tz := clampf(fz - z0, 0.0, 1.0)
	var a := lerpf(heights[idx(x0, z0)], heights[idx(x1, z0)], tx)
	var b := lerpf(heights[idx(x0, z1)], heights[idx(x1, z1)], tx)
	return lerpf(a, b, tz)


func world_pos(fx: float, fz: float) -> Vector3:
	var h := height_at_f(fx, fz)
	return Vector3((fx - size * 0.5) * CELL, (h - sea_level) * HEIGHT_SCALE, (fz - size * 0.5) * CELL)


func terrain_y(fx: float, fz: float) -> float:
	return (height_at_f(fx, fz) - sea_level) * HEIGHT_SCALE


func cell_to_world(cx: int, cz: int, y_off: float = 0.0) -> Vector3:
	return Vector3((cx - size * 0.5) * CELL, (heights[idx(cx, cz)] - sea_level) * HEIGHT_SCALE + y_off, (cz - size * 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2:
	return Vector2(p.x / CELL + size * 0.5, p.z / CELL + size * 0.5)


func is_water_cell(x: int, z: int) -> bool:
	return in_bounds(x, z) and water[idx(x, z)] > 0.0004


func is_land_cell(x: int, z: int) -> bool:
	return in_bounds(x, z) and heights[idx(x, z)] > sea_level and water[idx(x, z)] <= 0.0004


func water_surface_y(cx: int, cz: int) -> float:
	if not in_bounds(cx, cz):
		return 0.0
	var i := idx(cx, cz)
	var h := heights[i]
	if water[i] <= 0.0004:
		return (h - sea_level) * HEIGHT_SCALE
	if h <= sea_level:
		return 0.0
	return (h - sea_level) * HEIGHT_SCALE + 0.22 + water[i] * 30.0


func surface_y(cx: int, cz: int) -> float:
	if is_water_cell(cx, cz):
		return water_surface_y(cx, cz)
	return (heights[idx(cx, cz)] - sea_level) * HEIGHT_SCALE


# ------------------------------------------------------------------ generation

func generate(cfg: Dictionary, progress: Callable = Callable(), host: Node = null) -> void:
	size = clampi(int(cfg.get("size", 256)), 64, 512)
	seed = int(cfg.get("seed", randi()))
	preset_id = str(cfg.get("preset", "continent"))
	rng.seed = seed
	rng.state = seed * 7919 + 13
	var preset := D.preset(preset_id)
	biome_keys.clear(); biome_index.clear()
	var bi := 0
	for b in D.biomes:
		biome_keys.append(b["id"])
		biome_index[b["id"]] = bi
		bi += 1
	_alloc()
	world_name = _make_world_name()

	_phase(progress, "generating_terrain", 0.02)
	_generate_heights(preset)
	if host != null:
		await host.get_tree().process_frame
	_phase(progress, "generating_terrain", 0.30)
	_generate_rivers()
	if host != null:
		await host.get_tree().process_frame
	_phase(progress, "generating_climate", 0.45)
	_compute_distance_to_water()
	_compute_climate()
	if host != null:
		await host.get_tree().process_frame
	_phase(progress, "generating_climate", 0.62)
	_classify_biomes()
	_place_resources()
	if host != null:
		await host.get_tree().process_frame
	_phase(progress, "generating_life", 0.78)
	_grow_vegetation()
	_phase(progress, "generating_mesh", 0.9)
	_recount()
	_phase(progress, "generating_mesh", 1.0)


func _alloc() -> void:
	var c := n()
	heights = PackedFloat32Array(); heights.resize(c)
	moisture = PackedFloat32Array(); moisture.resize(c)
	temperature = PackedFloat32Array(); temperature.resize(c)
	vegetation = PackedFloat32Array(); vegetation.resize(c)
	fertility = PackedFloat32Array(); fertility.resize(c)
	water = PackedFloat32Array(); water.resize(c)
	radiation = PackedFloat32Array(); radiation.resize(c)
	burn = PackedFloat32Array(); burn.resize(c)
	biome_ids = PackedByteArray(); biome_ids.resize(c)
	res_type = PackedByteArray(); res_type.resize(c)
	res_amount = PackedFloat32Array(); res_amount.resize(c)
	dist_water = PackedInt32Array(); dist_water.resize(c)
	dist_water.fill(-1)


func _phase(cb: Callable, key: String, frac: float) -> void:
	if cb.is_valid():
		cb.call(key, frac)


func _generate_heights(preset: Dictionary) -> void:
	var freq: float = float(preset.get("freq", 2.0))
	var warp_amt: float = float(preset.get("warp", 1.2))
	var mountain_amt: float = float(preset.get("mountain", 1.0))

	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.014 * freq
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.fractal_gain = 0.52

	_noise2.seed = seed + 101
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise2.frequency = 0.055
	_noise2.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise2.fractal_octaves = 4

	_noise3.seed = seed + 202
	_noise3.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise3.frequency = 0.12
	_noise3.fractal_octaves = 2

	_warp.seed = seed + 303
	_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp.frequency = 0.008

	var inv := 1.0 / float(size - 1)
	for z in size:
		for x in size:
			var nx := x * inv
			var nz := z * inv
			var wx := _warp.get_noise_2d(x, z) * warp_amt * 12.0
			var wz := _warp.get_noise_2d(x + 500.0, z + 500.0) * warp_amt * 12.0
			var cont := (_noise.get_noise_2d(x + wx, z + wz) + 1.0) * 0.5
			var d := Vector2(nx - 0.5, nz - 0.5).length() * 2.0
			var falloff := 1.0 - smoothstep(0.62, 1.28, d)
			var h := cont * 0.62 + falloff * 0.56 - 0.30
			# горные хребты
			var ridge := (_noise2.get_noise_2d(x + wx * 0.5, z + wz * 0.5) + 1.0) * 0.5
			ridge = pow(clampf(ridge, 0.0, 1.0), 2.1)
			var mountain_mask := smoothstep(0.45, 0.78, cont) * smoothstep(0.05, 0.35, falloff)
			h += ridge * 0.42 * mountain_mask * mountain_amt
			# мелкая детализация
			h += _noise3.get_noise_2d(x, z) * 0.012
			# крупные равнины и речные низины: низкочастотная маска сглаживает рельеф
			var plain_n := (_warp.get_noise_2d(x * 0.35 + 9000.0, z * 0.35 + 9000.0) + 1.0) * 0.5
			var plain_mask := smoothstep(0.52, 0.82, plain_n)
			if plain_mask > 0.001:
				var base := 0.40 + (_noise3.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5) * 0.10
				h = lerpf(h, base, plain_mask * 0.62)
				# террасы в поймах
				h = lerpf(h, roundf(h * 48.0) / 48.0, plain_mask * 0.35)
			heights[idx(x, z)] = clampf(h, 0.0, 1.0)

	# уровень моря из целевой доли суши
	var target: float = float(preset.get("land", 0.55))
	var sorted := heights.duplicate()
	sorted.sort()
	var sea_idx := clampi(int((1.0 - target) * float(sorted.size())), 0, sorted.size() - 1)
	sea_level = clampf(sorted[sea_idx], 0.06, 0.86)
	# океанская кромка: карта не обрывается сушей на краю
	for z in size:
		for x in size:
			if x < 5 or z < 5 or x > size - 6 or z > size - 6:
				var edge := mini(mini(x, z), mini(size - 1 - x, size - 1 - z))
				var f := clampf(1.0 - float(edge) / 5.0, 0.0, 1.0)
				var ii := idx(x, z)
				heights[ii] = lerpf(heights[ii], sea_level - 0.035, f * 0.95)
	# гарантируем пологий шельф
	for i in n():
		var h := heights[i]
		if h < sea_level:
			water[i] = clampf(sea_level - h, 0.0, 0.12)
		else:
			water[i] = 0.0
	# сглаживание берегов
	for pass_i in 2:
		for z in range(1, size - 1):
			for x in range(1, size - 1):
				var i := idx(x, z)
				if absf(heights[i] - sea_level) < 0.035:
					var avg := (heights[idx(x - 1, z)] + heights[idx(x + 1, z)] + heights[idx(x, z - 1)] + heights[idx(x, z + 1)]) * 0.25
					heights[i] = lerpf(heights[i], avg, 0.4)
	# мягкая эрозия: убираем иглы и вертикальные обрывы
	for pass_i in 3:
		for z in range(1, size - 1):
			for x in range(1, size - 1):
				var i := idx(x, z)
				var avg := (heights[idx(x - 1, z)] + heights[idx(x + 1, z)] + heights[idx(x, z - 1)] + heights[idx(x, z + 1)]) * 0.25
				heights[i] = lerpf(heights[i], avg, 0.22)
	# удаление одиночных пиков и игл
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			var i2 := idx(x, z)
			var avg2 := (heights[idx(x - 1, z)] + heights[idx(x + 1, z)] + heights[idx(x, z - 1)] + heights[idx(x, z + 1)]) * 0.25
			if heights[i2] > avg2 + 0.09:
				heights[i2] = lerpf(heights[i2], avg2 + 0.06, 0.65)


func _generate_rivers() -> void:
	var cells := n()
	var order: Array = []
	var buckets: Array = []
	for b in 1024:
		buckets.append(PackedInt32Array())
	for i in cells:
		var h := clampf(heights[i], 0.0, 1.0)
		buckets[mini(1023, int(h * 1023.0))].append(i)
	for b in range(1023, -1, -1):
		for i in buckets[b]:
			order.append(i)
	var acc := PackedInt32Array()
	acc.resize(cells)
	acc.fill(1)
	for i in order:
		var x: int = i % size
		var z: int = i / size
		var h := heights[i]
		if h <= sea_level:
			continue
		var best_i := -1
		var best_h := h
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var xx: int = x + dx
				var zz: int = z + dz
				if xx < 0 or zz < 0 or xx >= size or zz >= size:
					continue
				var j := idx(xx, zz)
				if heights[j] < best_h:
					best_h = heights[j]
					best_i = j
		if best_i >= 0:
			acc[best_i] = mini(acc[best_i] + acc[i], 2000000)
	# русла
	var river_cells := 0
	for i in cells:
		var x := i % size
		var z := i / size
		var h := heights[i]
		if h <= sea_level + 0.012:
			continue
		if acc[i] > 58:
			var carve := minf(0.006, (h - sea_level) * 0.35)
			heights[i] = maxf(sea_level + 0.008, h - carve)
			water[i] = 0.0035 + minf(0.004, acc[i] / 400000.0)
			river_cells += 1
	# если рек почти нет — прорубим две вручную от высоких точек к морю
	if river_cells < 80:
		var peaks: Array = []
		for k in 2000:
			var i := rng.randi_range(0, cells - 1)
			if heights[i] > sea_level + 0.08:
				peaks.append(i)
			if peaks.size() >= 2:
				break
		for pi in peaks:
			var x: int = pi % size
			var z: int = pi / size
			for step in 900:
				var best := idx(x, z)
				var best_h := heights[best]
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var xx := clampi(x + dx, 0, size - 1)
						var zz := clampi(z + dz, 0, size - 1)
						var j := idx(xx, zz)
						if heights[j] < best_h:
							best_h = heights[j]
							best = j
				if best == idx(x, z):
					break
				x = best % size
				z = best / size
				water[best] = maxf(water[best], 0.004)
				if heights[best] <= sea_level:
					break


func _compute_distance_to_water() -> void:
	var cells := n()
	var queue := PackedInt32Array()
	for i in cells:
		if water[i] > 0.0004:
			dist_water[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % size
		var z := i / size
		var d := dist_water[i] + 1
		for off in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var xx: int = x + off.x
			var zz: int = z + off.y
			if xx < 0 or zz < 0 or xx >= size or zz >= size:
				continue
			var j := idx(xx, zz)
			if dist_water[j] < 0:
				dist_water[j] = d
				queue.append(j)


func _compute_climate() -> void:
	var inv := 1.0 / float(size - 1)
	for z in size:
		for x in size:
			var i := idx(x, z)
			var lat := absf(z * inv - 0.5) * 2.0
			var alt := maxf(0.0, heights[i] - sea_level)
			var t := 1.0 - lat * 1.02 - alt * 0.72 + _noise3.get_noise_2d(x * 2.0, z * 2.0) * 0.04
			if preset_id == "garden":
				t += 0.08
			elif preset_id == "ash":
				t += 0.02
			temperature[i] = clampf(t, 0.0, 1.0)
			var dw := dist_water[i]
			if dw < 0:
				dw = 200
			var m := 0.52 - float(dw) / 135.0 + _noise2.get_noise_2d(x + 900.0, z + 900.0) * 0.38
			if preset_id == "ash":
				m -= 0.08
			if preset_id == "garden":
				m += 0.06
			if heights[i] <= sea_level:
				m = 1.0
			moisture[i] = clampf(m, 0.0, 1.0)


func _classify_biomes() -> void:
	var bid := biome_index
	var volcano_centers: Array = []
	if preset_id == "ash":
		for k in 3:
			var cx := rng.randi_range(size / 6, size * 5 / 6)
			var cz := rng.randi_range(size / 6, size * 5 / 6)
			if heights[idx(cx, cz)] > sea_level:
				volcano_centers.append(Vector2i(cx, cz))
	for z in size:
		for x in size:
			var i := idx(x, z)
			var h := heights[i]
			var t := temperature[i]
			var m := moisture[i]
			var id := "ocean"
			if water[i] > 0.0004:
				if h <= sea_level:
					var depth := sea_level - h
					if depth > 0.055:
						id = "ocean"
					elif depth > 0.028:
						id = "shallow"
					else:
						id = "reef" if (t > 0.55 and m > 0.55 and (x * 7 + z * 13) % 5 == 0) else "shallow"
				else:
					var flat := absf(height_at(x + 1, z) - h) + absf(height_at(x, z + 1) - h)
					if flat < 0.01 and m > 0.55 and t > 0.35:
						id = "swamp"
					elif water[i] > 0.006:
						id = "lake"
					else:
						id = "river"
			else:
				var near_volcano := false
				for vc in volcano_centers:
					if abs(vc.x - x) + abs(vc.y - z) < 7:
						near_volcano = true
						break
				if near_volcano:
					id = "volcano" if (x * 5 + z * 3) % 7 == 0 else "ashland"
				elif h <= sea_level + 0.014:
					id = "beach"
				elif t < 0.10:
					id = "glacier" if h < sea_level + 0.15 else "snow"
				elif h > sea_level + 0.50:
					id = "snow"
				elif h > sea_level + 0.38:
					id = "mountains"
				elif t < 0.26 and m > 0.46:
					id = "taiga"
				elif t > 0.66 and m < 0.27:
					id = "desert"
				elif t > 0.60 and m < 0.40:
					id = "savanna"
				elif m < 0.35:
					id = "steppe"
				elif m > 0.68 and t > 0.62:
					id = "tropical"
				elif m > 0.55:
					id = "forest"
				elif h > sea_level + 0.26:
					id = "hills"
				else:
					id = "meadow"
				if id == "meadow" and h > sea_level + 0.20:
					id = "hills"
				if id in ["forest", "taiga", "tropical", "swamp"] and (x * 17 + z * 31) % 997 == 0:
					id = "rift"
			biome_ids[i] = bid.get(id, 0)


func _place_resources() -> void:
	res_type.fill(0)
	res_amount.fill(0.0)
	for z in size:
		for x in size:
			var i := idx(x, z)
			if water[i] > 0.0004:
				continue
			var id: String = biome_keys[biome_ids[i]]
			var roll := rng.randf()
			var rtype := 0
			var amt := 0.0
			match id:
				"mountains":
					if roll < 0.055: rtype = 1; amt = rng.randf_range(35, 90)
					elif roll < 0.10: rtype = 3; amt = rng.randf_range(15, 40)
					elif roll < 0.16: rtype = 4; amt = rng.randf_range(40, 100)
					elif roll < 0.167: rtype = 8; amt = rng.randf_range(8, 20)
					elif roll < 0.19: rtype = 2; amt = rng.randf_range(30, 70)
				"hills":
					if roll < 0.05: rtype = 1; amt = rng.randf_range(25, 60)
					elif roll < 0.085: rtype = 2; amt = rng.randf_range(25, 60)
					elif roll < 0.15: rtype = 4; amt = rng.randf_range(30, 80)
					elif roll < 0.165: rtype = 3; amt = rng.randf_range(10, 30)
				"desert":
					if roll < 0.025: rtype = 6; amt = rng.randf_range(10, 30)
					elif roll < 0.04: rtype = 7; amt = rng.randf_range(20, 60)
				"swamp":
					if roll < 0.03: rtype = 7; amt = rng.randf_range(20, 55)
					elif roll < 0.05: rtype = 5; amt = rng.randf_range(20, 50)
				"beach":
					if roll < 0.03: rtype = 6; amt = rng.randf_range(8, 24)
				"river":
					if roll < 0.05: rtype = 5; amt = rng.randf_range(15, 40)
				"rift":
					if roll < 0.09: rtype = 9; amt = rng.randf_range(20, 60)
				"forest", "taiga", "tropical":
					if roll < 0.012: rtype = 2; amt = rng.randf_range(15, 40)
			res_type[i] = rtype
			res_amount[i] = amt


func _grow_vegetation() -> void:
	fertility.resize(n())
	for i in n():
		var id: String = biome_keys[biome_ids[i]]
		var b := D.biome(id)
		var fert := float(b.get("fertility", 0.3))
		fertility[i] = fert
		if water[i] > 0.002 and heights[i] <= sea_level:
			vegetation[i] = 0.0
			continue
		var noise := (_noise3.get_noise_2d((i % size) * 4.0, (i / size) * 4.0) + 1.0) * 0.5
		vegetation[i] = clampf(fert * (0.62 + noise * 0.55), 0.0, 1.0)


func rebuild_fertility() -> void:
	fertility.resize(n())
	for i in n():
		fertility[i] = float(D.biome(biome_keys[biome_ids[i]]).get("fertility", 0.3))


func _recount() -> void:
	land_cells = 0
	water_cells = 0
	for i in n():
		if heights[i] > sea_level and water[i] <= 0.0004:
			land_cells += 1
		elif water[i] > 0.0004:
			water_cells += 1


func _make_world_name() -> String:
	var first := ["Аэ", "Эль", "Тер", "Мун", "Ве", "Дра", "Ксе", "Ил", "Ор", "Соль", "Тал", "Нир"]
	var mid := ["те", "да", "ра", "ни", "ва", "ло", "ми", "са", "ру", "эль"]
	var last := ["рия", "дор", "ния", "мир", "гард", "тэль", "рия", "анд", "ор", "ия"]
	var r := RandomNumberGenerator.new()
	r.seed = seed + 777
	return first[r.randi() % first.size()] + mid[r.randi() % mid.size()] + last[r.randi() % last.size()]


# ------------------------------------------------------------------ editing

func raise_area(cx: int, cz: int, radius: float, strength: float, mode: String = "add") -> Rect2i:
	var r := int(ceil(radius))
	var rect := Rect2i(maxi(0, cx - r), maxi(0, cz - r), 0, 0)
	var x1 := mini(size - 1, cx + r)
	var z1 := mini(size - 1, cz + r)
	rect.size = Vector2i(x1 - rect.position.x + 1, z1 - rect.position.y + 1)
	var water_dirty := false
	for z in range(rect.position.y, z1 + 1):
		for x in range(rect.position.x, x1 + 1):
			var d := Vector2(x - cx, z - cz).length()
			if d > radius:
				continue
			var fall := 1.0 - smoothstep(radius * 0.35, radius, d)
			var i := idx(x, z)
			match mode:
				"add":
					heights[i] = clampf(heights[i] + strength * fall, 0.0, 1.0)
				"sub":
					heights[i] = clampf(heights[i] - strength * fall, 0.0, 1.0)
				"smooth":
					var avg := 0.0
					var cnt := 0
					for dz in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							var xx := clampi(x + dx, 0, size - 1)
							var zz := clampi(z + dz, 0, size - 1)
							avg += heights[idx(xx, zz)]
							cnt += 1
					avg /= float(cnt)
					heights[i] = lerpf(heights[i], avg, clampf(strength * fall, 0.0, 1.0))
			if _update_water_after_height(i):
				water_dirty = true
			_reclassify_cell(x, z)
	_refresh_climate(rect)
	terrain_changed.emit(rect)
	biomes_changed.emit(rect)
	if water_dirty:
		water_changed.emit(rect)
	return rect


func paint_biome(cx: int, cz: int, radius: float, biome_id_name: String, blend: bool = false) -> Rect2i:
	var r := int(ceil(radius))
	var rect := Rect2i(maxi(0, cx - r), maxi(0, cz - r), 0, 0)
	var x1 := mini(size - 1, cx + r)
	var z1 := mini(size - 1, cz + r)
	rect.size = Vector2i(x1 - rect.position.x + 1, z1 - rect.position.y + 1)
	var bid: int = biome_index.get(biome_id_name, 0)
	for z in range(rect.position.y, z1 + 1):
		for x in range(rect.position.x, x1 + 1):
			var d := Vector2(x - cx, z - cz).length()
			if d > radius:
				continue
			var i := idx(x, z)
			biome_ids[i] = bid
			var b := D.biome(biome_id_name)
			vegetation[i] = float(b.get("fertility", 0.3)) * (0.8 if blend else 1.0)
			fertility[i] = float(b.get("fertility", 0.3))
			if biome_id_name == "river" or biome_id_name == "lake":
				water[i] = maxf(water[i], 0.0045)
			elif biome_id_name in ["forest", "tropical", "taiga"]:
				water[i] = 0.0
			elif biome_id_name in ["volcano", "ashland", "desert"]:
				burn[i] = maxf(burn[i], 0.15)
			elif biome_id_name in ["meadow", "steppe", "savanna", "hills"]:
				water[i] = 0.0 if heights[i] > sea_level else water[i]
	for z2 in range(rect.position.y, rect.position.y + rect.size.y):
		for x2 in range(rect.position.x, rect.position.x + rect.size.x):
			var i2 := idx(x2, z2)
			var lat := absf(float(z2) / float(size - 1) - 0.5) * 2.0
			var alt := maxf(0.0, heights[i2] - sea_level)
			temperature[i2] = clampf(1.0 - lat * 1.08 - alt * 0.72, 0.0, 1.0)
			if water[i2] > 0.0004 and heights[i2] <= sea_level:
				moisture[i2] = 1.0
	biomes_changed.emit(rect)
	return rect


func water_area(cx: int, cz: int, radius: float, kind: String) -> Rect2i:
	var r := int(ceil(radius))
	var rect := Rect2i(maxi(0, cx - r), maxi(0, cz - r), 0, 0)
	var x1 := mini(size - 1, cx + r)
	var z1 := mini(size - 1, cz + r)
	rect.size = Vector2i(x1 - rect.position.x + 1, z1 - rect.position.y + 1)
	for z in range(rect.position.y, z1 + 1):
		for x in range(rect.position.x, x1 + 1):
			var d := Vector2(x - cx, z - cz).length()
			if d > radius:
				continue
			var i := idx(x, z)
			match kind:
				"shallow":
					heights[i] = minf(heights[i], sea_level - 0.012)
					water[i] = maxf(water[i], sea_level - heights[i])
				"river":
					heights[i] = maxf(sea_level + 0.006, heights[i] - 0.008)
					water[i] = maxf(water[i], 0.0045)
					biome_ids[i] = biome_index.get("river", 0)
				"lake":
					heights[i] = maxf(sea_level + 0.006, heights[i] - 0.012)
					water[i] = maxf(water[i], 0.0075)
					biome_ids[i] = biome_index.get("lake", 0)
				"ocean":
					heights[i] = minf(heights[i], sea_level - 0.055)
					water[i] = sea_level - heights[i]
				"dry":
					water[i] = 0.0
					if heights[i] <= sea_level:
						heights[i] = sea_level + 0.004
					biome_ids[i] = biome_index.get("beach", 0)
				"lava":
					heights[i] = maxf(heights[i], sea_level + 0.01)
					water[i] = 0.0
					burn[i] = 1.0
					biome_ids[i] = biome_index.get("volcano", 0)
	_refresh_climate(rect)
	terrain_changed.emit(rect)
	biomes_changed.emit(rect)
	water_changed.emit(rect)
	return rect


func set_burn(cx: int, cz: int, radius: int, amount: float) -> void:
	for z in range(maxi(0, cz - radius), mini(size, cz + radius + 1)):
		for x in range(maxi(0, cx - radius), mini(size, cx + radius + 1)):
			if Vector2(x - cx, z - cz).length() <= radius:
				var i := idx(x, z)
				burn[i] = clampf(maxf(burn[i], amount), 0.0, 1.0)


func add_radiation(cx: int, cz: int, radius: int, amount: float) -> void:
	for z in range(maxi(0, cz - radius), mini(size, cz + radius + 1)):
		for x in range(maxi(0, cx - radius), mini(size, cx + radius + 1)):
			var d := Vector2(x - cx, z - cz).length()
			if d <= radius:
				var i := idx(x, z)
				radiation[i] = clampf(radiation[i] + amount * (1.0 - d / maxf(1.0, radius)), 0.0, 1.0)


func _update_water_after_height(i: int) -> bool:
	var before := water[i]
	var h := heights[i]
	if h < sea_level:
		water[i] = maxf(water[i], sea_level - h)
	elif water[i] > 0.012:
		water[i] = 0.0
	# небольшие лужи просто исчезают при подъёме
	if water[i] > 0.0004 and h > sea_level + 0.012:
		water[i] = minf(water[i], 0.006)
	return absf(water[i] - before) > 0.00001


func _refresh_climate(rect: Rect2i) -> void:
	for z in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var i := idx(x, z)
			if water[i] > 0.0004 and heights[i] <= sea_level:
				moisture[i] = 1.0
			var lat := absf(float(z) / float(size - 1) - 0.5) * 2.0
			var alt := maxf(0.0, heights[i] - sea_level)
			temperature[i] = clampf(1.0 - lat * 1.08 - alt * 0.72, 0.0, 1.0)
			if water[i] > 0.0004:
				continue
			var b: String = biome_keys[biome_ids[i]]
			if b in ["ocean", "shallow", "reef", "river", "lake", "beach", "glacier", "snow", "mountains", "meadow", "forest", "taiga", "tropical", "desert", "savanna", "steppe", "hills"]:
				_reclassify_cell(x, z)


func _land_biome(t: float, m: float, h: float) -> String:
	var alt := h - sea_level
	if h <= sea_level + 0.014:
		return "beach"
	if t < 0.10:
		return "glacier" if alt < 0.15 else "snow"
	if alt > 0.50:
		return "snow"
	if alt > 0.38:
		return "mountains"
	if t < 0.26 and m > 0.46:
		return "taiga"
	if t > 0.66 and m < 0.27:
		return "desert"
	if t > 0.60 and m < 0.40:
		return "savanna"
	if m < 0.35:
		return "steppe"
	if m > 0.68 and t > 0.62:
		return "tropical"
	if m > 0.55:
		return "forest"
	if alt > 0.20:
		return "hills"
	return "meadow"


func _reclassify_cell(x: int, z: int) -> void:
	var i := idx(x, z)
	var h := heights[i]
	var t := temperature[i]
	var m := moisture[i]
	if water[i] > 0.0004:
		if h <= sea_level:
			var depth := sea_level - h
			if depth > 0.055:
				biome_ids[i] = biome_index.get("ocean", 0)
			elif depth > 0.028:
				biome_ids[i] = biome_index.get("shallow", 0)
			else:
				biome_ids[i] = biome_index.get("reef", 0) if (t > 0.55 and m > 0.55) else biome_index.get("shallow", 0)
		else:
			var b: String = biome_keys[biome_ids[i]]
			if b in ["river", "lake", "swamp"]:
				pass
			elif water[i] > 0.006:
				biome_ids[i] = biome_index.get("lake", 0)
			else:
				biome_ids[i] = biome_index.get("river", 0)
		return
	var id := _land_biome(t, m, h)
	biome_ids[i] = biome_index.get(id, 0)


# ------------------------------------------------------------------ queries

func add_clearing(center: Vector2i, radius: float) -> void:
	clearings.append({"c": center, "r": radius})


func is_cleared(x: int, z: int) -> bool:
	for c in clearings:
		if Vector2(c.c).distance_squared_to(Vector2(x, z)) < c.r * c.r:
			return true
	return false


func find_settlement_sites(count: int, min_dist: float = 22.0) -> Array:
	var candidates: Array = []
	var step := maxi(2, size / 72)
	for z in range(step, size - step, step):
		for x in range(step, size - step, step):
			if not is_land_cell(x, z):
				continue
			var b := biome_name_at(x, z)
			if b in ["snow", "glacier", "volcano", "ashland", "ocean", "shallow", "reef", "mountains"]:
				continue
			if water[idx(x, z)] > 0.0004:
				continue
			var h := heights[idx(x, z)]
			if h < sea_level + 0.008:
				continue
			# уклон площадки 7x7: поселение не ставим на пики и крутые склоны
			var relief := 0.0
			var fp := 3
			for dz in range(-fp, fp + 1):
				for dx in range(-fp, fp + 1):
					var hh := heights[idx(clampi(x + dx, 0, size - 1), clampi(z + dz, 0, size - 1))]
					var dev := absf(hh - h)
					relief = maxf(relief, dev)
			if relief > 0.052:
				continue
			var rough := 0.0
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					rough += absf(heights[idx(clampi(x + dx, 0, size - 1), clampi(z + dz, 0, size - 1))] - h)
			if rough > 0.13:
				continue
			var score := 0.0
			score += clampf(1.0 - relief * 20.0, 0.0, 1.0) * 3.2
			# вода рядом
			var fresh := false
			var coast := false
			for dz in range(-5, 6):
				for dx in range(-5, 6):
					if dx * dx + dz * dz > 25:
						continue
					var xx := x + dx
					var zz := z + dz
					if not in_bounds(xx, zz):
						continue
					var wi := water[idx(xx, zz)]
					if wi > 0.0004:
						var wb := biome_name_at(xx, zz)
						if wb in ["river", "lake", "swamp"]:
							fresh = true
						if wb in ["ocean", "shallow", "reef"]:
							coast = true
			if fresh: score += 4.0
			elif coast: score += 1.5
			# растительность
			score += vegetation[idx(x, z)] * 2.5
			# ровность
			var flat := 0.0
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					flat += absf(heights[idx(clampi(x + dx, 0, size - 1), clampi(z + dz, 0, size - 1))] - h)
			score += clampf(1.0 - flat * 25.0, 0.0, 1.0) * 2.0
			# ресурсы
			if res_type[idx(x, z)] in [1, 2, 3, 4]:
				score += 1.0
			var biome := biome_at(x, z)
			var races: Array = biome.get("races", [])
			var race_id := "human"
			if races.size() > 0:
				race_id = races[rng.randi() % races.size()]
			if not fresh and not coast:
				score -= 2.5
			if biome.get("fertility", 0.0) < 0.2:
				score -= 1.5
			candidates.append({"cell": Vector2i(x, z), "score": score, "race": race_id, "biome": b})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	var picked: Array = []
	for c in candidates:
		if picked.size() >= count:
			break
		var ok := true
		for p in picked:
			if Vector2(c.cell - p.cell).length() < min_dist:
				ok = false
				break
		if ok and c.score > 0.0:
			picked.append(c)
	return picked


func biome_counts() -> Dictionary:
	var out: Dictionary = {}
	for i in n():
		var key: String = biome_keys[biome_ids[i]]
		out[key] = out.get(key, 0) + 1
	return out


func resource_name(t: int) -> String:
	if t <= 0 or t >= RES_NAMES.size():
		return ""
	return RES_NAMES[t]
