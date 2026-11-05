class_name FXView
extends Node3D
## Визуальные эффекты: молнии, взрывы, метеориты, ядерный гриб, смерч,
## огонь, благословения, курсор кисти.

signal screen_flash(color: Color, alpha: float)
signal screen_shake(amount: float, duration: float)

var world: WorldModel
var sim: SimWorld
var camera_rig: CameraRig
var tornadoes: Array = []
var hit_cooldown := 0.0
var fire_mm: MultiMeshInstance3D
var fire_timer := 0.0
var brush_ring: MeshInstance3D
var brush_mat: StandardMaterial3D
var brush_visible := false
var brush_radius := 5.0
var brush_color := Color("#e8c07a")


func setup(p_world: WorldModel, p_sim: SimWorld, p_camera: CameraRig) -> void:
	world = p_world
	sim = p_sim
	camera_rig = p_camera
	sim.effect.connect(play)
	_build_fire_view()
	_build_brush()


func play(kind: String, pos: Vector2, radius: float, data: Dictionary) -> void:
	if sim != null and sim.bulk_mode:
		return
	if DisplayServer.get_name() == "headless":
		return
	var wp := _world_pos(pos)
	match kind:
		"lightning":
			_lightning(wp)
			SFX.play("thunder", -2.0, randf_range(0.9, 1.08))
			screen_flash.emit(Color(0.75, 0.85, 1.0), 0.35)
			screen_shake.emit(0.8, 0.35)
		"meteor":
			_meteor(wp, radius)
		"bomb":
			_explosion(wp, radius, Color(1.0, 0.5, 0.1))
			screen_flash.emit(Color(1.0, 0.75, 0.35), 0.35)
			screen_shake.emit(1.2, 0.6)
			SFX.play("explosion", -1.0, 1.1)
		"nuke":
			_nuke_fx(wp, radius)
		"quake":
			_burst(wp + Vector3(0, 1, 0), Color(0.55, 0.48, 0.38, 0.7), 160, 4.0, 16.0, 3.0, -2.0, true)
			screen_shake.emit(2.2, 2.0)
			SFX.play("quake", -2.0)
		"hit", "battle":
			if hit_cooldown <= 0.0:
				hit_cooldown = 0.08
				_burst(wp + Vector3(0, 1.2, 0), Color(1.0, 0.55, 0.2, 0.9), 8, 0.45, 5.0, 0.18, -4.0, true)
		"fire":
			_burst(wp + Vector3(0, 1, 0), Color(1.0, 0.45, 0.1, 0.9), 70, 2.5, 5.0, 1.1, 2.0, true)
			SFX.play("fire", -8.0)
		"plague":
			_burst(wp + Vector3(0, 4, 0), Color(0.4, 0.9, 0.35, 0.35), 110, 6.0, 4.0, 3.0, -0.2, true)
			SFX.play("curse", -6.0, 0.8)
		"bless", "miracle", "prophet", "tech", "crown", "festival":
			_pillar(wp, Color(1.0, 0.86, 0.45), 2.0)
			_burst(wp + Vector3(0, 2, 0), Color(1.0, 0.9, 0.55, 1.0), 70, 3.0, 8.0, 0.5, 0.4, true)
			SFX.play("bless", -4.0)
		"curse":
			_burst(wp + Vector3(0, 3, 0), Color(0.55, 0.2, 0.7, 0.7), 90, 4.0, 6.0, 1.5, -0.5, true)
			SFX.play("curse", -4.0)
		"war_horn":
			SFX.play("horn", -5.0)
			screen_shake.emit(0.35, 0.5)
		"animal_spawn":
			_burst(wp + Vector3(0, 0.8, 0), Color(0.8, 0.95, 0.7, 0.6), 18, 1.0, 3.0, 0.25, -2.0, true)
		"spawn_tribe":
			_pillar(wp, Color(0.85, 1.0, 0.7), 2.5)
		"rain":
			SFX.play("brush", -12.0, 0.7)
		"acid_rain":
			screen_flash.emit(Color(0.5, 0.9, 0.3), 0.18)
			_burst(wp + Vector3(0, 10, 0), Color(0.5, 0.95, 0.3, 0.5), 120, 3.0, 3.0, 1.4, -6.0, true)
			SFX.play("curse", -8.0, 1.2)
		"drought":
			_burst(wp + Vector3(0, 4, 0), Color(0.75, 0.6, 0.35, 0.4), 80, 5.0, 4.0, 2.0, -0.5, true)
		"blizzard":
			_burst(wp + Vector3(0, 10, 0), Color(1, 1, 1, 0.8), 160, 4.0, 4.0, 1.2, -3.0, true)
			screen_flash.emit(Color(0.8, 0.9, 1.0), 0.12)
		"flood":
			_burst(wp + Vector3(0, 1, 0), Color(0.4, 0.8, 1.0, 0.55), 100, 3.0, 6.0, 2.0, -1.0, true)
		"volcano":
			_burst(wp + Vector3(0, 2, 0), Color(1.0, 0.35, 0.05, 0.95), 180, 5.0, 14.0, 2.0, 3.0, true)
			_burst(wp + Vector3(0, 12, 0), Color(0.25, 0.22, 0.2, 0.6), 140, 8.0, 6.0, 4.0, 1.0, true)
			screen_flash.emit(Color(1.0, 0.4, 0.1), 0.22)
			SFX.play("explosion", -2.0, 0.7)
		"tornado":
			_start_tornado(wp)
			SFX.play("horn", -10.0, 0.6)
		"hunt":
			_burst(wp + Vector3(0, 0.8, 0), Color(0.75, 0.15, 0.1, 0.8), 6, 0.4, 4.0, 0.15, -4.0, true)


