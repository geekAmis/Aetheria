class_name CreatureView
extends Node3D
## Отображение существ и животных через MultiMesh + маркер выбора.

var world: WorldModel
var sim: SimWorld
var agent_mm: MultiMeshInstance3D
var animal_mm: MultiMeshInstance3D
var agent_index: Dictionary = {}
var animal_index: Dictionary = {}
var slots_dirty := true
var selected_id: int = -1
var ring: MeshInstance3D
var label: Label3D
var ring_mat: StandardMaterial3D
var pulse := 0.0
var label_timer := 0.0


func setup(p_world: WorldModel, p_sim: SimWorld) -> void:
	world = p_world
	sim = p_sim
	var person := MeshKit.person_mesh()
	agent_mm = MultiMeshInstance3D.new()
	agent_mm.name = "Agents"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	agent_mm.multimesh = mm
	agent_mm.material_override = MeshKit.vertex_material()
	agent_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(agent_mm)
	agent_mm.multimesh.mesh = person

	var an_mesh := MeshKit.animal_mesh()
	animal_mm = MultiMeshInstance3D.new()
	animal_mm.name = "Animals"
	var amm := MultiMesh.new()
	amm.transform_format = MultiMesh.TRANSFORM_3D
	amm.use_colors = true
	amm.instance_count = 0
	animal_mm.multimesh = amm
	animal_mm.material_override = MeshKit.vertex_material()
	animal_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(animal_mm)
	animal_mm.multimesh.mesh = an_mesh

	# маркер выбора
	ring = MeshInstance3D.new()
	ring.mesh = MeshKit.ring_mesh(2.2, 3.0, 32, Color(1, 0.85, 0.4, 0.9))
	ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.vertex_color_use_as_albedo = true
	ring_mat.albedo_color = Color(1, 0.82, 0.35, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1, 0.7, 0.2)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.no_depth_test = true
	ring.material_override = ring_mat
	ring.visible = false
	add_child(ring)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 20
	label.outline_size = 10
	label.outline_modulate = Color(0.03, 0.04, 0.06, 0.9)
	label.modulate = Color(1, 0.95, 0.85)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	add_child(label)

	sim.agent_spawned.connect(func(_a): slots_dirty = true)
	sim.agent_died.connect(func(_a, _c): slots_dirty = true)
	sim.effect.connect(_on_effect)
	rebuild_slots()


func _process(delta: float) -> void:
	if sim == null:
		return
	if slots_dirty:
		rebuild_slots()
	_sync_agents()
	_sync_animals()
	_update_selection(delta)


func rebuild_slots() -> void:
	slots_dirty = false
	agent_index.clear()
	var mm := agent_mm.multimesh
	mm.instance_count = sim.agents.size()
	for i in sim.agents.size():
		var a: AgentData = sim.agents[i]
		agent_index[a.id] = i
		var col := _agent_color(a)
		mm.set_instance_color(i, col)
	animal_index.clear()
	var amm := animal_mm.multimesh
	amm.instance_count = sim.animals.size()
	for i in sim.animals.size():
		var an: Dictionary = sim.animals[i]
		animal_index[int(an.id)] = i
		var sp: Dictionary = D.animal(str(an.species))
		amm.set_instance_color(i, sp.get("color_c", Color.WHITE))


func _agent_color(a: AgentData) -> Color:
	var base: Color = D.race(a.race_id).get("color_c", Color.WHITE)
	if a.role == "leader":
		base = base.lerp(Color("#ffd87a"), 0.45)
	elif a.role == "warrior":
		base = base.darkened(0.12)
	if a.age < a.maturity():
		base = base.lightened(0.18)
	elif a.age > a.lifespan() * 0.78:
		base = base.darkened(0.08)
	return base


