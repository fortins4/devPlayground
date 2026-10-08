class_name BogSfx
extends RefCounted
## Placeholder procedural bog sounds (no imported audio). Built once, cached.
## splash = wet noise burst, squelch = low sucking bloop, gasp = breathy pant.

const MIX_RATE := 22050

static var _cache: Dictionary = {}


static func stream(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var wav: AudioStreamWAV
	match kind:
		&"squelch":
			wav = _build_squelch()
		&"gasp":
			wav = _build_gasp()
		_:
			wav = _build_splash()
	_cache[kind] = wav
	return wav


## One-shot 3D player at `at`, freed when done. strength 0..1.5 scales level.
static func play(host: Node, kind: StringName, at: Vector3, strength: float = 1.0) -> AudioStreamPlayer3D:
	if host == null or not host.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(kind)
	p.volume_db = linear_to_db(clampf(strength, 0.05, 1.6)) - (2.0 if kind == &"squelch" else 0.0)
	p.unit_size = 6.0 if kind == &"gasp" else 3.5
	p.max_distance = 40.0
	p.pitch_scale = randf_range(0.92, 1.08)
	host.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p


static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _build_splash() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7101
	var n := int(MIX_RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(1.0, t / 0.012) * exp(-t * 7.5)
		var w := rng.randf_range(-1.0, 1.0)
		# Two one-pole low-passes: dull, wet body rather than hiss.
		lp += (w - lp) * 0.32
		lp2 += (lp - lp2) * 0.45
		# A few sparse droplets in the tail.
		var drop := 0.0
		if t > 0.12 and rng.randf() < 0.0016:
			drop = rng.randf_range(0.4, 0.8)
		out[i] = (lp2 * 1.6 + drop) * env
	return _pack(out)


static func _build_squelch() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7102
	var n := int(MIX_RATE * 0.32)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := lerpf(210.0, 85.0, clampf(t / 0.28, 0.0, 1.0))
		phase += TAU * f / MIX_RATE
		var env := minf(1.0, t / 0.02) * exp(-t * 11.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		out[i] = (sin(phase) * 0.7 + lp * 0.9) * env
	return _pack(out)


static func _build_gasp() -> AudioStreamWAV:
	## In-breath gasp then two ragged pants. Band-limited noise with a vowel-ish hump.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7103
	var n := int(MIX_RATE * 1.25)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	var bands := [[0.0, 0.42, 1.0], [0.58, 0.82, 0.62], [0.92, 1.2, 0.48]]
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 0.0
		for b in bands:
			var a: float = b[0]
			var z: float = b[1]
			if t >= a and t <= z:
				var u := (t - a) / (z - a)
				env = maxf(env, sin(PI * u) * float(b[2]))
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.38
		var hp := lp - hp_prev * 0.92
		hp_prev = lp
		var voice := sin(TAU * 140.0 * t) * 0.15 * env
		out[i] = (hp * 1.4 + voice) * env
	return _pack(out)
