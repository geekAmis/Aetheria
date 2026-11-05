class_name SkyView
extends Node3D
## Небо, солнце, день/ночь, погода и атмосфера.

var world: WorldModel
var camera_rig: CameraRig
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var snow: GPUParticles3D
var ash: GPUParticles3D
var weather_mode := "clear"
var season := 0
var nuclear_winter := 0.0
var hour := 10.0
var _day_color_top := Color("#3c76b8")
var _day_color_hz := Color("#b8d6e6")
var _dusk_color_top := Color("#283266")
var _dusk_color_hz := Color("#e88a56")
var _night_color_top := Color("#050b1c")
var _night_color_hz := Color("#0e1a30")


func setup(p_world: WorldModel, p_camera: CameraRig) -> void:
	world = p_world
	camera_rig = p_camera
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.18
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color("#a8c0d0")
	env.fog_density = 0.00025
	env.fog_aerial_perspective = 0.22
	env.fog_sky_affect = 0.22
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.4
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color("#8fa8e0")
	moon.light_energy = 0.0
	add_child(moon)

	rain = _make_weather(false, Color(0.62, 0.78, 0.95, 0.7), 0.075, 1.1)
	snow = _make_weather(true, Color(1, 1, 1, 0.9), 0.13, 0.13)
	ash = _make_weather(true, Color(0.45, 0.42, 0.4, 0.8), 0.1, 0.1)
	apply(10.0, 0, "clear", 0.0)


func _make_weather(slow: bool, col: Color, w: float, h: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 3600 if not slow else 2000
	p.lifetime = 4.5 if slow else 1.8
	p.preprocess = 2.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-140, -80, -140), Vector3(280, 180, 280))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 4, 90)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0 if slow else 12.0
	pm.initial_velocity_max = 2.5 if slow else 20.0
	pm.gravity = Vector3(0, -1.2 if slow else -22.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color = col
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	add_child(p)
	return p


func apply(p_hour: float, p_season: int, p_weather: String, p_winter: float) -> void:
	hour = p_hour
	season = p_season
	weather_mode = p_weather
	nuclear_winter = p_winter
	var elev := sin((hour - 6.0) / 24.0 * TAU)
	var day := clampf(elev * 1.6 + 0.12, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) * 3.2, 0.0, 1.0)
	var night := clampf(-elev * 1.8 + 0.05, 0.0, 1.0)
	var top := _night_color_top.lerp(_day_color_top, day)
	var hz := _night_color_hz.lerp(_day_color_hz, day)
	top = top.lerp(_dusk_color_top, dusk * 0.85)
	hz = hz.lerp(_dusk_color_hz, dusk * 0.75)
	# сезонные оттенки
	if season == 3:
		top = top.lerp(Color("#5a6b80"), 0.18)
		hz = hz.lerp(Color("#cfd8de"), 0.20)
	elif season == 2:
		top = top.lerp(Color("#6a6a8a"), 0.08)
		hz = hz.lerp(Color("#e0c0a0"), 0.12)
	# погода
	var cloud := 0.22
	var fog := 0.00035
	if weather_mode == "rain":
		cloud = 0.95
		top = top.lerp(Color("#4a5a66"), 0.5)
		hz = hz.lerp(Color("#8a9aa2"), 0.42)
		fog = 0.0010
	elif weather_mode == "snow":
		cloud = 0.55
		top = top.lerp(Color("#7a8ca0"), 0.38)
		hz = hz.lerp(Color("#d8e2e8"), 0.45)
		fog = 0.0010
	elif weather_mode == "fog":
		cloud = 0.4
		top = top.lerp(Color("#8898a0"), 0.5)
		hz = hz.lerp(Color("#b8c8d0"), 0.7)
		fog = 0.0015
	elif weather_mode == "ash":
		cloud = 0.8
		top = top.lerp(Color("#4a4540"), 0.7)
		hz = hz.lerp(Color("#8a7a6a"), 0.7)
		fog = 0.0022
	if nuclear_winter > 0.0:
		top = top.lerp(Color("#3a3a3a"), 0.55)
		hz = hz.lerp(Color("#6a6a64"), 0.55)
		fog = maxf(fog, 0.0025)
		cloud = maxf(cloud, 0.7)
	sky_mat.set_shader_parameter("sky_top", top)
	sky_mat.set_shader_parameter("sky_horizon", hz)
	sky_mat.set_shader_parameter("ground_color", hz.darkened(0.55))
	sky_mat.set_shader_parameter("cloud_amount", cloud)
	sky_mat.set_shader_parameter("cloud_color", hz.lightened(0.18))
	sky_mat.set_shader_parameter("star_amount", night)
	var elev_angle := asin(clampf(elev, -1.0, 1.0)) * 0.82 + 0.18
	var az := (hour - 12.0) / 24.0 * TAU
	var sun_dir := Vector3(cos(az) * cos(elev_angle), sin(elev_angle), sin(az) * cos(elev_angle) * 0.75).normalized()
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_energy", clampf(elev, 0.0, 1.0) * 1.4 + 0.02)
	var sun_col := Color("#fff1d0").lerp(Color("#ff8a4a"), dusk)
	sky_mat.set_shader_parameter("sun_color", sun_col)
	# свет
	sun.light_color = sun_col
	sun.light_energy = clampf(elev, 0.0, 1.0) * 1.35 + 0.02
	sun.visible = elev > -0.08
	var basis := Basis.looking_at(-sun_dir, Vector3.UP)
	sun.transform.basis = basis
	moon.light_energy = clampf(-elev, 0.0, 1.0) * 0.55
	moon.light_color = Color("#9fb8f0")
	moon.transform.basis = Basis.looking_at(sun_dir, Vector3.UP)
	if elev < 0.02:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#5f7aa8")
		env.ambient_light_energy = 0.55
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.16 + clampf(elev, 0.0, 1.0) * 0.36
	env.tonemap_exposure = 0.95 + clampf(-elev, 0.0, 1.0) * 0.06
	env.fog_light_color = hz
	env.fog_density = fog
	env.glow_intensity = 0.7 + dusk * 0.35
	# погодные частицы
	rain.emitting = weather_mode == "rain" and not (season == 3 and hour > 6 and hour < 19 and false)
	snow.emitting = weather_mode == "snow"
	ash.emitting = weather_mode == "ash"
	# позиция погоды над камерой
	if camera_rig != null:
		var t := camera_rig.smooth_target
		for p in [rain, snow, ash]:
			p.position = Vector3(t.x, t.y + 45.0, t.z)


func set_season(s: int) -> void:
	season = s


func _process(_delta: float) -> void:
	if camera_rig == null:
		return
	var t := camera_rig.smooth_target
	for p in [rain, snow, ash]:
		if p.emitting:
			p.position = Vector3(t.x, t.y + 45.0, t.z)


func weather_name() -> String:
	return weather_mode
