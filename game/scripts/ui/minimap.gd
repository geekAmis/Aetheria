class_name MiniMap
extends Control
## Миникарта: текстура мира, поселения, камера. Клик/перетаскивание — переход.

var hud: HUD
var world: WorldModel
var texture: ImageTexture
var timer := 0.0
var dragging := false


func setup(p_hud: HUD) -> void:
	hud = p_hud
	world = hud.game.world
	custom_minimum_size = Vector2(280, 280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	timer = 0.0


func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = 0.3
		if hud != null and hud.game != null and hud.game.terrain_view != null:
			texture = hud.game.terrain_view.minimap_texture
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#0b1218"))
	if world == null:
		return
	if texture != null:
		draw_texture_rect(texture, r, false)
	else:
		draw_rect(r, Color("#1a2b24"))
	# сетка
	for i in range(1, 4):
		var x := size.x * i / 4.0
		var y := size.y * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.05), 1.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.05), 1.0)
	if hud != null and hud.game != null and hud.game.sim != null:
		for s in hud.game.sim.settlements:
			var p := Vector2(s.center) / float(world.size) * size
			if s.destroyed:
				draw_circle(p, 2.2, Color(0.35, 0.33, 0.3, 0.8))
				continue
			var col: Color = D.race(s.race_id).get("color_c", Color.WHITE)
			if s.wars.size() > 0:
				col = Color("#e05a4e")
			draw_circle(p, 3.2, Color(0, 0, 0, 0.5))
			draw_circle(p, 2.5, col)
			if s.id == hud.game.selected_settlement_id:
				draw_arc(p, 6.0, 0, TAU, 20, Color("#ffe3a3"), 1.4)
	# камера
	var cr: Rect2 = hud.game.camera_rig.screen_rect_cells()
	var pr := Rect2(cr.position / float(world.size) * size, cr.size / float(world.size) * size)
	pr = pr.intersection(Rect2(Vector2.ZERO, size))
	if pr.size.x > 1 and pr.size.y > 1:
		draw_rect(pr, Color(1, 0.88, 0.55, 0.18), true)
		draw_rect(pr, Color(1, 0.9, 0.6, 0.75), false, 1.2)
	# рамка
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.72, 0.45, 0.35), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			_jump(event.position)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		_jump(event.position)
		accept_event()


func _jump(p: Vector2) -> void:
	if hud == null or hud.game == null:
		return
	var cell := Vector2(
		clampf(p.x / maxf(1.0, size.x), 0.0, 1.0) * world.size,
		clampf(p.y / maxf(1.0, size.y), 0.0, 1.0) * world.size
	)
	hud.jump_to.emit(cell, -1)
