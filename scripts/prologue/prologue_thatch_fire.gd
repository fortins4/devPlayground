extends Node3D
class_name PrologueThatchFire
## Raid day, step 8: a roof of dry thatch fired from a brand at the eave. The fire takes at the
## point it was put to and runs up and round the roof over `grow_secs`: flames along the thatch
## (additive billboards), a thick grey-brown smoke column leaning off downwind, an orange light that
## flickers on the yard and the bank, the thatch charring dark, and the crackle. Wattle and thatch
## burn; the turf bank doesn't (nothing here touches it). Placeholder VFX: CPU particles, no
## imported textures.
## setup(): `points` are sample points on the roof surface (world); `top` the roof's crown.

const DawnSfx := preload("res://scripts/prologue/prologue_dawn_sfx.gd")

@export var grow_secs: float = 22.0

var _points: PackedVector3Array = PackedVector3Array()
var _start: Vector3 = Vector3.ZERO
var _top: Vector3 = Vector3.ZERO
var _char: Array[MeshInstance3D] = []
var _char_base: Array[Color] = []
var _flames: CPUParticles3D = null
var _embers: CPUParticles3D = null
var _smoke: CPUParticles3D = null
var _light: OmniLight3D = null
var _sound: AudioStreamPlayer3D = null
var _lit: bool = false
var _t: float = 0.0
var intensity: float = 0.0


func setup(points: PackedVector3Array, top: Vector3, char_meshes: Array) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_points = points
	_top = top
	for m in char_meshes:
		var mi := m as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat = mat.duplicate() as StandardMaterial3D
		mi.material_override = mat
		_char.append(mi)
		_char_base.append(mat.albedo_color)
	_build()


## Fired at `at` (the eave where the brand was put to it).
func ignite(at: Vector3) -> void:
	if _lit:
		return
	_lit = true
	_start = at
	_t = 0.0
	_flames.emitting = true
	_embers.emitting = true
	_smoke.emitting = true
	_light.visible = true
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = DawnSfx.stream(&"crackle")
	_sound.unit_size = 6.0
	_sound.max_distance = 120.0
	_sound.volume_db = -8.0
	add_child(_sound)
	_sound.global_position = at
	_sound.play()
	print("THATCH_FIRE_LIT %s at=%s" % [name, at])


func is_lit() -> bool:
	return _lit


func is_going() -> bool:
	return _lit and intensity > 0.6


func _process(delta: float) -> void:
	if not _lit:
		return
	_t += delta
	intensity = clampf(_t / grow_secs, 0.0, 1.0)
	var e := 0.15 + 0.85 * intensity
	# The fire spreads from the eave it was put to: only the roof points within `reach` emit.
	var reach := lerpf(1.2, 12.0, intensity)
	var pts := PackedVector3Array()
	for p in _points:
		if p.distance_to(_start) <= reach:
			pts.append(p)
	if pts.is_empty():
		pts.append(_start)
	_flames.emission_points = pts
	_embers.emission_points = pts
	# (CPUParticles3D has no amount_ratio: the fire grows by where it emits and how big.)
	_flames.scale_amount_min = 0.5 + 0.4 * e
	_flames.scale_amount_max = 0.9 + 0.9 * e
	_smoke.scale_amount_min = 1.2 + 1.2 * intensity
	_smoke.scale_amount_max = 1.8 + 1.8 * intensity
	# Smoke rises from the burning part, centred over it, more from the crown as it takes.
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	_smoke.global_position = c.lerp(_top, intensity * 0.6)
	_smoke.emission_sphere_radius = 0.6 + 2.2 * intensity
	var flick := 0.8 + 0.2 * sin(_t * 17.0) * sin(_t * 7.3 + 1.0)
	_light.global_position = c + Vector3(0, 1.0, 0)
	_light.light_energy = (1.2 + 3.8 * intensity) * flick
	_light.omni_range = 8.0 + 14.0 * intensity
	if _sound:
		_sound.volume_db = lerpf(-12.0, 2.0, intensity)
		_sound.global_position = c
	for i in _char.size():
		var mat := _char[i].material_override as StandardMaterial3D
		mat.albedo_color = _char_base[i].lerp(Color(0.1, 0.08, 0.07), clampf(intensity * 1.15 - 0.1, 0.0, 0.92))


