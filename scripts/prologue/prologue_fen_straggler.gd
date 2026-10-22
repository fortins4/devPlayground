extends Node3D
## Raid day, step 9 (raid-option1-spec.md): the straggler at the tóchar fen.
##
## The drove goes by on the lane past Bend8. The cow that bogged in the opening (cow_id 6, still
## stiff from it) lags, breaks west into the tóchar fen where Cian has the household down in the
## reeds, and bogs to the hocks at the margin of the deep pool. One Welsh archer comes after her
## alone — wild-elm self-bow slung on his back, long knife at his belt, padded jack with a low
## collar — and his way in passes near the hide. At the margin he stands bent over her, hauling
## by the horn and the rope, both hands busy, his back to the reeds; her bawling covers small
## noise (his hearing shrinks to HEAR_LOWING while she lows).
##
## Three paths, all open (no HUD preference):
##  killed  Cian reaches his back unseen with the knife drawn → E: a hand over the mouth, a cut to
##          the side of the neck above the jack's collar (all TAKEDOWN_* requirements hold). The
##          camera cuts to Cian's face and the reeds; a muffled struggle ~2.6 s, then still.
##  spared  lie still (crouched / under the water, Máire and the girl down beside him): he works
##          her free and leads her off the way he came; or a stone (G) into the reeds the other way
##          (≥ LURE_FAR_FROM_HIDE from the household): he looks, frees her quickly and goes.
##  fought  an open fight, or noticed on the approach (SUSPICIOUS: he turns, the window closes,
##          and if Cian is near or he goes ALERT it is face to face). The goad holds him off a
##          moment (FENDS_MAX fends), the knife can't close on a man with a long knife: within a
##          few exchanges Cian is cut; the horn sounds on the lane; he backs off with the cow,
##          alive (cut → deep if Cian kept at him).
## Emits `cian_struck(amount, tag, from)` for each cut (the raid applies it, with its below-20 HP
## fade) and `finished(outcome, flags)` once it is over. Nothing after step 9 is built here.

signal finished(outcome: StringName, flags: Dictionary)
signal cian_struck(amount: float, tag: StringName, from: Node3D)

const VillagerScript := preload("res://scripts/prologue/prologue_villager.gd")
const SensorScript := preload("res://systems/stealth/detection_sensor.gd")
const BogZoneScript := preload("res://systems/stealth/bog_zone.gd")
const Sfx := preload("res://scripts/prologue/prologue_dawn_sfx.gd")
const Terrain := preload("res://scripts/prologue/opening_terrain.gd")

const SEQ_STEP := &"fen"

# ---- the place (decision 13: the fen edge at (−55, 160) in the west wood; the tóchar at z 160)
const POOL_C := Vector3(-55.0, 0.0, 165.2)
const POOL_R := 2.6                       ## deep-water outline radius (BogZone, ~1.5–2 m deep)
const COW_AT := Vector3(-52.35, 0.0, 165.2) ## bogged at the pool's east margin, facing out
const HAUL_AT := Vector3(-51.15, 0.0, 165.25) ## he stands east of her, bent, facing west
const HAUL_YAW := PI * 0.5               ## facing −X (the rig faces −Z)
## The reed bed (a common-reed stand ~1.6–2.1 m) east of the pool, along his back.
const REED_MIN := Vector2(-50.45, 162.6)
const REED_MAX := Vector2(-44.0, 172.2)
const REED_TOP := 1.75
const REED_HIDE_DEPTH := 1.4              ## this much reed between eye and target hides it
const HIDE_CIAN := Vector3(-47.2, 0.0, 168.9)
const HIDE_MAIRE := Vector3(-47.55, 0.0, 169.85)
const HIDE_GIRL := Vector3(-46.65, 0.0, 170.05)
const CIAN_YAW := 0.82                    ## looking down toward the pool margin
## The lane (spec PathMarkers Bend7 → Bend8 → PastureMouth) and the drove's way on north.
const DROVE_WAY: Array[Vector3] = [Vector3(-16.0, 0.0, 164.0), Vector3(-28.0, 0.0, 178.0), Vector3(-33.0, 0.0, 192.0), Vector3(-36.0, 0.0, 206.0)]
const DROVE_START := Vector3(-4.0, 0.0, 152.0)
const COW_IN: Array[Vector3] = [Vector3(-38.0, 0.0, 166.6), Vector3(-45.6, 0.0, 165.4), Vector3(-50.7, 0.0, 165.15), COW_AT]
const COW_START := Vector3(-35.0, 0.0, 166.6)
const ARCHER_START := Vector3(-28.0, 0.0, 166.4)
const ARCHER_IN: Array[Vector3] = [Vector3(-40.0, 0.0, 166.4), Vector3(-46.0, 0.0, 165.6), HAUL_AT]
const ARCHER_OUT: Array[Vector3] = [Vector3(-46.0, 0.0, 165.4), Vector3(-40.0, 0.0, 166.2), Vector3(-30.0, 0.0, 166.5), Vector3(-18.0, 0.0, 165.0), Vector3(-24.0, 0.0, 174.0)]
const ARCHER_DELAY := 3.0                 ## he comes off the lane after her this long in
const GONE_DIST := 24.0                   ## away from the hide this far = gone

# ---- the archer
const VIEW_HALF := 55.0
const VIEW_DIST := 60.0
const HEAR_QUIET := 2.6                   ## m — between her bawls
const HEAR_LOWING := 0.9                  ## m — while she bawls (covers small noise)
const LOW_PERIOD := 3.6
const LOW_ON := 1.8
const HAUL_SECS := 38.0                   ## lying still: he works her free in this long
const FREE_SECS := 3.0                    ## the last heave, out of the mud
## Bogged: how far she is down in the margin mud (visual, opening_cow.visual_sink): hooves and
## lower legs under, the belly at the mud's surface. Eases in as she founders, out as she's freed.
const COW_SINK := 0.5
const COW_SINK_RATE := 0.45               ## m/s
const SUSPICIOUS_LOOK := 3.0              ## turned to look this long before going back to her
const NOTICE_NEAR := 4.5                  ## SUSPICIOUS with Cian this near → face to face
const FIND_DIST := 2.4                    ## he walks this near Máire / the girl → found
# ---- takedown (spec step 9.6)
const TAKEDOWN_REACH := 1.0
const TAKEDOWN_REAR_DEG := 60.0
const TAKEDOWN_GRAB := 1.0                ## hand over the mouth, the cut (Cian's motion)
const TAKEDOWN_CUTAWAY := 2.6             ## on Cian's face and the reeds: the struggle, then still
# ---- lure
const STONE_CD := 1.6
const STONE_THROW := 11.0
const STONE_FLIGHT := 0.75
const LURE_FAR_FROM_HIDE := 6.0
const LURE_HEARD := 26.0
const LURE_LOOK := 1.8
# ---- fight (decision 6: even the lone archer beats Cian face to face)
const FIGHT_GAP := 1.3
const FIGHT_STEP := 1.7
const CUT_WINDUP := 0.55
const CUT_EVERY := 1.6
const CUT_REACH := 1.75
const COUNTER_WINDUP := 0.25
const FENDS_MAX := 2                      ## the goad holds him off this many times, then no more
const CUT_DMG := 14.0
const DEEP_DMG := 18.0
const HORN_AFTER := 1.5
const BACK_OFF_SECS := 2.4
const ARCHER_HP_FLOOR := 45.0             ## padded jack, and he isn't killed face to face
const WELSH_COW := "Dere, dere… dere 'mlaen."
const WELSH_WHO := "Pwy sy 'na?"
const WELSH_FIGHT := "Ha! Dere 'ma, fachgen."

