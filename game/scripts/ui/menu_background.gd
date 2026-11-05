class_name MenuBackground
extends Control
## Живой фон главного меню: звёзды, рассвет, горы, туман и пыль.

var t := 0.0
var stars: Array = []
var motes: Array = []
var rng := RandomNumberGenerator.new()
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rng.seed = 1977
	for i in 170:
		stars.append({
			"x": rng.randf(), "y": rng.randf_range(0.02, 0.66),
			"r": rng.randf_range(0.5, 1.7), "p": rng.randf_range(0.3, 2.2),
			"a": rng.randf_range(0.25, 0.9)
		})
	for i in 46:
		motes.append({
			"x": rng.randf(), "y": rng.randf_range(0.3, 0.95),
			"r": rng.randf_range(0.6, 2.1), "v": rng.randf_range(0.004, 0.018),
			"p": rng.randf_range(0, TAU), "a": rng.randf_range(0.08, 0.35)
		})
	_font = load("res://assets/fonts/CormorantGaramond.ttf")
	set_process(true)


func _process(delta: float) -> void:
	t += delta
	for m in motes:
		m.y -= m.v * delta
		if m.y < 0.28:
			m.y = 0.98
			m.x = rng.randf()
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 10 or s.y < 10:
		return
	# небо
	var bands := 120
	for i in bands:
		var f := float(i) / bands
		var top := Color("#050a12")
		var mid := Color("#0c1a26")
		var horizon := Color("#26323a")
		var c := top.lerp(mid, minf(1.0, f * 1.8))
		if f > 0.52:
			c = mid.lerp(horizon, (f - 0.52) / 0.48)
		c = c.lerp(Color("#4a3a2c"), pow(maxf(0.0, f - 0.74) / 0.26, 2.0) * 0.55)
		draw_rect(Rect2(0, s.y * f, s.x, s.y / bands + 1), c)
	# звёзды
	for st in stars:
		var tw := 0.55 + 0.45 * sin(t * st.p + st.x * 30.0)
		var col := Color(0.85, 0.9, 1.0, st.a * tw)
		draw_circle(Vector2(st.x * s.x, st.y * s.y), st.r, col)
	# созвездие-корона
	var crown_pts := [Vector2(0.60, 0.20), Vector2(0.65, 0.14), Vector2(0.70, 0.18), Vector2(0.75, 0.11), Vector2(0.80, 0.17), Vector2(0.84, 0.13)]
	for i in crown_pts.size() - 1:
		var a := Vector2(crown_pts[i].x * s.x, crown_pts[i].y * s.y)
		var b := Vector2(crown_pts[i + 1].x * s.x, crown_pts[i + 1].y * s.y)
		draw_line(a, b, Color(0.85, 0.7, 0.4, 0.18), 1.0)
		draw_circle(a, 1.8, Color(0.95, 0.82, 0.55, 0.8))
	# солнце/луна
	var sun := Vector2(s.x * 0.72, s.y * 0.42)
	for i in range(7, 0, -1):
		var rr := 60.0 + i * 55.0
		draw_circle(sun, rr, Color(0.85, 0.62, 0.32, 0.012 * i))
	draw_circle(sun, 42.0, Color(0.95, 0.78, 0.48, 0.55))
	draw_circle(sun, 34.0, Color(1.0, 0.88, 0.62, 0.85))
	draw_arc(sun, 110.0, 0, TAU, 80, Color(0.9, 0.72, 0.4, 0.10), 1.0)
	draw_arc(sun, 155.0, 0, TAU, 80, Color(0.9, 0.72, 0.4, 0.07), 1.0)
	# горы — три слоя
	_draw_ridge(s, 0.63, 0.16, Color("#0a1620"), 0.0, 1.0)
	_draw_ridge(s, 0.73, 0.13, Color("#0d1c24"), 1.7, 0.7)
	_draw_ridge(s, 0.84, 0.10, Color("#111f24"), 3.1, 0.45)
	# туман
	for i in 9:
		var y := s.y * (0.74 + i * 0.018)
		draw_rect(Rect2(0, y, s.x, 12), Color(0.22, 0.28, 0.30, 0.035))
	# пыль
	for m in motes:
		var a: float = m.a * (0.6 + 0.4 * sin(t * 0.8 + m.p))
		draw_circle(Vector2(m.x * s.x, m.y * s.y), m.r, Color(0.95, 0.82, 0.55, a))
	# виньетка
	for i in 30:
		var a := 0.012 * (30 - i) / 30.0
		draw_rect(Rect2(i, i, s.x - i * 2, s.y - i * 2), Color(0, 0, 0, a), false, 2.0)


func _draw_ridge(s: Vector2, base: float, amp: float, col: Color, phase: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, s.y))
	var n := 14
	for i in n + 1:
		var x := s.x * float(i) / n
		var y := s.y * (base + sin(float(i) * 0.9 + phase + 0.4) * amp * 0.45 + sin(float(i) * 2.1 + phase * 2.0) * amp * 0.22)
		pts.append(Vector2(x, y))
	pts.append(Vector2(s.x, s.y))
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))
	# снежные вершины
	for i in range(1, n):
		if i % 3 == 1:
			var x := s.x * float(i) / n
			var y := s.y * (base + sin(float(i) * 0.9 + phase + 0.4) * amp * 0.45 + sin(float(i) * 2.1 + phase * 2.0) * amp * 0.22)
			var w := s.x * 0.014
			draw_colored_polygon(PackedVector2Array([Vector2(x - w, y + 4), Vector2(x, y - 6), Vector2(x + w, y + 4)]), Color(0.75, 0.82, 0.86, 0.18 * alpha))
