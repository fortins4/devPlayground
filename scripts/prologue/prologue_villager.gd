extends Node3D
class_name PrologueVillager
## Prologue (raid beat, after the opening's meal): a household / neighbour figure on the kerne rig
## (KerneMeshBuilder + KerneLocomotion, its own palette, no kit props), scaled to a real stature.
## Walks a list of waypoints over the terrain at a real walking pace, turns to face things, and
## speaks lines as a bark over the head plus the HUD flash (like Máire's lines). No collider and
## no AI: the raid sequence drives it. Right-hand pose hooks let a source hold a prop
## (`hold_right(on)`), and `reach_right(world_point, w)` points the right arm at a spot (pulling the
## hatchet from the block, handing over a dish).
## Raid-day additions (chunk 2): `kit` props worn or carried (period kit for May 1169: nasal helm,
## kite shield slung on the back on the march, an upright spear or lance, an unpolished wild-elm
## self-bow in the left hand with arrows in a bag at the belt), `beardless` for women and children,
## `riding` (sat astride, feet in the stirrups: the rider), `y_offset` (seat height above ground),
## `reach_left`, `follow(node, offset)` (at someone's side, e.g. a child by the hand) and
## `set_nocked(on)` (an archer with an arrow on the string, bow up — never loosed here).

signal arrived

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
## The kerne rig is modelled at 1.84 m (see PlayerController.CIAN_SCALE).
const RIG_STATURE := 1.84
const TURN_RATE := 5.0
const ARRIVE := 0.08

@export var display_name: String = ""
@export var stature_m: float = 1.65
@export var walk_speed: float = 1.2
## Palette keys as KerneMeshBuilder.PALETTE_PLAYER.
var palette: Dictionary = {}
## Kit props (StringName): nasal_helm, mail_coif, cap, hood_up, kite_shield, spear, lance,
## light_spears, sword, bow, arrow_bag.
var kit: Array = []
@export var beardless: bool = false
@export var riding: bool = false
## Added to the ground height (a rider's seat on the horse).
@export var y_offset: float = 0.0

var _visual: Node3D = null
var _loco: KerneLocomotion = null
var _label: Label3D = null
var _bark: Label3D = null
var _bark_t: float = 0.0
var _path: Array[Vector3] = []
var _speed_now: float = 0.0
var _face_yaw: float = NAN
var _director: Node = null
var _hold_w: float = 0.0
var _hold_on: bool = false
var _reach_point: Vector3 = Vector3.ZERO
var _reach_w: float = 0.0
var _right_hand: Node3D = null
var _left_hand: Node3D = null
var _reach_l_point: Vector3 = Vector3.ZERO
var _reach_l_w: float = 0.0
var _spear: Node3D = null
var _bow: Node3D = null
var _arrow: Node3D = null
var _nocked: bool = false
var _nock_w: float = 0.0
var _follow: Node3D = null
var _follow_off: Vector3 = Vector3.ZERO
var _follow_max: float = 3.0
var _kit_mats: Dictionary = {}
## Raid day, steps 7–8: crouched (as Cian crouches, or frozen in the ditch), struck down (lies
## still), a spear levelled at a point, a bow drawn.
var crouching: bool = false
var _down_on: bool = false
var _down_w: float = 0.0
var _thrust_point: Vector3 = Vector3.ZERO
var _thrust_w: float = 0.0
var _thrust_target_w: float = 0.0
var _draw_w: float = 0.0
var _drawing: bool = false


