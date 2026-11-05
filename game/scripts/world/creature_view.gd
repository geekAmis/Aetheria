class_name CreatureView
extends Node3D
## Отображение существ и животных через MultiMesh + маркер выбора.
## 8 визуальных вариантов, эмоции над головой, переносимые предметы и
## примитивная анимация действия (ходьба, работа, сон, охота).

const VARIANTS := 8

var world: WorldModel
var sim: SimWorld
var agent_mms: Array = []              # 8 MultiMeshInstance3D
var agent_slot: Dictionary = {}        # id -> [variant, instance]
var agent_colors: Dictionary = {}      # id -> Color
var animal_mm: MultiMeshInstance3D
var animal_index: Dictionary = {}
var emotion_mm: MultiMeshInstance3D
var emotion_slot: Dictionary = {}
var carry_mm: MultiMeshInstance3D
var carry_slot: Dictionary = {}
var slots_dirty := true
var selected_id: int = -1
var ring: MeshInstance3D
var label: Label3D
var ring_mat: StandardMaterial3D
var pulse := 0.0
var anim_time := 0.0
var label_timer := 0.0

var emotion_colors := {
	"neutral": Color("#c8c8c8"),
	"happy": Color("#ffd86a"),
	"sad": Color("#6a9ad8"),
	"angry": Color("#e05545"),
	"afraid": Color("#a06ad8"),
	"hungry": Color("#e08a3a"),
	"proud": Color("#6ad8a0"),
	"grieving": Color("#8a8ad8")
}
var action_icons := {
	"hunt": Color("#d86a3a"), "haul": Color("#b08a4a"), "eat": Color("#e0b04a"),
	"drink": Color("#4aa8d8"), "sleep": Color("#7a7ad8"), "work": Color("#c8c8a0"),
	"build": Color("#e0c060"), "socialize": Color("#e08ac8"), "pray": Color("#c8a8e0"),
	"play": Color("#8ad8e0"), "flee": Color("#b06ad8")
}


func setup(p_world: WorldModel, p_sim: SimWorld) -> void:
	world = p_world
	sim = p_sim
	for v in VARIANTS:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Agents_%d" % v
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = 0
		mm.mesh = MeshKit.person_mesh_variant(v)
		mmi.multimesh = mm
		mmi.material_override = MeshKit.vertex_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		agent_mms.append(mmi)

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

	# эмоции над головой — маленькие цветные ромбы
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	emat.vertex_color_use_as_albedo = true
	emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emat.no_depth_test = true
	emat.cull_mode = BaseMaterial3D.CULL_DISABLED
	emotion_mm = MultiMeshInstance3D.new()
	emotion_mm.name = "Emotions"
	var emm := MultiMesh.new()
	emm.transform_format = MultiMesh.TRANSFORM_3D
	emm.use_colors = true
	emm.instance_count = 0
	emm.mesh = quad
	emotion_mm.multimesh = emm
	emotion_mm.material_override = emat
	emotion_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emotion_mm)

	# переносимые предметы
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.42, 0.42)
	carry_mm = MultiMeshInstance3D.new()
	carry_mm.name = "Carried"
	var cmm := MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.use_colors = true
	cmm.instance_count = 0
	cmm.mesh = box
	carry_mm.multimesh = cmm
	carry_mm.material_override = MeshKit.vertex_material()
	carry_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(carry_mm)

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
	anim_time += delta
	if slots_dirty:
		rebuild_slots()
	_sync_agents(delta)
	_sync_animals()
	_update_selection(delta)


func rebuild_slots() -> void:
	slots_dirty = false
	agent_slot.clear()
	agent_colors.clear()
	var counts := PackedInt32Array()
	counts.resize(VARIANTS)
	counts.fill(0)
	for av in sim.agents:
		var a: AgentData = av
		var v := clampi(int(a.appearance.get("variant", a.id % VARIANTS)), 0, VARIANTS - 1)
		counts[v] += 1
	for v in VARIANTS:
		agent_mms[v].multimesh.instance_count = counts[v]
	var used := PackedInt32Array()
	used.resize(VARIANTS)
	used.fill(0)
	for av in sim.agents:
		var a: AgentData = av
		var v := clampi(int(a.appearance.get("variant", a.id % VARIANTS)), 0, VARIANTS - 1)
		var idx := used[v]
		used[v] += 1
		agent_slot[a.id] = [v, idx]
		var col := _agent_color(a)
		agent_colors[a.id] = col
		agent_mms[v].multimesh.set_instance_color(idx, col)

	emotion_slot.clear()
	emotion_mm.multimesh.instance_count = sim.agents.size()
	carry_slot.clear()
	carry_mm.multimesh.instance_count = sim.agents.size()
	for i in sim.agents.size():
		var id: int = sim.agents[i].id
		emotion_slot[id] = i
		carry_slot[id] = i

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
	var app := a.appearance
	var hue := float(app.get("hue", 0.5))
	base = base.lerp(Color.from_hsv(hue, 0.35, 0.9), 0.22)
	if a.role == "leader":
		base = base.lerp(Color("#ffd87a"), 0.45)
	elif a.role == "warrior":
		base = base.darkened(0.12)
	elif a.role == "builder":
		base = base.lerp(Color("#d8b060"), 0.18)
	elif a.role == "hunter":
		base = base.lerp(Color("#6a8a4a"), 0.18)
	if a.age < a.maturity():
		base = base.lightened(0.18)
	elif a.age > a.lifespan() * 0.78:
		base = base.darkened(0.08)
	if a.immortal:
		base = base.lerp(Color("#9ad8ff"), 0.35)
	return base


