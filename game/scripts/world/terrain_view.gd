class_name TerrainView
extends Node3D
## Рендер рельефа и воды по чанкам + миникарта. Плоские low-poly грани.

const CHUNK := 32

var world: WorldModel
var chunks: Dictionary = {}        # Vector2i -> MeshInstance3D
var water_chunks: Dictionary = {}
var terrain_mat: StandardMaterial3D
var water_mat: ShaderMaterial

var layer: String = "normal"
var minimap_image: Image
var minimap_texture: ImageTexture
var minimap_dirty := true

var res_colors := {
	1: Color("#b05a3a"), 2: Color("#3a3a3a"), 3: Color("#e8c04a"),
	4: Color("#9a9a8a"), 5: Color("#b07a4a"), 6: Color("#e8e2d2"),
	7: Color("#222222"), 8: Color("#6aff6a"), 9: Color("#b48aff")
}


func setup(p_world: WorldModel) -> void:
	world = p_world
	terrain_mat = StandardMaterial3D.new()
	terrain_mat.vertex_color_use_as_albedo = true
	terrain_mat.vertex_color_is_srgb = true
	terrain_mat.roughness = 0.93
	terrain_mat.metallic = 0.0
	terrain_mat.metallic_specular = 0.08
	terrain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	water_mat.set_shader_parameter("wave_amp", 0.06)
	# бесконечный океан за краем карты
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ocean.mesh = pm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color("#0c3550")
	om.roughness = 0.18
	om.metallic = 0.25
	om.metallic_specular = 0.6
	ocean.material_override = om
	ocean.position.y = -0.45
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)
	rebuild_all()
	world.terrain_changed.connect(_on_terrain_changed)
	world.biomes_changed.connect(_on_biomes_changed)


func _chunk_count() -> int:
	return int(ceil(float(world.size) / CHUNK))


func rebuild_all() -> void:
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	for c in water_chunks.values():
		c.queue_free()
	water_chunks.clear()
	var cc := _chunk_count()
	for cz in cc:
		for cx in cc:
			_build_chunk(Vector2i(cx, cz))
			_build_water_chunk(Vector2i(cx, cz))
	_build_minimap()
	minimap_dirty = false


func _on_terrain_changed(rect: Rect2i) -> void:
	rebuild_rect(rect)
	minimap_dirty = true


func _on_biomes_changed(rect: Rect2i) -> void:
	rebuild_rect(rect)
	minimap_dirty = true


func rebuild_rect(rect: Rect2i) -> void:
	var c0 := Vector2i(maxi(0, rect.position.x / CHUNK), maxi(0, rect.position.y / CHUNK))
	var c1 := Vector2i(mini(_chunk_count() - 1, (rect.position.x + rect.size.x) / CHUNK), mini(_chunk_count() - 1, (rect.position.y + rect.size.y) / CHUNK))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_build_chunk(Vector2i(cx, cz))
			_build_water_chunk(Vector2i(cx, cz))


func set_layer(l: String) -> void:
	if layer == l:
		return
	layer = l
	for key in chunks:
		_build_chunk(key)
	_build_minimap()
	minimap_dirty = false