func _ready() -> void:
	add_to_group("prologue_villager")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_loco = KerneLocomotion.new()
	_loco.name = "Locomotion"
	_loco.build_on_ready = false
	_loco.include_kit_props = false
	_loco.palette_override = palette
	add_child(_loco)
	_loco.rebuild()
	var s := stature_m / RIG_STATURE
	_visual.scale = Vector3.ONE * s
	_loco.body_scale = s
	var fore := _loco.get_joint("right_forearm")
	if fore:
		_right_hand = Node3D.new()
		_right_hand.name = "RightHand"
		_right_hand.position = Vector3(0.0, -0.26, 0.0)
		fore.add_child(_right_hand)
	var lfore := _loco.get_joint("left_forearm")
	if lfore:
		_left_hand = Node3D.new()
		_left_hand.name = "LeftHand"
		_left_hand.position = Vector3(0.0, -0.26, 0.0)
		lfore.add_child(_left_hand)
	if beardless:
		var beard := _visual.find_child("Beard", true, false) as Node3D
		if beard:
			beard.visible = false
	_build_kit()
	_label = Label3D.new()
	_label.name = "NameTag"
	_label.text = display_name
	_label.font_size = 36
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.92, 0.86, 0.7)
	_label.outline_size = 10
	_label.outline_modulate = Color(0.05, 0.05, 0.04, 0.85)
	_label.position = Vector3(0.0, stature_m + 0.22, 0.0)
	_label.visible = display_name != ""
	add_child(_label)
	_bark = Label3D.new()
	_bark.name = "Bark"
	_bark.font_size = 30
	_bark.pixel_size = 0.0085
	_bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bark.modulate = Color(1.0, 0.96, 0.82)
	_bark.outline_size = 12
	_bark.outline_modulate = Color(0.08, 0.06, 0.04, 0.92)
	_bark.position = Vector3(0.0, stature_m + 0.42, 0.0)
	_bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark.width = 560.0
	_bark.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bark.visible = false
	add_child(_bark)
	call_deferred("_bind")


func _bind() -> void:
	_director = get_tree().get_first_node_in_group("opening_drive")
	snap_to_ground()


# ---------------------------------------------------------------- driving

## Walk through `points` (world, y ignored) in order at walk_speed (or `speed` if > 0).
func walk_path(points: Array, speed: float = -1.0) -> void:
	_path.clear()
	for p in points:
		_path.append(Vector3(p.x, 0.0, p.z))
	if speed > 0.0:
		walk_speed = speed
	_face_yaw = NAN


func stop() -> void:
	_path.clear()


func is_walking() -> bool:
	return not _path.is_empty()


func place(p: Vector3, yaw: float) -> void:
	global_position = Terrain.surface_point(p, 0.0)
	rotation.y = yaw
	_path.clear()
	_face_yaw = NAN


func face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_face_yaw = atan2(-d.x, -d.z)


func face_yaw(yaw: float) -> void:
	_face_yaw = yaw


func say(line: String, secs: float = 5.0) -> void:
	_bark.text = line
	_bark.visible = true
	_bark_t = secs
	if _director == null:
		_director = get_tree().get_first_node_in_group("opening_drive")
	if _director and _director.has_method("flash"):
		_director.call("flash", "%s: %s" % [display_name, line], secs - 0.5)
	print("PROLOGUE_LINE speaker=%s line=%s" % [display_name, line])


func is_bark_visible() -> bool:
	return _bark.visible


func right_hand() -> Node3D:
	return _right_hand


## Forearm raised a little in front, as when carrying a dish or a tool by the handle.
func hold_right(on: bool) -> void:
	_hold_on = on


## Point the right arm at a world spot (weight w 0..1, eased by the caller).
func reach_right(world_point: Vector3, w: float) -> void:
	_reach_point = world_point
	_reach_w = clampf(w, 0.0, 1.0)


func snap_to_ground() -> void:
	if is_inside_tree():
		global_position.y = Terrain.surface_y(global_position.x, global_position.z) + y_offset


func left_hand() -> Node3D:
	return _left_hand


## Point the left arm at a world spot (weight w 0..1, eased by the caller).
func reach_left(world_point: Vector3, w: float) -> void:
	_reach_l_point = world_point
	_reach_l_w = clampf(w, 0.0, 1.0)


## Keep at `node`'s side: `offset` in the node's own frame (x right, z back), at up to `max_speed`.
## null stops following.
func follow(node: Node3D, offset: Vector3 = Vector3(0.5, 0.0, 0.35), max_speed: float = 3.0) -> void:
	_follow = node
	_follow_off = offset
	_follow_max = max_speed
	_path.clear()


