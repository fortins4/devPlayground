extends Node
class_name OpeningTimeOfDay
## Opening only: time of day follows the set sequence (no clock, nothing outside this scene).
## May, south Leinster (~52.5°N, sun declination ~+19°):
##   0 afternoon      (~15:30) intro, Máire's door talk, the bucket job: sun ~44° up in the SW
##   1 late afternoon (~18:00) the drive: sun ~25° up in the W
##   2 dusk           (~20:50) penning, the milk-cow tie, the meal: sun ~5° up in the WNW (it sets
##                    ~21:10 a little NW of west) — warm, low, long shadows, dimmer sky + ambient,
##                    still bright enough to play.
## Progress value p (0..2) comes from OpeningSequence / OpeningDriveDirector; the shown value eases
## toward it at RATE stages/s and each stage pair is blended with a smoothstep, so there are no pops.
## Drives the scene's own DirectionalLight3D ("Sun") and WorldEnvironment (a per-instance
## copy, so the packed scene resource is never edited).

@export var light_path: NodePath = ^"../Sun"
@export var env_path: NodePath = ^"../WorldEnvironment"
## Stages per second the light moves at (a whole stage takes ~22 s of play).
const RATE := 1.0 / 22.0

## Per stage: sun azimuth (deg, compass: N 0, E 90, S 180, W 270), elevation (deg), sun colour +
## energy, sky top / horizon, ground horizon, sky energy, ambient colour + energy + sky share, fog
## colour.
const STAGES := [
	{
		"name": "afternoon", "az": 235.0, "el": 44.0,
		"sun": Color(1.0, 0.96, 0.88), "sun_e": 1.25,
		"top": Color(0.40, 0.57, 0.78), "hor": Color(0.80, 0.82, 0.80), "ghor": Color(0.62, 0.62, 0.54),
		"sky_e": 1.0, "amb": Color(0.78, 0.80, 0.80), "amb_e": 0.72, "amb_sky": 1.0, "fog": Color(0.78, 0.80, 0.80),
	},
	{
		"name": "late_afternoon", "az": 272.0, "el": 25.0,
		"sun": Color(1.0, 0.86, 0.66), "sun_e": 1.12,
		"top": Color(0.42, 0.55, 0.74), "hor": Color(0.90, 0.80, 0.64), "ghor": Color(0.66, 0.60, 0.50),
		"sky_e": 0.95, "amb": Color(0.80, 0.75, 0.66), "amb_e": 0.75, "amb_sky": 0.85, "fog": Color(0.86, 0.77, 0.62),
	},
	{
		"name": "dusk", "az": 300.0, "el": 5.0,
		"sun": Color(1.0, 0.6, 0.34), "sun_e": 0.95,
		"top": Color(0.30, 0.35, 0.54), "hor": Color(0.94, 0.62, 0.42), "ghor": Color(0.52, 0.42, 0.36),
		"sky_e": 0.85, "amb": Color(0.80, 0.74, 0.76), "amb_e": 1.0, "amb_sky": 0.55, "fog": Color(0.72, 0.56, 0.48),
	},
]

var _light: DirectionalLight3D = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _seq: Node = null
var _drive: Node = null
var _shown: float = 0.0
var _target: float = 0.0
var _last_stage: String = ""


func _ready() -> void:
	add_to_group("opening_time_of_day")
	_light = get_node_or_null(light_path) as DirectionalLight3D
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we and we.environment:
		_env = we.environment.duplicate(true) as Environment
		we.environment = _env
		if _env.sky:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	_apply(0.0)
	call_deferred("_bind")


func _bind() -> void:
	_seq = get_tree().get_first_node_in_group("opening_sequence")
	_drive = get_tree().get_first_node_in_group("opening_drive")
	_target = story_progress()
	_shown = _target  # the scene opens on its stage, no blend in
	_apply(_shown)
	print("OPENING_TIME_OF_DAY_READY stage=%s p=%.2f" % [stage_name(), _shown])


func _process(delta: float) -> void:
	_target = story_progress()
	if not is_equal_approx(_shown, _target):
		_shown = move_toward(_shown, _target, RATE * delta)
		_apply(_shown)
	var s := stage_name()
	if s != _last_stage:
		_last_stage = s
		print("OPENING_TIME_OF_DAY stage=%s p=%.2f target=%.2f" % [s, _shown, _target])


## Where the story is (0 afternoon … 1 late afternoon … 2 dusk).
func story_progress() -> float:
	if _seq == null or not is_instance_valid(_seq):
		return _shown
	if bool(_seq.call("is_finished")):
		return 2.0
	match StringName(_seq.call("current_step_id")):
		&"maire":
			return 0.0
		&"bucket":
			return 0.25 if bool(_seq.call("is_step_active", &"bucket")) else 0.4
		&"drive":
			if not bool(_seq.call("is_step_active", &"drive")):
				return 0.5  # back to Máire for the drive job
			return _drive_progress()
	return 2.0  # milk, meal, closer: dusk


## The drive runs the light from late afternoon toward dusk; the herd in the pen is dusk.
func _drive_progress() -> float:
	if _drive == null or not is_instance_valid(_drive):
		return 1.0
	if bool(_drive.get("succeeded")):
		return 2.0
	match String(_drive.call("drive_beat")):
		"walk_out":
			return 1.0
		"missing", "free_her":
			return 1.15
		"rejoin", "stir":
			return 1.3
		"driving", "ambush", "regather":
			return 1.55
		"latch", "success":
			return 2.0
	return 1.0


func shown_progress() -> float:
	return _shown


func stage_name() -> String:
	return String(STAGES[clampi(int(round(_shown)), 0, STAGES.size() - 1)]["name"])


func sun_elevation_deg() -> float:
	return float(_eval(_shown)["el"])


func sun_azimuth_deg() -> float:
	return float(_eval(_shown)["az"])


## Smoke / capture helper: jump straight to a progress value (no blend).
func debug_set_progress(p: float) -> void:
	_shown = clampf(p, 0.0, 2.0)
	_apply(_shown)


func _eval(p: float) -> Dictionary:
	var v := clampf(p, 0.0, float(STAGES.size() - 1))
	var i := mini(int(floor(v)), STAGES.size() - 2)
	var f := smoothstep(0.0, 1.0, v - float(i))
	var a: Dictionary = STAGES[i]
	var b: Dictionary = STAGES[i + 1]
	var out := {}
	for k in a:
		if k == "name":
			continue
		var x = a[k]
		var y = b[k]
		out[k] = x.lerp(y, f) if x is Color else lerpf(x, y, f)
	return out


func _apply(p: float) -> void:
	var s := _eval(p)
	if _light:
		var az := deg_to_rad(float(s["az"]))
		var el := deg_to_rad(float(s["el"]))
		# Towards the sun (north −Z, east +X); the light shines along its −Z, away from it.
		var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		_light.global_transform.basis = Basis.looking_at(-to_sun, Vector3.UP)
		_light.light_color = s["sun"]
		_light.light_energy = s["sun_e"]
	if _env:
		_env.ambient_light_color = s["amb"]
		_env.ambient_light_energy = s["amb_e"]
		# The opening's ambient comes from the sky; at dusk part of it is the flat fill colour so
		# the yard in the bank's long shadow stays readable.
		_env.ambient_light_sky_contribution = s["amb_sky"]
		_env.fog_light_color = s["fog"]
	if _sky_mat:
		_sky_mat.sky_top_color = s["top"]
		_sky_mat.sky_horizon_color = s["hor"]
		_sky_mat.ground_horizon_color = s["ghor"]
		_sky_mat.sky_energy_multiplier = s["sky_e"]