func _build() -> void:
	# Flames: short-lived bright tongues licking up off the thatch.
	_flames = CPUParticles3D.new()
	_flames.name = "Flames"
	_flames.emitting = false
	_flames.amount = 260
	_flames.lifetime = 0.9
	_flames.local_coords = false
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_flames.emission_points = PackedVector3Array([Vector3.ZERO])
	_flames.direction = Vector3.UP
	_flames.spread = 18.0
	_flames.initial_velocity_min = 1.2
	_flames.initial_velocity_max = 2.6
	_flames.gravity = Vector3(0.3, 2.2, 0.0)
	_flames.scale_amount_min = 0.7
	_flames.scale_amount_max = 1.5
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1.0, 0.15))
	_flames.scale_amount_curve = sc
	var fr := Gradient.new()
	fr.set_color(0, Color(1.0, 0.78, 0.3, 0.95))
	fr.set_color(1, Color(0.55, 0.1, 0.02, 0.0))
	fr.add_point(0.35, Color(0.95, 0.42, 0.08, 0.85))
	_flames.color_ramp = fr
	var fq := QuadMesh.new()
	fq.size = Vector2(0.75, 1.1)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.disable_fog = true  # the flames glow through the mist
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_texture = _soft_tex(true)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.no_depth_test = false
	fq.material = fm
	_flames.mesh = fq
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)
	# Sparks / burning straws carried up.
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.emitting = false
	_embers.amount = 60
	_embers.lifetime = 3.0
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_embers.emission_points = PackedVector3Array([Vector3.ZERO])
	_embers.direction = Vector3.UP
	_embers.spread = 35.0
	_embers.initial_velocity_min = 2.0
	_embers.initial_velocity_max = 4.5
	_embers.gravity = Vector3(0.6, 0.6, 0.0)
	_embers.scale_amount_min = 0.05
	_embers.scale_amount_max = 0.12
	var er := Gradient.new()
	er.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	er.set_color(1, Color(0.6, 0.15, 0.02, 0.0))
	_embers.color_ramp = er
	var eq := QuadMesh.new()
	eq.size = Vector2(0.6, 0.6)
	eq.material = fm
	_embers.mesh = eq
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_embers)
	# Smoke column: big slow puffs, dark grey-brown, spreading and leaning off downwind.
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.emitting = false
	_smoke.amount = 160
	_smoke.lifetime = 11.0
	_smoke.preprocess = 0.0
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 1.0
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 1.6
	_smoke.initial_velocity_max = 2.6
	_smoke.gravity = Vector3(0.55, 0.35, 0.15)
	_smoke.damping_min = 0.05
	_smoke.damping_max = 0.15
	_smoke.scale_amount_min = 2.0
	_smoke.scale_amount_max = 3.2
	var ss := Curve.new()
	ss.add_point(Vector2(0.0, 0.35))
	ss.add_point(Vector2(1.0, 1.0))
	_smoke.scale_amount_curve = ss
	var sr := Gradient.new()
	sr.set_color(0, Color(0.16, 0.13, 0.11, 0.0))
	sr.set_color(1, Color(0.42, 0.41, 0.4, 0.0))
	sr.add_point(0.06, Color(0.17, 0.14, 0.12, 0.95))
	sr.add_point(0.55, Color(0.3, 0.28, 0.27, 0.75))
	_smoke.color_ramp = sr
	var sq := QuadMesh.new()
	sq.size = Vector2(3.6, 3.6)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = _soft_tex(false)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sq.material = sm
	_smoke.mesh = sq
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(60, 60, 60))
	_flames.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 20, 30))
	_embers.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 30, 30))
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = Color(1.0, 0.55, 0.22)
	_light.light_energy = 0.0
	_light.omni_range = 10.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


static var _tex_cache: Dictionary = {}


## Soft round blob (flame: hot centre, smoke: soft cloud) as a small generated texture.
static func _soft_tex(hot: bool) -> Texture2D:
	if _tex_cache.has(hot):
		return _tex_cache[hot]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 if hot else 43
	for y in n:
		for x in n:
			var dx := (float(x) + 0.5) / n * 2.0 - 1.0
			var dy := (float(y) + 0.5) / n * 2.0 - 1.0
			var r := 0.0
			if hot:
				# Tongue: narrower towards the top.
				r = sqrt(dx * dx / maxf(0.15, 0.55 + dy * 0.4) + dy * dy)
			else:
				r = sqrt(dx * dx + dy * dy) + rng.randf_range(-0.06, 0.06)
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[hot] = tex
	return tex