enum S { IDLE, WALK_IN, HAUL, LOOK, LURED, FREE, LEAVE, TAKEDOWN, FIGHT, BACK_OFF, DONE }

var _raid: Node = null
var _player: CharacterBody3D = null
var _maire: Node3D = null
var _girl: Node3D = null
var _cow: Node3D = null
var _drove_cows: Array = []
var _drove_i: Dictionary = {}
var _drovers: Array = []
var archer: Node3D = null
var sensor: Node3D = null
var _acombat: Node = null
var pool: Area3D = null
var _rope: MeshInstance3D = null
var _mud: Node3D = null
var _mist: Array = []
var _cut_cam: Camera3D = null

var _state: S = S.IDLE
var _t: float = 0.0
var _st: float = 0.0
var _cow_i: int = 0
var _cow_bogged: bool = false
var _low_t: float = 0.0
var _haul_t: float = 0.0
var _lowing_left: float = 0.0
var _stone_cd: float = 0.0
var _stones: Array = []
var _lure_point: Vector3 = Vector3.INF
var _lure_near_hide: bool = false
var _out_i: int = 0
var _outcome: StringName = &""
var _flags: Dictionary = {}
var _cuts: int = 0
var _fends: int = 0
var _cut_phase: String = ""
var _cut_t: float = 0.0
var _horn_t: float = -1.0
var _horned: bool = false
var _kept_fighting: bool = false
var _seen_face: bool = false
var _stagger_t: float = 0.0
var _found: bool = false
var _aborted: bool = false
var _hooked: bool = false
var _started: bool = false
var stats := {"max_meter": 0.0, "suspicious": 0, "lures": 0, "stones": 0, "fends": 0, "cuts": 0, "counter": 0}


func _ready() -> void:
	add_to_group("prologue_chore")
	add_to_group("prologue_fen")


# ---------------------------------------------------------------- set-up (under the black)

## Build the fen's set and put everyone in place: household down in the reeds, the drove on the
## lane, the cow (and later the archer) coming in. Called by the raid under the black.
func setup(raid: Node, player: CharacterBody3D, maire: Node3D, girl: Node3D, cows: Array, palette: Dictionary) -> void:
	_raid = raid
	_player = player
	_maire = maire
	_girl = girl
	_build_pool()
	_build_reeds()
	_build_mist()
	_pick_cows(cows)
	_spawn_drovers(palette)
	_spawn_archer(palette)
	_place_household()
	_hook_combat()
	_state = S.IDLE
	print("FEN_SETUP pool=%s cow=%s archer=%s" % [pool.global_position, _cow.name if _cow else "none", archer.global_position])


func start() -> void:
	_t = 0.0
	_state = S.IDLE
	_started = true
	print("FEN_START")


func abort() -> void:
	_aborted = true
	if archer:
		archer.call("say", "", 0.1)


func is_resolved() -> bool:
	return _outcome != &""


func outcome() -> StringName:
	return _outcome


func state_name() -> String:
	return S.keys()[_state]


func cow() -> Node3D:
	return _cow


func cow_bogged() -> bool:
	return _cow_bogged


func is_lowing() -> bool:
	return _lowing_left > 0.0


func awareness() -> int:
	return int(sensor.get("awareness")) if sensor else 0


func meter() -> float:
	return float(sensor.get("meter")) if sensor else 0.0


func hide_point() -> Vector3:
	return HIDE_CIAN


func haul_point() -> Vector3:
	return HAUL_AT


func cutaway_active() -> bool:
	return _cut_cam != null and _cut_cam.current


func _ground(p: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, Terrain.surface_y(p.x, p.z) + lift, p.z)


func _build_pool() -> void:
	pool = BogZoneScript.new()
	pool.name = "FenDeepPool"
	pool.set("label_text", "")
	pool.set("deep_water", true)
	pool.set("water_level", 0.06)
	pool.set("deep_radius", POOL_R)
	pool.set("deep_edge_margin", 0.45)
	pool.set("build_water_visual", true)
	pool.set("hide_sink_depth", 1.7)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = POOL_R
	cyl.height = 2.0
	cs.shape = cyl
	pool.add_child(cs)
	add_child(pool)
	pool.global_position = _ground(POOL_C)
	var bl := pool.get_node_or_null("BogLabel") as Label3D
	if bl:
		bl.visible = false


func _in_reeds(x: float, z: float) -> bool:
	if x < REED_MIN.x or x > REED_MAX.x or z < REED_MIN.y or z > REED_MAX.y:
		return false
	# Ragged edges: the stand thins out over the last ~0.6 m.
	var edge := minf(minf(x - REED_MIN.x, REED_MAX.x - x), minf(z - REED_MIN.y, REED_MAX.y - z))
	return edge > 0.25 + 0.3 * (0.5 + 0.5 * sin(x * 2.3 + z * 1.7))


## DetectionSensor cover hook: Cian under the pool's water is hidden; reeds between his eye and Cian hide him (a crouched man in a reed
## bed is lost at a few metres; at arm's length they don't hide anyone; standing, the head shows).
func _reed_cover(eye: Vector3, aim: Vector3) -> float:
	# Under the peat-brown water nothing shows (PlayerBogSubmerge puts the aim at the head).
	if pool and bool(pool.call("is_in_water", aim)) and aim.y <= float(pool.call("water_surface_y")) + 0.06:
		return 0.0
	var d := eye.distance_to(aim)
	var inside := 0.0
	var n := 14
	for i in n:
		var p := eye.lerp(aim, (float(i) + 0.5) / float(n))
		if _in_reeds(p.x, p.z) and p.y < Terrain.surface_y(p.x, p.z) + REED_TOP:
			inside += d / float(n)
	if inside <= 0.0:
		return 1.0
	var f := clampf(1.0 - inside / REED_HIDE_DEPTH, 0.03, 1.0)
	if aim.y - Terrain.surface_y(aim.x, aim.z) > 1.2:
		f = maxf(f, 0.45)
	if d < 1.3:
		f = maxf(f, 0.5)
	return f