func _sync_agents(delta: float) -> void:
	if sim.agents.is_empty():
		return
	var half := world.size * 0.5
	var t := anim_time
	for av in sim.agents:
		var a: AgentData = av
		var slot: Array = agent_slot.get(a.id, [])
		if slot.is_empty():
			slots_dirty = true
			return
		var p := a.pos
		var wp := Vector3((p.x - half) * WorldModel.CELL, 0, (p.y - half) * WorldModel.CELL)
		var wx := world.world_to_cell(wp)
		var ground := world.terrain_y(wx.x, wx.y) + 0.05
		if world.is_water_cell(clampi(int(p.x), 0, world.size - 1), clampi(int(p.y), 0, world.size - 1)):
			ground = world.water_surface_y(int(p.x), int(p.y)) - 0.4
		var ang := 0.0
		var d := a.target - a.pos
		var moving := d.length() > 0.3
		if moving:
			ang = atan2(d.x, d.y)
		var sc := 1.55
		if a.age < a.maturity(): sc = 1.05
		elif a.age > a.lifespan() * 0.8: sc = 1.35
		if a.immortal: sc *= 1.04
		var pitch := 0.0
		var y_off := 0.0
		var sx := sc
		var sy := sc
		var sz := sc
		if moving:
			y_off += absf(sin(t * 9.0 + float(a.id))) * 0.07
			pitch = sin(t * 9.0 + float(a.id)) * 0.06
		match a.action:
			"build":
				pitch = sin(t * 11.0 + float(a.id)) * 0.32
				y_off += absf(sin(t * 11.0 + float(a.id))) * 0.03
			"work":
				pitch = sin(t * 6.0 + float(a.id)) * 0.12
			"sleep":
				sy = sc * 0.55
				y_off -= 0.18
			"eat", "drink":
				pitch = sin(t * 13.0 + float(a.id)) * 0.18
			"hunt":
				sy = sc * 0.92
				pitch = -0.08
			"flee":
				y_off += absf(sin(t * 14.0 + float(a.id))) * 0.08
			"pray":
				pitch = -0.15
		var basis := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, pitch) * Basis.from_scale(Vector3(sx, sy, sz))
		var mm: MultiMesh = agent_mms[int(slot[0])].multimesh
		mm.set_instance_transform(int(slot[1]), Transform3D(basis, Vector3(wp.x, ground + y_off, wp.z)))
		_update_emotion_icon(a, wp, ground, t)
		_update_carry(a, wp, ground, ang, t)


func _update_emotion_icon(a: AgentData, wp: Vector3, ground: float, t: float) -> void:
	var idx: int = emotion_slot.get(a.id, -1)
	if idx < 0:
		return
	var mm: MultiMesh = emotion_mm.multimesh
	var e := a.emotion
	if e == "neutral" or a.emotion_timer <= 0.0:
		mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(wp.x, ground, wp.z)))
		return
	var col: Color = emotion_colors.get(e, Color.WHITE)
	var s := 1.0 + sin(t * 5.0 + float(a.id)) * 0.12
	var b := Basis(Vector3.UP, 0.0) * Basis.from_scale(Vector3(s, s, s))
	mm.set_instance_transform(idx, Transform3D(b, Vector3(wp.x, ground + 3.4, wp.z)))
	mm.set_instance_color(idx, col)


func _update_carry(a: AgentData, wp: Vector3, ground: float, ang: float, t: float) -> void:
	var idx: int = carry_slot.get(a.id, -1)
	if idx < 0:
		return
	var mm: MultiMesh = carry_mm.multimesh
	if a.carrying.is_empty():
		mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(wp.x, ground, wp.z)))
		return
	var off := Vector3(0, 1.15, -0.55).rotated(Vector3.UP, ang)
	var s := 0.8 + a.carry_amount * 0.35
	var col := Color("#a05a3a")
	match a.carrying:
		"wood":
			col = Color("#8a6a3a")
		"stone":
			col = Color("#9a9a9a")
		"food":
			col = Color("#d8b04a")
	var bob := absf(sin(t * 9.0 + float(a.id))) * 0.05
	mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(wp.x, ground + off.y + bob, wp.z) + Vector3(off.x, 0, off.z)))
	mm.set_instance_color(idx, col)


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
		var emo := ""
		if a.emotion != "neutral":
			emo = " · " + L.t("emotion_" + a.emotion) if L.t("emotion_" + a.emotion) != "emotion_" + a.emotion else " · " + a.emotion
		label.text = "%s\n%s · HP %d%%%s" % [a.display_name(), L.t("role_" + a.role), hp, emo]


func set_selected(id: int) -> void:
	selected_id = id
	label_timer = 0.0


func _on_effect(kind: String, pos: Vector2, _radius: float, _data: Dictionary) -> void:
	if kind in ["hit", "battle"]:
		slots_dirty = false  # смерть сама обновит


func agent_screen_position(a: AgentData) -> Vector3:
	var half := world.size * 0.5
	return Vector3((a.pos.x - half) * WorldModel.CELL, world.terrain_y(a.pos.x, a.pos.y) + 2.0, (a.pos.y - half) * WorldModel.CELL)
