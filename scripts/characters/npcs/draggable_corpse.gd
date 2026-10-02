extends CharacterBody3D
## FULL draggable corpse: hold-E to drag, release to drop (or hide in bog), sink VFX.
## Spawned from combat kills via CorpseSpawner, or placed as greybox spoof.

enum State { GROUND, DRAGGED, HIDING, HIDDEN }

signal drag_started(by: Node3D)
signal drag_stopped
signal hidden_in_bog
signal discovered

@export var interact_range: float = 2.2
@export var drag_follow_distance: float = 1.15
@export var drag_height: float = 0.18
@export var drag_follow_lerp: float = 12.0

var state: State = State.GROUND
var _player: Node3D
var _prompt: Label3D
var _status: Label3D
var _visual: Node3D
var _mat: StandardMaterial3D
var _discovered: bool = false
var _hide_tween: Tween
var _hold_grabbed: bool = false
var discovery_count: int = 0
var _under_investigation: bool = false
var _investigate_remaining: float = 0.0


func _ready() -> void:
	add_to_group("corpse")
	collision_layer = 4
	collision_mask = 1
	_visual = get_node_or_null("Visual")
	_ensure_prompt()
	_ensure_status()
	_cache_mat()
	_find_player()
	_apply_ground_pose()
	_refresh_labels()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
	match state:
		State.DRAGGED:
			_follow_dragger(delta)
			_poll_hold_release()
		State.GROUND:
			pass
		_:
			pass
	_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _player == null:
		return
	match state:
		State.GROUND:
			if _player_in_range() and not _player_is_dragging_other():
				start_drag(_player)
				_hold_grabbed = true
				get_viewport().set_input_as_handled()
		State.DRAGGED:
			# Hold-to-drag: press while already dragging is ignored; release handles drop/hide.
			pass
		_:
			pass


func start_drag(by: Node3D) -> void:
	if state != State.GROUND:
		return
	_player = by
	state = State.DRAGGED
	_hold_grabbed = true
	if by.has_method("begin_drag"):
		by.call("begin_drag", self)
	_apply_drag_pose()
	drag_started.emit(by)
	_refresh_labels()


func stop_drag() -> void:
	if state != State.DRAGGED:
		return
	state = State.GROUND
	_hold_grabbed = false
	if _player and _player.has_method("end_drag"):
		_player.call("end_drag")
	_apply_ground_pose()
	drag_stopped.emit()
	_refresh_labels()


