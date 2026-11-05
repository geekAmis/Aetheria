class_name MeshKit
extends RefCounted
## Низкополигональная геометрия, собираемая кодом: деревья, люди, животные,
## здания, кольца территорий. Всё запекается в vertex colors — один материал.

static var _mat: StandardMaterial3D
static var _mat_unshaded: StandardMaterial3D


static func vertex_material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.92
		_mat.metallic = 0.0
		_mat.metallic_specular = 0.15
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat


static func unshaded_material() -> StandardMaterial3D:
	if _mat_unshaded == null:
		_mat_unshaded = StandardMaterial3D.new()
		_mat_unshaded.vertex_color_use_as_albedo = true
		_mat_unshaded.vertex_color_is_srgb = true
		_mat_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_unshaded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_unshaded.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat_unshaded


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _v(st: SurfaceTool, p: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(p)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_v(st, a, col)
	_v(st, b, col)
	_v(st, c, col)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(st, a, b, c, col)
	tri(st, a, c, d, col)


static func commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var m := st.commit()
	return m


# ------------------------------------------------------------------ primitives

static func box(st: SurfaceTool, center: Vector3, sz: Vector3, col: Color, shade: bool = true) -> void:
	var h := sz * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z)
	]
	var top := col.lightened(0.10) if shade else col
	var side := col
	var front := col.darkened(0.05) if shade else col
	quad(st, p[4], p[5], p[6], p[7], top)
	quad(st, p[0], p[3], p[2], p[1], col.darkened(0.25))
	quad(st, p[0], p[1], p[5], p[4], front)
	quad(st, p[1], p[2], p[6], p[5], side)
	quad(st, p[2], p[3], p[7], p[6], front)
	quad(st, p[3], p[0], p[4], p[7], side)


static func cylinder(st: SurfaceTool, base: Vector3, radius: float, height: float, col: Color, sides: int = 6, top_radius: float = -1.0) -> void:
	if top_radius < 0.0:
		top_radius = radius
	var top := base + Vector3(0, height, 0)
	var tc := col.lightened(0.06)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var b0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := top + Vector3(cos(a0) * top_radius, 0, sin(a0) * top_radius)
		var t1 := top + Vector3(cos(a1) * top_radius, 0, sin(a1) * top_radius)
		quad(st, b0, b1, t1, t0, col.darkened(0.04 * float(i % 2)))
		if top_radius > 0.001:
			tri(st, top, t0, t1, tc)
		tri(st, base, b1, b0, col.darkened(0.2))


static func cone(st: SurfaceTool, base: Vector3, radius: float, height: float, col: Color, sides: int = 7) -> void:
	var top := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var b0 := base + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := base + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		tri(st, b0, b1, top, col.darkened(0.03 * float(i % 2)))
		tri(st, base, b1, b0, col.darkened(0.2))


static func sphere(st: SurfaceTool, center: Vector3, radius: float, col: Color, seg: int = 8, rings: int = 5, scale: Vector3 = Vector3.ONE) -> void:
	for r in rings:
		var v0 := PI * float(r) / rings
		var v1 := PI * float(r + 1) / rings
		for s in seg:
			var u0 := TAU * float(s) / seg
			var u1 := TAU * float(s + 1) / seg
			var p00 := center + Vector3(sin(v0) * cos(u0), cos(v0), sin(v0) * sin(u0)) * radius * scale
			var p01 := center + Vector3(sin(v0) * cos(u1), cos(v0), sin(v0) * sin(u1)) * radius * scale
			var p10 := center + Vector3(sin(v1) * cos(u0), cos(v1), sin(v1) * sin(u0)) * radius * scale
			var p11 := center + Vector3(sin(v1) * cos(u1), cos(v1), sin(v1) * sin(u1)) * radius * scale
			var c := col.lightened(0.04 * float(s % 2))
			tri(st, p00, p10, p11, c)
			tri(st, p00, p11, p01, c)