func _process(delta: float) -> void:
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = 0.7
		_refresh_fire()
	_update_tornadoes(delta)
	if brush_ring != null and brush_visible:
		var cb := brush_ring.material_override as StandardMaterial3D
		if cb != null:
			cb.albedo_color = brush_color
			cb.emission = brush_color


func _world_pos(p: Vector2) -> Vector3:
	var half := world.size * 0.5
	return Vector3((p.x - half) * WorldModel.CELL, world.terrain_y(p.x, p.y), (p.y - half) * WorldModel.CELL)


# ------------------------------------------------------------------ brush cursor

func _build_brush() -> void:
	brush_ring = MeshInstance3D.new()
	brush_ring.mesh = MeshKit.ring_mesh(0.90, 1.0, 64, Color.WHITE)
	brush_mat = StandardMaterial3D.new()
	brush_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brush_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	brush_mat.vertex_color_use_as_albedo = true
	brush_mat.albedo_color = brush_color
	brush_mat.emission_enabled = true
	brush_mat.emission = brush_color
	brush_mat.emission_energy_multiplier = 2.5
	brush_mat.no_depth_test = true
	brush_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	brush_ring.material_override = brush_mat
	brush_ring.visible = false
	add_child(brush_ring)


func update_brush(cell: Vector2i, radius: float, color: Color, visible_now: bool) -> void:
	brush_visible = visible_now
	brush_radius = radius
	brush_color = color
	brush_ring.visible = visible_now
	if not visible_now:
		return
	var wp := _world_pos(Vector2(cell))
	wp.y = world.terrain_y(cell.x, cell.y) + 0.35
	brush_ring.position = wp
	brush_ring.scale = Vector3(radius, 1.0, radius)


# ------------------------------------------------------------------ lightning

func _lightning(wp: Vector3) -> void:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.92, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.75, 1.0)
	mat.emission_energy_multiplier = 8.0
	mat.no_depth_test = true
	var top := wp + Vector3(randf_range(-14, 14), 95, randf_range(-14, 14))
	var pts: Array = []
	pts.append(top)
	var n := 7
	for i in range(1, n):
		var t := float(i) / n
		var p := top.lerp(wp, t) + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7))
		pts.append(p)
	pts.append(wp + Vector3(0, 0.4, 0))
	for i in pts.size() - 1:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		MeshKit.cylinder_between(st, pts[i], pts[i + 1], 0.28, Color.WHITE, 4)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 10.0
	light.omni_range = 60.0
	light.position = wp + Vector3(0, 10, 0)
	light.shadow_enabled = false
	root.add_child(light)
	add_child(root)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	tw.tween_callback(root.queue_free)


# ------------------------------------------------------------------ explosions

func _meteor(wp: Vector3, radius: float) -> void:
	var start := wp + Vector3(-55, 170, -40)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 6.0
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 7.0
	ball.material_override = mat
	ball.position = start
	add_child(ball)
	var trail := _burst_node(ball, Color(1.0, 0.55, 0.15, 0.9), 90, 1.2, 4.0, 1.2, 0.5, false)
	trail.emitting = true
	var tw := create_tween()
	tw.tween_property(ball, "position", wp + Vector3(0, 2, 0), 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		ball.queue_free()
		trail.queue_free()
		_explosion(wp, radius, Color(1.0, 0.4, 0.08))
		screen_flash.emit(Color(1.0, 0.7, 0.3), 0.55)
		screen_shake.emit(2.0, 0.9)
		SFX.play("explosion", 0.0, 0.8)
	)


func _explosion(wp: Vector3, radius: float, color: Color) -> void:
	_burst(wp + Vector3(0, 2, 0), Color(color.r, color.g, color.b, 0.95), 180, 3.5, 22.0, 2.0, -2.0, true)
	_burst(wp + Vector3(0, 3, 0), Color(0.16, 0.14, 0.12, 0.55), 120, 6.0, 10.0, 4.0, 0.5, true)
	_shockwave(wp, radius, color)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 12.0
	light.omni_range = radius * 6.0 + 20.0
	light.position = wp + Vector3(0, 8, 0)
	add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.8)
	tw.tween_callback(light.queue_free)


