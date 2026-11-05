class_name NatureView
extends Node3D
## Леса, кусты, камни, камыш, кристаллы — через MultiMesh.

var world: WorldModel
var multimesshes: Dictionary = {}
var dirty := false
var rebuild_delay := 0.0

const TYPES := ["broadleaf", "conifer", "palm", "swamp", "dead", "cactus", "acacia", "crystal", "bush", "reed", "flowers", "mushroom", "rock"]


func setup(p_world: WorldModel) -> void:
	world = p_world
	rebuild()
	world.biomes_changed.connect(func(_r): mark_dirty())
	world.terrain_changed.connect(func(_r): mark_dirty())


func mark_dirty() -> void:
	dirty = true
	rebuild_delay = 0.7


func _process(delta: float) -> void:
	if not dirty:
		return
	rebuild_delay -= delta
	if rebuild_delay <= 0.0:
		dirty = false
		rebuild()


func rebuild() -> void:
	for m in multimesshes.values():
		m.queue_free()
	multimesshes.clear()
	var buckets: Dictionary = {}
	for t in TYPES:
		buckets[t] = []
	var half := world.size * 0.5
	for z in range(1, world.size - 1):
		for x in range(1, world.size - 1):
			var i := world.idx(x, z)
			if world.water[i] > 0.0004:
				# камыш у воды
				if world.heights[i] > world.sea_level and _hash(x, z, 3) < 0.10:
					_add(buckets, "reed", x, z, 0.8 + _hash(x, z, 4) * 0.6, _hash(x, z, 5))
				continue
			if world.is_cleared(x, z):
				continue
			var bid: int = world.biome_ids[i]
			var b: Dictionary = D.biomes[bid]
			var veg: float = world.vegetation[i]
			if veg < 0.04:
				continue
			var h := _hash(x, z, 11)
			var kind := str(b.get("tree", "none"))
			var density := float(b.get("tree_density", 0.0))
			# деревья
			if kind in ["broadleaf", "conifer", "palm", "swamp", "dead", "cactus", "acacia", "crystal"]:
				var p := density * (0.6 + veg * 0.7)
				if h < p:
					var sc := 0.65 + _hash(x, z, 12) * 0.5
					_add(buckets, kind, x, z, sc, _hash(x, z, 13))
					if kind in ["broadleaf", "palm", "swamp"] and _hash(x, z, 14) < 0.10:
						_add(buckets, kind, x, z, sc * 0.72, _hash(x, z, 15))
			# камни
			var rock_d := float(b.get("rock", 0.0))
			if rock_d > 0.0 and _hash(x, z, 21) < rock_d * 0.25:
				_add(buckets, "rock", x, z, 0.6 + _hash(x, z, 22) * 1.3, _hash(x, z, 23))
			# кусты
			if _hash(x, z, 31) < clampf(veg * 0.055, 0.0, 0.05):
				_add(buckets, "bush", x, z, 0.7 + _hash(x, z, 32) * 0.8, _hash(x, z, 33))
			# цветы
			if str(b.id) in ["meadow", "savanna", "steppe"] and _hash(x, z, 41) < 0.010:
				_add(buckets, "flowers", x, z, 0.7 + _hash(x, z, 42) * 0.6, _hash(x, z, 43))
			# грибы
			if str(b.id) in ["forest", "swamp", "taiga"] and _hash(x, z, 51) < 0.010:
				_add(buckets, "mushroom", x, z, 0.7 + _hash(x, z, 52) * 0.7, _hash(x, z, 53))
	for t in TYPES:
		var arr: Array = buckets[t]
		if arr.is_empty():
			continue
		var mesh: ArrayMesh = MeshKit.tree_mesh(t) if t != "rock" else MeshKit.rock_mesh()
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
			var b := Basis(Vector3.UP, rot * TAU).scaled(Vector3(sc, sc * (0.85 + item.h * 0.3), sc))
			mm.set_instance_transform(idx, Transform3D(b, Vector3(wx, wy, wz)))
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
		add_child(mmi)
		multimesshes[t] = mmi


func _add(buckets: Dictionary, kind: String, x: int, z: int, sc: float, r: float) -> void:
	var ox := _hash(x, z, 61) * 0.86 - 0.43
	var oz := _hash(x, z, 62) * 0.86 - 0.43
	buckets[kind].append({"x": x, "z": z, "ox": ox, "oz": oz, "sc": sc, "rot": r, "h": _hash(x, z, 63), "tint": _hash(x, z, 64), "tint2": _hash(x, z, 65)})


func _hash(x: int, z: int, salt: int) -> float:
	var v := sin(float(x) * 127.1 + float(z) * 311.7 + float(salt) * 74.7) * 43758.5453
	return v - floor(v)


func tree_count() -> int:
	var c := 0
	if multimesshes.has("broadleaf"): c += multimesshes["broadleaf"].multimesh.instance_count
	if multimesshes.has("conifer"): c += multimesshes["conifer"].multimesh.instance_count
	if multimesshes.has("palm"): c += multimesshes["palm"].multimesh.instance_count
	if multimesshes.has("swamp"): c += multimesshes["swamp"].multimesh.instance_count
	if multimesshes.has("acacia"): c += multimesshes["acacia"].multimesh.instance_count
	if multimesshes.has("dead"): c += multimesshes["dead"].multimesh.instance_count
	if multimesshes.has("cactus"): c += multimesshes["cactus"].multimesh.instance_count
	return c
