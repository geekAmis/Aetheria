extends Node
## Audio — процедурная эмбиент-музыка и синтезированные звуки катастроф
## плюс CC0-звуки интерфейса Kenney. Не требует внешних медиа-средств,
## кроме нескольких OGG для UI.

const RATE := 22050

var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _calm: AudioStreamWAV
var _tense: AudioStreamWAV
var _music_started := false
var _war_target := 0.0
var _music_mix := 0.0
var master_volume := 0.9
var music_volume := 0.55
var sfx_volume := 0.8


func _ready() -> void:
	_load_settings()
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	music_a.bus = "Master"
	music_b.bus = "Master"
	add_child(music_a)
	add_child(music_b)
	_load_kenney()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		master_volume = float(cfg.get_value("audio", "master", 0.9))
		music_volume = float(cfg.get_value("audio", "music", 0.55))
		sfx_volume = float(cfg.get_value("audio", "sfx", 0.8))


func _load_kenney() -> void:
	var files := {
		"click": "res://assets/sfx/click.ogg",
		"confirm": "res://assets/sfx/confirm.ogg",
		"error": "res://assets/sfx/error.ogg",
		"back": "res://assets/sfx/back.ogg",
		"drop": "res://assets/sfx/drop.ogg",
		"bong": "res://assets/sfx/bong.ogg",
	}
	for k in files:
		if ResourceLoader.exists(files[k]):
			_sfx_cache[k] = load(files[k])