func _shockwave(wp: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.ring_mesh(0.86, 1.0, 64, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = wp + Vector3(0, 0.4, 0)
	mi.scale = Vector3(1, 1, 1)
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius * 4.0, 1, radius * 4.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(mi.queue_free)


func _nuke_fx(wp: Vector3, radius: float) -> void:
	screen_flash.emit(Color(1, 1, 1), 0.92)
	screen_shake.emit(3.2, 2.5)
	SFX.play("nuke", 0.0)
	_explosion(wp, radius * 1.4, Color(1.0, 0.65, 0.2))
	_shockwave(wp, radius * 2.0, Color(1.0, 0.8, 0.4))
	# воронка
	var crater := MeshInstance3D.new()
	crater.mesh = MeshKit.ring_mesh(0.2, 1.0, 48, Color.WHITE)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.vertex_color_use_as_albedo = true
	cmat.albedo_color = Color(0.05, 0.04, 0.035, 0.85)
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	crater.material_override = cmat
	crater.position = wp + Vector3(0, 0.35, 0)
	crater.scale = Vector3(radius * 2.2, 1, radius * 2.2)
	add_child(crater)
	var ctw := create_tween()
	ctw.tween_interval(24.0)
	ctw.tween_property(cmat, "albedo_color:a", 0.0, 5.0)
	ctw.tween_callback(crater.queue_free)
	# ножка гриба
	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.bottom_radius = radius * 0.5
	sm.top_radius = radius * 0.8
	sm.height = 36.0
	sm.radial_segments = 16
	sm.rings = 1
	stem.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.28, 0.24, 0.21, 0.22)
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	stem.material_override = smat
	stem.position = wp + Vector3(0, 18, 0)
	add_child(stem)
	var stw := create_tween()
	stw.set_parallel(true)
	stw.tween_property(stem, "scale", Vector3(1.0, 1.0, 1.0), 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	stw.tween_interval(5.0)
	stw.chain().tween_property(smat, "albedo_color:a", 0.0, 5.0)
	stw.chain().tween_callback(stem.queue_free)
	# шляпка
	var capm := MeshInstance3D.new()
	var capmesh := SphereMesh.new()
	capmesh.radius = 1.0
	capmesh.height = 1.0
	capmesh.radial_segments = 16
	capmesh.rings = 6
	capm.mesh = capmesh
	var capmat := StandardMaterial3D.new()
	capmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	capmat.albedo_color = Color(0.25, 0.21, 0.18, 0.34)
	capmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	capm.material_override = capmat
	capm.position = wp + Vector3(0, 37, 0)
	capm.scale = Vector3(radius * 0.35, radius * 0.12, radius * 0.35)
	add_child(capm)
	var captw := create_tween()
	captw.set_parallel(true)
	captw.tween_property(capm, "scale", Vector3(radius * 2.4, radius * 0.72, radius * 2.4), 5.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	captw.tween_interval(9.0)
	captw.chain().tween_property(capmat, "albedo_color:a", 0.0, 5.0)
	captw.chain().tween_callback(capm.queue_free)
	# частицы
	var cap_parts := _burst_static(wp + Vector3(0, 38, 0), Color(0.32, 0.28, 0.24, 0.55), 140, 14.0, 7.0, 12.0, 0.4)
	var stem_parts := _burst_static(wp + Vector3(0, 4, 0), Color(0.36, 0.3, 0.25, 0.55), 150, 11.0, 8.0, 4.0, 1.8)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 22.0
	light.omni_range = 140.0
	light.position = wp + Vector3(0, 20, 0)
	add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 2.8)
	tw.tween_callback(light.queue_free)
	# долгий столб дыма
	var timer := get_tree().create_timer(15.0)
	timer.timeout.connect(func():
		if is_instance_valid(cap_parts): cap_parts.queue_free()
		if is_instance_valid(stem_parts): stem_parts.queue_free()
	)


func _burst_static(pos: Vector3, color: Color, amount: int, life: float, speed: float, size: float, up: float) -> GPUParticles3D:
	var p := _burst_node(null, color, amount, life, speed, size, up, false)
	p.position = pos
	p.emitting = true
	var timer := get_tree().create_timer(life + 1.0)
	timer.timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	return p


func _burst(pos: Vector3, color: Color, amount: int, life: float, speed: float, size: float, up: float, one: bool) -> GPUParticles3D:
	var p := _burst_node(null, color, amount, life, speed, size, up, one)
	p.position = pos
	p.emitting = true
	var timer := get_tree().create_timer(life + 1.5)
	timer.timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	return p


func _burst_node(parent: Node = null, color: Color = Color.WHITE, amount: int = 50, life: float = 1.0, speed: float = 5.0, size: float = 1.0, up: float = -9.8, one: bool = true) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one
	p.explosiveness = 1.0 if one else 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.5 if one else 4.0
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.2
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, up, 0)
	pm.damping_min = speed * 0.25
	pm.damping_max = speed * 0.6
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.5
	pm.color = color
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.material = mat
	p.draw_pass_1 = sm
	(parent if parent != null else self).add_child(p)
	return p


func _pillar(wp: Vector3, color: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.bottom_radius = radius
	sm.top_radius = radius * 0.3
	sm.height = 40.0
	sm.radial_segments = 12
	sm.rings = 1
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.28)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = wp + Vector3(0, 20, 0)
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.5)
	tw.tween_property(mi, "scale", Vector3(1.4, 1.1, 1.4), 2.5)
	tw.chain().tween_callback(mi.queue_free)