func begin_hide_in_bog(bog: Node3D, sink_depth: float, duration: float) -> void:
	if state == State.HIDDEN or state == State.HIDING:
		return
	if state == State.DRAGGED:
		_hold_grabbed = false
		if _player and _player.has_method("end_drag"):
			_player.call("end_drag")
	state = State.HIDING
	if bog:
		var target_xz := bog.global_position
		global_position.x = lerpf(global_position.x, target_xz.x, 0.55)
		global_position.z = lerpf(global_position.z, target_xz.z, 0.55)
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = create_tween()
	var sink_pos := global_position + Vector3(0.0, -sink_depth, 0.0)
	_hide_tween.set_parallel(true)
	_hide_tween.tween_property(self, "global_position", sink_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _visual:
		_hide_tween.tween_property(_visual, "scale", Vector3(1.05, 0.22, 1.05), duration)
		_hide_tween.tween_property(_visual, "rotation_degrees:x", 12.0, duration)
	if _mat:
		var fade := _mat.duplicate() as StandardMaterial3D
		_mat = fade
		_apply_mat_to_visual(fade)
		fade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hide_tween.tween_property(fade, "albedo_color:a", 0.12, duration)
		_hide_tween.tween_property(fade, "albedo_color", Color(0.12, 0.16, 0.1, 0.12), duration)
	_hide_tween.set_parallel(false)
	_hide_tween.tween_callback(_finish_hide)


func mark_hidden() -> void:
	_finish_hide()


func mark_discovered() -> void:
	if state == State.HIDDEN or state == State.HIDING:
		return
	_discovered = true
	discovery_count += 1
	discovered.emit()
	_refresh_labels()


func clear_discovered_flag() -> void:
	## Allows rediscovery bumps to re-flash UI without clearing heat history.
	_discovered = false
	_refresh_labels()


func set_investigation(active: bool, remaining: float = 0.0) -> void:
	## HeatTracker: body is under sentry scrutiny (pre-discovery delay).
	_under_investigation = active
	_investigate_remaining = maxf(0.0, remaining)
	_refresh_labels()


func is_under_investigation() -> bool:
	return _under_investigation


func is_hidden() -> bool:
	return state == State.HIDDEN or state == State.HIDING


func is_being_dragged() -> bool:
	return state == State.DRAGGED


func get_visibility_point() -> Vector3:
	var h := 0.55 if state == State.DRAGGED else 0.28
	return global_position + Vector3(0.0, h, 0.0)


func _finish_hide() -> void:
	state = State.HIDDEN
	_discovered = false
	_hold_grabbed = false
	hidden_in_bog.emit()
	var heat := get_tree().get_first_node_in_group("heat_tracker")
	if heat and heat.has_method("note_body_hidden"):
		heat.call("note_body_hidden", self)
	_refresh_labels()


func _try_hide_via_bog() -> bool:
	for bog in get_tree().get_nodes_in_group("bog_zone"):
		if bog and bog.has_method("try_hide") and bool(bog.call("try_hide", self)):
			return true
	return false


func _poll_hold_release() -> void:
	## Hold-to-drag: releasing Interact drops, or hides if inside a bog.
	if not _hold_grabbed:
		return
	if Input.is_action_pressed("interact"):
		return
	_hold_grabbed = false
	if _try_hide_via_bog():
		return
	stop_drag()


func _follow_dragger(delta: float) -> void:
	if _player == null:
		return
	var back := -_player.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		back = Vector3.FORWARD
	else:
		back = back.normalized()
	var want := _player.global_position - back * drag_follow_distance
	want.y = _player.global_position.y + drag_height
	global_position = global_position.lerp(want, clampf(drag_follow_lerp * delta, 0.0, 1.0))
	var face := _player.global_position - global_position
	face.y = 0.0
	if face.length_squared() > 0.01:
		rotation.y = atan2(-face.x, -face.z)


func _player_in_range() -> bool:
	if _player == null:
		return false
	return global_position.distance_to(_player.global_position) <= interact_range


func _player_is_dragging_other() -> bool:
	if _player and _player.has_method("is_dragging"):
		return bool(_player.call("is_dragging"))
	return false


func _apply_ground_pose() -> void:
	rotation.x = deg_to_rad(82.0)
	rotation.z = 0.0
	if _visual:
		_visual.position = Vector3(0.0, 0.2, 0.0)


func _apply_drag_pose() -> void:
	rotation.x = deg_to_rad(70.0)
	if _visual:
		_visual.position = Vector3(0.0, 0.15, 0.0)


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _ensure_prompt() -> void:
	_prompt = get_node_or_null("Prompt") as Label3D
	if _prompt:
		return
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.position = Vector3(0.0, 1.15, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 34
	_prompt.modulate = Color(0.92, 0.92, 0.78)
	_prompt.outline_size = 6
	_prompt.outline_modulate = Color(0.05, 0.05, 0.02, 0.85)
	add_child(_prompt)


func _ensure_status() -> void:
	_status = get_node_or_null("Status") as Label3D
	if _status:
		return
	_status = Label3D.new()
	_status.name = "Status"
	_status.position = Vector3(0.0, 1.65, 0.0)
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 30
	_status.outline_size = 6
	_status.outline_modulate = Color(0.05, 0.05, 0.02, 0.85)
	add_child(_status)


func _refresh_labels() -> void:
	if _prompt:
		match state:
			State.GROUND:
				_prompt.visible = _player_in_range()
				_prompt.text = "Hold E — Drag body"
				_prompt.modulate = Color(0.92, 0.92, 0.78)
			State.DRAGGED:
				_prompt.visible = true
				if _in_bog_now():
					_prompt.text = "Release E — Hide in bog"
					_prompt.modulate = Color(0.7, 0.95, 0.65)
				else:
					_prompt.text = "Hold E — dragging · release to drop"
					_prompt.modulate = Color(0.95, 0.9, 0.55)
			State.HIDING:
				_prompt.visible = true
				_prompt.text = "Sinking into peat…"
				_prompt.modulate = Color(0.55, 0.7, 0.5)
			State.HIDDEN:
				_prompt.visible = true
				_prompt.text = "CONCEALED in bog"
				_prompt.modulate = Color(0.4, 0.7, 0.45)
			_:
				_prompt.visible = false
	if _status:
		if state == State.HIDDEN:
			_status.text = "[CONCEALED]"
			_status.modulate = Color(0.35, 0.75, 0.45)
		elif _discovered:
			var n := discovery_count if discovery_count > 0 else 1
			_status.text = "[DISCOVERED ×%d]" % n
			_status.modulate = Color(0.98, 0.28, 0.18)
		elif _under_investigation:
			_status.text = "[UNDER SCRUTINY %.1fs]" % _investigate_remaining
			_status.modulate = Color(0.98, 0.82, 0.28)
		elif state == State.DRAGGED:
			_status.text = "[dragging]"
			_status.modulate = Color(0.9, 0.82, 0.4)
		elif state == State.HIDING:
			_status.text = "[hiding…]"
			_status.modulate = Color(0.55, 0.7, 0.5)
		else:
			_status.text = "[body]"
			_status.modulate = Color(0.72, 0.66, 0.55)


func _in_bog_now() -> bool:
	for bog in get_tree().get_nodes_in_group("bog_zone"):
		if bog and bog.has_method("can_hide_here") and bool(bog.call("can_hide_here", self)):
			return true
	return false


func _cache_mat() -> void:
	if _visual == null:
		return
	var body := _visual.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var existing := body.get_active_material(0)
	if existing is StandardMaterial3D:
		_mat = (existing as StandardMaterial3D).duplicate() as StandardMaterial3D
		body.material_override = _mat
	else:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.35, 0.28, 0.25)
		body.material_override = _mat


func _apply_mat_to_visual(mat: StandardMaterial3D) -> void:
	if _visual == null:
		return
	for child in _visual.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat
