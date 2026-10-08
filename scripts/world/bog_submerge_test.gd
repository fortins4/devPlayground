extends Node3D
## Minimal bog-submerge test ground: flat peat field, one deep bog, a patrol
## path that brushes the bank, and a watch post. Geometry built at runtime so
## the .tscn stays small; gameplay nodes (Player, BogZone, Sentries) live in it.

@export var ground_size: float = 60.0


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_reeds()


func _build_environment() -> void:
	if get_node_or_null("WorldEnvironment") == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.42, 0.52, 0.62)
		mat.sky_horizon_color = Color(0.70, 0.72, 0.70)
		mat.ground_horizon_color = Color(0.45, 0.46, 0.38)
		mat.ground_bottom_color = Color(0.22, 0.22, 0.16)
		sky.sky_material = mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.45
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color(0.66, 0.68, 0.64)
		env.fog_density = 0.006
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		we.environment = env
		add_child(we)
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
		sun.light_energy = 0.95
		sun.light_color = Color(1.0, 0.96, 0.88)
		sun.shadow_enabled = true
		add_child(sun)


func _build_ground() -> void:
	if get_node_or_null("Ground") != null:
		return
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 1.0, ground_size)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.29, 0.13)
	m.roughness = 0.96
	mi.material_override = m
	body.add_child(mi)
	add_child(body)


func _build_reeds() -> void:
	var bog := get_node_or_null("DeepBog") as Node3D
	if bog == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.46, 0.22)
	mat.roughness = 0.9
	var holder := Node3D.new()
	holder.name = "Reeds"
	add_child(holder)
	for i in 40:
		var a := rng.randf() * TAU
		var r := 3.9 + rng.randf_range(0.0, 1.6)
		# Leave the patrol side (+Z) and the player's approach (-X) open.
		if sin(a) > 0.55 or cos(a) < -0.75:
			continue
		var reed := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.008
		cyl.bottom_radius = 0.02
		cyl.height = rng.randf_range(0.6, 1.2)
		cyl.radial_segments = 4
		reed.mesh = cyl
		reed.material_override = mat
		reed.position = bog.position + Vector3(cos(a) * r, cyl.height * 0.5, sin(a) * r)
		reed.rotation = Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		holder.add_child(reed)