func play(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sfx_cache.has(name):
		if name in ["thunder", "explosion", "nuke", "quake", "bless", "brush", "horn", "fire", "curse"]:
			_sfx_cache[name] = _synth(name)
		else:
			return
	var p: AudioStreamPlayer = null
	for pl in sfx_players:
		if not pl.playing:
			p = pl
			break
	if p == null:
		p = sfx_players[0]
	p.stream = _sfx_cache[name]
	p.volume_db = linear_to_db(clampf(sfx_volume * master_volume, 0.001, 1.0)) + vol_db
	p.pitch_scale = pitch
	p.play()


func ui_click() -> void:
	play("click", -6.0, randf_range(0.96, 1.05))

func ui_confirm() -> void:
	play("confirm", -4.0)

func ui_error() -> void:
	play("error", -5.0)

func ui_back() -> void:
	play("back", -4.0)


func start_music() -> void:
	if _music_started:
		return
	_music_started = true
	if DisplayServer.get_name() == "headless":
		return
	if _calm == null:
		_calm = _gen_calm()
		_tense = _gen_tense()
	music_a.stream = _calm
	music_b.stream = _tense
	music_a.volume_db = linear_to_db(clampf(music_volume * master_volume * 0.6, 0.001, 1.0))
	music_b.volume_db = -80.0
	music_a.play()
	music_b.play()
	music_b.seek(3.0)


func set_war(intensity: float) -> void:
	_war_target = clampf(intensity, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _music_started:
		return
	_music_mix = move_toward(_music_mix, _war_target, delta * 0.15)
	if music_a != null:
		music_a.volume_db = linear_to_db(max(0.0001, music_volume * master_volume * 0.6 * (1.0 - _music_mix * 0.75)))
	if music_b != null:
		music_b.volume_db = linear_to_db(max(0.0001, music_volume * master_volume * 0.55 * (0.15 + _music_mix * 0.85)))


func apply_volumes(master: float, music: float, sfx: float) -> void:
	master_volume = clampf(master, 0.0, 1.0)
	music_volume = clampf(music, 0.0, 1.0)
	sfx_volume = clampf(sfx, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save("user://settings.cfg")


# ---------------------------------------------------------------- synthesis

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var s := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _synth(name: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	match name:
		"thunder":
			var n := int(RATE * 1.4)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 77
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.06)
				var boom := sin(TAU * 42.0 * t) * exp(-t * 2.0) * 0.55
				var crack := rng.randf_range(-1, 1) * exp(-t * 18.0) * 0.5
				samples[i] = (lp * 1.9 + boom + crack) * 0.6
		"explosion":
			var n := int(RATE * 0.9)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 12
			for i in n:
				var t := float(i) / RATE
				var noise := rng.randf_range(-1, 1) * exp(-t * 5.0)
				var thump := sin(TAU * (55.0 - t * 22.0) * t) * exp(-t * 4.0)
				samples[i] = (noise * 0.7 + thump * 0.9)
		"nuke":
			var n := int(RATE * 3.2)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 909
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.02)
				var sub := sin(TAU * (30.0 + 8.0 * sin(t * 0.7)) * t) * exp(-t * 0.7)
				var crack := rng.randf_range(-1, 1) * exp(-t * 12.0) * 0.55
				samples[i] = clampf(lp * 2.2 + sub * 0.8 + crack, -1, 1)
		"quake":
			var n := int(RATE * 2.2)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 33
			var brown := 0.0
			for i in n:
				var t := float(i) / RATE
				brown = clampf(brown * 0.985 + rng.randf_range(-1, 1) * 0.035, -1, 1)
				var env := sin(PI * clampf(t / 2.2, 0, 1))
				samples[i] = brown * env * 1.6
		"bless":
			var n := int(RATE * 2.0)
			samples.resize(n)
			for i in n:
				var t := float(i) / RATE
				var env := exp(-t * 1.9)
				samples[i] = (sin(TAU * 523.25 * t) + sin(TAU * 659.25 * t) * 0.7 + sin(TAU * 783.99 * t) * 0.5) * env * 0.12
		"curse":
			var n := int(RATE * 1.8)
			samples.resize(n)
			for i in n:
				var t := float(i) / RATE
				var env := exp(-t * 1.3)
				samples[i] = (sin(TAU * 110.0 * t + sin(t * 9.0)) + sin(TAU * 116.5 * t) * 0.7) * env * 0.15
		"brush":
			var n := int(RATE * 0.22)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 5
			var lp := 0.0
			for i in n:
				var t := float(i) / RATE
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.15)
				samples[i] = lp * exp(-t * 16.0) * 0.5
		"horn":
			var n := int(RATE * 1.6)
			samples.resize(n)
			for i in n:
				var t := float(i) / RATE
				var env := clampf(t * 8.0, 0, 1) * clampf((1.6 - t) * 3.0, 0, 1)
				var vib := sin(TAU * 5.0 * t) * 2.0
				samples[i] = (sin(TAU * (110.0 + vib) * t) * 0.6 + sin(TAU * (165.0 + vib) * t) * 0.25) * env * 0.22
		"fire":
			var n := int(RATE * 1.0)
			samples.resize(n)
			var rng := RandomNumberGenerator.new(); rng.seed = 4
			for i in n:
				var t := float(i) / RATE
				samples[i] = rng.randf_range(-1, 1) * (0.15 + 0.1 * sin(t * 40.0)) * (1.0 - t) * 0.35
		_:
			samples.resize(64)
	return _wav(samples)


func _gen_calm() -> AudioStreamWAV:
	# 24-секундная петля: тёплые пэды, редкие щипковые ноты, дыхание мира.
	var dur := 24.0
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[146.83, 220.00, 293.66],  # Dm
		[130.81, 196.00, 261.63],  # C
		[174.61, 261.63, 349.23],  # F
		[196.00, 293.66, 392.00],  # G
	]
	var seg := dur / chords.size()
	for i in n:
		var t := float(i) / RATE
		var ci := clampi(int(t / seg), 0, chords.size() - 1)
		var lt := t - ci * seg
		var env := clampf(lt * 1.5, 0, 1) * clampf((seg - lt) * 1.3, 0, 1)
		var s := 0.0
		for j in chords[ci].size():
			var f: float = chords[ci][j]
			s += sin(TAU * f * t) * 0.05
			s += sin(TAU * f * 2.0 * t) * 0.012
			s += sin(TAU * f * 0.5 * t) * 0.018
		# мягкая атака волнами
		s *= env * (0.7 + 0.3 * sin(t * 0.7))
		out[i] = s
	# редкие ноты пентатоники
	var notes := [587.33, 659.25, 783.99, 880.0, 1046.5]
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for k in 22:
		var start := rng.randf_range(0.2, dur - 2.0)
		var f: float = notes[rng.randi() % notes.size()]
		var amp := rng.randf_range(0.04, 0.09)
		var idx := int(start * RATE)
		var ln := int(RATE * 1.6)
		for q in ln:
			if idx + q >= n:
				break
			var tt := float(q) / RATE
			var e := exp(-tt * 3.2) * (1.0 - exp(-tt * 40.0))
			out[idx + q] += (sin(TAU * f * tt) + 0.3 * sin(TAU * f * 2.01 * tt)) * e * amp
	# лёгкий фейд на границе петли
	var fade := int(RATE * 0.5)
	for i in fade:
		var a := float(i) / fade
		out[i] *= a
		out[n - 1 - i] *= a
	return _wav(out, true)


func _gen_tense() -> AudioStreamWAV:
	var dur := 24.0
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var drone := sin(TAU * 55.0 * t) * 0.05 + sin(TAU * 82.5 * t) * 0.025
		var pulse := pow(max(0.0, sin(t * PI * 1.15)), 14.0) * 0.09
		var s := drone + pulse * sin(TAU * 110.0 * t)
		# далёкие раскаты
		s += sin(TAU * 41.0 * t + sin(t * 0.4) * 3.0) * 0.035 * (0.5 + 0.5 * sin(t * 0.55))
		out[i] = s
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	for k in 14:
		var start := rng.randf_range(0.0, dur - 0.8)
		var idx := int(start * RATE)
		for q in int(RATE * 0.5):
			if idx + q >= n:
				break
			var tt := float(q) / RATE
			out[idx + q] += rng.randf_range(-1, 1) * exp(-tt * 14.0) * 0.025
	var fade := int(RATE * 0.5)
	for i in fade:
		var a := float(i) / fade
		out[i] *= a
		out[n - 1 - i] *= a
	return _wav(out, true)
