extends Node3D
class_name OpeningKnifeHitchChore
## Self-contained opening-farm chore: cut a tethered cow free near the byre with the knife.
## Additive soft progress cue; does not gate cattle soft success.
##
## Interact: E in range (~2.5 m) with knife equipped. States: tethered → cut → done.

enum HitchState { TETHERED, CUT, DONE }

const INTERACT_RANGE := 2.5
## Hitch post east of byre trough — outside byre door / home-pen side, clear of trough & bucket.
const HITCH_POS := Vector3(9.5, 0.0, 1.8)
const ANIMAL_TETHERED_POS := Vector3(10.35, 0.0, 2.55)
const ANIMAL_FREE_POS := Vector3(12.2, 0.0, 4.6)
## Avoid clipping: trough (8.2,0,0.4), bucket spawn (5.2,0,2.5).

const C_POST := Color(0.38, 0.28, 0.16)
const C_POST_DARK := Color(0.28, 0.20, 0.12)
const C_ROPE := Color(0.55, 0.48, 0.32)
const C_HIDE := Color(0.62, 0.48, 0.32)
const C_HIDE_DARK := Color(0.48, 0.36, 0.24)
const C_HORN := Color(0.78, 0.72, 0.58)

@export var director_path: NodePath = ^"../OpeningDriveDirector"

var _state: HitchState = HitchState.TETHERED
var _player: Node3D = null
var _director: Node = null
var _hitch_root: Node3D = null
var _rope: Node3D = null
var _animal: Node3D = null
var _prompt_timer: float = 0.0
var _mats: Dictionary = {}
var _free_wander_t: float = 0.0


func _ready() -> void:
	add_to_group("opening_knife_hitch")
	_build_props()
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_director = get_node_or_null(director_path)
	print(
		"OPENING_KNIFE_HITCH_READY hitch=%s animal=%s"
		% [HITCH_POS, ANIMAL_TETHERED_POS]
	)


func _process(delta: float) -> void:
	if _prompt_timer > 0.0:
		_prompt_timer -= delta
	if _state == HitchState.DONE and _animal and _animal.visible:
		_free_wander_t += delta
		# Gentle idle sway so the freed animal reads as free, not a statue.
		var wobble := sin(_free_wander_t * 0.7) * 0.08
		_animal.position = ANIMAL_FREE_POS + Vector3(wobble, 0.0, wobble * 0.4)
		_animal.rotation.y = 0.35 + sin(_free_wander_t * 0.4) * 0.12


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_E:
			if _try_interact():
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- queries (smoke / stills)

func chore_done() -> bool:
	return _state == HitchState.DONE


func hitch_state() -> String:
	match _state:
		HitchState.TETHERED:
			return "tethered"
		HitchState.CUT:
			return "cut"
		HitchState.DONE:
			return "done"
	return "unknown"


func hitch_pos() -> Vector3:
	return HITCH_POS


func animal_pos() -> Vector3:
	if _animal and is_instance_valid(_animal):
		return _animal.global_position
	return ANIMAL_TETHERED_POS


func interact_prompt() -> String:
	if _state != HitchState.TETHERED or _player == null or not is_instance_valid(_player):
		return ""
	if not _near(_player.global_position, HITCH_POS):
		return ""
	if _knife_equipped():
		return "E — cut tether"
	return "Draw knife (2) to cut the tether"


func is_active() -> bool:
	return _state != HitchState.DONE


## Smoke / capture: force state without walking.
func debug_set_state(state_name: String) -> void:
	force_state(state_name)


func force_state(state_name: String) -> void:
	match state_name:
		"tethered":
			_set_tethered()
		"cut":
			_set_tethered()
			_apply_cut(false)
		"done":
			_set_tethered()
			_apply_cut(false)
			_finish_free(false)
		_:
			push_warning("OpeningKnifeHitchChore.force_state unknown: " + state_name)


## Capture helper: cut tether immediately (requires no player proximity).
func debug_cut() -> void:
	if _state == HitchState.TETHERED:
		_apply_cut(true)
		_finish_free(true)


# ---------------------------------------------------------------- interact

func try_interact() -> bool:
	return _try_interact()


func _try_interact() -> bool:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return false
	if _state != HitchState.TETHERED:
		return false
	var p := _player.global_position
	if not _near(p, HITCH_POS):
		return false
	if not _knife_equipped():
		_flash("Draw the knife (2) to cut the tether.", 3.0)
		return true
	_apply_cut(true)
	_finish_free(true)
	return true


func _knife_equipped() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var combat := _player.get_node_or_null("CombatSystem")
	if combat == null:
		return false
	# CombatSystem.Weapon.KNIFE = 1
	if "current_weapon" in combat:
		return int(combat.get("current_weapon")) == 1
	if combat.has_method("weapon_name"):
		return String(combat.call("weapon_name")) == "knife"
	return false