func is_following() -> bool:
	return _follow != null and is_instance_valid(_follow)


## An archer's arrow on the string, bow raised before him (not drawn, never loosed in this beat).
func set_nocked(on: bool) -> void:
	_nocked = on


func is_nocked() -> bool:
	return _nocked and _nock_w > 0.9


func has_kit(k: StringName) -> bool:
	return kit.has(k)


func right_hand_point() -> Vector3:
	return _right_hand.global_position if _right_hand else global_position + Vector3(0, 1.0, 0)


func set_crouch(on: bool) -> void:
	crouching = on


## Struck down: he goes over backwards and lies still (no blood, no close-up).
func set_down(on: bool) -> void:
	_down_on = on
	if on:
		_path.clear()
		_follow = null


func is_down() -> bool:
	return _down_on and _down_w > 0.95


## Level the spear at `world_point` (w 0..1, eased here): a serjeant's guard / thrust.
func level_spear(world_point: Vector3, w: float) -> void:
	_thrust_point = world_point
	_thrust_target_w = clampf(w, 0.0, 1.0)


## An archer drawing: the nocked arrow pulled back to the cheek (w eased here).
func set_drawing(on: bool) -> void:
	_drawing = on
	if on:
		_nocked = true


func is_drawn() -> bool:
	return _drawing and _draw_w > 0.9


## The arrow leaves the string: drawn → empty-handed, the next one nocked a moment later.
func loose() -> void:
	_drawing = false
	_draw_w = 0.0
	_nock_w = 0.0


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	var speed := 0.0
	if is_following():
		var tgt_f: Vector3 = _follow.global_transform * Vector3(_follow_off.x, 0.0, _follow_off.z)
		var to_f := Vector3(tgt_f.x - global_position.x, 0.0, tgt_f.z - global_position.z)
		var d_f := to_f.length()
		if d_f > 0.12:
			var want_f := atan2(-to_f.x, -to_f.z)
			speed = clampf(d_f * 2.6, 0.0, _follow_max)
			if d_f > 0.45:
				rotation.y = rotate_toward(rotation.y, want_f, TURN_RATE * 1.4 * delta)
			else:
				rotation.y = rotate_toward(rotation.y, _follow.global_rotation.y, TURN_RATE * delta)
			global_position += to_f / d_f * minf(d_f, speed * delta)
		else:
			rotation.y = rotate_toward(rotation.y, _follow.global_rotation.y, TURN_RATE * delta)
	elif not _path.is_empty():
		var tgt := _path[0]
		var to := Vector3(tgt.x - global_position.x, 0.0, tgt.z - global_position.z)
		var d := to.length()
		if d <= ARRIVE:
			_path.remove_at(0)
			if _path.is_empty():
				arrived.emit()
		else:
			var want := atan2(-to.x, -to.z)
			rotation.y = rotate_toward(rotation.y, want, TURN_RATE * delta)
			var aligned := absf(angle_difference(rotation.y, want)) < 0.7
			speed = walk_speed if aligned else walk_speed * 0.3
			var step := minf(d, speed * delta)
			global_position += to / d * step
	elif not is_nan(_face_yaw):
		rotation.y = rotate_toward(rotation.y, _face_yaw, TURN_RATE * 0.6 * delta)
	_speed_now = lerpf(_speed_now, speed, clampf(delta * 8.0, 0.0, 1.0))
	snap_to_ground()
	if _loco:
		_loco.tick(delta, 0.0 if (riding or _down_on) else _speed_now, false, crouching and not _down_on, false, Vector3(0, 0, -1) if (_speed_now > 0.05 and not riding) else Vector3.ZERO)
		_pose_right_arm(delta)
		_pose_left_arm(delta)
		if riding:
			_pose_riding()
		_pose_down(delta)
		_place_kit(delta)
	if _bark_t > 0.0:
		_bark_t -= delta
		if _bark_t <= 0.0:
			_bark.visible = false


