class_name NatureView
extends Node3D
## Леса, кусты, камни, камыш, кристаллы — MultiMesh по чанкам.
## Любое изменение мира обновляет только затронутые чанки.

const CHUNK := 32
const TYPES := ["broadleaf", "conifer", "palm", "swamp", "dead", "cactus", "acacia", "crystal", "bush", "reed", "flowers", "mushroom", "rock"]
const TREE_KINDS := ["broadleaf", "conifer", "palm", "swamp", "dead", "cactus", "acacia", "crystal"]

var world: WorldModel
var chunks: Dictionary = {}          # Vector2i -> Node3D
var dirty_chunks: Dictionary = {}
var chunk_counts: Dictionary = {}    # Vector2i -> количество деревьев
var mesh_cache: Dictionary = {}
var chunks_per_frame := 2
var full_requested := false
var prof_us := 0
var prof_n := 0
var prof_on := false
var bio_tree_idx := PackedInt32Array()
var bio_density := PackedFloat32Array()
var bio_rock := PackedFloat32Array()
var bio_flower := PackedByteArray()
var bio_mushroom := PackedByteArray()
var defer_until_ms := 0


func setup(p_world: WorldModel) -> void:
	world = p_world
	_cache_biomes()
	rebuild_all()
	world.biomes_changed.connect(func(r): mark_dirty_rect(r))
	world.terrain_changed.connect(func(r): mark_dirty_rect(r))


func _cache_biomes() -> void:
	var n := D.biomes.size()
	bio_tree_idx.resize(n)
	bio_density.resize(n)
	bio_rock.resize(n)
	bio_flower.resize(n)
	bio_mushroom.resize(n)
	for i in n:
		var b: Dictionary = D.biomes[i]
		var kind := str(b.get("tree", "none"))
		bio_tree_idx[i] = TREE_KINDS.find(kind)
		bio_density[i] = float(b.get("tree_density", 0.0))
		bio_rock[i] = float(b.get("rock", 0.0))
		var bid := str(b.get("id", ""))
		bio_flower[i] = 1 if bid in ["meadow", "savanna", "steppe"] else 0
		bio_mushroom[i] = 1 if bid in ["forest", "swamp", "taiga"] else 0


func mark_dirty() -> void:
	full_requested = true
	dirty_chunks.clear()
	var cc := int(ceil(float(world.size) / CHUNK))
	for cz in cc:
		for cx in cc:
			dirty_chunks[Vector2i(cx, cz)] = true


func mark_dirty_rect(rect: Rect2i) -> void:
	# во время активного мазка природа не пересобирается: копим грязные чанки
	# и обновляем их пачкой после короткой паузы, чтобы не отбирать кадр у рельефа
	defer_until_ms = Time.get_ticks_msec() + 400
	var cc := int(ceil(float(world.size) / CHUNK))
	var c0 := Vector2i(maxi(0, rect.position.x / CHUNK), maxi(0, rect.position.y / CHUNK))
	var c1 := Vector2i(mini(cc - 1, (rect.position.x + rect.size.x) / CHUNK), mini(cc - 1, (rect.position.y + rect.size.y) / CHUNK))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			dirty_chunks[Vector2i(cx, cz)] = true


func _process(_delta: float) -> void:
	if dirty_chunks.is_empty():
		return
	if Time.get_ticks_msec() < defer_until_ms:
		return
	var t0 := Time.get_ticks_usec()
	var keys := dirty_chunks.keys()
	var per_frame := chunks_per_frame
	if Time.get_ticks_msec() - defer_until_ms > 300:
		per_frame = maxi(per_frame, 2)
	var budget := mini(per_frame, keys.size())
	for i in budget:
		var key: Vector2i = keys[i]
		dirty_chunks.erase(key)
		_rebuild_chunk(key)
	if not prof_on and "--profile" in OS.get_cmdline_args():
		prof_on = true
	if prof_on:
		prof_us += Time.get_ticks_usec() - t0
		prof_n += 1
		if prof_n >= 60:
			print("[perf] nature %.1fms/frame" % (prof_us / float(prof_n) / 1000.0))
			prof_us = 0
			prof_n = 0


func rebuild_all() -> void:
	full_requested = false
	dirty_chunks.clear()
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	chunk_counts.clear()
	var cc := int(ceil(float(world.size) / CHUNK))
	for cz in cc:
		for cx in cc:
			_rebuild_chunk(Vector2i(cx, cz))