func _build_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 916
	var stems: Array = []
	var area := (REED_MAX.x - REED_MIN.x) * (REED_MAX.y - REED_MIN.y)
	var want := int(area * 15.0)
	var tries := 0
	while stems.size() < want and tries < want * 4:
		tries += 1
		var x := rng.randf_range(REED_MIN.x, REED_MAX.x)
		var z := rng.randf_range(REED_MIN.y, REED_MAX.y)
		if not _in_reeds(x, z) and rng.randf() > 0.2:
			continue
		# A trodden gap where he stands to haul (his heels at the stand's edge).
		if Vector2(x - HAUL_AT.x, z - HAUL_AT.z).length() < 0.45:
			continue
		stems.append(Vector3(x, Terrain.surface_y(x, z) - 0.05, z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.016, 1.0, 0.016)
	mm.mesh = bm
	mm.instance_count = stems.size()
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.use_colors = true
	var hm := BoxMesh.new()
	hm.size = Vector3(0.03, 0.22, 0.03)
	heads.mesh = hm
	heads.instance_count = stems.size()
	for i in stems.size():
		var base: Vector3 = stems[i]
		var h := rng.randf_range(1.45, 2.1)
		var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.16, 0.16), rng.randf() * TAU, rng.randf_range(-0.16, 0.16)))
		mm.set_instance_transform(i, Transform3D(tilt.scaled(Vector3(1.0, h, 1.0)), base + tilt * Vector3(0.0, h * 0.5, 0.0)))
		var g := rng.randf_range(0.0, 1.0)
		mm.set_instance_color(i, Color(0.42, 0.44, 0.27).lerp(Color(0.6, 0.55, 0.38), g))
		heads.set_instance_transform(i, Transform3D(tilt * Basis.from_euler(Vector3(0.25, 0, 0)), base + tilt * Vector3(0.0, h + 0.08, 0.0)))
		heads.set_instance_color(i, Color(0.38, 0.3, 0.26).lerp(Color(0.55, 0.47, 0.38), g))
	for pair in [[mm, "FenReeds"], [heads, "FenReedHeads"]]:
		var mi := MultiMeshInstance3D.new()
		mi.name = pair[1]
		mi.multimesh = pair[0]
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.roughness = 0.95
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	print("FEN_REEDS stems=%d" % stems.size())


## Low fen mist: soft grey sheets drifting knee-to-chest high over the pool and the reeds.
func _build_mist() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 3310
	for i in 16:
		var q := QuadMesh.new()
		q.size = Vector2(rng.randf_range(7.0, 12.0), rng.randf_range(1.6, 2.6))
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.albedo_texture = tex
		mat.albedo_color = Color(0.8, 0.82, 0.84, rng.randf_range(0.22, 0.38))
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.2
		var mi := MeshInstance3D.new()
		mi.name = "FenMist%d" % i
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 18.0)
		var p := Vector3(-50.0 + cos(a) * r * 1.3, 0.0, 166.0 + sin(a) * r)
		add_child(mi)
		mi.global_position = _ground(p, rng.randf_range(0.55, 1.05))
		mi.set_meta("drift", Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(0.04, 0.16)))
		mi.set_meta("home", mi.global_position)
		_mist.append(mi)


func _pick_cows(cows: Array) -> void:
	var chore := get_tree().get_first_node_in_group("opening_bogged_cow")
	if chore and chore.has_method("get_chore_cow"):
		_cow = chore.call("get_chore_cow") as Node3D
	if _cow == null:
		for c in cows:
			if int((c as Node).get("cow_id")) == 6:
				_cow = c
	if _cow == null and not cows.is_empty():
		_cow = cows.back()
	var k := 0
	for c in cows:
		var cow := c as Node3D
		if cow == _cow or cow == null:
			continue
		_drove_cows.append(cow)
		_drove_i[cow] = 0
		_cow_reset(cow)
		cow.global_position = _ground(DROVE_START + Vector3(-1.6 * (k % 2), 0.0, 3.0 * k), 0.15)
		cow.set("delivered", true)
		cow.call("set_pen_slot", DROVE_WAY[0])
		k += 1
	if _cow:
		_cow_reset(_cow)
		_cow.global_position = _ground(COW_START, 0.15)
		_cow.set("delivered", true)
		_cow.call("set_pen_slot", COW_IN[0])
		_cow.visible = true


func _cow_reset(cow: Node3D) -> void:
	cow.visible = true
	cow.process_mode = Node.PROCESS_MODE_INHERIT
	cow.set("bog_hold_still", false)
	cow.set("bogged", false)
	cow.set("goad_locked", true)
	if cow is CharacterBody3D:
		(cow as CharacterBody3D).velocity = Vector3.ZERO


func _spawn_drovers(palette: Dictionary) -> void:
	for i in 2:
		var v: Node3D = VillagerScript.new()
		v.name = "FenDrover_%d" % i
		v.set("display_name", "")
		v.set("palette", palette.get("serjeant", {}) if i == 0 else palette.get("archer2", {}))
		v.set("stature_m", 1.7)
		v.set("walk_speed", 1.35)
		v.set("kit", [&"spear", &"nasal_helm"] if i == 0 else [&"bow", &"arrow_bag", &"cap"])
		add_child(v)
		v.call("place", _ground(DROVE_START + Vector3(1.2 * i, 0.0, -4.0 - 1.5 * i)), PI)
		v.call("walk_path", DROVE_WAY.duplicate())
		_drovers.append(v)