func _pose_down(delta: float) -> void:
	_down_w = move_toward(_down_w, 1.0 if _down_on else 0.0, delta * 1.6)
	if _down_w <= 0.0:
		return
	var root := _loco.get_joint("root")
	if root == null:
		return
	# Over backwards (rig faces −Z: +X rotation tips the head to +Z) and down onto the ground.
	var e := _down_w * _down_w * (3.0 - 2.0 * _down_w)
	root.rotation.x += PI * 0.5 * e
	root.position.y -= 0.8 * e
	root.position.z += 0.1 * e
	for j in ["left_thigh", "right_thigh"]:
		var t := _loco.get_joint(j)
		if t:
			t.rotation.x += 0.25 * e
	for j in ["left_arm", "right_arm"]:
		var a := _loco.get_joint(j)
		if a:
			a.rotation.z += (0.9 if j == "left_arm" else -0.9) * e


func _pose_right_arm(delta: float) -> void:
	var arm := _loco.get_joint("right_arm")
	var fore := _loco.get_joint("right_forearm")
	if arm == null or fore == null:
		return
	_thrust_w = move_toward(_thrust_w, _thrust_target_w, delta * 7.0)
	if _thrust_w > 0.0:
		var sh0 := arm.global_position
		var aim := (_thrust_point - sh0)
		aim.y = clampf(aim.y, -0.6, 0.2)
		if aim.length() > 0.05:
			var local0 := (arm.get_parent() as Node3D).global_transform.basis.orthonormalized().inverse() * aim.normalized()
			var b0 := Basis.looking_at(local0, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
			arm.basis = arm.basis.orthonormalized().slerp(b0.orthonormalized(), _thrust_w * 0.85)
			fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(25.0), 0.0, 0.0), _thrust_w)
		return
	_hold_w = move_toward(_hold_w, 1.0 if _hold_on else 0.0, delta * 3.0)
	if _hold_w > 0.0:
		# Upper arm down by the side, forearm forward (elbow ~80°): a dish or tool held in front.
		arm.rotation = arm.rotation.lerp(Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(-6.0)), _hold_w)
		fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(78.0), 0.0, 0.0), _hold_w)
	if _reach_w > 0.0:
		var sh := arm.global_position
		var dir := (_reach_point - sh)
		if dir.length() > 0.05:
			var local := (arm.get_parent() as Node3D).global_transform.basis.orthonormalized().inverse() * dir.normalized()
			# Arm hangs along its −Y: aim −Y at the target.
			var b := Basis.looking_at(local, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
			var cur := arm.basis.orthonormalized()
			arm.basis = cur.slerp(b.orthonormalized(), _reach_w)
			fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(15.0), 0.0, 0.0), _reach_w)