func _cell_color(x: int, z: int) -> Color:
	var i := world.idx(x, z)
	var bid: int = world.biome_ids[i]
	var bcolor: Color = D.biomes[bid].get("color_c", Color.MAGENTA)
	var v: float = world.vegetation[i]
	var h: float = world.heights[i]
	var water: float = world.water[i]
	var hash := _hash(x, z)
	match layer:
		"height":
			var t := clampf((h - 0.0) / 1.0, 0.0, 1.0)
			return Color(0.08 + t * 0.75, 0.10 + t * 0.8, 0.16 + t * 0.7)
		"temp":
			var t := clampf(world.temperature[i], 0.0, 1.0)
			return Color(0.1, 0.25, 0.85).lerp(Color(0.95, 0.35, 0.12), t) if t > 0.5 else Color(0.15, 0.45, 0.9).lerp(Color(0.9, 0.85, 0.25), t * 2.0)
		"moisture":
			var m := clampf(world.moisture[i], 0.0, 1.0)
			return Color(0.55, 0.45, 0.28).lerp(Color(0.12, 0.55, 0.55), m)
		"resource":
			var rt: int = world.res_type[i]
			if rt > 0:
				return Color(0.16, 0.16, 0.18).lerp(res_colors.get(rt, Color.WHITE), 0.85)
			return Color(0.10, 0.11, 0.12)
		"radiation":
			var r: float = clampf(world.radiation[i], 0.0, 1.0)
			return Color(0.06, 0.09, 0.06).lerp(Color(0.35, 1.0, 0.3), r)
		"biome":
			if water > 0.0004 and h <= world.sea_level:
				return bcolor.darkened(0.25)
			return bcolor
		_:
			pass
	if water > 0.0004:
		return bcolor.darkened(0.38)
	var c := bcolor
	# высота и растительность
	c = c.darkened(clampf((0.5 - h) * 0.35, -0.12, 0.3))
	c = c.lerp(Color("#2d5a24"), clampf(v * 0.22, 0.0, 0.25))
	c = c.lightened(clampf((h - world.sea_level) * 0.28, 0.0, 0.18))
	if h > world.sea_level + 0.36:
		c = c.lerp(Color("#e8eef2"), clampf((h - world.sea_level - 0.36) * 2.8, 0.0, 0.7))
	if world.burn[i] > 0.01:
		c = c.lerp(Color("#241c18"), clampf(world.burn[i], 0.0, 0.85))
	if world.radiation[i] > 0.01:
		c = c.lerp(Color("#55cc44"), clampf(world.radiation[i] * 0.6, 0.0, 0.55))
	# тонкая вариация
	var n := (hash - 0.5) * 0.075
	c = Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1), 1.0)
	return c


func _hash(x: int, z: int) -> float:
	var v := sin(float(x) * 12.9898 + float(z) * 78.233) * 43758.5453
	return v - floor(v)


func _build_chunk(key: Vector2i) -> void:
	var x0 := key.x * CHUNK
	var z0 := key.y * CHUNK
	var x1 := mini(x0 + CHUNK, world.size)
	var z1 := mini(z0 + CHUNK, world.size)
	if x0 >= x1 or z0 >= z1:
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var vcount := 0
	var half := world.size * 0.5
	for z in range(z0, z1):
		for x in range(x0, x1):
			var col := _cell_color(x, z)
			var p00 := Vector3((x - half) * WorldModel.CELL, (world.heights[world.idx(x, z)] - world.sea_level) * WorldModel.HEIGHT_SCALE, (z - half) * WorldModel.CELL)
			var p10 := Vector3((x + 1 - half) * WorldModel.CELL, (world.heights[world.idx(mini(x + 1, world.size - 1), z)] - world.sea_level) * WorldModel.HEIGHT_SCALE, (z - half) * WorldModel.CELL)
			var p01 := Vector3((x - half) * WorldModel.CELL, (world.heights[world.idx(x, mini(z + 1, world.size - 1))] - world.sea_level) * WorldModel.HEIGHT_SCALE, (z + 1 - half) * WorldModel.CELL)
			var p11 := Vector3((x + 1 - half) * WorldModel.CELL, (world.heights[world.idx(mini(x + 1, world.size - 1), mini(z + 1, world.size - 1))] - world.sea_level) * WorldModel.HEIGHT_SCALE, (z + 1 - half) * WorldModel.CELL)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0: n = -n
			var shade := 1.0 - clampf((1.0 - n.y) * 0.8, 0.0, 0.45)
			var cc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			verts.append(p00); verts.append(p01); verts.append(p11); verts.append(p10)
			for k in 4:
				norms.append(n)
				cols.append(cc)
			idxs.append(vcount); idxs.append(vcount + 1); idxs.append(vcount + 2)
			idxs.append(vcount); idxs.append(vcount + 2); idxs.append(vcount + 3)
			vcount += 4
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi: MeshInstance3D = chunks.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Terrain_%d_%d" % [key.x, key.y]
		mi.material_override = terrain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		chunks[key] = mi
	mi.mesh = mesh