func _spawn_archer(palette: Dictionary) -> void:
	archer = VillagerScript.new()
	archer.name = "FenStraggler"
	archer.set("display_name", "")
	archer.set("palette", palette.get("archer", {}))
	archer.set("stature_m", 1.69)
	archer.set("walk_speed", 1.5)
	archer.set("kit", [&"bow", &"bow_slung", &"long_knife", &"jack", &"cap", &"arrow_bag"])
	archer.set_meta("role", &"archer")
	archer.set_meta("armour", &"padded")
	add_child(archer)
	archer.call("place", _ground(ARCHER_START), HAUL_YAW)
	archer.visible = false
	# Hurtbox + combat body (as the raiders'): padded jack.
	var hb := Area3D.new()
	hb.name = "Hurtbox"
	hb.collision_layer = 4
	hb.collision_mask = 0
	hb.monitorable = true
	hb.monitoring = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	hb.add_child(cs)
	archer.add_child(hb)
	var cb := CombatSystem.new()
	cb.name = "CombatSystem"
	cb.team = 1
	cb.starting_weapon = CombatSystem.Weapon.UNARMED
	cb.show_damage_numbers = false
	cb.armour = &"padded"
	archer.add_child(cb)
	_acombat = cb
	sensor = SensorScript.new()
	sensor.name = "DetectionSensor"
	sensor.set("show_debug_cone", false)
	sensor.set("view_distance", VIEW_DIST)
	sensor.set("view_half_angle_deg", VIEW_HALF)
	sensor.set("eye_height", 1.5)
	sensor.set("hearing_range", HEAR_QUIET)
	sensor.set("light_factor", 0.5)
	sensor.set("low_mist_top", 1.4)
	sensor.set("low_mist_hide_beyond", 22.0)
	archer.add_child(sensor)
	sensor.set("cover_factor", Callable(self, "_reed_cover"))
	var lbl := sensor.get_node_or_null("AwarenessLabel") as Node3D
	if lbl:
		lbl.visible = false
	sensor.process_mode = Node.PROCESS_MODE_DISABLED
	# The rope from his fist to her horns.
	_rope = MeshInstance3D.new()
	_rope.name = "HaulRope"
	var rb := BoxMesh.new()
	rb.size = Vector3(0.02, 0.02, 1.0)
	_rope.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.5, 0.42, 0.3)
	_rope.material_override = rm
	_rope.top_level = true
	_rope.visible = false
	add_child(_rope)


func _place_household() -> void:
	if _player:
		_player.global_position = _ground(HIDE_CIAN, 0.05)
		_player.rotation.y = CIAN_YAW
		_player.velocity = Vector3.ZERO
		var pivot := _player.get_node_or_null("CameraPivot") as Node3D
		if pivot:
			pivot.rotation.x = deg_to_rad(-10.0)
	if _maire:
		_maire.call("place_at", HIDE_MAIRE, CIAN_YAW)
		_maire.call("set_crouch", true)
	if _girl:
		_girl.call("follow", null, Vector3.ZERO, 0.0)
		_girl.call("place", _ground(HIDE_GIRL), CIAN_YAW)
		_girl.call("set_crouch", true)


func _hook_combat() -> void:
	if _hooked or _player == null:
		return
	var c: Node = _player.get("combat")
	if c == null:
		return
	_hooked = true
	c.connect("attack_performed", _on_player_attack)
	c.connect("hit_landed", _on_player_hit)


# ---------------------------------------------------------------- HUD contract (prologue_chore)

func _open() -> bool:
	return _raid != null and _started and bool(_raid.call("is_step_active", SEQ_STEP)) and _state != S.DONE and _outcome == &"" and not _aborted


func is_active() -> bool:
	return _open()


func interact_prompt() -> String:
	if _open() and can_takedown():
		return "E — from behind: a hand over his mouth, the knife"
	return ""


func objective_text() -> String:
	if not _open():
		return ""
	match _state:
		S.TAKEDOWN:
			return ""
		S.FIGHT, S.BACK_OFF:
			return "He has his knife out."
	return "Keep him from finding Máire and your sister.  (G throws a stone.)"


## All of spec step 9.6, checked live.
func takedown_check() -> Dictionary:
	var r := {"unaware": false, "rear": false, "near": false, "occupied": false, "knife": false}
	if archer == null or _player == null:
		return r
	r["unaware"] = awareness() == 0
	var to := _player.global_position - archer.global_position
	to.y = 0.0
	var d := to.length()
	r["near"] = d <= TAKEDOWN_REACH
	var fwd := -archer.global_transform.basis.z
	fwd.y = 0.0
	if d > 0.01 and fwd.length() > 0.01:
		var ang := rad_to_deg(fwd.normalized().angle_to(to / d))
		r["rear"] = ang >= 180.0 - TAKEDOWN_REAR_DEG
	r["occupied"] = _state == S.HAUL and _cow_bogged
	var c: Node = _player.get("combat")
	r["knife"] = c != null and int(c.get("current_weapon")) == 1
	return r


func can_takedown() -> bool:
	if _state != S.HAUL or bool(_player.call("is_input_locked")):
		return false
	var r := takedown_check()
	for k in r:
		if not bool(r[k]):
			return false
	return true


func _input(event: InputEvent) -> void:
	if not _open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_E and try_takedown():
			get_viewport().set_input_as_handled()
		elif kc == KEY_G and throw_stone():
			get_viewport().set_input_as_handled()


func try_interact() -> bool:
	return try_takedown()


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if _raid == null or _aborted:
		return
	if not _started or not bool(_raid.call("is_step_active", SEQ_STEP)):
		return
	_t += delta
	_st += delta
	_stone_cd = maxf(0.0, _stone_cd - delta)
	_tick_mist(delta)
	_tick_drove()
	_tick_stones(delta)
	_tick_cow(delta)
	if sensor and sensor.process_mode != Node.PROCESS_MODE_DISABLED:
		sensor.set("hearing_range", HEAR_LOWING if _lowing_left > 0.0 else HEAR_QUIET)
		stats["max_meter"] = maxf(float(stats["max_meter"]), meter())
	match _state:
		S.IDLE:
			if _t >= ARCHER_DELAY:
				archer.visible = true
				archer.call("walk_path", ARCHER_IN.duplicate())
				sensor.process_mode = Node.PROCESS_MODE_INHERIT
				_to(S.WALK_IN)
		S.WALK_IN:
			_tick_walk_in()
		S.HAUL:
			_tick_haul(delta)
		S.LOOK:
			_tick_look()
		S.LURED:
			_tick_lured()
		S.FREE:
			_tick_free()
		S.LEAVE:
			_tick_leave()
		S.TAKEDOWN:
			_tick_takedown()
		S.FIGHT:
			_tick_fight(delta)
		S.BACK_OFF:
			_tick_back_off(delta)
	_tick_rope()


func _to(s: S) -> void:
	_state = s
	_st = 0.0
	print("FEN_STATE %s t=%.1f" % [S.keys()[s], _t])


func _tick_mist(_delta: float) -> void:
	for m in _mist:
		var mi := m as Node3D
		var dr: Vector2 = mi.get_meta("drift")
		var home: Vector3 = mi.get_meta("home")
		mi.global_position = home + Vector3(sin(_t * 0.05 * (1.0 + dr.x) + home.x) * 2.5, sin(_t * 0.3 + home.z) * 0.05, sin(_t * 0.04 * (1.0 + dr.y) + home.z) * 1.8)


