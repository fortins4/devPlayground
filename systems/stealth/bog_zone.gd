extends Area3D
## Wetland greybox: accept a dragged corpse and sink/conceal it (FULL bog body-drag).
## Deeper sink + splash/ripple stub for readable conceal.
## deep_water: the player can also slip in (PlayerBogSubmerge reads is_deep_at /
## water_surface_y and calls play_ripple / play_bog_sound). Off by default, so the
## body-drag bogs behave exactly as before.

signal body_hidden(corpse: Node3D)

@export var label_text: String = "Bog — hold-drag body here · release to hide"
@export var hide_sink_depth: float = 1.35
@export var hide_duration: float = 1.4
@export var splash_enabled: bool = true

@export_group("Deep water (player submerge)")
## Deep enough to slip under. Shallow body-drag bogs leave this off.
@export var deep_water: bool = false
## Water surface height, local to this zone.
@export var water_level: float = 0.04
## Mean radius of the organic open-water outline (local XZ).
@export var deep_radius: float = 3.2
## Keep the sink this far inside the outline so the body never meets the bank.
@export var deep_edge_margin: float = 0.45
## Build the murky water surface + mud rim for this zone at runtime.
@export var build_water_visual: bool = true

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
	if deep_water:
		add_to_group("bog_deep")
		if build_water_visual:
			_build_deep_water_visual()


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


# --- Deep water (player submerge) -------------------------------------------

func is_deep() -> bool:
	return deep_water


func water_surface_y() -> float:
	return global_position.y + water_level


## Outline radius at local angle theta (lumpy, not a circle).
func outline_radius(theta: float) -> float:
	return deep_radius * (1.0 + 0.11 * sin(3.0 * theta + 1.3) + 0.06 * sin(5.0 * theta + 0.4) + 0.04 * sin(7.0 * theta + 2.1))


## True where the water is deep enough to slip under (inside the outline, with margin).
func is_deep_at(world_pos: Vector3) -> bool:
	if not deep_water:
		return false
	var local := to_local(world_pos)
	var r := Vector2(local.x, local.z)
	var theta := atan2(r.y, r.x)
	return r.length() <= outline_radius(theta) - deep_edge_margin


func is_in_water(world_pos: Vector3) -> bool:
	if not deep_water:
		return false
	var local := to_local(world_pos)
	var r := Vector2(local.x, local.z)
	return r.length() <= outline_radius(atan2(r.y, r.x))


## Flat ripple on the deep-water surface. strength ~0.3 (creep) .. 1.4 (fast / slip-in).
func play_ripple(at: Vector3, strength: float = 1.0) -> void:
	var y := water_surface_y() + 0.015
	var rings := 1 if strength < 0.55 else (2 if strength < 1.0 else 3)
	var host := get_parent() if get_parent() else self
	for i in rings:
		var ring := MeshInstance3D.new()
		ring.name = "BogRipple"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.5
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.62, 0.66, 0.52, clampf(0.35 + 0.35 * strength, 0.25, 0.8))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(ring)
		ring.global_position = Vector3(at.x, y + 0.004 * i, at.z)
		var s0 := 0.35 + 0.15 * i
		ring.scale = Vector3(s0, 0.04, s0)
		var s1 := (1.1 + 1.6 * strength) * (1.0 - 0.22 * i)
		var dur := 0.9 + 0.5 * strength + 0.15 * i
		var tw := ring.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "scale", Vector3(s1, 0.04, s1), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.09 * i)
		tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.09 * i)
		tw.set_parallel(false)
		tw.tween_callback(ring.queue_free)


## Splash / squelch / gasp one-shot (placeholder procedural audio).
func play_bog_sound(kind: StringName, at: Vector3, strength: float = 1.0) -> void:
	var host := get_parent() if get_parent() else self
	BogSfx.play(host, kind, at, strength)


func _build_deep_water_visual() -> void:
	if get_node_or_null("DeepWater") != null:
		return
	var segs := 48
	# Opaque murky surface: dark peat water, low roughness for a wet sheen.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.0, water_level, 0.0)
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var p0 := Vector3(cos(a0) * outline_radius(a0), water_level, sin(a0) * outline_radius(a0))
		var p1 := Vector3(cos(a1) * outline_radius(a1), water_level, sin(a1) * outline_radius(a1))
		st.set_normal(Vector3.UP)
		st.set_color(Color(0.035, 0.03, 0.018))
		st.add_vertex(center)
		st.set_color(Color(0.075, 0.062, 0.035))
		st.add_vertex(p1)
		st.add_vertex(p0)
	var water := MeshInstance3D.new()
	water.name = "DeepWater"
	water.mesh = st.commit()
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.albedo_color = Color(1.0, 1.0, 1.0)
	wm.roughness = 0.3
	wm.metallic_specular = 0.22
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# Mud rim: a soft band from the waterline out onto the bank.
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wet := Color(0.17, 0.14, 0.09)
	var dry := Color(0.27, 0.25, 0.15)
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var r0 := outline_radius(a0)
		var r1 := outline_radius(a1)
		var w0 := 0.9 + 0.35 * sin(4.0 * a0 + 0.7)
		var w1 := 0.9 + 0.35 * sin(4.0 * a1 + 0.7)
		var y := water_level - 0.015
		var yo := 0.012
		var i0 := Vector3(cos(a0) * (r0 - 0.08), y, sin(a0) * (r0 - 0.08))
		var i1 := Vector3(cos(a1) * (r1 - 0.08), y, sin(a1) * (r1 - 0.08))
		var o0 := Vector3(cos(a0) * (r0 + w0), yo, sin(a0) * (r0 + w0))
		var o1 := Vector3(cos(a1) * (r1 + w1), yo, sin(a1) * (r1 + w1))
		for v in [[i0, wet], [o1, dry], [o0, dry], [i0, wet], [i1, wet], [o1, dry]]:
			rim.set_normal(Vector3.UP)
			rim.set_color(v[1])
			rim.add_vertex(v[0])
	var rim_mi := MeshInstance3D.new()
	rim_mi.name = "MudRim"
	rim_mi.mesh = rim.commit()
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.roughness = 0.55
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim_mi.material_override = rm
	rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim_mi)
	# A few tussocks on the rim so it reads as bog, not a puddle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var tuft_mat := StandardMaterial3D.new()
	tuft_mat.albedo_color = Color(0.36, 0.38, 0.17)
	tuft_mat.roughness = 0.95
	for k in 14:
		var a := rng.randf() * TAU
		var rr := outline_radius(a) + rng.randf_range(0.15, 0.9)
		var tuft := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = rng.randf_range(0.05, 0.12)
		cyl.bottom_radius = rng.randf_range(0.18, 0.3)
		cyl.height = rng.randf_range(0.18, 0.42)
		cyl.radial_segments = 7
		tuft.mesh = cyl
		tuft.material_override = tuft_mat
		tuft.position = Vector3(cos(a) * rr, cyl.height * 0.5, sin(a) * rr)
		tuft.name = "Tussock%d" % k
		add_child(tuft)