func _build_water_chunk(key: Vector2i) -> void:
	var x0 := key.x * CHUNK
	var z0 := key.y * CHUNK
	var x1 := mini(x0 + CHUNK, world.size)
	var z1 := mini(z0 + CHUNK, world.size)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idxs := PackedInt32Array()
	var vcount := 0
	var half := world.size * 0.5
	for z in range(z0, z1):
		for x in range(x0, x1):
			var i := world.idx(x, z)
			if world.water[i] <= 0.00045:
				continue
			var y := world.water_surface_y(x, z)
			var wd := world.water[i]
			var h := world.heights[i]
			var col := Color("#2a86a8")
			var alpha := 0.78
			if h <= world.sea_level:
				if wd > 0.06:
					col = Color("#0d4a78")
					alpha = 0.9
				elif wd > 0.024:
					col = Color("#166a9a")
					alpha = 0.84
				else:
					col = Color("#3cb8c9")
					alpha = 0.68
			else:
				col = Color("#4aa8c4")
				alpha = 0.72
			# пена у берега
			var shore := false
			if not world.is_water_cell(clampi(x + 1, 0, world.size - 1), z) or not world.is_water_cell(clampi(x - 1, 0, world.size - 1), z) or not world.is_water_cell(x, clampi(z + 1, 0, world.size - 1)) or not world.is_water_cell(x, clampi(z - 1, 0, world.size - 1)):
				shore = true
			if shore:
				col = Color("#bfeef0")
				alpha = 0.55
			var p00 := Vector3((x - half) * WorldModel.CELL, y, (z - half) * WorldModel.CELL)
			var p10 := Vector3((x + 1 - half) * WorldModel.CELL, y, (z - half) * WorldModel.CELL)
			var p01 := Vector3((x - half) * WorldModel.CELL, y, (z + 1 - half) * WorldModel.CELL)
			var p11 := Vector3((x + 1 - half) * WorldModel.CELL, y, (z + 1 - half) * WorldModel.CELL)
			verts.append(p00); verts.append(p01); verts.append(p11); verts.append(p10)
			var cc := Color(col.r, col.g, col.b, alpha)
			for k in 4:
				cols.append(cc)
				norms.append(Vector3.UP)
			idxs.append(vcount); idxs.append(vcount + 1); idxs.append(vcount + 2)
			idxs.append(vcount); idxs.append(vcount + 2); idxs.append(vcount + 3)
			vcount += 4
	var mi: MeshInstance3D = water_chunks.get(key)
	if verts.is_empty():
		if mi != null:
			mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Water_%d_%d" % [key.x, key.y]
		mi.material_override = water_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		water_chunks[key] = mi
	mi.mesh = mesh


func _build_minimap() -> void:
	var n := world.size
	if minimap_image == null or minimap_image.get_width() != n:
		minimap_image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for z in n:
		for x in n:
			var i := world.idx(x, z)
			var c := Color.BLACK
			if world.water[i] > 0.0004:
				var depth := 0.0
				if world.heights[i] <= world.sea_level:
					depth = world.sea_level - world.heights[i]
				c = Color("#1d5f8a").lerp(Color("#0a2c48"), clampf(depth * 12.0, 0.0, 1.0))
				if world.water[i] < 0.006:
					c = Color("#4fb4c8")
			else:
				c = D.biomes[world.biome_ids[i]].get("color_c", Color.BLACK)
				c = c.darkened(clampf((0.45 - world.heights[i]) * 0.4, -0.1, 0.35))
				c = c.lerp(Color("#244d1e"), world.vegetation[i] * 0.18)
				if world.burn[i] > 0.05:
					c = c.lerp(Color("#2a1a12"), 0.6)
				if world.radiation[i] > 0.1:
					c = c.lerp(Color("#4faf3a"), 0.5)
			minimap_image.set_pixel(x, z, c)
	if minimap_texture == null:
		minimap_texture = ImageTexture.create_from_image(minimap_image)
	else:
		minimap_texture.update(minimap_image)


func refresh_minimap_if_dirty() -> bool:
	if not minimap_dirty:
		return false
	_build_minimap()
	minimap_dirty = false
	return true


func minimap_cell_at(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(int(uv.x * world.size), 0, world.size - 1), clampi(int(uv.y * world.size), 0, world.size - 1))