func _tick_drove() -> void:
	for c in _drove_cows:
		var cow := c as Node3D
		if not cow.visible:
			continue
		var i := int(_drove_i[cow])
		if i >= DROVE_WAY.size():
			cow.visible = false
			cow.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		var tgt: Vector3 = DROVE_WAY[i]
		if Vector2(cow.global_position.x - tgt.x, cow.global_position.z - tgt.z).length() < 1.6:
			_drove_i[cow] = i + 1
			if i + 1 < DROVE_WAY.size():
				cow.call("set_pen_slot", DROVE_WAY[i + 1])
		else:
			cow.call("set_pen_slot", tgt)
	for v in _drovers:
		var d := v as Node3D
		if d.visible and not bool(d.call("is_walking")):
			d.visible = false
			d.process_mode = Node.PROCESS_MODE_DISABLED


func _tick_cow(delta: float) -> void:
	if _cow == null:
		return
	_lowing_left = maxf(0.0, _lowing_left - delta)
	var sink_to := COW_SINK if _cow_bogged else 0.0
	if _cow_bogged and _state == S.FREE:
		sink_to = COW_SINK * (1.0 - 0.5 * clampf(_st / FREE_SECS, 0.0, 1.0))  # the last heave lifts her
	_cow.set("visual_sink", move_toward(float(_cow.get("visual_sink")), sink_to, COW_SINK_RATE * delta))
	if not _cow_bogged:
		if _state in [S.IDLE, S.WALK_IN] and _cow_i < COW_IN.size():
			var tgt: Vector3 = COW_IN[_cow_i]
			if Vector2(_cow.global_position.x - tgt.x, _cow.global_position.z - tgt.z).length() < (0.5 if _cow_i == COW_IN.size() - 1 else 1.2):
				_cow_i += 1
				if _cow_i >= COW_IN.size():
					_bog_cow()
					return
				tgt = COW_IN[_cow_i]
			_cow.call("set_pen_slot", tgt)
		return
	# Bogged: she bawls (the haul has her frightened), on a cycle.
	_low_t += delta
	if _low_t >= LOW_PERIOD:
		_low_t = 0.0
		_lowing_left = LOW_ON
		Sfx.play(self, &"low", _cow.global_position + Vector3(0, 1.0, 0), 2.0, 10.0)


func _bog_cow() -> void:
	_cow_bogged = true
	_cow.set("delivered", false)
	_cow.set("driven", false)
	_cow.call("set_bogged", true)
	_cow.set("bog_hold_still", true)
	if _cow is CharacterBody3D:
		(_cow as CharacterBody3D).velocity = Vector3.ZERO
	_cow.global_position = _ground(COW_AT, 0.05)
	_cow.look_at(_ground(COW_AT + Vector3(1.0, 0, 0), 0.05), Vector3.UP)
	_low_t = LOW_PERIOD - 0.3
	# No "bogged!" status word over her in the prologue's fen (the scene has no world tags).
	var lb := _cow.get("label") as VisualInstance3D
	if lb:
		lb.layers = 0  # the cow keeps rewriting its text / colour; off every camera instead
	# Down past the knees in the black margin mud (she sinks into it: visual_sink, _tick_cow).
	_mud = Node3D.new()
	_mud.name = "CowMud"
	add_child(_mud)
	_mud.global_position = _ground(COW_AT, 0.0)
	# A wide, nearly flat skin of wet churned mud round her, its top a few cm over the turf (at
	# her sunk belly), the rim under the turf; a lip of churned lumps at her flanks.
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.13, 0.1, 0.065)
	mm.roughness = 0.72  # wet, but not a mirror
	_mud.rotation.y = PI * 0.5
	for lump in [[Vector3(0.0, -0.15, 0.0), Vector3(1.1, 0.22, 1.5)], [Vector3(0.5, -0.03, 0.3), Vector3(0.22, 0.13, 0.32)], [Vector3(-0.5, -0.03, -0.35), Vector3(0.22, 0.12, 0.34)], [Vector3(-0.15, -0.04, -0.98), Vector3(0.32, 0.12, 0.22)]]:
		var mud := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 1.0
		cm.height = 2.0
		cm.radial_segments = 12
		cm.rings = 6
		mud.mesh = cm
		mud.position = lump[0]
		mud.scale = lump[1]
		mud.material_override = mm
		_mud.add_child(mud)
	print("FEN_COW_BOGGED at=%s" % _cow.global_position)


func _cow_free_follow() -> void:
	if _cow == null:
		return
	_cow_bogged = false
	_cow.set("bog_hold_still", false)
	_cow.set("bogged", false)
	_cow.set("delivered", true)
	if _mud:
		_mud.visible = false


func _cow_lead(off: float = 1.6) -> void:
	if _cow == null or _cow_bogged:
		return
	var back := archer.global_transform.basis.z
	back.y = 0.0
	_cow.call("set_pen_slot", archer.global_position + back.normalized() * off)


func _horn_point() -> Vector3:
	if _cow == null:
		return archer.global_position + Vector3(-1, 1, 0)
	return _cow.global_position + (-_cow.global_transform.basis.z) * 0.55 + Vector3(0, 0.85 - float(_cow.get("visual_sink")) * 0.75, 0)  # opening_cow.HEAD_SINK_K


func _tick_rope() -> void:
	var on := _state in [S.HAUL, S.FREE, S.LOOK] and _cow_bogged and archer.visible
	_rope.visible = on
	if not on:
		return
	var a: Vector3 = archer.call("left_hand").global_position if archer.call("left_hand") else archer.global_position + Vector3(0, 1, 0)
	var b := _horn_point()
	var d := b - a
	if d.length() < 0.05:
		return
	_rope.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP).scaled(Vector3(1, 1, d.length())), (a + b) * 0.5)


# ---------------------------------------------------------------- the archer

func _haul_pose(on: bool, heave: float = 0.0) -> void:
	archer.call("set_crouch", on)
	if on:
		var hp := _horn_point()
		archer.call("reach_right", hp, 1.0)
		archer.call("reach_left", hp + Vector3(0, -0.12, 0.1), 1.0)
		archer.call("set_lean", -0.3 * heave)
	else:
		archer.call("reach_right", Vector3.ZERO, 0.0)
		archer.call("reach_left", Vector3.ZERO, 0.0)
		archer.call("set_lean", 0.0)