func _pose_left_arm(delta: float) -> void:
	var arm := _loco.get_joint("left_arm")
	var fore := _loco.get_joint("left_forearm")
	if arm == null or fore == null:
		return
	_nock_w = move_toward(_nock_w, 1.0 if _nocked else 0.0, delta * 2.5)
	_draw_w = move_toward(_draw_w, 1.0 if (_drawing and _nock_w > 0.9) else 0.0, delta * 2.2)
	var w := _reach_l_w
	var pt := _reach_l_point
	if _nock_w > 0.0 and _bow:
		# Bow hand out before him at chest height, a little to his left; drawn, at full stretch.
		pt = global_transform * Vector3(-0.12 * (stature_m / RIG_STATURE), (1.25 + 0.12 * _draw_w) * (stature_m / RIG_STATURE), -0.6 - 0.15 * _draw_w)
		w = maxf(w, _nock_w)
	if w <= 0.0:
		return
	var sh := arm.global_position
	var dir := pt - sh
	if dir.length() > 0.05:
		var local := (arm.get_parent() as Node3D).global_transform.basis.orthonormalized().inverse() * dir.normalized()
		var b := Basis.looking_at(local, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		arm.basis = arm.basis.orthonormalized().slerp(b.orthonormalized(), w)
		fore.rotation = fore.rotation.lerp(Vector3(deg_to_rad(10.0), 0.0, 0.0), w)


## Astride: thighs forward and apart over the barrel, shins down to the stirrups.
func _pose_riding() -> void:
	for side in [["left_thigh", -1.0], ["right_thigh", 1.0]]:
		var t := _loco.get_joint(String(side[0]))
		if t:
			t.rotation = Vector3(deg_to_rad(72.0), 0.0, deg_to_rad(24.0) * float(side[1]))
	for sh in ["left_shin", "right_shin"]:
		var j := _loco.get_joint(sh)
		if j:
			j.rotation = Vector3(deg_to_rad(-78.0), 0.0, 0.0)
	var hips := _loco.get_joint("hips")
	if hips:
		hips.rotation = Vector3.ZERO


# ---------------------------------------------------------------- kit (raid day)

func _kmat(c: Color, metal: float = 0.0) -> StandardMaterial3D:
	var k := "%s/%.2f" % [c.to_html(), metal]
	if not _kit_mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.55 if metal > 0.0 else 0.9
		m.metallic = metal
		_kit_mats[k] = m
	return _kit_mats[k]


func _kbox(parent: Node3D, pos: Vector3, size: Vector3, c: Color, metal: float = 0.0, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _kmat(c, metal)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_kit() -> void:
	if kit.is_empty():
		return
	var iron := Color(0.42, 0.43, 0.45)
	var wood := Color(0.45, 0.33, 0.2)
	var elm := Color(0.5, 0.38, 0.24)
	var head := _loco.get_joint("head")
	var torso := _loco.get_joint("torso")
	var hips := _loco.get_joint("hips")
	if head and kit.has(&"nasal_helm"):
		# Conical iron cap with a nasal bar (rig head: sphere r 0.145, faces −Z).
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015
		cm.bottom_radius = 0.165
		cm.height = 0.2
		cm.radial_segments = 10
		cone.mesh = cm
		cone.material_override = _kmat(iron, 0.5)
		cone.position = Vector3(0.0, 0.11, 0.0)
		head.add_child(cone)
		_kbox(head, Vector3(0.0, 0.0, -0.15), Vector3(0.028, 0.13, 0.02), iron, 0.5)
		var hair := _visual.find_child("Hair", true, false) as Node3D
		if hair:
			hair.visible = false
	if head and kit.has(&"cap"):
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.155
		sm.height = 0.17
		cap.mesh = sm
		cap.material_override = _kmat(Color(0.4, 0.33, 0.24))
		cap.position = Vector3(0.0, 0.07, 0.0)
		head.add_child(cap)
	if torso and kit.has(&"kite_shield"):
		# Slung on the back by its guige on the march: point down, painted face out.
		var sh := Node3D.new()
		sh.name = "KiteShield"
		sh.position = Vector3(0.0, 0.18, 0.23)
		sh.rotation = Vector3(0.0, PI, 0.08)
		torso.add_child(sh)
		_kbox(sh, Vector3(0.0, 0.18, 0.0), Vector3(0.44, 0.42, 0.035), Color(0.55, 0.16, 0.12))
		_kbox(sh, Vector3(0.0, -0.18, 0.0), Vector3(0.3, 0.34, 0.035), Color(0.55, 0.16, 0.12))
		_kbox(sh, Vector3(0.0, -0.42, 0.0), Vector3(0.14, 0.2, 0.035), Color(0.55, 0.16, 0.12))
		_kbox(sh, Vector3(0.0, 0.05, -0.025), Vector3(0.06, 0.06, 0.03), iron, 0.5)  # boss
	if hips and kit.has(&"sword"):
		_kbox(hips, Vector3(-0.2, -0.32, -0.02), Vector3(0.05, 0.85, 0.04), Color(0.25, 0.18, 0.12), 0.0, Vector3(0.12, 0.0, 0.1))
	if hips and kit.has(&"arrow_bag"):
		var bag := _kbox(hips, Vector3(0.22, -0.1, 0.06), Vector3(0.1, 0.36, 0.1), Color(0.42, 0.34, 0.24), 0.0, Vector3(-0.15, 0.0, -0.1))
		for i in 4:
			_kbox(bag, Vector3(-0.025 + 0.017 * i, 0.24, 0.0), Vector3(0.008, 0.16, 0.008), Color(0.7, 0.66, 0.6))
	if kit.has(&"spear") or kit.has(&"lance") or kit.has(&"light_spears"):
		_spear = Node3D.new()
		_spear.name = "Spear"
		_spear.top_level = true
		add_child(_spear)
		var long := 2.9 if kit.has(&"lance") else (2.0 if kit.has(&"light_spears") else 2.5)
		var n := 2 if kit.has(&"light_spears") else 1
		for i in n:
			var shaft := _kbox(_spear, Vector3(0.035 * i, long * 0.5 - 0.9, 0.0), Vector3(0.032, long, 0.032), wood)
			_kbox(shaft, Vector3(0.0, long * 0.5 + 0.1, 0.0), Vector3(0.045, 0.22, 0.012), iron, 0.6)
		hold_right(true)
	if kit.has(&"bow"):
		# Wild-elm self-bow, ~1.55 m, unpolished: a thick plain stave, gently bent, strung.
		_bow = Node3D.new()
		_bow.name = "ElmBow"
		_bow.top_level = true
		add_child(_bow)
		for seg in [[0.0, 0.0, 0.46, 0.0], [0.5, -0.03, 0.4, 0.12], [-0.5, -0.03, 0.4, -0.12], [0.73, -0.07, 0.12, 0.3], [-0.73, -0.07, 0.12, -0.3]]:
			_kbox(_bow, Vector3(0.0, seg[0], seg[1]), Vector3(0.034, seg[2], 0.03), elm, 0.0, Vector3(seg[3], 0.0, 0.0))
		_kbox(_bow, Vector3(0.0, 0.0, 0.06), Vector3(0.006, 1.5, 0.006), Color(0.82, 0.78, 0.7))  # string
		_arrow = _kbox(_bow, Vector3(0.0, 0.0, -0.05), Vector3(0.012, 0.012, 0.72), Color(0.7, 0.62, 0.48))
		_arrow.visible = false


func _place_kit(_delta: float) -> void:
	var s := stature_m / RIG_STATURE
	var yaw := Basis(Vector3.UP, global_rotation.y)
	if _spear and _right_hand:
		# Upright in the right hand, butt by the foot; levelled (blade at the target) on guard.
		var up_b := yaw * Basis(Vector3.RIGHT, -0.06)
		if _thrust_w > 0.0:
			var dirv := (_thrust_point - _right_hand.global_position)
			if dirv.length() > 0.1:
				dirv = dirv.normalized()
				var xa := dirv.cross(Vector3.UP)
				if xa.length() < 0.01:
					xa = Vector3.RIGHT
				xa = xa.normalized()
				var lvl := Basis(xa, dirv, xa.cross(dirv).normalized())
				up_b = Basis(up_b.get_rotation_quaternion().slerp(lvl.get_rotation_quaternion(), _thrust_w))
		# Levelled, the hand holds it nearer the butt (a third of the way up).
		var off := up_b * Vector3(0.0, 0.45 * _thrust_w, 0.0)
		_spear.global_transform = Transform3D(up_b, _right_hand.global_position + off)
	if _bow and _left_hand:
		var tilt := Basis(Vector3.RIGHT, lerpf(0.12, 0.0, _nock_w)) * Basis(Vector3.FORWARD, lerpf(0.0, 0.25, _nock_w))
		_bow.global_transform = Transform3D(yaw * tilt, _left_hand.global_position)
		_bow.scale = Vector3.ONE * maxf(s, 0.9)
		if _arrow:
			_arrow.visible = _nock_w > 0.6
			_arrow.position = Vector3(0.0, 0.0, -0.05 + 0.32 * _draw_w)