func _apply_cut(announce: bool) -> void:
	_state = HitchState.CUT
	if _rope:
		_rope.visible = false
	if announce:
		_flash("Tether cut — she's free to join the drive.", 3.5)
		print("OPENING_KNIFE_HITCH_CUT")


func _finish_free(announce: bool) -> void:
	_state = HitchState.DONE
	if _rope:
		_rope.visible = false
	if _animal:
		_animal.position = ANIMAL_FREE_POS
		_animal.rotation.y = 0.35
	_free_wander_t = 0.0
	if announce:
		print("OPENING_KNIFE_HITCH_SOFT_SUCCESS")


func _set_tethered() -> void:
	_state = HitchState.TETHERED
	_free_wander_t = 0.0
	if _rope:
		_rope.visible = true
	if _animal:
		_animal.position = ANIMAL_TETHERED_POS
		_animal.rotation.y = -0.55


# ---------------------------------------------------------------- geometry

func _build_props() -> void:
	_hitch_root = Node3D.new()
	_hitch_root.name = "HitchPost"
	_hitch_root.position = HITCH_POS
	add_child(_hitch_root)

	# Timber post + cross-rail.
	_mesh_cyl(_hitch_root, Vector3(0.0, 0.7, 0.0), 0.09, 0.11, 1.4, C_POST)
	_mesh_box(_hitch_root, Vector3(0.0, 1.15, 0.0), Vector3(0.55, 0.08, 0.08), C_POST_DARK)
	_mesh_box(_hitch_root, Vector3(0.0, 0.08, 0.0), Vector3(0.28, 0.12, 0.28), C_POST_DARK)

	var label := Label3D.new()
	label.text = "Hitch"
	label.font_size = 26
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9, 0.85, 0.65)
	label.outline_size = 8
	label.position = Vector3(0.0, 1.85, 0.0)
	_hitch_root.add_child(label)

	_rope = Node3D.new()
	_rope.name = "TetherRope"
	add_child(_rope)
	_build_rope()

	_animal = _make_calf_mesh("TetheredCalf")
	_animal.position = ANIMAL_TETHERED_POS
	_animal.rotation.y = -0.55
	add_child(_animal)


func _build_rope() -> void:
	# Simple segmented rope from post rail toward animal neck.
	var from := HITCH_POS + Vector3(0.0, 1.15, 0.0)
	var to := ANIMAL_TETHERED_POS + Vector3(0.0, 0.85, 0.15)
	var mid := from.lerp(to, 0.5) + Vector3(0.0, -0.18, 0.0)
	_rope_seg(from, mid)
	_rope_seg(mid, to)
	# Collar knot at neck.
	_mesh_cyl(_rope, to, 0.07, 0.07, 0.06, C_ROPE.darkened(0.15))


func _rope_seg(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = maxf(0.05, length)
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _mat(C_ROPE)
	# Orient cylinder (Y-up) along a→b via Basis — safe before add_child.
	var dir := (b - a).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT)
	# Cylinder height is along local Y; looking_at aims -Z, so rotate +90° about X.
	mi.transform = Transform3D(basis, mid) * Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3.ZERO)
	_rope.add_child(mi)


func _make_calf_mesh(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	# Compact greybox calf — smaller than herd cows, readable next to hitch.
	_mesh_box(root, Vector3(0.0, 0.55, 0.0), Vector3(0.55, 0.55, 1.05), C_HIDE)
	_mesh_box(root, Vector3(0.0, 0.72, 0.58), Vector3(0.38, 0.38, 0.42), C_HIDE_DARK)
	_mesh_box(root, Vector3(0.0, 0.55, 0.82), Vector3(0.22, 0.18, 0.2), C_HIDE)
	# Legs.
	for ox in [-0.18, 0.18]:
		for oz in [-0.35, 0.32]:
			_mesh_box(root, Vector3(ox, 0.18, oz), Vector3(0.1, 0.36, 0.1), C_HIDE_DARK)
	# Short horns.
	_mesh_box(root, Vector3(-0.16, 0.95, 0.55), Vector3(0.06, 0.12, 0.06), C_HORN)
	_mesh_box(root, Vector3(0.16, 0.95, 0.55), Vector3(0.06, 0.12, 0.06), C_HORN)
	return root


# ---------------------------------------------------------------- helpers

func _near(p: Vector3, target: Vector3, range_m: float = INTERACT_RANGE) -> bool:
	var a := Vector3(p.x, 0.0, p.z)
	var b := Vector3(target.x, 0.0, target.z)
	return a.distance_to(b) <= range_m


func _flash(text: String, secs: float = 3.0) -> void:
	_prompt_timer = secs
	if _director and _director.has_method("flash"):
		_director.call("flash", text, secs)
	elif _director and _director.has_method("_flash"):
		_director.call("_flash", text, secs)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	_mats[key] = m
	return m


func _mesh_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mesh_cyl(parent: Node, pos: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi
