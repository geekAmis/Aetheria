class_name SettlementView
extends Node3D
## Поселения: здания, кольца территорий, подписи, костры и стройки.

var world: WorldModel
var sim: SimWorld
var camera_rig: CameraRig
var nodes: Dictionary = {}
var building_cache: Dictionary = {}
var selected_id: int = -1
var timer := 0.0
var flame_mat: StandardMaterial3D
var ruin_mat: StandardMaterial3D
var road_root: Node3D
var road_sig := ""
var road_mesh: BoxMesh
var road_mat: StandardMaterial3D
var road_paved_mat: StandardMaterial3D
var last_rebuild_us := 0
var last_roads_us := 0


func setup(p_world: WorldModel, p_sim: SimWorld, p_camera: CameraRig = null) -> void:
	world = p_world
	sim = p_sim
	camera_rig = p_camera
	flame_mat = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.45, 0.1)
	flame_mat.emission_energy_multiplier = 4.0
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ruin_mat = StandardMaterial3D.new()
	ruin_mat.vertex_color_use_as_albedo = true
	ruin_mat.vertex_color_is_srgb = true
	ruin_mat.roughness = 1.0
	sim.settlement_founded.connect(func(_s):
		if not sim.bulk_mode:
			_ensure_node(_s)
	)
	sim.settlement_structure_changed.connect(_on_structure_changed)
	sim.settlement_changed.connect(_on_structure_changed)
	road_root = Node3D.new()
	road_root.name = "Roads"
	add_child(road_root)
	road_mesh = BoxMesh.new()
	road_mesh.size = Vector3(1.9, 0.09, 1.4)
	road_mat = StandardMaterial3D.new()
	road_mat.albedo_color = Color("#6a5638")
	road_mat.roughness = 1.0
	road_paved_mat = StandardMaterial3D.new()
	road_paved_mat.albedo_color = Color("#2b2b30")
	road_paved_mat.roughness = 0.85
	road_paved_mat.metallic = 0.05
	for s in sim.settlements:
		_ensure_node(s)


func _ensure_node(s: SettlementData) -> void:
	if nodes.has(s.id):
		return
	var n := Node3D.new()
	n.name = "Settlement_" + str(s.id)
	var center := s.center
	var half := world.size * 0.5
	n.position = Vector3((center.x - half) * WorldModel.CELL, world.terrain_y(center.x, center.y), (center.y - half) * WorldModel.CELL)
	add_child(n)
	var data := {
		"root": n,
		"ring": null,
		"label": null,
		"buildings": Node3D.new(),
		"construction": null,
		"lights": [],
		"signature": "",
		"stage": ""
	}
	data.buildings.name = "Buildings"
	n.add_child(data.buildings)
	nodes[s.id] = data
	_rebuild_settlement(s, data)


func _on_structure_changed(id: int) -> void:
	if sim.bulk_mode:
		return
	var s: SettlementData = sim.settlement_by_id.get(id, null)
	if s == null:
		return
	_ensure_node(s)
	_rebuild_settlement(s, nodes[id])


func _rebuild_settlement(s: SettlementData, data: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var n: Node3D = data.root
	# кольцо территории
	if data.ring != null:
		data.ring.queue_free()
	var ring := MeshInstance3D.new()
	ring.mesh = _territory_mesh(s)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	data.ring = ring
	# подпись
	if data.label == null:
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.font_size = 19
		lbl.pixel_size = 0.0012
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0.02, 0.03, 0.04, 0.9)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector3(0, 8.5, 0)
		n.add_child(lbl)
		data.label = lbl
	# здания
	for c in data.buildings.get_children():
		c.queue_free()
	for l in data.lights:
		if is_instance_valid(l):
			l.queue_free()
	data.lights.clear()
	if s.destroyed:
		data.label.text = s.name + "\n" + L.t("stage_ruins")
		data.label.modulate = Color(0.55, 0.5, 0.45)
		for i in 3:
			var r := MeshInstance3D.new()
			r.mesh = MeshKit.rock_mesh()
			r.material_override = ruin_mat
			r.scale = Vector3(0.8 + i * 0.2, 0.5, 0.7)
			r.position = Vector3((i - 1) * 3.0, 0.2, (i % 2) * 2.0)
			data.buildings.add_child(r)
		data.stage = "ruins"
		data.signature = _signature(s)
		return
	var center_terrain := world.terrain_y(s.center.x, s.center.y)
	var has_campfire := false
	for b in s.buildings:
		var type := str(b.type)
		var mesh := _get_building_mesh(type)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = MeshKit.vertex_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var bx := float(b.x)
		var bz := float(b.z)
		var by := world.terrain_y(bx, bz) - center_terrain
		mi.position = Vector3((bx - s.center.x) * WorldModel.CELL, by, (bz - s.center.y) * WorldModel.CELL)
		mi.rotation.y = float(b.get("rot", 0.0))
		var lvl := float(b.get("level", 1))
		mi.scale = Vector3(lvl, lvl, lvl)
		data.buildings.add_child(mi)
		if type == "campfire" and not has_campfire:
			has_campfire = true
			_add_flame(data, mi.position, s)
		if type in ["temple", "library", "university", "monument", "market"]:
			var l := OmniLight3D.new()
			l.position = mi.position + Vector3(0, 3.0, 0)
			l.light_color = Color(1.0, 0.72, 0.35)
			l.light_energy = 0.8
			l.omni_range = 12.0
			l.shadow_enabled = false
			data.buildings.add_child(l)
			data.lights.append(l)
	data.stage = s.stage
	data.signature = _signature(s)
	# строительная площадка
	_update_construction(s, data)
	last_rebuild_us = Time.get_ticks_usec() - t0


func _add_flame(data: Dictionary, pos: Vector3, s: SettlementData) -> void:
	var flame := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.cone(st, Vector3(0, 0, 0), 0.9, 2.2, Color.WHITE, 6)
	MeshKit.cone(st, Vector3(0.25, 0, 0.2), 0.5, 1.5, Color.WHITE, 5)
	flame.mesh = MeshKit.commit(st)
	flame.material_override = flame_mat
	flame.position = pos + Vector3(0, 0.4, 0)
	flame.name = "Flame"
	data.buildings.add_child(flame)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 2.2, 0)
	l.light_color = Color(1.0, 0.55, 0.18)
	l.light_energy = 2.2
	l.omni_range = 14.0
	l.shadow_enabled = false
	l.name = "CampLight"
	data.buildings.add_child(l)
	data.lights.append(l)


func _update_construction(s: SettlementData, data: Dictionary) -> void:
	if data.construction != null and is_instance_valid(data.construction):
		data.construction.queue_free()
		data.construction = null
	if s.construction.is_empty() or s.destroyed:
		return
	var c := s.construction
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.box(st, Vector3(0, 0.5, 0), Vector3(4.0, 1.0, 4.0), Color(0.55, 0.45, 0.3, 0.35))
	var mesh := MeshKit.commit(st)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.6)
	mi.material_override = mat
	node.add_child(mi)
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.font_size = 22
	lbl.pixel_size = 0.00075
	lbl.modulate = Color(1, 0.9, 0.65)
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.text = "%s %d%%" % [L.tc(D.building(str(c.get("type", "hut")))), int(100.0 * float(c.get("progress", 0.0)) / maxf(1.0, float(c.get("days", 8.0))))]
	lbl.position = Vector3(0, 2.4, 0)
	node.add_child(lbl)
	var center_terrain := world.terrain_y(s.center.x, s.center.y)
	var bx := float(c.get("x", s.center.x))
	var bz := float(c.get("z", s.center.y))
	node.position = Vector3((bx - s.center.x) * WorldModel.CELL, world.terrain_y(bx, bz) - center_terrain + 0.1, (bz - s.center.y) * WorldModel.CELL)
	data.root.add_child(node)
	data.construction = node


func _get_building_mesh(type: String) -> ArrayMesh:
	if building_cache.has(type):
		return building_cache[type]
	var data: Dictionary = D.building(type)
	if data.is_empty():
		return null
	var mesh := MeshKit.building_mesh(type, data)
	building_cache[type] = mesh
	return mesh


func _territory_points(s: SettlementData) -> Array:
	var seg := 18
	var r := s.territory_radius
	var pts: Array = []
	for i in seg:
		var ang := TAU * i / seg
		var dir := Vector2(cos(ang), sin(ang))
		var rr := r * (0.88 + 0.18 * absf(sin(float(s.id) * 3.7 + i * 1.9)))
		# граница тянется к соседу, но не заходит на его землю
		for o in sim.settlements:
			if o.id == s.id or o.destroyed:
				continue
			var to := Vector2(o.center) - Vector2(s.center)
			var dist := to.length()
			if dist < 1.0 or dist > r * 2.2:
				continue
			var dot := dir.dot(to.normalized())
			if dot > 0.55:
				rr = minf(rr, dist * 0.48 + 1.0)
		pts.append(dir * rr)
	return pts


func _territory_mesh(s: SettlementData) -> ArrayMesh:
	var pts := _territory_points(s)
	var center_y := world.terrain_y(s.center.x, s.center.y)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var base := Color(s.color.r, s.color.g, s.color.b, 0.10)
	if not s.wars.is_empty():
		base = Color(0.95, 0.28, 0.2, 0.16)
	if s.destroyed:
		base = Color(0.3, 0.28, 0.26, 0.07)
	if s.id == selected_id:
		base = base.lightened(0.25)
		base.a = 0.30
	var vc := 0
	var n := pts.size()
	for i in n:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % n]
		var q0 := p0 * 0.975
		var q1 := p1 * 0.975
		for d in [q0, p0, p1, q1]:
			var dv: Vector2 = d
			var wx: float = s.center.x + dv.x
			var wz: float = s.center.y + dv.y
			var y: float = world.terrain_y(wx, wz) - center_y
			verts.append(Vector3(dv.x * WorldModel.CELL, y + 0.12, dv.y * WorldModel.CELL))
			cols.append(base)
		idxs.append(vc); idxs.append(vc + 1); idxs.append(vc + 2)
		idxs.append(vc); idxs.append(vc + 2); idxs.append(vc + 3)
		vc += 4
	if s.id == selected_id:
		var gold := Color(1.0, 0.82, 0.38, 0.78)
		for i in n:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % n]
			var q0 := p0 * 1.015
			var q1 := p1 * 1.015
			var q2 := p1 * 1.05
			var q3 := p0 * 1.05
			for d2 in [q0, q1, q2, q3]:
				var dv2: Vector2 = d2
				var wx: float = s.center.x + dv2.x
				var wz: float = s.center.y + dv2.y
				var yy: float = world.terrain_y(wx, wz) - center_y
				verts.append(Vector3(dv2.x * WorldModel.CELL, yy + 0.16, dv2.y * WorldModel.CELL))
				cols.append(gold)
			idxs.append(vc); idxs.append(vc + 2); idxs.append(vc + 1)
			idxs.append(vc); idxs.append(vc + 3); idxs.append(vc + 2)
			vc += 4
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _signature(s: SettlementData) -> String:
	var ctype := ""
	if not s.construction.is_empty():
		ctype = str(s.construction.get("type", ""))
	return "%d|%s|%s|%s|%s|%d" % [s.buildings.size(), s.stage, str(s.destroyed), str(s.wars.size()), ctype, s.id]


