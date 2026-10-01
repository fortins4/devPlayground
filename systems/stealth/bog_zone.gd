extends Area3D
## Wetland greybox: accept a dragged corpse and sink/conceal it (FULL bog body-drag).
## Deeper sink + splash/ripple stub for readable conceal.

signal body_hidden(corpse: Node3D)

@export var label_text: String = "Bog — hold-drag body here · release to hide"
@export var hide_sink_depth: float = 1.35
@export var hide_duration: float = 1.4
@export var splash_enabled: bool = true

var _label: Label3D
var _prompt: Label3D
var _player_inside: bool = false
var _bodies_inside: Array[Node3D] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2 | 4  # player + enemy/corpse layers
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_ensure_labels()
	add_to_group("bog_zone")


func _physics_process(_delta: float) -> void:
	_refresh_prompt()


func can_hide_here(corpse: Node3D) -> bool:
	if corpse == null or not is_instance_valid(corpse):
		return false
	if corpse.has_method("is_hidden") and bool(corpse.call("is_hidden")):
		return false
	if corpse in _bodies_inside:
		return true
	if _player_inside and corpse.has_method("is_being_dragged") and bool(corpse.call("is_being_dragged")):
		return true
	var flat := corpse.global_position - global_position
	flat.y = 0.0
	return flat.length() <= _approx_radius()


func try_hide(corpse: Node3D) -> bool:
	if not can_hide_here(corpse):
		return false
	if splash_enabled:
		_play_splash(corpse.global_position)
	if corpse.has_method("begin_hide_in_bog"):
		corpse.call("begin_hide_in_bog", self, hide_sink_depth, hide_duration)
	else:
		_fallback_sink(corpse)
	body_hidden.emit(corpse)
	return true


func _approx_radius() -> float:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node and shape_node.shape is BoxShape3D:
		var b := shape_node.shape as BoxShape3D
		return maxf(b.size.x, b.size.z) * 0.55
	return 3.2


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
	elif body.is_in_group("corpse"):
		if body not in _bodies_inside:
			_bodies_inside.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
	elif body.is_in_group("corpse"):
		_bodies_inside.erase(body)


func _ensure_labels() -> void:
	_label = get_node_or_null("BogLabel") as Label3D
	if _label == null:
		_label = Label3D.new()
		_label.name = "BogLabel"
		_label.position = Vector3(0.0, 1.35, 0.0)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 28
		_label.modulate = Color(0.4, 0.55, 0.38)
		add_child(_label)
	_label.text = label_text

	_prompt = get_node_or_null("HidePrompt") as Label3D
	if _prompt == null:
		_prompt = Label3D.new()
		_prompt.name = "HidePrompt"
		_prompt.position = Vector3(0.0, 2.15, 0.0)
		_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt.font_size = 38
		_prompt.modulate = Color(0.85, 0.95, 0.7)
		_prompt.outline_size = 6
		add_child(_prompt)
	_prompt.visible = false


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var show := false
	if player and player.has_method("get_dragged_body"):
		var corpse: Node3D = player.call("get_dragged_body") as Node3D
		if corpse and can_hide_here(corpse):
			show = true
			_prompt.text = "Release E — Hide body in bog"
	_prompt.visible = show


func _play_splash(at: Vector3) -> void:
	## Greybox splash / ripple stub: expanding ring that fades.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.55
	torus.rings = 12
	torus.ring_segments = 24
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 0.55, 0.4, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	var host := get_parent() if get_parent() else self
	host.add_child(ring)
	ring.global_position = Vector3(at.x, global_position.y + 0.08, at.z)
	ring.scale = Vector3(0.4, 0.15, 0.4)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(2.8, 0.2, 2.8), 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Secondary smaller ripple
	var ring2 := MeshInstance3D.new()
	var torus2 := TorusMesh.new()
	torus2.inner_radius = 0.2
	torus2.outer_radius = 0.32
	ring2.mesh = torus2
	var mat2 := mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(0.55, 0.65, 0.5, 0.55)
	ring2.material_override = mat2
	host.add_child(ring2)
	ring2.global_position = ring.global_position + Vector3(0.0, 0.02, 0.0)
	ring2.scale = Vector3(0.25, 0.1, 0.25)
	var tw2 := ring2.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring2, "scale", Vector3(1.8, 0.12, 1.8), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(mat2, "albedo_color:a", 0.0, 0.55)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)
	tw2.set_parallel(false)
	tw2.tween_callback(ring2.queue_free)


func _fallback_sink(corpse: Node3D) -> void:
	var tween := create_tween()
	var target := corpse.global_position + Vector3(0.0, -hide_sink_depth, 0.0)
	tween.tween_property(corpse, "global_position", target, hide_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if corpse.has_method("mark_hidden"):
		tween.tween_callback(Callable(corpse, "mark_hidden"))