func _rebuild_chunk(key: Vector2i) -> void:
	if chunks.has(key):
		var old: Node3D = chunks[key]
		old.queue_free()
		chunks.erase(key)
	var x0 := key.x * CHUNK
	var z0 := key.y * CHUNK
	var x1 := mini(x0 + CHUNK, world.size)
	var z1 := mini(z0 + CHUNK, world.size)
	if x0 >= x1 or z0 >= z1:
		return
	var root := Node3D.new()
	root.name = "Nature_%d_%d" % [key.x, key.y]
	add_child(root)
	chunks[key] = root
	var buckets: Dictionary = {}
	for t in TYPES:
		buckets[t] = []
	var trees := 0
	var half := world.size * 0.5
	var heights := world.heights
	var water := world.water
	var vegs := world.vegetation
	var bids := world.biome_ids
	var sea := world.sea_level
	for z in range(z0, z1):
		for x in range(x0, x1):
			var i := z * world.size + x
			if water[i] > 0.0004:
				if heights[i] > sea and _hash(x, z, 3) < 0.10:
					_add(buckets, "reed", x, z, 0.8 + _hash(x, z, 4) * 0.6, _hash(x, z, 5))
				continue
			if world.is_cleared(x, z):
				continue
			var veg: float = vegs[i]
			if veg < 0.04:
				continue
			var bid: int = bids[i]
			var kind_idx: int = bio_tree_idx[bid]
			var h := _hash(x, z, 11)
			if kind_idx >= 0:
				var p := bio_density[bid] * (0.6 + veg * 0.7)
				if h < p:
					var kind: String = TREE_KINDS[kind_idx]
					var sc := 0.65 + _hash(x, z, 12) * 0.5
					_add(buckets, kind, x, z, sc, _hash(x, z, 13))
					trees += 1
					if kind_idx <= 3 and _hash(x, z, 14) < 0.10:
						_add(buckets, kind, x, z, sc * 0.72, _hash(x, z, 15))
						trees += 1
			var rock_d := bio_rock[bid]
			if rock_d > 0.0 and _hash(x, z, 21) < rock_d * 0.25:
				_add(buckets, "rock", x, z, 0.6 + _hash(x, z, 22) * 1.3, _hash(x, z, 23))
			if _hash(x, z, 31) < clampf(veg * 0.055, 0.0, 0.05):
				_add(buckets, "bush", x, z, 0.7 + _hash(x, z, 32) * 0.8, _hash(x, z, 33))
			if bio_flower[bid] == 1 and _hash(x, z, 41) < 0.010:
				_add(buckets, "flowers", x, z, 0.7 + _hash(x, z, 42) * 0.6, _hash(x, z, 43))
			if bio_mushroom[bid] == 1 and _hash(x, z, 51) < 0.010:
				_add(buckets, "mushroom", x, z, 0.7 + _hash(x, z, 52) * 0.7, _hash(x, z, 53))
	chunk_counts[key] = trees
	for t in TYPES:
		var arr: Array = buckets[t]
		if arr.is_empty():
			continue
		var mesh: ArrayMesh = _mesh_for(t)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = arr.size()
		mm.mesh = mesh
		var idx := 0
		for item in arr:
			var sx: float = item.x
			var sz: float = item.z
			var sc: float = item.sc
			var rot: float = item.rot
			var wx: float = (sx + item.ox - half) * WorldModel.CELL
			var wz: float = (sz + item.oz - half) * WorldModel.CELL
			var wy: float = world.terrain_y(sx + item.ox, sz + item.oz)
			var basis := Basis(Vector3.UP, rot * TAU).scaled(Vector3(sc, sc * (0.85 + item.h * 0.3), sc))
			mm.set_instance_transform(idx, Transform3D(basis, Vector3(wx, wy, wz)))
			var tint := Color(0.78 + item.tint * 0.22, 0.82 + item.tint2 * 0.18, 0.78 + item.tint * 0.2, 1.0)
			if t in ["dead", "rock"]:
				tint = Color(0.85 + item.tint * 0.25, 0.85 + item.tint * 0.25, 0.85 + item.tint * 0.25, 1.0)
			mm.set_instance_color(idx, tint)
			idx += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + t
		mmi.multimesh = mm
		mmi.material_override = MeshKit.vertex_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 700.0
		root.add_child(mmi)


func _mesh_for(kind: String) -> ArrayMesh:
	if mesh_cache.has(kind):
		return mesh_cache[kind]
	var m: ArrayMesh = MeshKit.tree_mesh(kind) if kind != "rock" else MeshKit.rock_mesh()
	mesh_cache[kind] = m
	return m


func _add(buckets: Dictionary, kind: String, x: int, z: int, sc: float, r: float) -> void:
	var ox := _hash(x, z, 61) * 0.86 - 0.43
	var oz := _hash(x, z, 62) * 0.86 - 0.43
	buckets[kind].append({"x": x, "z": z, "ox": ox, "oz": oz, "sc": sc, "rot": r, "h": _hash(x, z, 63), "tint": _hash(x, z, 64), "tint2": _hash(x, z, 65)})


func _hash(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = (h ^ (h >> 16)) & 0x7fffffff
	return float(h) / 2147483647.0


func tree_count() -> int:
	var c := 0
	for v in chunk_counts.values():
		c += int(v)
	return c