func _process(delta: float) -> void:
	timer -= delta
	if timer > 0.0:
		return
	timer = 0.45
	var label_slots: Array = []
	var ordered: Array = []
	for s in sim.settlements:
		if not nodes.has(s.id):
			_ensure_node(s)
		ordered.append(s)
	ordered.sort_custom(func(a, b):
		if a.id == selected_id: return true
		if b.id == selected_id: return false
		return a.population > b.population
	)
	for s in ordered:
		var data: Dictionary = nodes[s.id]
		var sig := _signature(s)
		if sig != data.signature:
			_rebuild_settlement(s, data)
		var lbl: Label3D = data.label
		if lbl != null:
			if s.destroyed:
				lbl.text = s.name + " · " + L.t("stage_ruins")
			else:
				var war_mark := " ⚔" if not s.wars.is_empty() else ""
				lbl.text = "%s%s · %s" % [s.name, war_mark, L.num(s.population)]
				var faith_col := sim.religion_color(s.religion).lerp(Color.WHITE, 0.55)
				lbl.modulate = Color(1, 0.88, 0.7) if not s.wars.is_empty() else (Color(1, 0.9, 0.5) if s.id == selected_id else faith_col)
			# декластеризация подписей
			var wp: Vector3 = data.root.global_position + Vector3(0, 6.0, 0)
			if camera_rig != null and camera_rig.camera != null:
				if camera_rig.camera.is_position_behind(wp):
					lbl.visible = false
				else:
					var sp := camera_rig.camera.unproject_position(wp)
					var vs := get_viewport().get_visible_rect().size
					var blocked := sp.x < 12 or sp.x > vs.x - 370 or sp.y < 92 or sp.y > vs.y - 195
					for q in label_slots:
						if sp.distance_to(q) < 190.0:
							blocked = true
							break
					if s.id == selected_id:
						blocked = false
					lbl.visible = not blocked
					if not blocked:
						label_slots.append(sp)
			else:
				lbl.visible = true
		# мигание огня
		for l in data.lights:
			if is_instance_valid(l):
				l.light_energy = 1.9 + sin(Time.get_ticks_msec() * 0.008 + s.id) * 0.35
		if data.construction != null and is_instance_valid(data.construction):
			data.construction.visible = camera_rig == null or camera_rig.distance < 130.0
			for ch in data.construction.get_children():
				if ch is Label3D and not s.construction.is_empty():
					var c: Dictionary = s.construction
					ch.text = "%s %d%%" % [L.tc(D.building(str(c.get("type", "hut")))), int(100.0 * float(c.get("progress", 0.0)) / maxf(1.0, float(c.get("days", 8.0))))]
				elif ch is Label3D:
					ch.text = ""
		# пламя
		for c in data.buildings.get_children():
			if c is MeshInstance3D and c.name == "Flame":
				var k := 0.75 + sin(Time.get_ticks_msec() * 0.012 + s.id) * 0.18
				c.scale = Vector3(k, 0.9 + k * 0.25, k)
	_rebuild_roads()


func _rebuild_roads() -> void:
	var tr0 := Time.get_ticks_usec()
	var sig := ""
	for s in sim.settlements:
		if s.destroyed:
			continue
		for oid in s.roads:
			var r: Dictionary = s.roads[oid]
			sig += "%d:%d:%.2f:%d:%s;" % [s.id, int(oid), float(r.get("progress", 0.0)), int(r.get("segments", []).size()), str(bool(r.get("paved", false)))]
	if sig == road_sig:
		last_roads_us = Time.get_ticks_usec() - tr0
		return
	road_sig = sig
	for c in road_root.get_children():
		c.queue_free()
	var dirt: Array = []
	var paved: Array = []
	for s in sim.settlements:
		if s.destroyed:
			continue
		for oid in s.roads:
			var r: Dictionary = s.roads[oid]
			var segs: Array = r.get("segments", [])
			var is_paved := bool(r.get("paved", false))
			for i in segs.size():
				var seg: Array = segs[i]
				var x := float(seg[0])
				var z := float(seg[1])
				var dir := Vector2(1, 0)
				var j := mini(i + 1, segs.size() - 1)
				var nxt: Array = segs[j]
				var dd := Vector2(float(nxt[0]) - x, float(nxt[1]) - z)
				if dd.length() > 0.01:
					dir = dd.normalized()
				var item := [x, z, atan2(dir.x, dir.y)]
				if is_paved:
					paved.append(item)
				else:
					dirt.append(item)
	var half := world.size * 0.5
	if not dirt.is_empty():
		_spawn_road_mm(dirt, road_mat, "RoadDirt", half)
	if not paved.is_empty():
		_spawn_road_mm(paved, road_paved_mat, "RoadPaved", half)
	last_roads_us = Time.get_ticks_usec() - tr0


func _spawn_road_mm(items: Array, mat: Material, node_name: String, half: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = road_mesh
	mm.instance_count = items.size()
	for i in items.size():
		var tr: Array = items[i]
		var x := float(tr[0])
		var z := float(tr[1])
		var wy := world.terrain_y(x, z) + 0.10
		var basis := Basis(Vector3.UP, float(tr[2]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3((x - half) * WorldModel.CELL, wy, (z - half) * WorldModel.CELL)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	road_root.add_child(mmi)


func select(id: int) -> void:
	selected_id = id
	for sid in nodes:
		var s: SettlementData = sim.settlement_by_id.get(sid, null)
		if s != null:
			_rebuild_settlement(s, nodes[sid])


func focus_position(id: int) -> Vector3:
	var s: SettlementData = sim.settlement_by_id.get(id, null)
	if s == null:
		return Vector3.ZERO
	var half := world.size * 0.5
	return Vector3((s.center.x - half) * WorldModel.CELL, 0, (s.center.y - half) * WorldModel.CELL)
