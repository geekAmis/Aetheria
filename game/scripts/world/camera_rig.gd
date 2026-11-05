class_name CameraRig
extends Node3D
## Изометрическая камера: панорама, поворот, зум, наклон, тряска.

var camera: Camera3D
var world: WorldModel
var target: Vector3 = Vector3.ZERO
var smooth_target: Vector3 = Vector3.ZERO
var yaw: float = deg_to_rad(35.0)
var pitch: float = deg_to_rad(52.0)
var distance: float = 165.0
var smooth_distance: float = 165.0
var min_distance: float = 26.0
var max_distance: float = 420.0
var shake_amount: float = 0.0
var shake_time: float = 0.0
var follow_id: int = -1
var follow_node = null
var dragging := false
var drag_button: int = 0
var drag_last := Vector2.ZERO
var enabled := true
var last_mouse_cell := Vector2i(-1, -1)


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 46.0
	camera.near = 0.3
	camera.far = 1400.0
	add_child(camera)
	camera.current = true


func setup(p_world: WorldModel) -> void:
	world = p_world
	target = Vector3(0, 0, 0)
	smooth_target = target
	distance = clampf(p_world.size * 0.85, 120.0, 340.0)
	smooth_distance = distance
	yaw = deg_to_rad(32.0)
	pitch = deg_to_rad(52.0)
	_apply(0.0)


func focus_cell(cell: Vector2, p_distance: float = -1.0) -> void:
	if world == null:
		return
	target = world.world_pos(cell.x, cell.y)
	smooth_target = target
	if p_distance > 0.0:
		distance = p_distance
		smooth_distance = p_distance


func focus_settlement(cell: Vector2i) -> void:
	focus_cell(Vector2(cell), maxf(120.0, distance * 0.9))


func add_shake(amount: float, duration: float = 0.5) -> void:
	shake_amount = maxf(shake_amount, amount)
	shake_time = maxf(shake_time, duration)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance * 0.88, min_distance, max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance * 1.14, min_distance, max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			drag_button = MOUSE_BUTTON_MIDDLE
			drag_last = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			drag_button = MOUSE_BUTTON_RIGHT
			drag_last = event.position
	if event is InputEventMouseMotion and dragging:
		var d: Vector2 = event.relative
		if drag_button == MOUSE_BUTTON_MIDDLE:
			yaw -= d.x * 0.005
			pitch = clampf(pitch - d.y * 0.004, deg_to_rad(22.0), deg_to_rad(82.0))
			get_viewport().set_input_as_handled()
		else:
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var speed := distance * 0.0016
			target += (-right * d.x + fwd * d.y) * speed
			smooth_target = target
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world == null:
		return
	if enabled:
		var pan := Vector2.ZERO
		if Input.is_action_pressed("pan_forward"): pan.y += 1
		if Input.is_action_pressed("pan_back"): pan.y -= 1
		if Input.is_action_pressed("pan_left"): pan.x -= 1
		if Input.is_action_pressed("pan_right"): pan.x += 1
		if pan != Vector2.ZERO:
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var speed := distance * 0.9 * delta
			target += (right * pan.x + fwd * pan.y) * speed
		if Input.is_action_pressed("rotate_left"):
			yaw += delta * 0.9
		if Input.is_action_pressed("rotate_right"):
			yaw -= delta * 0.9
		# edge pan
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var vs := vp.get_visible_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x <= vs.x and mp.y <= vs.y and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) == false:
			var edge := 6.0
			if mp.x < edge: target += Vector3(cos(yaw), 0, -sin(yaw)) * -distance * 0.7 * delta
			elif mp.x > vs.x - edge: target += Vector3(cos(yaw), 0, -sin(yaw)) * distance * 0.7 * delta
			if mp.y < edge: target += Vector3(-sin(yaw), 0, -cos(yaw)) * distance * 0.7 * delta
			elif mp.y > vs.y - edge: target += Vector3(-sin(yaw), 0, -cos(yaw)) * -distance * 0.7 * delta
	var half := world.size * WorldModel.CELL * 0.5
	target.x = clampf(target.x, -half + 8, half - 8)
	target.z = clampf(target.z, -half + 8, half - 8)
	target.y = 0.0
	if follow_id >= 0 and follow_node != null:
		var p = follow_node
		target = Vector3(p.x, 0, p.y) if p is Vector2 else target
	smooth_target = smooth_target.lerp(target, clampf(delta * 8.0, 0.0, 1.0))
	smooth_distance = lerpf(smooth_distance, distance, clampf(delta * 10.0, 0.0, 1.0))
	_apply(delta)


func _apply(delta: float) -> void:
	if camera == null:
		return
	if shake_time > 0.0:
		shake_time -= delta
		var sh := shake_amount * clampf(shake_time * 2.0, 0.0, 1.0)
		smooth_target += Vector3(randf_range(-sh, sh), 0, randf_range(-sh, sh))
		if shake_time <= 0.0:
			shake_amount = 0.0
	var back := Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) * smooth_distance
	var up := Vector3(0, sin(pitch) * smooth_distance, 0)
	camera.position = smooth_target + back + up
	var ground_y := world.terrain_y(world.world_to_cell(camera.position).x, world.world_to_cell(camera.position).y) if world != null else 0.0
	if camera.position.y < ground_y + 8.0:
		camera.position.y = ground_y + 8.0
	camera.look_at(smooth_target, Vector3.UP)


func mouse_ray() -> Array:
	var mp := get_viewport().get_mouse_position()
	return [camera.project_ray_origin(mp), camera.project_ray_normal(mp)]


func pick_cell() -> Vector2i:
	var ray := mouse_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if world == null:
		return Vector2i(-1, -1)
	var max_t := 1600.0
	var step := 1.2
	var prev := origin
	var t := 0.0
	while t < max_t:
		t += step
		var p := origin + dir * t
		var fc := world.world_to_cell(p)
		if fc.x < -2 or fc.y < -2 or fc.x > world.size + 2 or fc.y > world.size + 2:
			prev = p
			continue
		var gy := world.terrain_y(fc.x, fc.y)
		if p.y <= gy:
			# бинарное уточнение
			var lo := prev
			var hi := p
			for i in 8:
				var mid := (lo + hi) * 0.5
				var mc := world.world_to_cell(mid)
				if mid.y <= world.terrain_y(mc.x, mc.y):
					hi = mid
				else:
					lo = mid
			var cell := world.world_to_cell(hi)
			return world.cell_of(cell)
		prev = p
	return Vector2i(-1, -1)


func screen_rect_cells() -> Rect2:
	var vp := get_viewport()
	var pts: Array = []
	for p in [Vector2(0, 0), Vector2(vp.get_visible_rect().size.x, 0), Vector2(0, vp.get_visible_rect().size.y), vp.get_visible_rect().size]:
		var o := camera.project_ray_origin(p)
		var d := camera.project_ray_normal(p)
		if absf(d.y) < 0.001:
			continue
		var t := -o.y / d.y
		if t > 0:
			var w := o + d * t
			pts.append(world.world_to_cell(w))
	if pts.is_empty():
		return Rect2(Vector2.ZERO, Vector2(world.size, world.size))
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)


func current_cell() -> Vector2:
	return world.world_to_cell(smooth_target)