func _tick_walk_in() -> void:
	if _check_noticed():
		return
	_check_found()
	if not bool(archer.call("is_walking")) and _cow_bogged:
		archer.call("place", _ground(HAUL_AT), HAUL_YAW)
		archer.call("face_yaw", HAUL_YAW)
		_haul_t = 0.0
		archer.call("say", WELSH_COW, 3.0)
		_to(S.HAUL)


func _tick_haul(delta: float) -> void:
	_haul_t += delta
	var heave := 0.5 + 0.5 * sin(_haul_t * 2.2)
	_haul_pose(true, heave)
	archer.call("face_yaw", HAUL_YAW)
	if _check_noticed():
		return
	if _lure_point != Vector3.INF:
		_haul_pose(false)
		stats["lures"] = int(stats["lures"]) + 1
		archer.call("face_point", _lure_point)
		archer.call("say", WELSH_WHO, 2.5)
		_to(S.LURED)
		return
	if _haul_t >= HAUL_SECS:
		_to(S.FREE)


## Noticed: SUSPICIOUS turns him (the takedown window closes); near, or ALERT → face to face.
func _check_noticed() -> bool:
	var aw := awareness()
	if aw == 0:
		return false
	if _state != S.LOOK:
		stats["suspicious"] = int(stats["suspicious"]) + 1
	var d := _flat(_player.global_position, archer.global_position)
	if aw == 2 or d <= NOTICE_NEAR:
		_start_fight("noticed_%s" % ("alert" if aw == 2 else "near"))
		return true
	if _state != S.LOOK:
		_haul_pose(false)
		archer.call("stop")
		archer.call("face_point", sensor.get("last_known_position"))
		archer.call("say", WELSH_WHO, 2.5)
		_to(S.LOOK)
	return true


func _tick_look() -> void:
	var aw := awareness()
	var d := _flat(_player.global_position, archer.global_position)
	if aw == 2 or (aw >= 1 and d <= NOTICE_NEAR):
		_start_fight("noticed_%s" % ("alert" if aw == 2 else "near"))
		return
	if _st >= SUSPICIOUS_LOOK and aw == 0:
		# Nothing. Back to her (or on in, if he hadn't reached her yet).
		if _cow_bogged and _flat(archer.global_position, HAUL_AT) < 0.6:
			archer.call("face_yaw", HAUL_YAW)
			_to(S.HAUL)
		else:
			archer.call("walk_path", [HAUL_AT])
			_to(S.WALK_IN)


func _tick_lured() -> void:
	if _st < LURE_LOOK:
		if awareness() == 2:
			_start_fight("noticed_alert")
		return
	if _lure_near_hide:
		# The stone fell by the household: he goes to see what's in the reeds there.
		if _st < LURE_LOOK + 0.1:
			archer.call("walk_path", [_lure_point])
		_check_found()
		if _check_noticed_moving():
			return
		if not bool(archer.call("is_walking")) and not _found:
			_start_fight("lure_by_hide")
		return
	# The other way: someone in the reeds over there — not his business alone. He frees her fast.
	_to(S.FREE)


func _check_noticed_moving() -> bool:
	if awareness() == 2 or (awareness() >= 1 and _flat(_player.global_position, archer.global_position) <= NOTICE_NEAR):
		_start_fight("noticed_alert")
		return true
	return false


func _check_found() -> void:
	if _found:
		return
	for who in [_maire, _girl]:
		if who and _flat((who as Node3D).global_position, archer.global_position) <= FIND_DIST:
			_found = true
			print("FEN_HOUSEHOLD_FOUND")
			_start_fight("found_household")
			return


func _tick_free() -> void:
	var quick := _lure_point != Vector3.INF
	var secs := FREE_SECS * (0.6 if quick else 1.0)
	_haul_pose(true, 1.0 if fmod(_st, 1.0) < 0.5 else 0.2)
	archer.call("face_yaw", HAUL_YAW)
	if _check_noticed():
		return
	if _st >= secs:
		_haul_pose(false)
		_cow_free_follow()
		_out_i = 0
		archer.set("walk_speed", 1.8 if quick else 1.4)
		archer.call("walk_path", ARCHER_OUT.duplicate())
		print("FEN_COW_FREED quick=%s" % quick)
		_to(S.LEAVE)


func _tick_leave() -> void:
	_cow_lead()
	if _check_noticed_moving():
		return
	_check_found()
	if _found:
		return
	if _flat(archer.global_position, HIDE_CIAN) >= GONE_DIST or not bool(archer.call("is_walking")):
		_resolve(&"spared", {"straggler": "spared"})


func _start_fight(reason: String) -> void:
	if _state in [S.FIGHT, S.BACK_OFF, S.TAKEDOWN, S.DONE]:
		return
	_haul_pose(false)
	archer.call("stop")
	archer.call("set_knife_drawn", true)
	archer.call("say", WELSH_FIGHT, 2.0)
	if sensor:
		sensor.call("force_awareness", 2)
	_seen_face = true
	_cut_phase = "close"
	_cut_t = 0.0
	print("FEN_FIGHT reason=%s" % reason)
	_flags["fight_reason"] = reason
	_to(S.FIGHT)


func _tick_fight(delta: float) -> void:
	_fight_step(delta, true)
	if _horn_t >= 0.0:
		_horn_t += delta
		if _horn_t >= HORN_AFTER and not _horned:
			_horned = true
			Sfx.play(self, &"horn", _ground(Vector3(-22.0, 0, 172.0), 3.0), 4.0, 30.0)
			if _raid:
				_raid.call("_caption", "A horn, down on the lane. He looks that way, and back at you.", 4.0)
			archer.call("level_spear", Vector3.ZERO, 0.0)
			_cut_phase = ""
			_to(S.BACK_OFF)