static func prism_roof(st: SurfaceTool, center: Vector3, width: float, depth: float, height: float, col: Color) -> void:
	var hw := width * 0.5
	var hd := depth * 0.5
	var p0 := center + Vector3(-hw, 0, -hd)
	var p1 := center + Vector3(hw, 0, -hd)
	var p2 := center + Vector3(hw, 0, hd)
	var p3 := center + Vector3(-hw, 0, hd)
	var r0 := center + Vector3(0, height, -hd)
	var r1 := center + Vector3(0, height, hd)
	tri(st, p0, r0, p1, col.lightened(0.06))
	tri(st, p3, p2, r1, col.darkened(0.1))
	# скаты
	quad(st, p0, p3, r1, r0, col)
	quad(st, p1, r0, r1, p2, col.darkened(0.06))
	# торцы
	tri(st, p0, r0, p3, col.darkened(0.14))
	tri(st, p1, p2, r0, col.darkened(0.14))


# ------------------------------------------------------------------ props

static func tree_mesh(kind: String) -> ArrayMesh:
	var st := _st()
	match kind:
		"conifer":
			cylinder(st, Vector3(0, 0, 0), 0.18, 1.25, Color("#5b4630"))
			cone(st, Vector3(0, 1.0, 0), 1.25, 2.4, Color("#2f5a35"), 8)
			cone(st, Vector3(0, 2.25, 0), 0.95, 2.1, Color("#356b3c"), 8)
			cone(st, Vector3(0, 3.35, 0), 0.62, 1.7, Color("#3d7a43"), 8)
		"palm":
			cylinder(st, Vector3(0, 0, 0), 0.20, 3.4, Color("#7a5c3a"), 7, 0.13)
			for i in 6:
				var a := TAU * i / 6.0
				var dir := Vector3(cos(a), -0.28, sin(a))
				var base := Vector3(0, 3.2, 0)
				var tip := base + dir * 1.9
				# лист — тонкий ромб
				var side := Vector3(-dir.z, 0, dir.x).normalized() * 0.34
				tri(st, base, base + side, tip, Color("#3f8f4a"))
				tri(st, base, tip, base - side, Color("#4aa356"))
			sphere(st, Vector3(0, 3.15, 0), 0.28, Color("#6b4a2a"), 6, 3)
		"swamp":
			cylinder(st, Vector3(0, 0, 0), 0.22, 2.2, Color("#4a3d2b"), 6)
			sphere(st, Vector3(0, 2.35, 0), 1.0, Color("#3e5c38"), 7, 4, Vector3(1.25, 0.75, 1.25))
			sphere(st, Vector3(0.35, 2.1, -0.2), 0.55, Color("#496b41"), 6, 3)
		"dead":
			cylinder(st, Vector3(0, 0, 0), 0.17, 2.4, Color("#5a4a3a"), 5, 0.08)
			var b1 := Vector3(0, 1.4, 0)
			var b2 := Vector3(0.55, 2.1, 0.2)
			cylinder_between(st, b1, b2, 0.07, Color("#514333"), 4)
			cylinder_between(st, Vector3(0.1, 1.8, 0), Vector3(-0.5, 2.4, -0.25), 0.06, Color("#4a3e30"), 4)
		"cactus":
			cylinder(st, Vector3(0, 0, 0), 0.34, 1.7, Color("#4f8f4a"), 7, 0.28)
			cylinder(st, Vector3(0.34, 0.7, 0), 0.16, 0.8, Color("#4f8f4a"), 6)
			cylinder(st, Vector3(-0.34, 0.95, 0), 0.15, 0.6, Color("#4f8f4a"), 6)
		"acacia":
			cylinder(st, Vector3(0, 0, 0), 0.20, 2.2, Color("#6b5136"), 6)
			sphere(st, Vector3(0, 2.6, 0), 1.35, Color("#6f7f33"), 8, 4, Vector3(1.3, 0.35, 1.3))
		"crystal":
			cone(st, Vector3(0, 0, 0), 0.42, 2.6, Color("#8b6fe0"), 5)
			cone(st, Vector3(0.4, 0, 0.2), 0.22, 1.4, Color("#a488ff"), 5)
			cone(st, Vector3(-0.3, 0, -0.25), 0.18, 1.0, Color("#7a5ccc"), 5)
		"bush":
			sphere(st, Vector3(0, 0.38, 0), 0.55, Color("#4b7a38"), 7, 4, Vector3(1.2, 0.8, 1.2))
			sphere(st, Vector3(0.35, 0.3, 0.15), 0.4, Color("#588a42"), 6, 3)
		"reed":
			for i in 5:
				var a := TAU * i / 5.0
				var p := Vector3(cos(a) * 0.18, 0, sin(a) * 0.18)
				cylinder(st, p, 0.035, 1.1 + 0.2 * (i % 3), Color("#6b7f3a"), 4)
		"flowers":
			sphere(st, Vector3(0, 0.22, 0), 0.3, Color("#5f8f3a"), 6, 3, Vector3(1.5, 0.6, 1.5))
			for i in 4:
				var a := TAU * i / 4.0
				sphere(st, Vector3(cos(a) * 0.2, 0.42, sin(a) * 0.2), 0.09, Color("#e8d05a") if i % 2 == 0 else Color("#e07a9a"), 4, 2)
		"mushroom":
			for i in 3:
				var p := Vector3((i - 1) * 0.25, 0, (i % 2) * 0.2)
				cylinder(st, p, 0.05, 0.28, Color("#d8c8a8"), 4)
				sphere(st, p + Vector3(0, 0.3, 0), 0.16, Color("#c05040"), 6, 3, Vector3(1, 0.55, 1))
		_:
			cylinder(st, Vector3(0, 0, 0), 0.22, 1.7, Color("#6b4f34"), 6)
			sphere(st, Vector3(0, 2.1, 0), 1.25, Color("#3f7a3f"), 8, 4, Vector3(1.15, 0.95, 1.15))
			sphere(st, Vector3(0.55, 1.85, 0.2), 0.72, Color("#4a8a46"), 7, 3)
			sphere(st, Vector3(-0.5, 1.9, -0.25), 0.68, Color("#356f36"), 7, 3)
	return commit(st)


