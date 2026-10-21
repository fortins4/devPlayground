class_name PrologueDawnSfx
extends RefCounted
## Raid day, step 4: what Cian hears waking at first light (placeholder procedural sounds, no
## imported audio, built once and cached; same pattern as BogSfx). Each cue also has a caption
## line (RaidSequence shows it on the HUD) so it reads without sound.
##   bark     a farm dog giving tongue hard (a run of rough barks)
##   yelp     the bark cut short: one high yelp, then nothing
##   blow     a horse blowing through its nose, far off
##   jingle   harness / bit rings and iron, faint
##   voices   low men's voices, far, the words not made out (not Irish — the caption says so)
##   cattle   the herd shifting and blowing in the pen (one lows: OpeningBoggedCowChore's moo)

const MIX_RATE := 22050
const MooScript := preload("res://scripts/prologue/opening_bogged_cow_chore.gd")

static var _cache: Dictionary = {}


static func stream(kind: StringName) -> AudioStream:
	if _cache.has(kind):
		return _cache[kind]
	var wav: AudioStream
	match kind:
		&"bark":
			wav = _build_barks()
		&"yelp":
			wav = _build_yelp()
		&"blow":
			wav = _build_blow()
		&"jingle":
			wav = _build_jingle()
		&"voices":
			wav = _build_voices()
		&"low":
			wav = MooScript._moo_wav()
		_:
			wav = _build_blow()
	_cache[kind] = wav
	return wav


## One-shot 3D player at `at`, freed when done.
static func play(host: Node, kind: StringName, at: Vector3, db: float = 0.0, unit: float = 8.0) -> AudioStreamPlayer3D:
	if host == null or not host.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(kind)
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = 220.0
	host.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p


static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


## One bark: a short harsh tone (falling pitch, rich harmonics) with a noisy attack.
static func _bark_into(out: PackedFloat32Array, start: int, f0: float, len_s: float, rng: RandomNumberGenerator, amp: float) -> void:
	var n := int(len_s * MIX_RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / len_s
		var f := f0 * (1.25 - 0.45 * u)
		ph += TAU * f / MIX_RATE
		var env := smoothstep(0.0, 0.01, t) * pow(1.0 - u, 1.6)
		var v: float = sin(ph) * 0.5 + sin(ph * 2.0) * 0.28 + sin(ph * 3.0) * 0.16 + signf(sin(ph)) * 0.12
		v += rng.randf_range(-1.0, 1.0) * (0.35 if t < 0.03 else 0.12)
		var k := start + i
		if k < out.size():
			out[k] += v * env * amp


static func _build_barks() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1169
	var out := PackedFloat32Array()
	out.resize(int(3.2 * MIX_RATE))
	var t := 0.05
	while t < 2.9:
		_bark_into(out, int(t * MIX_RATE), rng.randf_range(420.0, 520.0), rng.randf_range(0.12, 0.18), rng, 0.8)
		t += rng.randf_range(0.26, 0.42)
	return _pack(out)


static func _build_yelp() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var out := PackedFloat32Array()
	out.resize(int(0.6 * MIX_RATE))
	var ph := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var u := t / 0.6
		var f := 900.0 + 500.0 * sin(u * PI) - 400.0 * u
		ph += TAU * f / MIX_RATE
		var env := smoothstep(0.0, 0.015, t) * pow(1.0 - u, 2.4)
		out[i] = (sin(ph) * 0.6 + sin(ph * 2.0) * 0.2 + rng.randf_range(-0.1, 0.1)) * env
	return _pack(out)


static func _build_blow() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var out := PackedFloat32Array()
	out.resize(int(1.1 * MIX_RATE))
	var lp := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var u := t / 1.1
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
		var flutter := 0.6 + 0.4 * sin(TAU * 28.0 * t)
		out[i] = lp * flutter * smoothstep(0.0, 0.08, t) * pow(1.0 - u, 1.2) * 0.9
	return _pack(out)


static func _build_jingle() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var out := PackedFloat32Array()
	out.resize(int(1.2 * MIX_RATE))
	for hit in 5:
		var st := int(rng.randf_range(0.0, 0.9) * MIX_RATE)
		var f := rng.randf_range(2400.0, 3600.0)
		for i in int(0.25 * MIX_RATE):
			var k := st + i
			if k >= out.size():
				break
			var t := float(i) / MIX_RATE
			out[k] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.51 * t)) * exp(-t * 18.0) * 0.25
	return _pack(out)


## Men talking low and far: a few voiced syllables (formant-ish buzz), no words.
static func _build_voices() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1066
	var out := PackedFloat32Array()
	out.resize(int(3.0 * MIX_RATE))
	var t := 0.1
	while t < 2.7:
		var syl := rng.randf_range(0.12, 0.26)
		var f0 := rng.randf_range(95.0, 135.0)
		var form := rng.randf_range(450.0, 800.0)
		var st := int(t * MIX_RATE)
		var ph := 0.0
		for i in int(syl * MIX_RATE):
			var k := st + i
			if k >= out.size():
				break
			var tt := float(i) / MIX_RATE
			ph += TAU * f0 / MIX_RATE
			var env := sin(PI * tt / syl)
			var buzz := sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(TAU * form * tt) * 0.15 * (0.5 + 0.5 * sin(ph))
			out[k] += buzz * env * 0.35
		t += syl + rng.randf_range(0.03, 0.35)
	return _pack(out)