## Close to FIGHT_GAP, wind up (telegraphed: the arm goes back), cut. `advance` false = holding.
func _fight_step(delta: float, advance: bool) -> void:
	var pp := _player.global_position
	var ap := archer.global_position
	archer.call("face_point", pp)
	var d := _flat(pp, ap)
	if _stagger_t > 0.0:
		_stagger_t -= delta
		var away := Vector3(ap.x - pp.x, 0.0, ap.z - pp.z).normalized()
		archer.global_position = _ground(ap + away * 1.6 * delta)
		archer.call("level_spear", pp + Vector3(0, 1.0, 0), 0.0)
		return
	if advance and d > FIGHT_GAP + 0.1 and _cut_phase != "cut":
		var to := Vector3(pp.x - ap.x, 0.0, pp.z - ap.z).normalized()
		archer.global_position = _ground(ap + to * minf(FIGHT_STEP * delta, d - FIGHT_GAP))
	_cut_t += delta
	match _cut_phase:
		"close":
			archer.call("level_spear", pp + Vector3(0, 1.1, 0), 0.25)
			if _cut_t >= (CUT_EVERY - CUT_WINDUP if _cuts > 0 else 0.5) and d <= CUT_REACH + 0.6:
				_cut_phase = "windup"
				_cut_t = 0.0
		"windup", "counter":
			# Telegraph: the knife hand drawn back high by his ear.
			archer.call("level_spear", ap + Vector3(0, 1.75, 0) + archer.global_transform.basis.z * 0.5, 1.0)
			var wu := COUNTER_WINDUP if _cut_phase == "counter" else CUT_WINDUP
			if _cut_t >= wu:
				_cut_phase = "cut"
				_cut_t = 0.0
				Sfx.play(self, &"clash", ap + Vector3(0, 1.2, 0), -6.0, 6.0)
		"cut":
			archer.call("level_spear", pp + Vector3(0, 1.0, 0), 1.0)
			if _cut_t >= 0.12 and _cut_t - delta < 0.12:
				_land_cut(d)
			if _cut_t >= 0.35:
				_cut_phase = "" if _state == S.BACK_OFF else "close"
				_cut_t = 0.0
		_:
			archer.call("level_spear", pp + Vector3(0, 1.0, 0), 0.2)


func _land_cut(d: float) -> void:
	if d > CUT_REACH:
		return
	var c: Node = _player.get("combat")
	# The goad's shaft across him stops the cut — a moment, and only FENDS_MAX times.
	if c and bool(c.get("is_shaft_blocking")) and int(c.get("current_weapon")) == 2 and _fends < FENDS_MAX:
		_fends += 1
		stats["fends"] = _fends
		print("FEN_CUT_BLOCKED by=goad fends=%d" % _fends)
		return
	_cuts += 1
	stats["cuts"] = _cuts
	var deep := _cuts >= 2 and _kept_fighting
	var tag := &"deep" if deep else &"cut"
	print("FEN_CIAN_CUT n=%d tag=%s" % [_cuts, tag])
	if _raid:
		_raid.call("_caption", "His knife opens your arm." if _cuts == 1 else "He cuts you again, deeper.", 3.0)
	cian_struck.emit(DEEP_DMG if deep else CUT_DMG, tag, archer)
	_flags["cian_wound"] = String(tag)
	if _horn_t < 0.0:
		_horn_t = 0.0


func _tick_back_off(delta: float) -> void:
	var pp := _player.global_position
	var ap := archer.global_position
	if _st < BACK_OFF_SECS:
		# Facing Cian, knife up, backing toward her; he cuts at anyone who still comes on.
		if _cut_phase != "":
			_fight_step(delta, false)
		else:
			archer.call("face_point", pp)
			archer.call("level_spear", pp + Vector3(0, 1.1, 0), 0.35)
			var back := _ground(_cow.global_position if _cow else ap)
			var to := Vector3(back.x - ap.x, 0, back.z - ap.z)
			if to.length() > 1.4:
				archer.global_position = _ground(ap + to.normalized() * 1.0 * delta)
		return
	if _cow_bogged:
		_cow_free_follow()
		archer.call("level_spear", Vector3.ZERO, 0.0)
		archer.set("walk_speed", 1.9)
		archer.call("walk_path", ARCHER_OUT.duplicate())
		print("FEN_BACK_OFF_LEAVING")
	_cow_lead()
	if _cut_phase != "":
		_fight_step(delta, false)
	if _flat(ap, HIDE_CIAN) >= GONE_DIST * 0.6 or (not bool(archer.call("is_walking")) and _st > BACK_OFF_SECS + 1.0):
		archer.call("set_knife_drawn", false)
		var wound := String(_flags.get("cian_wound", "none"))
		_resolve(&"fought", {"straggler": "fought", "cian_wound": wound, "seen": true})


func _on_player_attack(_attacker: Node, _kind: StringName, weapon: StringName) -> void:
	if not _open() or archer == null or not archer.visible:
		return
	var d := _flat(_player.global_position, archer.global_position)
	match _state:
		S.FIGHT, S.BACK_OFF:
			if _state == S.BACK_OFF and d <= 3.2:
				_kept_fighting = true
				if _cut_phase == "" or _cut_phase == "close":
					_cut_phase = "counter"
					_cut_t = 0.0
					stats["counter"] = int(stats["counter"]) + 1
			elif String(weapon) == "knife" and d <= 2.2 and _cut_phase == "close":
				# The knife can't close on a man with a long knife: he's in first.
				_cut_phase = "counter"
				_cut_t = 0.0
				stats["counter"] = int(stats["counter"]) + 1
			if _cuts >= 1:
				_kept_fighting = true
		S.TAKEDOWN, S.DONE, S.IDLE:
			pass
		_:
			if d <= 2.6:
				_start_fight("open_attack")


func _on_player_hit(_attacker: Node, target: Node, _dmg: float, _kind: StringName) -> void:
	if not _open() or archer == null:
		return
	if target != archer and (target == null or target.get_parent() != archer):
		return
	if _acombat and float(_acombat.get("health")) < ARCHER_HP_FLOOR:
		_acombat.set("health", ARCHER_HP_FLOOR)
	if _state != S.FIGHT and _state != S.BACK_OFF:
		_start_fight("open_hit")
		return
	var c: Node = _player.get("combat")
	if c and int(c.get("current_weapon")) == 2 and _fends < FENDS_MAX and _cut_phase in ["windup", "close"]:
		# The goad's butt in his chest: he gives back a step and comes again.
		_fends += 1
		stats["fends"] = _fends
		_stagger_t = 0.45
		_cut_phase = "close"
		_cut_t = 0.0
		print("FEN_GOAD_FEND fends=%d" % _fends)


# ---------------------------------------------------------------- the takedown

func try_takedown() -> bool:
	if not _open() or not can_takedown():
		return false
	_player.call("begin_cinematic")
	_haul_pose(false)
	archer.call("stop")
	if sensor:
		sensor.process_mode = Node.PROCESS_MODE_DISABLED
	# Close in at his back.
	var back := archer.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	_player.global_position = _ground(archer.global_position + back * 0.5, 0.05)
	_player.rotation.y = archer.global_rotation.y
	_player.velocity = Vector3.ZERO
	print("FEN_TAKEDOWN check=%s" % [takedown_check()])
	_to(S.TAKEDOWN)
	return true