static func cylinder_between(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, col: Color, sides: int = 4) -> void:
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized() * radius
	var z := dir.cross(x).normalized() * radius
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var o0 := x * cos(a0) + z * sin(a0)
		var o1 := x * cos(a1) + z * sin(a1)
		quad(st, a + o0, a + o1, b + o1, b + o0, col)
		tri(st, a, a + o1, a + o0, col.darkened(0.2))
		tri(st, b, b + o0, b + o1, col.darkened(0.2))


static func ring_mesh(inner: float, outer: float, segments: int, col: Color) -> ArrayMesh:
	var st := _st()
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var p00 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var p01 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var p10 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var p11 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		quad(st, p00, p10, p11, p01, col)
	return commit(st)


static func obelisk_mesh(width: float, height: float, col: Color) -> ArrayMesh:
	var st := _st()
	box(st, Vector3(0, height * 0.08, 0), Vector3(width * 1.6, height * 0.16, width * 1.6), col.darkened(0.25))
	cylinder(st, Vector3(0, height * 0.16, 0), width * 0.5, height * 0.7, col, 4, width * 0.32)
	cone(st, Vector3(0, height * 0.86, 0), width * 0.34, height * 0.14, Color("#f0d070"), 4)
	return commit(st)


static func rock_mesh() -> ArrayMesh:
	var st := _st()
	sphere(st, Vector3(0, 0.25, 0), 0.62, Color("#8a8a84"), 7, 4, Vector3(1.25, 0.65, 1.0))
	sphere(st, Vector3(0.35, 0.2, 0.3), 0.35, Color("#76766f"), 5, 3, Vector3(1, 0.7, 1))
	return commit(st)


static func person_mesh() -> ArrayMesh:
	var st := _st()
	# ноги
	cylinder(st, Vector3(-0.12, 0, 0), 0.075, 0.62, Color("#43474e"), 5)
	cylinder(st, Vector3(0.12, 0, 0), 0.075, 0.62, Color("#43474e"), 5)
	# тело
	cylinder(st, Vector3(0, 0.55, 0), 0.26, 0.78, Color("#e8e8e8"), 6, 0.22)
	# руки
	cylinder(st, Vector3(-0.27, 0.62, 0), 0.065, 0.58, Color("#d8d8d8"), 4)
	cylinder(st, Vector3(0.27, 0.62, 0), 0.065, 0.58, Color("#d8d8d8"), 4)
	# голова
	sphere(st, Vector3(0, 1.55, 0), 0.22, Color("#f2ddc8"), 8, 5)
	# волосы/капюшон
	sphere(st, Vector3(0, 1.63, -0.02), 0.23, Color("#4a4038"), 7, 3, Vector3(1, 0.62, 1))
	# пояс
	cylinder(st, Vector3(0, 0.56, 0), 0.27, 0.08, Color("#7a5a32"), 6)
	return commit(st)