func _sync_agents() -> void:
	if sim.agents.is_empty():
		return
	var mm := agent_mm.multimesh
	if mm.instance_count != sim.agents.size():
		slots_dirty = true
		return
	var half := world.size * 0.5
	for i in sim.agents.size():
		var a: AgentData = sim.agents[i]
		var p := a.pos
		var wp := Vector3((p.x - half) * WorldModel.CELL, 0, (p.y - half) * WorldModel.CELL)
		var wx := world.world_to_cell(wp)
		wp.y = world.terrain_y(wx.x, wx.y) + 0.05
		if world.is_water_cell(clampi(int(p.x), 0, world.size - 1), clampi(int(p.y), 0, world.size - 1)):
			wp.y = world.water_surface_y(int(p.x), int(p.y)) - 0.4
		var ang := 0.0
		var d := a.target - a.pos
		if d.length() > 0.25:
			ang = atan2(d.x, d.y)
		var sc := 1.55
		if a.age < a.maturity(): sc = 1.05
		elif a.age > a.lifespan() * 0.8: sc = 1.35
		if sim.weather_mode == "rain" or sim.weather_mode == "snow":
			sc *= 0.98
		var basis := Basis(Vector3.UP, ang).scaled(Vector3(sc, sc, sc))
		mm.set_instance_transform(i, Transform3D(basis, wp))


func _sync_animals() -> void:
	if sim.animals.is_empty():
		return
	var mm := animal_mm.multimesh
	if mm.instance_count != sim.animals.size():
		slots_dirty = true
		return
	var half := world.size * 0.5
	for i in sim.animals.size():
		var an: Dictionary = sim.animals[i]
		var p: Vector2 = an.pos
		var sp: Dictionary = D.animal(str(an.species))
		var wp := Vector3((p.x - half) * WorldModel.CELL, 0, (p.y - half) * WorldModel.CELL)
		var wx := world.world_to_cell(wp)
		wp.y = world.terrain_y(wx.x, wx.y) + 0.05
		if world.is_water_cell(clampi(int(p.x), 0, world.size - 1), clampi(int(p.y), 0, world.size - 1)):
			wp.y = world.water_surface_y(int(p.x), int(p.y)) - 0.2
		var d: Vector2 = an.target - p
		var ang := atan2(d.x, d.y) - PI * 0.5
		if d.length() < 0.1:
			ang = float(an.age) * 3.0
		var size := float(sp.get("size", 0.7))
		var sc := (0.7 + size * 0.55) * 1.35
		var basis := Basis(Vector3.UP, ang).scaled(Vector3(sc, sc, sc))
		mm.set_instance_transform(i, Transform3D(basis, wp))


func _update_selection(delta: float) -> void:
	pulse += delta
	if selected_id < 0:
		ring.visible = false
		label.visible = false
		return
	var a: AgentData = sim.agent_by_id.get(selected_id, null)
	if a == null or not a.alive:
		selected_id = -1
		ring.visible = false
		label.visible = false
		return
	var half := world.size * 0.5
	var wx := (a.pos.x - half) * WorldModel.CELL
	var wz := (a.pos.y - half) * WorldModel.CELL
	var wy := world.terrain_y(a.pos.x, a.pos.y) + 0.12
	ring.position = Vector3(wx, wy, wz)
	ring.scale = Vector3.ONE * (1.0 + sin(pulse * 3.0) * 0.08)
	ring.visible = true
	label.position = Vector3(wx, wy + 4.2, wz)
	label.visible = true
	label_timer -= delta
	if label_timer <= 0.0:
		label_timer = 0.25
		var hp := int(round(a.health / a.max_health * 100.0))
		label.text = "%s\n%s · HP %d%%" % [a.display_name(), L.t("role_" + a.role), hp]


func set_selected(id: int) -> void:
	selected_id = id
	label_timer = 0.0


func _on_effect(kind: String, pos: Vector2, _radius: float, _data: Dictionary) -> void:
	if kind in ["hit", "battle"]:
		slots_dirty = false  # смерть сама обновит


func agent_screen_position(a: AgentData) -> Vector3:
	var half := world.size * 0.5
	return Vector3((a.pos.x - half) * WorldModel.CELL, world.terrain_y(a.pos.x, a.pos.y) + 2.0, (a.pos.y - half) * WorldModel.CELL)