## Cian's motion: left hand up and over the mouth, the knife hand from out at his right across to
## the side of the neck above the collar. Mid-arc around 0.4–0.7 s.
func takedown_pose(u: float) -> Dictionary:
	var grab := smoothstep(0.0, 0.35, u)
	var arc := smoothstep(0.3, 0.85, u)
	return {
		"left_arm": Vector3(deg_to_rad(120.0) * grab, 0.0, deg_to_rad(-25.0) * grab),
		"left_forearm": Vector3(deg_to_rad(70.0) * grab, 0.0, 0.0),
		"right_arm": Vector3(deg_to_rad(lerpf(70.0, 100.0, arc)) * grab, deg_to_rad(lerpf(-35.0, 40.0, arc)) * grab, deg_to_rad(lerpf(35.0, -20.0, arc)) * grab),
		"right_forearm": Vector3(deg_to_rad(lerpf(30.0, 75.0, arc)) * grab, 0.0, 0.0),
		"torso": Vector3(deg_to_rad(8.0) * grab, 0.0, 0.0),
	}


func takedown_progress() -> float:
	return clampf(_st / TAKEDOWN_GRAB, 0.0, 1.0) if _state == S.TAKEDOWN else 0.0


func _tick_takedown() -> void:
	if _st < TAKEDOWN_GRAB:
		var u := _st / TAKEDOWN_GRAB
		_player.call("set_cinematic_pose", takedown_pose(u))
		archer.call("set_crouch", false)
		archer.call("set_seized", smoothstep(0.1, 0.4, u))
		return
	if _cut_cam == null:
		_player.call("set_cinematic_pose", takedown_pose(1.0))
		_start_cutaway()
		return
	if _st >= TAKEDOWN_GRAB + TAKEDOWN_CUTAWAY:
		_end_cutaway()
		archer.visible = true
		_player.call("set_cinematic_pose", {})
		# Up off him, to one side (he lies where he went over, at the margin, in the reeds).
		_player.global_position = _ground(archer.global_position + archer.global_transform.basis.x.normalized() * 0.95 + archer.global_transform.basis.z.normalized() * 0.3, 0.05)
		_player.call("end_cinematic")
		_resolve(&"killed", {"straggler": "killed", "cian_wound": "none"})


func _start_cutaway() -> void:
	_cut_cam = Camera3D.new()
	_cut_cam.name = "TakedownCutaway"
	_cut_cam.fov = 36.0
	add_child(_cut_cam)
	# Tight on Cian's face from in front and a little to his left, the reed stand behind him. The
	# archer (between, held) is out of the shot for the cutaway: nothing of him is shown.
	var head := _player.global_position + Vector3(0, 1.56, 0)
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	_cut_cam.global_position = head + fwd * 1.0 - side * 0.38 + Vector3(0, 0.04, 0)
	_cut_cam.look_at(head + Vector3(0, -0.06, 0), Vector3.UP)
	_cut_cam.current = true
	# Off camera he goes down and is still: by the cut back he lies at the margin.
	archer.visible = false
	archer.call("set_seized", 0.0)
	archer.call("set_down", true)
	Sfx.play(self, &"struggle", archer.global_position + Vector3(0, 0.8, 0), 0.0, 6.0)
	if _raid:
		_raid.call("_caption", "He fights the hand for a moment. Then he's still.", TAKEDOWN_CUTAWAY)
	print("FEN_CUTAWAY")


func _end_cutaway() -> void:
	if _cut_cam:
		_cut_cam.current = false
		var pc: Camera3D = _player.get("camera") as Camera3D
		if pc:
			pc.current = true
		_cut_cam.queue_free()
		_cut_cam = null


# ---------------------------------------------------------------- the stone

## Throw a stone (G): ~STONE_THROW m along the view, into the reeds / water. Public for smokes.
func throw_stone(target: Vector3 = Vector3.INF) -> bool:
	if not _open() or _stone_cd > 0.0 or _player == null or bool(_player.call("is_input_locked")):
		return false
	if _state in [S.FIGHT, S.BACK_OFF, S.TAKEDOWN]:
		return false
	_stone_cd = STONE_CD
	var from := _player.global_position + Vector3(0, 1.1, 0)
	if target == Vector3.INF:
		var cam := _player.get("camera") as Camera3D
		var f := -(cam.global_transform.basis.z if cam else _player.global_transform.basis.z)
		f.y = 0.0
		target = _player.global_position + f.normalized() * STONE_THROW
	target = _ground(target)
	var st := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.06
	st.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.43, 0.4)
	st.material_override = m
	st.top_level = true
	add_child(st)
	st.global_position = from
	_stones.append({"node": st, "from": from, "to": target, "t": 0.0})
	stats["stones"] = int(stats["stones"]) + 1
	print("FEN_STONE_THROWN to=%s" % target)
	return true


func _tick_stones(delta: float) -> void:
	for s in _stones.duplicate():
		s["t"] = float(s["t"]) + delta
		var u := clampf(float(s["t"]) / STONE_FLIGHT, 0.0, 1.0)
		var p: Vector3 = (s["from"] as Vector3).lerp(s["to"], u) + Vector3(0, 2.2 * u * (1.0 - u) * 2.0, 0)
		(s["node"] as Node3D).global_position = p
		if u >= 1.0:
			_stones.erase(s)
			(s["node"] as Node3D).queue_free()
			_stone_landed(s["to"])


func _stone_landed(at: Vector3) -> void:
	Sfx.play(self, &"stone", at + Vector3(0, 0.3, 0), 0.0, 6.0)
	if pool and bool(pool.call("is_in_water", at)):
		pool.call("play_ripple", at, 0.6)
	if archer == null or not archer.visible or _flat(at, archer.global_position) > LURE_HEARD:
		return
	if _state != S.HAUL:
		print("FEN_STONE_IGNORED state=%s" % S.keys()[_state])
		return
	var hide_d := minf(_flat(at, HIDE_MAIRE), _flat(at, HIDE_GIRL))
	_lure_near_hide = hide_d < LURE_FAR_FROM_HIDE
	_lure_point = at
	print("FEN_STONE_LURE at=%s hide_d=%.1f near_hide=%s" % [at, hide_d, _lure_near_hide])


# ---------------------------------------------------------------- end

func _resolve(o: StringName, flags: Dictionary) -> void:
	if _outcome != &"":
		return
	_outcome = o
	for k in flags:
		_flags[k] = flags[k]
	_flags["straggler"] = String(o)
	if o == &"fought":
		_flags["seen"] = true
	_flags["fen_stats"] = stats.duplicate()
	_to(S.DONE)
	if sensor:
		sensor.process_mode = Node.PROCESS_MODE_DISABLED
	print("FEN_RESOLVED outcome=%s flags=%s" % [o, _flags])
	finished.emit(o, _flags)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