static func animal_mesh() -> ArrayMesh:
	var st := _st()
	# тело
	sphere(st, Vector3(0, 0.52, 0), 0.42, Color("#e0ddd5"), 7, 4, Vector3(1.45, 0.8, 0.8))
	# голова
	sphere(st, Vector3(0.6, 0.72, 0), 0.24, Color("#e8e4dc"), 6, 4)
	# уши/рога
	cone(st, Vector3(0.62, 0.9, 0.1), 0.05, 0.3, Color("#cfc8ba"), 4)
	cone(st, Vector3(0.62, 0.9, -0.1), 0.05, 0.3, Color("#cfc8ba"), 4)
	# ноги
	for x in [-0.35, 0.35]:
		for z in [-0.24, 0.24]:
			cylinder(st, Vector3(x, 0, z), 0.055, 0.42, Color("#b8b2a6"), 4)
	# хвост
	cylinder(st, Vector3(-0.52, 0.55, 0), 0.04, 0.35, Color("#cfc8ba"), 4)
	return commit(st)


# ------------------------------------------------------------------ buildings

static func building_mesh(type: String, data: Dictionary) -> ArrayMesh:
	var st := _st()
	var col: Color = data.get("color_c", Color("#8a7a5a"))
	var roof: Color = data.get("roof_c", Color("#6a5a3a"))
	var s: float = float(data.get("size", 1.2)) * WorldModel.CELL * 1.05
	var h: float = float(data.get("height", 1.0)) * WorldModel.CELL * 0.9
	match type:
		"campfire":
			for i in 7:
				var a := TAU * i / 7.0
				var p := Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55)
				box(st, p, Vector3(0.22, 0.18, 0.22), Color("#777770"))
			cylinder_between(st, Vector3(-0.38, 0.18, 0), Vector3(0.38, 0.3, 0.12), 0.10, Color("#5a3e26"), 5)
			cylinder_between(st, Vector3(-0.35, 0.22, 0.22), Vector3(0.35, 0.32, -0.18), 0.09, Color("#4d3420"), 5)
		"farm":
			box(st, Vector3(0, 0.04, 0), Vector3(s * 1.5, 0.08, s * 1.2), Color("#6b5636"), false)
			for i in 6:
				var x := -s * 0.62 + i * (s * 1.24 / 5.0)
				box(st, Vector3(x, 0.16, 0), Vector3(0.08, 0.14, s * 1.1), Color("#a8b05a") if i % 2 == 0 else Color("#8a9a45"), false)
		"pasture":
			box(st, Vector3(0, 0.02, 0), Vector3(s * 1.5, 0.04, s * 1.2), Color("#7a8a42"), false)
			for i in 10:
				var a := TAU * i / 10.0
				box(st, Vector3(cos(a) * s * 0.7, 0.24, sin(a) * s * 0.55), Vector3(0.06, 0.48, 0.06), Color("#8a6a42"))
		"temple":
			box(st, Vector3(0, 0.08, 0), Vector3(s * 1.2, 0.16, s * 1.2), col.darkened(0.12))
			box(st, Vector3(0, h * 0.34, 0), Vector3(s * 0.85, h * 0.55, s * 0.85), col)
			for i in 4:
				var x := (-0.34 + 0.68 * (i % 2)) * s
				var z := (-0.34 + 0.68 * (i / 2)) * s
				cylinder(st, Vector3(x, 0, z), 0.08, h * 0.72, col.lightened(0.15), 6)
			prism_roof(st, Vector3(0, h * 0.62, 0), s * 1.0, s * 1.0, h * 0.45, roof)
			cone(st, Vector3(0, h * 1.02, 0), 0.12, h * 0.35, Color("#e8c05a"), 5)
		"monument":
			box(st, Vector3(0, 0.15, 0), Vector3(s * 0.9, 0.3, s * 0.9), col.darkened(0.2))
			cylinder(st, Vector3(0, 0.3, 0), s * 0.22, h * 1.5, col, 4, s * 0.10)
			cone(st, Vector3(0, h * 1.8, 0), s * 0.11, h * 0.25, Color("#e8c05a"), 4)
		"wall":
			box(st, Vector3(0, h * 0.35, 0), Vector3(s * 1.8, h * 0.7, s * 0.32), col)
			for i in 4:
				box(st, Vector3(-s * 0.7 + i * s * 0.47, h * 0.78, 0), Vector3(s * 0.16, h * 0.18, s * 0.34), col.darkened(0.08))
		"mine":
			box(st, Vector3(0, h * 0.4, 0), Vector3(s * 0.9, h * 0.8, s * 0.6), col)
			box(st, Vector3(0, h * 0.28, s * 0.32), Vector3(s * 0.3, h * 0.55, 0.2), Color("#161616"))
			box(st, Vector3(0, h * 0.82, 0), Vector3(s * 1.0, 0.12, s * 0.7), roof)
		"factory":
			box(st, Vector3(0, h * 0.38, 0), Vector3(s * 1.25, h * 0.76, s * 0.9), col)
			cylinder(st, Vector3(s * 0.38, h * 0.72, 0), 0.16, h * 0.95, Color("#5a5a5a"), 6)
			box(st, Vector3(-s * 0.38, h * 0.78, 0), Vector3(s * 0.3, h * 0.16, s * 0.9), roof)
		"silo":
			cylinder(st, Vector3(0, 0, 0), s * 0.35, h * 0.8, Color("#777770"), 8)
			cone(st, Vector3(0, h * 0.8, 0), s * 0.38, h * 0.3, Color("#c84a2a"), 8)
			box(st, Vector3(0, 0.12, s * 0.45), Vector3(s * 0.3, 0.24, 0.3), Color("#333"))
		"spaceport":
			box(st, Vector3(0, 0.1, 0), Vector3(s * 1.4, 0.2, s * 1.2), Color("#9a9a9a"))
			box(st, Vector3(-s * 0.45, h * 0.35, 0), Vector3(s * 0.25, h * 0.7, s * 0.25), Color("#c8c8c8"))
			cylinder(st, Vector3(s * 0.25, 0.2, 0), s * 0.16, h * 1.25, Color("#e8e8e8"), 8)
			cone(st, Vector3(s * 0.25, h * 1.45, 0), s * 0.16, h * 0.35, Color("#d84a3a"), 6)
		"market":
			box(st, Vector3(0, 0.12, 0), Vector3(s * 1.3, 0.24, s * 0.9), col.darkened(0.15))
			for i in 3:
				var x := (-0.45 + i * 0.45) * s
				for j in 2:
					cylinder(st, Vector3(x - 0.25, 0, -s * 0.3 + j * s * 0.6), 0.05, h * 0.8, Color("#7a5a32"), 4)
				box(st, Vector3(x, h * 0.82, 0), Vector3(s * 0.34, 0.08, s * 0.8), roof.lightened(0.1 * (i % 2)))
		"library", "university", "lab":
			box(st, Vector3(0, h * 0.4, 0), Vector3(s * 1.0, h * 0.8, s * 0.9), col)
			prism_roof(st, Vector3(0, h * 0.8, 0), s * 1.05, s * 0.95, h * 0.32, roof)
			for i in 3:
				box(st, Vector3((i - 1) * s * 0.28, h * 0.45, s * 0.46), Vector3(s * 0.14, h * 0.32, 0.05), Color("#f0d890"))
		"power":
			box(st, Vector3(0, h * 0.35, 0), Vector3(s * 1.2, h * 0.7, s * 0.9), col)
			cylinder(st, Vector3(s * 0.35, h * 0.65, 0), 0.28, h * 0.9, Color("#b0b0b8"), 8)
			cylinder(st, Vector3(-s * 0.35, h * 0.65, 0), 0.22, h * 0.7, Color("#b0b0b8"), 8)
		_:
			# базовый дом
			box(st, Vector3(0, h * 0.4, 0), Vector3(s * 0.95, h * 0.8, s * 0.85), col)
			prism_roof(st, Vector3(0, h * 0.8, 0), s * 1.05, s * 0.95, h * 0.42, roof)
			# дверь
			box(st, Vector3(0, h * 0.25, s * 0.44), Vector3(s * 0.20, h * 0.5, 0.06), Color("#3a2a1a"))
			if type in ["workshop", "granary", "barracks"]:
				box(st, Vector3(s * 0.32, h * 0.55, s * 0.44), Vector3(s * 0.12, h * 0.14, 0.04), Color("#f0d890"))
	return commit(st)