# ------------------------------------------------------------------ tornado

func _start_tornado(wp: Vector3) -> void:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.42, 0.4, 0.38, 0.24)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = 3.4 - i * 0.35
		cm.top_radius = 2.0 + i * 1.2
		cm.height = 10.0
		cm.radial_segments = 16
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		mi.position.y = 5.0 + i * 7.0
		root.add_child(mi)
	root.position = wp + Vector3(0, 0, 0)
	add_child(root)
	var dust := _burst_node(root, Color(0.55, 0.48, 0.38, 0.5), 140, 3.0, 8.0, 2.0, -1.0, false)
	dust.position = Vector3(0, 2, 0)
	dust.emitting = true
	var wc := world.world_to_cell(wp)
	var tor := {"node": root, "cell": Vector2(wc.x, wc.y), "dir": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized(), "life": 18.0, "dmg": 0.0, "dust": dust}
	tornadoes.append(tor)


func _update_tornadoes(delta: float) -> void:
	for i in range(tornadoes.size() - 1, -1, -1):
		var t: Dictionary = tornadoes[i]
		t.life -= delta
		var node: Node3D = t.node
		if not is_instance_valid(node) or t.life <= 0.0:
			if is_instance_valid(node):
				var tw := create_tween()
				tw.tween_property(node, "scale", Vector3(0.1, 1.5, 0.1), 0.8)
				tw.tween_callback(node.queue_free)
			tornadoes.remove_at(i)
			continue
		node.rotation.y += delta * 3.0
		var cell: Vector2 = t.cell + t.dir * delta * 1.1
		if cell.x < 3 or cell.y < 3 or cell.x > world.size - 3 or cell.y > world.size - 3:
			t.dir = -t.dir
		t.cell = cell
		var wp := _world_pos(cell)
		node.position = wp
		t.dmg -= delta
		if t.dmg <= 0.0:
			t.dmg = 0.28
			sim.tornado_strike(int(cell.x), int(cell.y), 4.0)
			_burst(wp + Vector3(0, 2, 0), Color(0.55, 0.5, 0.42, 0.5), 18, 1.2, 7.0, 1.0, -1.0, false)


# ------------------------------------------------------------------ fire

func _build_fire_view() -> void:
	fire_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 0
	fire_mm.multimesh = mm
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	MeshKit.cone(st, Vector3(0, 0, 0), 0.55, 1.7, Color.WHITE, 5)
	MeshKit.cone(st, Vector3(0.2, 0, 0.15), 0.3, 1.0, Color.WHITE, 4)
	fire_mm.multimesh.mesh = MeshKit.commit(st)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.12)
	mat.emission_energy_multiplier = 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fire_mm.material_override = mat
	fire_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire_mm)


func _refresh_fire() -> void:
	if sim == null or sim.burning.is_empty():
		fire_mm.multimesh.instance_count = 0
		return
	var keys := sim.burning.keys()
	var count := mini(keys.size(), 120)
	fire_mm.multimesh.instance_count = count
	var half := world.size * 0.5
	for i in count:
		var k: int = keys[i]
		var x := k % world.size
		var z := int(k / world.size)
		var wp := Vector3((x - half) * WorldModel.CELL, world.terrain_y(x, z) + 0.4, (z - half) * WorldModel.CELL)
		var sc := 0.42 + float((x * 7 + z * 13) % 10) * 0.035
		var b := Basis(Vector3.UP, float(k) * 0.37).scaled(Vector3(sc, sc * 1.6, sc))
		fire_mm.multimesh.set_instance_transform(i, Transform3D(b, wp))
		var c := Color(1.0, 0.55, 0.1, 1.0).lerp(Color(1.0, 0.9, 0.35), float((x + z) % 5) * 0.2)
		fire_mm.multimesh.set_instance_color(i, c)
