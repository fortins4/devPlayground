extends Node3D
class_name PrologueHaze
## Prologue step 2: a thin haze and a low smudge of smoke far off to the south-south-west, toward
## the coast, hanging against the last of the afterglow — what is never said in-game: the cooking
## fires of the camp at the strand, ~10 km off. Low, flat, spread haze (no columns, no fire-glow on
## the sky): it stays a hint the herd-hand can put down to someone's charcoal clamp.
## Built from a few soft unshaded sheets standing at the world's far edge, facing the ráth; fog
## off on them (they are already "distance").

const Terrain := preload("res://scripts/prologue/opening_terrain.gd")
const ORIGIN := Vector3(2.4, 0.0, 17.45)  ## the bank by the gate, where it is seen from
const DIR_DEG := 195.0                    ## compass bearing (S = 180): a little west of south
const DIST := 330.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.52, 0.47, 0.46, 1.0);
uniform float density = 0.3;
uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	float across = smoothstep(0.0, 0.3, uv.x) * smoothstep(1.0, 0.7, uv.x);
	float up = smoothstep(1.0, 0.55, uv.y) * smoothstep(0.0, 0.25, uv.y);
	float wisp = 0.55 + 0.45 * n(vec2(uv.x * 7.0, uv.y * 2.5)) * n(vec2(uv.x * 3.0 + 4.0, uv.y * 5.0));
	ALBEDO = tint.rgb;
	ALPHA = clamp(across * up * wisp * density, 0.0, 1.0);
}
"""

var _sheets: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("prologue_haze")
	top_level = true
	global_transform = Transform3D.IDENTITY
	var sh := Shader.new()
	sh.code = SHADER
	var az := deg_to_rad(DIR_DEG)
	var fwd := Vector3(sin(az), 0.0, -cos(az))  # compass: N −Z, E +X
	var centre := ORIGIN + fwd * DIST
	var right := Vector3.UP.cross(-fwd).normalized()
	# Sit the sheets on the skyline as seen from the bank: they rise from just behind the last
	# hill line (not hidden under it, not floating above it).
	var base_y := _skyline_y(fwd) - 3.0
	print("PROLOGUE_HAZE bearing=%.0f dist=%.0f base_y=%.1f" % [DIR_DEG, DIST, base_y])
	# [offset along the horizon (m), base y, width, height, density, tint, seed]
	var layers := [
		[0.0, 0.0, 300.0, 18.0, 0.42, Color(0.56, 0.50, 0.50), 1.0],   # the wide thin haze
		[-30.0, 1.0, 120.0, 13.0, 0.5, Color(0.45, 0.41, 0.42), 2.0],  # thicker core of it
		[-38.0, 2.0, 42.0, 10.0, 0.62, Color(0.33, 0.31, 0.33), 3.0],   # the low smudge of smoke
	]
	for i in layers.size():
		var L: Array = layers[i]
		var mi := MeshInstance3D.new()
		mi.name = "HazeSheet%d" % i
		var q := QuadMesh.new()
		q.size = Vector2(L[2], L[3])
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tint", L[5])
		m.set_shader_parameter("density", L[4])
		m.set_shader_parameter("seed", L[6])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p: Vector3 = centre + right * float(L[0]) + Vector3(0.0, base_y + float(L[1]) + float(L[3]) * 0.5, 0.0) - fwd * float(i) * 4.0
		# Quad faces +Z: turn it to face back toward the ráth.
		mi.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), p)
		add_child(mi)
		_sheets.append(mi)


func bearing_deg() -> float:
	return DIR_DEG


func centre_point() -> Vector3:
	var az := deg_to_rad(DIR_DEG)
	return ORIGIN + Vector3(sin(az), 0.0, -cos(az)) * DIST + Vector3(0.0, 8.0, 0.0)


## Height at DIST of the skyline seen from a man on the bank (eye ~1.6 m over the crest): the
## steepest terrain rise along the bearing, carried out to the sheets.
func _skyline_y(fwd: Vector3) -> float:
	var eye := Terrain.surface_y(ORIGIN.x, ORIGIN.z) + 1.6
	var best := -INF
	var d := 20.0
	while d < DIST - 5.0:
		var p := ORIGIN + fwd * d
		best = maxf(best, (Terrain.surface_y(p.x, p.z) - eye) / d)
		d += 5.0
	return eye + best * DIST
