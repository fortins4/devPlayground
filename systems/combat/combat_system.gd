class_name CombatSystem
extends Node
## Reusable greybox combat component. Player feel target is the cattle goad
## (hold-release shaft swings, same 0.75s full charge as the hatchet).
## Hatchet hold-release (top/left/right only) stays intact. No charge glow.
## Goad guard follows look. It is not a parry and not a held key. Chest stops
## any frontal hit. Left, right, high, and low stop only that side.
## The point jab is an uncharged bottom strike, never a charge direction.
## Knife is a tap: left/right cuts, top thrust. No knife charge, no bottom stab.
## Attach as child of a CharacterBody3D (player or NPC). Expects optional siblings:
## Hitbox (Area3D), Hurtbox (Area3D), WeaponVisual (Node3D with mesh children).

const StaminaEconomy := preload("res://systems/combat/stamina_economy.gd")
const HatchetAttackTable := preload("res://systems/combat/hatchet_attack_table.gd")
const ChargeStaminaTable := preload("res://systems/combat/charge_stamina_table.gd")

signal attack_performed(attacker: Node, kind: StringName, weapon: StringName)
signal hit_landed(attacker: Node, target: Node, damage: float, kind: StringName)
signal damage_taken(amount: float, from: Node)
signal stamina_changed(current: float, maximum: float)
signal health_changed(current: float, maximum: float)
signal blocked(defender: Node, attacker: Node, mitigated: float)
## Posture pool emptied — CombatTags stagger applied (Godot feel / sparring AI hook).
signal posture_broken(victim: Node, stagger_tag: StringName, duration_sec: float)
signal died(victim: Node)
signal weapon_changed(weapon: StringName)
signal charge_started(weapon: StringName)
signal charge_updated(ratio: float, direction: StringName)
signal charge_cancelled(weapon: StringName)
signal charge_released(ratio: float, direction: StringName, kind: StringName)

enum Weapon { HATCHET, KNIFE, GOAD }
enum StrikeDirection { TOP, LEFT, RIGHT, BOTTOM }

const DIRECTION_NAMES := {
	StrikeDirection.TOP: &"top",
	StrikeDirection.LEFT: &"left",
	StrikeDirection.RIGHT: &"right",
	StrikeDirection.BOTTOM: &"bottom",
}

const WEAPON_NAMES := {
	Weapon.HATCHET: &"hatchet",
	Weapon.KNIFE: &"knife",
	Weapon.GOAD: &"goad",
}

@export var max_health: float = 100.0
## Defaults seed from StaminaEconomy (systems/combat/stamina_economy.gd).
@export var max_stamina: float = StaminaEconomy.MAX_STAMINA
@export var stamina_regen_per_sec: float = StaminaEconomy.REGEN_PER_SEC
@export var sprint_stamina_per_sec: float = StaminaEconomy.SPRINT_DRAIN_PER_SEC
@export var team: int = 0 ## 0 = player allies, 1 = hostiles
@export var starting_weapon: Weapon = Weapon.HATCHET
@export var enable_block: bool = false ## Shield later; off for cattle-farm starter kit
@export var enable_face_guard: bool = false ## Sparring face-guard / posture; off for player kit
@export var enable_hit_feedback: bool = true
@export var hurt_flash_secs: float = 0.14
@export var knockback_light: float = 2.8
@export var knockback_heavy: float = 4.6
@export var hit_stop_light: float = 0.045
@export var hit_stop_heavy: float = 0.075
@export var hit_stop_charged: float = 0.11 ## Extra freeze on charged/heavy hatchet contact
@export var charged_impact_scale: float = 0.05 ## Engine time_scale during charged hit-stop
@export var show_damage_numbers: bool = true
@export var charge_full_secs: float = 0.75 ## Hold time to reach full power (hatchet) — USER LOCK
@export var charge_min_release_secs: float = 0.08 ## Below this = tap light
@export var enable_directional_hatchet: bool = true

var health: float = 100.0
var stamina: float = StaminaEconomy.MAX_STAMINA
var current_weapon: Weapon = Weapon.HATCHET
var is_dead: bool = false
var is_blocking: bool = false
## Goad only: held shaft guard. Not enable_block (shield) and not a timed parry.
var is_shaft_blocking: bool = false
## Which way the held goad faces. chest | left | right | high | low.
## chest keeps the old frontal catch. The other four stop only that side.
## Independent of sparring guard_face / BlockPostureTable.
var shaft_guard_face: StringName = &"chest"
## Which strike face is guarded when blocking (top/left/right). Mismatch = open.
var guard_direction: StrikeDirection = StrikeDirection.TOP
## Face-guard posture (BlockPostureTable). Used when enable_face_guard; independent of shield block.
var guard_face: StringName = BlockPostureTable.DEFAULT_FACE
var posture: float = BlockPostureTable.MAX_POSTURE
var posture_break_left: float = 0.0
## Last posture-break → stagger apply (probe / Godot).
var _last_posture_break: Dictionary = {}
var _last_guard_resolve: Dictionary = {}
var _last_flank_resolve: Dictionary = {}
var is_attacking: bool = false
var attack_recovery_left: float = 0.0
var hitbox_active_left: float = 0.0
## Countdown before passive regen after spend / after attack recovery ends.
var stamina_regen_delay_left: float = 0.0

var _hit_this_swing: Dictionary = {} ## instance_id -> true
var _owner_body: Node3D
var _hitbox: Area3D
var _hurtbox: Area3D
var _weapon_visual: Node3D
var _weapon_rest_transform: Transform3D
var _swing_tween: Tween
var _last_attack_kind: StringName = &"light"
var _last_windup: float = 0.16
var _last_active: float = 0.12
var _last_recovery: float = 0.34
var _last_attack_direction: StringName = &""
var _last_attack_tier: StringName = &""
var _last_attack_damage: float = -1.0
var _last_attack_reach: float = -1.0
## Power passed into the last committed strike. -1 = discrete light/heavy.
## 0 = tap release, 1 = full 0.75s hold. Mid values sit between.
var last_attack_power: float = -1.0
## Last hatchet charge↔STA spend (ChargeStaminaTable; set on release commit).
var _last_charge_spend_tier: StringName = &""
var _last_charge_spend_cost: float = -1.0
## Last CombatTags applied on a successful hit (attacker-side probe).
var _last_hit_tags: Array[StringName] = []
var _last_hit_tags_weapon: StringName = &""
## Target-local stagger stub (seconds left). Godot / dummy can poll; no full CC sim.
var stagger_left: float = 0.0
var last_stagger_tag: StringName = &""
var last_stagger_interrupt: int = 0
var knockback_vel: Vector3 = Vector3.ZERO
var _hurt_flash_tween: Tween
var _hit_stop_running: bool = false
var _mesh_overlays: Array[MeshInstance3D] = []

## Hold-to-charge (hatchet-first directional chop).
var is_charging: bool = false
var charge_time: float = 0.0
var charge_ratio: float = 0.0
var charge_direction: StrikeDirection = StrikeDirection.TOP
var _last_strike_direction: StrikeDirection = StrikeDirection.TOP
var _charge_pose_tween: Tween

# Per-weapon feel timings. Knife/goad: damage+reach live here.
# Hatchet damage/reach: HatchetAttackTable (direction × charge tier). PROFILES
# hatchet damage/reach kept as fallback when table unavailable.
# Stamina cost + recovery: StaminaEconomy.ATTACK for knife/goad light/heavy.
# Hatchet charge-tier STA: ChargeStaminaTable (tap/charged/max) on release commit.
const PROFILES := {
	Weapon.HATCHET: {
		# Timing polish: clearer windup telegraph, readable contact, non-spam recover.
		# Direction multipliers applied in try_attack via HATCHET_DIR_TIMING.
		&"light": {"damage": 14.0, "windup": 0.16, "active": 0.12, "reach": 1.35},
		&"heavy": {"damage": 28.0, "windup": 0.34, "active": 0.16, "reach": 1.5},
	},
	Weapon.KNIFE: {
		# Longer than the old chest-tuck, still short of the goad (1.65 / 2.2).
		&"light": {"damage": 8.0, "windup": 0.06, "active": 0.1, "reach": 1.28},
		&"heavy": {"damage": 16.0, "windup": 0.12, "active": 0.12, "reach": 1.42},
	},
	Weapon.GOAD: {
		# Hold-release: tap/early = light, full 0.75s = heavy. Power lerps between.
		&"light": {"damage": 10.0, "windup": 0.18, "active": 0.14, "reach": 1.65},
		&"heavy": {"damage": 22.0, "windup": 0.30, "active": 0.18, "reach": 2.2},
	},
}

## Per-direction timing scales for hatchet (feel): top = overhead telegraph + commit;
## left/right = snappier cock, slightly wider contact, quicker recover.
const HATCHET_DIR_TIMING := {
	StrikeDirection.TOP: {"windup": 1.00, "active": 0.95, "recovery": 1.05},
	StrikeDirection.LEFT: {"windup": 0.82, "active": 1.10, "recovery": 0.90},
	StrikeDirection.RIGHT: {"windup": 0.85, "active": 1.15, "recovery": 0.92},
}


func _ready() -> void:
	health = max_health
	stamina = max_stamina
	posture = BlockPostureTable.MAX_POSTURE
	guard_face = BlockPostureTable.DEFAULT_FACE
	current_weapon = starting_weapon
	_owner_body = get_parent() as Node3D
	_hitbox = get_node_or_null("../Hitbox") as Area3D
	if _hitbox == null:
		_hitbox = get_node_or_null("Hitbox") as Area3D
	_hurtbox = get_node_or_null("../Hurtbox") as Area3D
	if _hurtbox == null:
		_hurtbox = get_node_or_null("Hurtbox") as Area3D
	_weapon_visual = get_node_or_null("../WeaponVisual") as Node3D
	if _weapon_visual == null:
		_weapon_visual = get_node_or_null("WeaponVisual") as Node3D
	if _hitbox:
		_hitbox.monitoring = false
		_hitbox.monitorable = false
		if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			_hitbox.body_entered.connect(_on_hitbox_body_entered)
		if not _hitbox.area_entered.is_connected(_on_hitbox_area_entered):
			_hitbox.area_entered.connect(_on_hitbox_area_entered)
	if _weapon_visual:
		_weapon_rest_transform = _weapon_visual.transform
	_apply_weapon_visual()
	stamina_changed.emit(stamina, max_stamina)
	health_changed.emit(health, max_health)
	weapon_changed.emit(WEAPON_NAMES[current_weapon])


func _physics_process(delta: float) -> void:
	if knockback_vel.length_squared() > 0.0001:
		knockback_vel = knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
	else:
		knockback_vel = Vector3.ZERO

	if stagger_left > 0.0:
		stagger_left = maxf(0.0, stagger_left - delta)

	if is_dead:
		return

	if is_charging:
		charge_time += delta
		charge_ratio = clampf(charge_time / maxf(0.05, charge_full_secs), 0.0, 1.0)
		_update_charge_pose(charge_ratio, charge_direction)
		charge_updated.emit(charge_ratio, DIRECTION_NAMES[charge_direction])

	if attack_recovery_left > 0.0:
		attack_recovery_left = maxf(0.0, attack_recovery_left - delta)
		if attack_recovery_left <= 0.0:
			is_attacking = false
			# Recover window closed — gate regen so the recovery beat matters.
			_arm_stamina_regen_delay()

	if hitbox_active_left > 0.0:
		hitbox_active_left = maxf(0.0, hitbox_active_left - delta)
		if hitbox_active_left <= 0.0 and _hitbox:
			_hitbox.monitoring = false

	if stamina_regen_delay_left > 0.0:
		stamina_regen_delay_left = maxf(0.0, stamina_regen_delay_left - delta)

	var regenerating := (
		not is_attacking
		and not is_blocking
		and not is_shaft_blocking
		and not is_charging
		and stamina_regen_delay_left <= 0.0
	)
	if regenerating and stamina < max_stamina:
		stamina = minf(max_stamina, stamina + stamina_regen_per_sec * delta)
		stamina_changed.emit(stamina, max_stamina)

	if is_blocking and enable_block:
		var block_drain := StaminaEconomy.BLOCK_DRAIN_PER_SEC * delta
		if stamina >= block_drain:
			_spend_stamina(block_drain)
		else:
			is_blocking = false

	_tick_face_guard_posture(delta)


func weapon_name() -> StringName:
	return WEAPON_NAMES[current_weapon]


func can_move() -> bool:
	## Stagger stub gates movement/AI the same way recovery does (minimal CC hook).
	return not is_dead and attack_recovery_left <= 0.05 and stagger_left <= 0.0


func can_strafe_while_charging() -> bool:
	return is_charging and not is_dead and not is_attacking


func is_in_recovery() -> bool:
	return attack_recovery_left > 0.0


func set_weapon(weapon: Weapon) -> void:
	if is_attacking:
		return
	if is_charging:
		cancel_charge()
	is_shaft_blocking = false
	current_weapon = weapon
	_apply_weapon_visual()
	weapon_changed.emit(WEAPON_NAMES[current_weapon])


func cycle_weapon(direction: int = 1) -> void:
	# Goad is the default feel. Q steps goad → knife → hatchet (hatchet still in the cycle).
	var values: Array = [Weapon.GOAD, Weapon.KNIFE, Weapon.HATCHET]
	var idx := values.find(current_weapon)
	idx = (idx + direction) % values.size()
	if idx < 0:
		idx += values.size()
	set_weapon(values[idx])


func try_sprint_drain(delta: float) -> bool:
	if is_dead or is_attacking:
		return false
	if is_charging:
		cancel_charge()
	# Sprint drops a held shaft guard the same way it drops a charge.
	is_shaft_blocking = false
	var cost := sprint_stamina_per_sec * delta
	if stamina < cost * 0.5:
		return false
	_spend_stamina(cost)
	return stamina > 0.0


func direction_name(direction: StrikeDirection = charge_direction) -> StringName:
	return DIRECTION_NAMES.get(direction, &"top")


func _clamp_strike_direction(direction: StrikeDirection) -> StrikeDirection:
	## Bottom exists only on the cattle goad (point stab). Knife and hatchet stay top/left/right.
	if direction != StrikeDirection.BOTTOM:
		return direction
	if current_weapon == Weapon.GOAD:
		return direction
	return StrikeDirection.TOP


func last_strike_direction() -> StrikeDirection:
	return _last_strike_direction


func last_attack_timings() -> Dictionary:
	## Resolved windup / active / recovery used by the most recent swing (post dir scale).
	return {
		"windup": _last_windup,
		"active": _last_active,
		"recovery": _last_recovery,
		"kind": _last_attack_kind,
		"direction": DIRECTION_NAMES.get(_last_strike_direction, &"top"),
	}


func resolved_hatchet_timings(kind: StringName, direction: StrikeDirection) -> Dictionary:
	## Preview timings without spending stamina (smoke / capture / HUD helpers).
	var profile: Dictionary = PROFILES[Weapon.HATCHET].get(kind, PROFILES[Weapon.HATCHET][&"light"])
	var windup := float(profile["windup"])
	var active := float(profile["active"])
	var recovery := StaminaEconomy.attack_recovery(&"hatchet", kind)
	var scales: Dictionary = HATCHET_DIR_TIMING.get(direction, HATCHET_DIR_TIMING[StrikeDirection.TOP])
	windup *= float(scales.get("windup", 1.0))
	active *= float(scales.get("active", 1.0))
	recovery *= float(scales.get("recovery", 1.0))
	return {"windup": windup, "active": active, "recovery": recovery, "total": windup + active + recovery}


func get_charge_ratio() -> float:
	return charge_ratio if is_charging else 0.0


func begin_charge() -> bool:
	## Hold-to-charge. Hatchet and goad: top/left/right shaft. Not the goad jab.
	## Knife stays a tap (this returns false) so a light press is not a windup.
	if is_dead or is_attacking or is_charging:
		return false
	var hatchet := current_weapon == Weapon.HATCHET and enable_directional_hatchet
	var goad := current_weapon == Weapon.GOAD
	if not hatchet and not goad:
		return false
	is_charging = true
	is_blocking = false
	is_shaft_blocking = false
	charge_time = 0.0
	charge_ratio = 0.0
	charge_direction = StrikeDirection.TOP
	charge_started.emit(WEAPON_NAMES[current_weapon])
	charge_updated.emit(0.0, DIRECTION_NAMES[charge_direction])
	_update_charge_pose(0.0, charge_direction)
	return true


func set_charge_direction(direction: StrikeDirection) -> void:
	if not is_charging:
		return
	# Bottom is the uncharged goad jab, not a shaft charge. Hatchet/knife clamp to top.
	direction = _clamp_strike_direction(direction)
	if current_weapon == Weapon.GOAD and direction == StrikeDirection.BOTTOM:
		direction = StrikeDirection.TOP
	if charge_direction == direction:
		return
	charge_direction = direction
	_update_charge_pose(charge_ratio, charge_direction)
	charge_updated.emit(charge_ratio, DIRECTION_NAMES[charge_direction])


func cancel_charge() -> void:
	if not is_charging:
		return
	is_charging = false
	charge_time = 0.0
	charge_ratio = 0.0
	_clear_charge_pose()
	charge_cancelled.emit(WEAPON_NAMES[current_weapon])


func release_charged_attack() -> bool:
	## Release hold: power scales with charge_ratio. Tap (~min secs) = light; full hold = heavy.
	## STA spend fires inside try_attack via ChargeStaminaTable (on commit only).
	if not is_charging:
		return false
	var held := charge_time
	var ratio := charge_ratio
	var direction := charge_direction
	# A shaft release is never the point jab, even if the field was poked.
	if current_weapon == Weapon.GOAD and direction == StrikeDirection.BOTTOM:
		direction = StrikeDirection.TOP
	is_charging = false
	charge_time = 0.0
	charge_ratio = 0.0
	# Keep weapon/arm at charge cock — swing continues from current pose (no rest snap).
	if _charge_pose_tween and _charge_pose_tween.is_valid():
		_charge_pose_tween.kill()
	var kind: StringName = &"light" if held < charge_min_release_secs or ratio < 0.22 else &"heavy"
	# Blend: short hold still light; mid/full uses heavy profile with scaled damage/cost.
	# Near-full charge maps to HatchetAttackTable &"max" tier via power >= 0.95.
	var power := 0.0 if kind == &"light" else clampf(ratio, 0.22, 1.0)
	charge_released.emit(power if kind == &"heavy" else 0.0, DIRECTION_NAMES[direction], kind)
	var committed := try_attack(kind, direction, power)
	if not committed:
		# Release with no stamina must not freeze the windup pose.
		_clear_charge_pose()
		charge_cancelled.emit(WEAPON_NAMES[current_weapon])
	return committed


func try_attack_directional(direction: StringName, tier: StringName) -> bool:
	## Directional + charge-tier entry (StringName API for table probes / future aim).
	var dir_enum := StrikeDirection.TOP
	match HatchetAttackTable.normalize_direction(direction):
		&"left":
			dir_enum = StrikeDirection.LEFT
		&"right":
			dir_enum = StrikeDirection.RIGHT
		_:
			dir_enum = StrikeDirection.TOP
	var kind: StringName = HatchetAttackTable.kind_from_tier(tier)
	var power := -1.0
	var nt := HatchetAttackTable.normalize_tier(tier)
	if nt == &"max":
		power = 1.0
	elif nt == &"charged":
		power = 0.7
	return try_attack(kind, dir_enum, power)


func try_attack(
	kind: StringName = &"light",
	direction: StrikeDirection = StrikeDirection.TOP,
	power: float = -1.0
) -> bool:
	if is_dead or is_attacking:
		return false
	if is_charging:
		cancel_charge()
	direction = _clamp_strike_direction(direction)
	var profile: Dictionary = PROFILES[current_weapon].get(kind, PROFILES[current_weapon][&"light"])
	var wname: StringName = WEAPON_NAMES[current_weapon]
	var light_p: Dictionary = PROFILES[current_weapon][&"light"]
	var heavy_p: Dictionary = PROFILES[current_weapon][&"heavy"]
	# power < 0 → discrete light/heavy; else lerp light→heavy by power (0..1).
	# Knife/goad cost+recovery: StaminaEconomy. Hatchet charge STA: ChargeStaminaTable
	# on release commit (after tier resolve below). Feel timings from PROFILES.
	var cost: float
	var damage: float
	var windup: float
	var active: float
	var recovery: float
	var reach: float
	if power < 0.0:
		cost = StaminaEconomy.attack_cost(wname, kind)
		damage = float(profile["damage"])
		windup = float(profile["windup"])
		active = float(profile["active"])
		recovery = StaminaEconomy.attack_recovery(wname, kind)
		reach = float(profile["reach"])
	else:
		var t := clampf(power, 0.0, 1.0)
		cost = lerpf(
			StaminaEconomy.attack_cost(wname, &"light"),
			StaminaEconomy.attack_cost(wname, &"heavy"),
			t,
		)
		damage = lerpf(float(light_p["damage"]), float(heavy_p["damage"]), t)
		windup = lerpf(float(light_p["windup"]), float(heavy_p["windup"]), t)
		active = lerpf(float(light_p["active"]), float(heavy_p["active"]), t)
		recovery = lerpf(
			StaminaEconomy.attack_recovery(wname, &"light"),
			StaminaEconomy.attack_recovery(wname, &"heavy"),
			t,
		)
		reach = lerpf(float(light_p["reach"]), float(heavy_p["reach"]), t)
		kind = &"heavy" if t >= 0.55 else &"light"
	# Hatchet: Systems tables own damage/reach + charge-tier STA; dir scales feel.
	var resolved_dir: StringName = &""
	var resolved_tier: StringName = &""
	if current_weapon == Weapon.HATCHET:
		var dir_name: StringName = DIRECTION_NAMES.get(direction, &"top")
		var tier: StringName = HatchetAttackTable.tier_from_kind(kind)
		if power >= ChargeStaminaTable.RATIO_MAX_MIN:
			tier = &"max"
		elif power >= ChargeStaminaTable.RATIO_CHARGED_MIN:
			tier = &"charged"
		elif power >= 0.0:
			tier = &"tap"
		var cell: Dictionary = HatchetAttackTable.entry(dir_name, tier)
		resolved_dir = cell["direction"]
		resolved_tier = cell["tier"]
		damage = float(cell["damage"])
		reach = float(cell["reach"])
		# Discrete charge↔STA cost (replaces light↔heavy lerp for hatchet).
		cost = ChargeStaminaTable.cost_for_tier(resolved_tier)
		if enable_directional_hatchet:
			if power >= 0.0 and power < ChargeStaminaTable.RATIO_CHARGED_MIN:
				# Blend tap→charged for partial charge holds (damage/reach only).
				var tap: Dictionary = HatchetAttackTable.entry(dir_name, &"tap")
				var ch: Dictionary = HatchetAttackTable.entry(dir_name, &"charged")
				var bt := clampf(power / ChargeStaminaTable.RATIO_CHARGED_MIN, 0.0, 1.0)
				damage = lerpf(float(tap["damage"]), float(ch["damage"]), bt)
				reach = lerpf(float(tap["reach"]), float(ch["reach"]), bt)
			var scales: Dictionary = HATCHET_DIR_TIMING.get(direction, HATCHET_DIR_TIMING[StrikeDirection.TOP])
			windup *= float(scales.get("windup", 1.0))
			active *= float(scales.get("active", 1.0))
			recovery *= float(scales.get("recovery", 1.0))
	# Goad point jab is a quicker commit than a shaft swing, and reaches a bit farther.
	if current_weapon == Weapon.GOAD and direction == StrikeDirection.BOTTOM:
		windup *= 0.72
		active *= 0.85
		reach += 0.2
	# Knife top is a chest-height thrust: farther than a side cut, still short of the goad.
	if current_weapon == Weapon.KNIFE and direction == StrikeDirection.TOP:
		windup *= 0.82
		active *= 0.9
		reach += 0.16
	# Spend fires here on strike commit (release path). Refuse if insufficient.
	if current_weapon == Weapon.HATCHET and resolved_tier != &"":
		if not spend_for_charge(resolved_tier):
			return false
	else:
		if stamina < cost:
			return false
		_spend_stamina(cost)
	is_attacking = true
	is_blocking = false
	is_shaft_blocking = false
	_hit_this_swing.clear()
	attack_recovery_left = windup + active + recovery
	_last_attack_kind = kind
	_last_strike_direction = direction
	_last_windup = windup
	_last_active = active
	_last_recovery = recovery
	_last_attack_direction = resolved_dir
	_last_attack_tier = resolved_tier
	_last_attack_damage = damage
	_last_attack_reach = reach
	last_attack_power = power
	_play_weapon_swing(kind, windup, active, recovery, direction)
	attack_performed.emit(_owner_body, kind, wname)
	_activate_hitbox_after(windup, active, reach, damage, kind, direction)
	return true



func set_blocking(holding: bool) -> void:
	if not enable_block or is_dead or is_attacking:
		is_blocking = false
		return
	is_blocking = holding and stamina > StaminaEconomy.BLOCK_MIN_STAMINA


## Hold the cattle goad. Goad only — knife and hatchet refuse.
## This is a guard, not a perfect-parry: there is no timing window.
## Raising the guard starts on the chest face (any frontal hit). Call
## set_shaft_guard_face while it is held to shift left / right / high / low.
## Releasing the hold clears it. A mismatched face does not catch.
func set_shaft_block(holding: bool) -> bool:
	if (
		not holding
		or current_weapon != Weapon.GOAD
		or is_dead
		or is_attacking
		or is_charging
		or stamina <= StaminaEconomy.BLOCK_MIN_STAMINA
	):
		is_shaft_blocking = false
		shaft_guard_face = &"chest"
		return false
	var raising := not is_shaft_blocking
	is_shaft_blocking = true
	is_blocking = false
	if raising:
		shaft_guard_face = &"chest"
	return true


## Shift the held guard. Ignored names fall back to chest.
## top/bottom are accepted as high/low so look dirs can be passed through.
func set_shaft_guard_face(face: StringName) -> void:
	shaft_guard_face = normalize_shaft_guard_face(face)


static func normalize_shaft_guard_face(face: StringName) -> StringName:
	match face:
		&"left", &"right", &"high", &"low", &"chest":
			return face
		&"top":
			return &"high"
		&"bottom":
			return &"low"
		_:
			return &"chest"


## True when the current held face covers this strike.
## chest: every direction. left/right/high/low: that side only.
## Low is the face that stops a bottom stab. High and the sides do not.
func shaft_face_stops_direction(direction: StrikeDirection) -> bool:
	match shaft_guard_face:
		&"left":
			return direction == StrikeDirection.LEFT
		&"right":
			return direction == StrikeDirection.RIGHT
		&"high":
			return direction == StrikeDirection.TOP
		&"low":
			return direction == StrikeDirection.BOTTOM
		_:
			return true


## Sparring face-guard (BlockPostureTable). Independent of enable_block shield stubs.
func set_face_guard(face: StringName) -> void:
	guard_face = BlockPostureTable.normalize_face(face)


## Bridge for Godot sparring foe (StrikeDirection → face StringName + enum).
func set_guard_direction(direction: StrikeDirection) -> void:
	guard_direction = direction
	set_face_guard(DIRECTION_NAMES.get(direction, &"top"))


## Godot API: outfit this CombatSystem as a sparring foe using BlockPostureTable
## soak/posture numbers. Enables face-guard (proper path). Leaves enable_block
## stubs intact — do not hardcode posture/mitigation in foe scripts.
func apply_sparring_foe_guard_defaults() -> Dictionary:
	return _apply_sparring_foe_guard_defaults_internal(
		BlockPostureTable.get_sparring_foe_posture_defaults()
	)


func _apply_sparring_foe_guard_defaults_internal(defaults: Dictionary) -> Dictionary:
	enable_face_guard = true
	# enable_block intentionally untouched (older frontal/directional path).
	posture = BlockPostureTable.MAX_POSTURE
	posture_break_left = 0.0
	_last_guard_resolve = {}
	var start: StringName = BlockPostureTable.SPARRING_FOE_STARTING_FACE
	# Sync StringName face + StrikeDirection enum (dummy cycles TOP/LEFT/RIGHT).
	match start:
		&"left":
			set_guard_direction(StrikeDirection.LEFT)
		&"right":
			set_guard_direction(StrikeDirection.RIGHT)
		_:
			set_guard_direction(StrikeDirection.TOP)
	var out := defaults.duplicate(true)
	out["applied_to"] = str(get_path()) if is_inside_tree() else name
	out["guard_face"] = String(guard_face)
	out["posture"] = posture
	out["enable_face_guard"] = enable_face_guard
	out["enable_block"] = enable_block
	return out


## Static/dict form — same numbers without requiring a live CombatSystem.
static func get_sparring_foe_posture_defaults() -> Dictionary:
	return BlockPostureTable.get_sparring_foe_posture_defaults()


## Outfit a CombatSystem or a body that owns one (CharacterBody3D + child).
static func apply_sparring_foe_guard_defaults_to(node: Object) -> Dictionary:
	return BlockPostureTable.apply_sparring_foe_guard_defaults(node)


func guard_direction_name() -> StringName:
	return DIRECTION_NAMES.get(guard_direction, &"top")


func mitigation_for(guard: StringName, attack_dir: StringName) -> float:
	return BlockPostureTable.mitigation_for(guard, attack_dir)


## Apply table costs for a matched face-guard hit. Returns resolve dict.
## Does not change HP — caller / apply_damage handles remaining damage.
func apply_guard_hit_cost(attack_dir: StringName, incoming_damage: float) -> Dictionary:
	var resolved: Dictionary = BlockPostureTable.resolve_guard_hit(
		guard_face, attack_dir, incoming_damage
	)
	_last_guard_resolve = resolved
	if not bool(resolved.get("matched", false)):
		return resolved
	if posture_break_left > 0.0:
		# Broken posture cannot absorb — treat as open.
		resolved["matched"] = false
		resolved["open_side"] = true
		resolved["mitigation"] = 0.0
		resolved["mitigated_amount"] = 0.0
		resolved["remaining_damage"] = float(resolved.get("incoming_damage", incoming_damage))
		resolved["stamina_cost"] = 0.0
		resolved["posture_chip"] = 0.0
		_last_guard_resolve = resolved
		return resolved
	var sta_cost := float(resolved.get("stamina_cost", 0.0))
	if sta_cost > 0.0:
		_spend_stamina(sta_cost)
	var chip := float(resolved.get("posture_chip", 0.0))
	if chip > 0.0:
		posture = maxf(0.0, posture - chip)
		if posture <= 0.01:
			posture = 0.0
			guard_face = &"open"
			_on_posture_break()
	return resolved


func _tick_face_guard_posture(delta: float) -> void:
	if not enable_face_guard:
		return
	if posture_break_left > 0.0:
		posture_break_left = maxf(0.0, posture_break_left - delta)
		return
	if posture >= BlockPostureTable.MAX_POSTURE:
		return
	var rate := BlockPostureTable.REGEN_PER_SEC * BlockPostureTable.recover_rate_for(guard_face)
	posture = minf(BlockPostureTable.MAX_POSTURE, posture + rate * delta)


## Posture pool emptied: open window + existing CombatTags stagger (no parallel CC).
## Duration driven by BlockPostureTable.break_stun_sec() (= CombatTags stagger_heavy).
func _on_posture_break() -> void:
	var tag: StringName = BlockPostureTable.break_stagger_tag()
	var dur := BlockPostureTable.break_stun_sec()
	posture_break_left = maxf(posture_break_left, dur)
	var entry: Dictionary = apply_stagger_tag(tag)
	# Keep break stun and stagger_left linked (same window).
	if not entry.is_empty():
		var tag_dur := float(entry.get("duration_sec", dur))
		dur = maxf(dur, tag_dur)
		posture_break_left = maxf(posture_break_left, dur)
		stagger_left = maxf(stagger_left, dur)
	_last_posture_break = {
		"stagger_tag": tag,
		"duration_sec": dur,
		"interrupt_strength": int(entry.get("interrupt_strength", 0)) if not entry.is_empty() else 0,
		"posture_break_left": posture_break_left,
		"stagger_left": stagger_left,
	}
	# Session bus when this CombatSystem is the player (sparring self-break rare but wired).
	if _combat_owner_is_player(self):
		var ch := _session_character_health()
		if ch:
			ch.apply_stagger_tag(tag)
	posture_broken.emit(_owner_body, tag, dur)


func apply_damage(
	amount: float,
	from: Node = null,
	frontal: bool = true,
	strike_direction: StrikeDirection = StrikeDirection.TOP
) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	# Held shaft catch. No timing window, no counter.
	# Chest stops any frontal hit (the old block). A faced guard stops only
	# its side: low stops a front stab, high stops an overhead, sides stop
	# that flank. A face that does not cover the strike lets it through.
	if (
		is_shaft_blocking
		and current_weapon == Weapon.GOAD
		and frontal
		and shaft_face_stops_direction(strike_direction)
	):
		var caught := amount
		_spend_stamina(StaminaEconomy.BLOCK_HIT_COST)
		blocked.emit(_owner_body, from, caught)
		if stamina <= StaminaEconomy.BLOCK_MIN_STAMINA:
			is_shaft_blocking = false
			shaft_guard_face = &"chest"
		return 0.0
	# Hit-stun: drop any in-progress charge.
	if is_charging:
		cancel_charge()
	if is_shaft_blocking:
		is_shaft_blocking = false
		shaft_guard_face = &"chest"
	var mitigated := 0.0
	var attack_dir: StringName = DIRECTION_NAMES.get(strike_direction, &"top")
	var face_mitigated := false
	# Face-guard path (Systems BlockPostureTable). Independent of enable_block.
	# Resolve order: (1) face-guard mitigate on match; (2) FlankBonusTable only when
	# face guard does NOT mitigate (open / mismatch / posture-broken).
	if enable_face_guard:
		if posture_break_left <= 0.0:
			var resolved := apply_guard_hit_cost(attack_dir, amount)
			if bool(resolved.get("matched", false)):
				mitigated = float(resolved.get("mitigated_amount", 0.0))
				amount = float(resolved.get("remaining_damage", amount))
				face_mitigated = true
				blocked.emit(_owner_body, from, mitigated)
				if amount <= 0.01:
					_last_flank_resolve = {}
					return 0.0
		if not face_mitigated:
			# Broken posture / open / mismatch → open-side flank bonus on remaining.
			var guard_for_flank: StringName = (
				&"open" if posture_break_left > 0.0 else guard_face
			)
			var flank: Dictionary = FlankBonusTable.resolve(
				guard_for_flank, attack_dir, amount, not frontal
			)
			_last_flank_resolve = flank
			amount = float(flank.get("dealt_damage", amount))
		else:
			_last_flank_resolve = {}
	# Directional face-block (Godot sparring / enable_block): guarded face only.
	elif enable_block and is_blocking and stamina > 0.0:
		var face_match := strike_direction == guard_direction
		if face_match:
			mitigated = amount * 0.85
			amount -= mitigated
			_spend_stamina(StaminaEconomy.BLOCK_HIT_COST)
			blocked.emit(_owner_body, from, mitigated)
			if amount <= 0.01:
				return 0.0
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	damage_taken.emit(amount, from)
	if enable_hit_feedback:
		_play_hurt_feedback(amount, from)
	if health <= 0.0:
		_die()
	return amount


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	is_attacking = false
	is_blocking = false
	is_shaft_blocking = false
	is_charging = false
	posture_break_left = 0.0
	if _hitbox:
		_hitbox.monitoring = false
	reset_weapon_pose()
	died.emit(_owner_body)


func _activate_hitbox_after(
	windup: float,
	active: float,
	reach: float,
	damage: float,
	kind: StringName,
	direction: StrikeDirection = StrikeDirection.TOP
) -> void:
	await get_tree().create_timer(windup).timeout
	if is_dead or not is_instance_valid(self):
		return
	if _hitbox:
		_position_hitbox(reach, direction)
		_hitbox.set_meta("damage", damage)
		_hitbox.set_meta("kind", kind)
		_hitbox.set_meta("direction", DIRECTION_NAMES.get(direction, &"top"))
		_hitbox.set_meta("tier", _last_attack_tier)
		_hitbox.monitoring = true
		hitbox_active_left = active
		# Immediate overlap check (bodies already inside)
		for body in _hitbox.get_overlapping_bodies():
			_try_damage_target(body, damage, kind)
		for area in _hitbox.get_overlapping_areas():
			_on_hitbox_area_entered(area)


func _position_hitbox(reach: float, direction: StrikeDirection = StrikeDirection.TOP) -> void:
	if _hitbox == null or _owner_body == null:
		return
	var shape_node := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box: BoxShape3D = null
	if shape_node and shape_node.shape is BoxShape3D:
		box = (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
	# Goad bottom is a narrow point jab straight ahead, not a wide shaft arc.
	if direction == StrikeDirection.BOTTOM:
		_hitbox.position = Vector3(0.08, 1.05, -reach * 0.82)
		if box:
			box.size = Vector3(0.22, 0.22, reach * 0.62)
			shape_node.shape = box
		return
	# Knife top thrust: narrow point at chest height. Not a wide cut, not the goad's low stab.
	if current_weapon == Weapon.KNIFE and direction == StrikeDirection.TOP:
		_hitbox.position = Vector3(0.2, 1.22, -reach * 0.74)
		if box:
			box.size = Vector3(0.26, 0.26, reach * 0.48)
			shape_node.shape = box
		return
	if current_weapon == Weapon.KNIFE:
		var cut_lat := -0.62 if direction == StrikeDirection.LEFT else 0.62
		_hitbox.position = Vector3(cut_lat, 1.12, -reach * 0.58)
		if box:
			box.size = Vector3(0.9, 0.5, reach * 0.62)
			shape_node.shape = box
		return
	# Local -Z is facing forward for CharacterBody3D yaw; bias by strike side.
	var lateral := 0.0
	var height := 1.0
	match direction:
		StrikeDirection.LEFT:
			lateral = -0.48
			height = 1.05
		StrikeDirection.RIGHT:
			lateral = 0.48
			height = 1.05
		_:
			lateral = 0.0
			height = 1.25 if current_weapon == Weapon.HATCHET else 1.0
	_hitbox.position = Vector3(lateral, height, -reach * 0.55)
	if box:
		# USER LOCK: wider side hitboxes for sparring / flank chops.
		var width := 1.15 if direction != StrikeDirection.TOP else 0.55
		var tall := 0.85 if direction == StrikeDirection.TOP else 0.72
		box.size = Vector3(width, tall, reach * 0.95)
		shape_node.shape = box


func _on_hitbox_body_entered(body: Node) -> void:
	if not _hitbox or not _hitbox.monitoring:
		return
	var damage: float = float(_hitbox.get_meta("damage", 10.0))
	var kind: StringName = _hitbox.get_meta("kind", &"light")
	_try_damage_target(body, damage, kind)


func _on_hitbox_area_entered(area: Area3D) -> void:
	if not _hitbox or not _hitbox.monitoring:
		return
	var target := area.get_parent()
	if target == null:
		return
	var damage: float = float(_hitbox.get_meta("damage", 10.0))
	var kind: StringName = _hitbox.get_meta("kind", &"light")
	_try_damage_target(target, damage, kind)


func _try_damage_target(target: Node, damage: float, kind: StringName) -> void:
	if target == null or target == _owner_body:
		return
	var id := target.get_instance_id()
	if _hit_this_swing.has(id):
		return
	# Cattle goad: impulse/steer raid cows (Hurtbox parent or body). Other weapons ignore herd.
	var cattle := _resolve_raid_cattle(target)
	if cattle != null:
		_hit_this_swing[id] = true
		_hit_this_swing[cattle.get_instance_id()] = true
		if current_weapon == Weapon.GOAD and cattle.has_method("apply_goad"):
			var fwd := Vector3.FORWARD
			var from_pos := cattle.global_position
			if _owner_body:
				fwd = -_owner_body.global_transform.basis.z
				from_pos = _owner_body.global_position
			var strength := 1.55 if kind == &"heavy" else 1.0
			cattle.call("apply_goad", from_pos, fwd, strength, kind)
			hit_landed.emit(_owner_body, cattle, 0.0, kind)
			if enable_hit_feedback:
				_play_hit_confirm(kind)
		return
	var other: CombatSystem = _find_combat(target)
	if other == null:
		# Hurtbox parent may be the combatant
		if target is Area3D:
			other = _find_combat(target.get_parent())
	if other == null or other == self or other.is_dead:
		return
	if other.team == team:
		return
	_hit_this_swing[id] = true
	var facing_ok := _is_frontal(other)
	var strike_dir := _last_strike_direction
	if _hitbox and _hitbox.has_meta("direction"):
		var dname: StringName = _hitbox.get_meta("direction")
		for key in DIRECTION_NAMES:
			if DIRECTION_NAMES[key] == dname:
				strike_dir = key
				break
	var dealt := other.apply_damage(damage, _owner_body, facing_ok, strike_dir)
	if dealt > 0.0:
		hit_landed.emit(_owner_body, other.get_parent(), dealt, kind)
		_apply_hit_tags(other, kind)
		if enable_hit_feedback:
			_play_hit_confirm(kind)


func _resolve_raid_cattle(target: Node) -> Node3D:
	if target == null:
		return null
	if target.is_in_group("raid_cattle") and target is Node3D:
		return target as Node3D
	if target is Area3D:
		var parent := target.get_parent()
		if parent and parent.is_in_group("raid_cattle") and parent is Node3D:
			return parent as Node3D
	return null


func _is_frontal(other: CombatSystem) -> bool:
	var defender_body := other.get_parent() as Node3D
	if defender_body == null or _owner_body == null:
		return true
	var to_attacker: Vector3 = _owner_body.global_position - defender_body.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		return true
	var defender_fwd: Vector3 = -defender_body.global_transform.basis.z
	defender_fwd.y = 0.0
	if defender_fwd.length_squared() < 0.001:
		return true
	return defender_fwd.normalized().dot(to_attacker.normalized()) > 0.25


func _find_combat(node: Node) -> CombatSystem:
	if node == null:
		return null
	if node is CombatSystem:
		return node
	var child := node.get_node_or_null("CombatSystem")
	if child is CombatSystem:
		return child
	return null


func _apply_weapon_visual() -> void:
	if _weapon_visual == null:
		return
	for child in _weapon_visual.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	var wname := String(WEAPON_NAMES[current_weapon]).capitalize()
	# Expect Hatchet / Knife / Goad mesh children
	var mesh := _weapon_visual.get_node_or_null(wname)
	if mesh is Node3D:
		(mesh as Node3D).visible = true
	else:
		# fallback: show first child
		if _weapon_visual.get_child_count() > 0 and _weapon_visual.get_child(0) is Node3D:
			(_weapon_visual.get_child(0) as Node3D).visible = true


func _play_weapon_swing(
	kind: StringName,
	windup: float,
	active: float,
	recovery: float,
	direction: StrikeDirection = StrikeDirection.TOP
) -> void:
	if _weapon_visual == null:
		return
	# Goad/knife stay in the hand. The body pose turns them; a free tween would
	# float the mesh off the kerne. Hatchet keeps this swing tween.
	if current_weapon != Weapon.HATCHET:
		return
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	if _charge_pose_tween and _charge_pose_tween.is_valid():
		_charge_pose_tween.kill()
	# Keep authored idle rest for recovery. Current transform may already be a charge cock
	# (hand-follow + arm pose) — swing arcs from here instead of snapping to rest first.

	var poses := _swing_poses(kind, direction)
	var windup_rot: Vector3 = poses["windup_rot"]
	var contact_rot: Vector3 = poses["contact_rot"]
	var follow_rot: Vector3 = poses["follow_rot"]
	var windup_pos: Vector3 = poses["windup_pos"]
	var contact_pos: Vector3 = poses["contact_pos"]
	var follow_pos: Vector3 = poses["follow_pos"]
	var rest_rot := Vector3(
		rad_to_deg(_weapon_rest_transform.basis.get_euler().x),
		rad_to_deg(_weapon_rest_transform.basis.get_euler().y),
		rad_to_deg(_weapon_rest_transform.basis.get_euler().z)
	)

	_swing_tween = create_tween()
	_swing_tween.set_parallel(false)
	# Phase splits (feel): windup cock + brief hold telegraph; active = strike→hold→follow.
	var phases := swing_phase_durations(kind, windup, active, recovery)
	var windup_move: float = phases["windup_move"]
	var windup_hold: float = phases["windup_hold"]
	var to_contact: float = phases["to_contact"]
	var contact_hold: float = phases["contact_hold"]
	var follow_dur: float = phases["follow"]
	# Windup: cock back/up before hit frames
	var tw := _swing_tween.tween_property(_weapon_visual, "rotation_degrees", windup_rot, windup_move)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", windup_pos, windup_move)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if windup_hold > 0.0:
		_swing_tween.tween_interval(windup_hold)
	# Active: accelerate into contact, brief readable hold, then follow-through
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", contact_rot, to_contact)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", contact_pos, to_contact)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if contact_hold > 0.0:
		_swing_tween.tween_interval(contact_hold)
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", follow_rot, follow_dur)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", follow_pos, follow_dur)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Recovery: return to rest (non-spam gate)
	tw = _swing_tween.tween_property(_weapon_visual, "rotation_degrees", rest_rot, recovery)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw = _swing_tween.parallel().tween_property(_weapon_visual, "position", _weapon_rest_transform.origin, recovery)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func swing_phase_durations(kind: StringName, windup: float, active: float, recovery: float) -> Dictionary:
	## Procedural phase splits shared by weapon tween + body additives.
	## Heavy holds longer at cock + contact so telegraph/impact read; light stays snappy.
	var heavy := kind == &"heavy"
	var hold_frac := 0.18 if heavy else 0.08
	var windup_hold := windup * hold_frac
	var windup_move := maxf(0.04, windup - windup_hold)
	var contact_hold := active * (0.22 if heavy else 0.12)
	var to_contact := active * (0.40 if heavy else 0.48)
	var follow_dur := maxf(0.03, active - to_contact - contact_hold)
	return {
		"windup_move": windup_move,
		"windup_hold": windup_hold,
		"to_contact": to_contact,
		"contact_hold": contact_hold,
		"follow": follow_dur,
		"recovery": recovery,
	}


func _swing_poses(kind: StringName, direction: StrikeDirection = StrikeDirection.TOP) -> Dictionary:
	## Degrees + local positions; heavy = bigger arc / higher cock than light.
	## Hatchet: top / left / right only. Knife/goad weapon tween is unused
	## (hand-glued); body poses live in tool_strike_poses.gd.
	var rest_pos := _weapon_rest_transform.origin
	var heavy := kind == &"heavy"
	match current_weapon:
		Weapon.KNIFE:
			if heavy:
				return {
					"windup_rot": Vector3(-25.0, 35.0, 55.0),
					"contact_rot": Vector3(15.0, -50.0, -95.0),
					"follow_rot": Vector3(25.0, -70.0, -130.0),
					"windup_pos": rest_pos + Vector3(0.05, 0.12, 0.08),
					"contact_pos": rest_pos + Vector3(0.02, 0.02, -0.28),
					"follow_pos": rest_pos + Vector3(-0.08, -0.05, -0.18),
				}
			return {
				"windup_rot": Vector3(-10.0, 20.0, 35.0),
				"contact_rot": Vector3(8.0, -30.0, -70.0),
				"follow_rot": Vector3(12.0, -40.0, -95.0),
				"windup_pos": rest_pos + Vector3(0.03, 0.06, 0.04),
				"contact_pos": rest_pos + Vector3(0.0, 0.0, -0.18),
				"follow_pos": rest_pos + Vector3(-0.04, -0.02, -0.1),
			}
		Weapon.GOAD:
			if heavy:
				return {
					"windup_rot": Vector3(-55.0, 25.0, 40.0),
					"contact_rot": Vector3(35.0, -15.0, -55.0),
					"follow_rot": Vector3(50.0, -25.0, -75.0),
					"windup_pos": rest_pos + Vector3(0.08, 0.22, 0.12),
					"contact_pos": rest_pos + Vector3(0.05, 0.05, -0.45),
					"follow_pos": rest_pos + Vector3(-0.05, -0.08, -0.35),
				}
			return {
				"windup_rot": Vector3(-30.0, 10.0, 20.0),
				"contact_rot": Vector3(20.0, -5.0, -25.0),
				"follow_rot": Vector3(30.0, -10.0, -40.0),
				"windup_pos": rest_pos + Vector3(0.04, 0.1, 0.06),
				"contact_pos": rest_pos + Vector3(0.02, 0.02, -0.35),
				"follow_pos": rest_pos + Vector3(0.0, -0.04, -0.22),
			}
		_:
			return _hatchet_directional_poses(heavy, direction, rest_pos)


func _hatchet_directional_poses(heavy: bool, direction: StrikeDirection, rest_pos: Vector3) -> Dictionary:
	## Top = overhead chop; left = open-side horizontal; right = cross-body horizontal.
	match direction:
		StrikeDirection.LEFT:
			if heavy:
				return {
					"windup_rot": Vector3(-28.0, 95.0, 42.0),
					"contact_rot": Vector3(12.0, -30.0, -48.0),
					"follow_rot": Vector3(24.0, -82.0, -62.0),
					"windup_pos": rest_pos + Vector3(-0.30, 0.22, 0.08),
					"contact_pos": rest_pos + Vector3(0.06, 0.08, -0.32),
					"follow_pos": rest_pos + Vector3(0.34, -0.02, -0.18),
				}
			return {
				"windup_rot": Vector3(-12.0, 50.0, 25.0),
				"contact_rot": Vector3(8.0, -10.0, -25.0),
				"follow_rot": Vector3(14.0, -45.0, -40.0),
				"windup_pos": rest_pos + Vector3(-0.14, 0.1, 0.04),
				"contact_pos": rest_pos + Vector3(0.02, 0.04, -0.2),
				"follow_pos": rest_pos + Vector3(0.18, -0.02, -0.1),
			}
		StrikeDirection.RIGHT:
			if heavy:
				return {
					"windup_rot": Vector3(-32.0, -90.0, -58.0),
					"contact_rot": Vector3(18.0, 36.0, 30.0),
					"follow_rot": Vector3(28.0, 88.0, 52.0),
					"windup_pos": rest_pos + Vector3(0.32, 0.2, 0.1),
					"contact_pos": rest_pos + Vector3(-0.04, 0.06, -0.32),
					"follow_pos": rest_pos + Vector3(-0.36, -0.04, -0.16),
				}
			return {
				"windup_rot": Vector3(-14.0, -45.0, -35.0),
				"contact_rot": Vector3(10.0, 18.0, 15.0),
				"follow_rot": Vector3(16.0, 50.0, 30.0),
				"windup_pos": rest_pos + Vector3(0.16, 0.1, 0.05),
				"contact_pos": rest_pos + Vector3(0.0, 0.04, -0.2),
				"follow_pos": rest_pos + Vector3(-0.2, -0.02, -0.1),
			}
		_:
			# TOP overhead chop; heavy is a larger cock-and-drop.
			if heavy:
				return {
					"windup_rot": Vector3(-118.0, 28.0, 85.0),
					"contact_rot": Vector3(42.0, -12.0, -100.0),
					"follow_rot": Vector3(78.0, -28.0, -140.0),
					"windup_pos": rest_pos + Vector3(0.1, 0.55, 0.08),
					"contact_pos": rest_pos + Vector3(0.04, -0.02, -0.34),
					"follow_pos": rest_pos + Vector3(-0.08, -0.28, -0.2),
				}
			return {
				"windup_rot": Vector3(-68.0, 18.0, 55.0),
				"contact_rot": Vector3(24.0, -8.0, -78.0),
				"follow_rot": Vector3(48.0, -18.0, -108.0),
				"windup_pos": rest_pos + Vector3(0.06, 0.32, 0.05),
				"contact_pos": rest_pos + Vector3(0.02, 0.0, -0.24),
				"follow_pos": rest_pos + Vector3(-0.04, -0.14, -0.14),
			}



## Idle grip rest used by recovery / cancel. Player hand-follow updates this while idle.
func set_weapon_rest_transform(xf: Transform3D) -> void:
	_weapon_rest_transform = xf


func get_weapon_rest_transform() -> Transform3D:
	return _weapon_rest_transform


## Procedural right-arm / torso additives for hatchet charge aim (radians).
## Blends rest→full cock by charge_ratio so full charge reads clearly cocked.
static func hatchet_charge_arm_pose(direction: StrikeDirection, ratio: float) -> Dictionary:
	var t := clampf(ratio, 0.0, 1.0)
	t = t * t  # ease early cock so taps don't look charged
	var arm := Vector3.ZERO
	var torso := Vector3.ZERO
	var fore_scale := 0.35
	match direction:
		StrikeDirection.LEFT:
			# Open-side cock: arm lifted out to the character's left.
			arm = Vector3(
				deg_to_rad(lerpf(-10.0, -55.0, t)),
				deg_to_rad(lerpf(8.0, 70.0, t)),
				deg_to_rad(lerpf(-14.0, -75.0, t))
			)
			torso = Vector3(
				deg_to_rad(lerpf(0.0, -8.0, t)),
				deg_to_rad(lerpf(0.0, 28.0, t)),
				deg_to_rad(lerpf(0.0, -6.0, t))
			)
			fore_scale = lerpf(0.3, 0.6, t)
		StrikeDirection.RIGHT:
			# Cross-body cock: arm hauled back over the right shoulder.
			arm = Vector3(
				deg_to_rad(lerpf(-10.0, -62.0, t)),
				deg_to_rad(lerpf(-8.0, -72.0, t)),
				deg_to_rad(lerpf(-14.0, 42.0, t))
			)
			torso = Vector3(
				deg_to_rad(lerpf(0.0, -8.0, t)),
				deg_to_rad(lerpf(0.0, -32.0, t)),
				deg_to_rad(lerpf(0.0, 6.0, t))
			)
			fore_scale = lerpf(0.3, 0.6, t)
		_:
			# TOP overhead cock — nearly vertical raise.
			arm = Vector3(
				deg_to_rad(lerpf(-14.0, -125.0, t)),
				deg_to_rad(lerpf(-4.0, -6.0, t)),
				deg_to_rad(lerpf(-16.0, -18.0, t))
			)
			torso = Vector3(
				deg_to_rad(lerpf(0.0, -20.0, t)),
				deg_to_rad(lerpf(0.0, -6.0, t)),
				0.0
			)
			fore_scale = lerpf(0.35, 0.7, t)
	return {
		"right_arm": arm,
		"right_forearm": Vector3(arm.x * fore_scale, 0.0, 0.0),
		"torso": torso,
		"fore_scale": fore_scale,
	}


## Idle hatchet ready-hold (radians) — avoids dead T-pose when standing with kit drawn.
static func hatchet_idle_arm_pose() -> Dictionary:
	var arm := Vector3(deg_to_rad(-22.0), deg_to_rad(10.0), deg_to_rad(-24.0))
	return {
		"right_arm": arm,
		"right_forearm": Vector3(deg_to_rad(-8.0), 0.0, 0.0),
		"torso": Vector3(deg_to_rad(2.0), deg_to_rad(4.0), 0.0),
	}


func _update_charge_pose(ratio: float, direction: StrikeDirection) -> void:
	if _weapon_visual == null or is_attacking:
		return
	# Goad charge is a whole-body pose glued to the hand (player controller).
	# Do not run the hatchet weapon-cock tween or the shaft floats off the arm.
	if current_weapon != Weapon.HATCHET:
		return
	# Fallback weapon cock for capture/smoke hosts without player hand-follow.
	# Live player overwrites this each frame by parenting the hatchet to the posed arm.
	var poses := _swing_poses(&"heavy" if ratio > 0.55 else &"light", direction)
	var t := clampf(ratio, 0.0, 1.0)
	var blend := t * t
	var windup_rot: Vector3 = poses["windup_rot"]
	var windup_pos: Vector3 = poses["windup_pos"]
	var rest_euler := _weapon_rest_transform.basis.get_euler()
	var rest_rot := Vector3(rad_to_deg(rest_euler.x), rad_to_deg(rest_euler.y), rad_to_deg(rest_euler.z))
	_weapon_visual.rotation_degrees = rest_rot.lerp(windup_rot, blend * 0.92)
	_weapon_visual.position = _weapon_rest_transform.origin.lerp(windup_pos, blend * 0.92)


func _clear_charge_pose() -> void:
	if _charge_pose_tween and _charge_pose_tween.is_valid():
		_charge_pose_tween.kill()
	if _weapon_visual and not is_attacking:
		_weapon_visual.transform = _weapon_rest_transform



func _spend_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(0.0, stamina - amount)
	_arm_stamina_regen_delay()
	stamina_changed.emit(stamina, max_stamina)


func _arm_stamina_regen_delay() -> void:
	stamina_regen_delay_left = maxf(
		stamina_regen_delay_left, StaminaEconomy.REGEN_DELAY_SEC
	)


## True if current STA covers the charge-tier cost (no spend).
func can_afford_charge(tier: StringName) -> bool:
	return ChargeStaminaTable.can_afford(stamina, tier)


## Spend STA for a hatchet charge tier. Call on release / strike commit only —
## never while holding, never on cancel. Returns false if insufficient (Godot
## must refuse the strike). Updates last-spend probe fields on success.
func spend_for_charge(tier: StringName) -> bool:
	var preview: Dictionary = ChargeStaminaTable.try_spend_preview(stamina, tier)
	if not bool(preview["ok"]):
		return false
	var cost := float(preview["cost"])
	var resolved: StringName = preview["tier"]
	_spend_stamina(cost)
	_last_charge_spend_tier = resolved
	_last_charge_spend_cost = cost
	return true


## Alias of spend_for_charge — try semantics for Godot hold-release callers.
func try_spend_for_charge(tier: StringName) -> bool:
	return spend_for_charge(tier)


func get_attack_profile(kind: StringName = &"light", direction: StringName = &"top") -> Dictionary:
	## Merged feel profile + stamina cost/recovery. Hatchet overlays table damage/reach + charge STA.
	var base: Dictionary = PROFILES[current_weapon].get(kind, PROFILES[current_weapon][&"light"]).duplicate()
	var wname: StringName = WEAPON_NAMES[current_weapon]
	base["cost"] = StaminaEconomy.attack_cost(wname, kind)
	base["recovery"] = StaminaEconomy.attack_recovery(wname, kind)
	if current_weapon == Weapon.HATCHET:
		var tier := HatchetAttackTable.tier_from_kind(kind)
		var cell: Dictionary = HatchetAttackTable.entry(direction, tier)
		base["damage"] = cell["damage"]
		base["reach"] = cell["reach"]
		base["direction"] = cell["direction"]
		base["tier"] = cell["tier"]
		base["cost"] = ChargeStaminaTable.cost_for_tier(tier)
		base["spend_fires"] = &"on_release_commit"
	return base


func get_stamina_economy_debug_text() -> String:
	return StaminaEconomy.get_debug_text(stamina)


func dump_stamina_economy() -> void:
	## Cheap F5 probe — print economy constants + current STA.
	print(get_stamina_economy_debug_text())


func get_hatchet_attack_table_debug_text() -> String:
	return HatchetAttackTable.get_debug_text(
		_last_attack_direction, _last_attack_tier, _last_attack_damage, _last_attack_reach
	)


func dump_hatchet_attack_table() -> void:
	## Cheap F5 probe — print hatchet direction×tier table + last resolved cell.
	print(get_hatchet_attack_table_debug_text())


func get_charge_stamina_debug_text() -> String:
	return ChargeStaminaTable.get_debug_text(
		stamina, _last_charge_spend_tier, _last_charge_spend_cost
	)


func dump_charge_stamina_table() -> void:
	## Cheap F5 probe — print charge↔STA spend table + last release spend.
	print(get_charge_stamina_debug_text())


## Resolve CharacterHealth autoload without a bare global (keeps -s smokes / check-only compiling).
func _session_character_health() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("CharacterHealth")


func get_combat_tags_debug_text() -> String:
	return CombatTags.get_debug_text(
		_last_hit_tags, _last_hit_tags_weapon, _last_attack_direction, _last_attack_tier
	)


func dump_combat_tags() -> void:
	## Cheap F5 probe — print CombatTags catalog + last applied hit tags.
	print(get_combat_tags_debug_text())
	var ch := _session_character_health()
	if ch:
		var names: PackedStringArray = PackedStringArray()
		for tag in ch.get_wound_tags():
			names.append(String(tag))
		print(
			"CharacterHealth tags: wounds=[%s] last_wound=%s stagger=%s (%.2fs / int=%d)" % [
				", ".join(names),
				String(ch.last_wound_tag),
				String(ch.last_stagger_tag),
				ch.last_stagger_duration_sec,
				ch.last_stagger_interrupt,
			]
		)


func get_block_posture_debug_text() -> String:
	return BlockPostureTable.get_debug_text(posture, guard_face, _last_guard_resolve)


func dump_block_posture_table() -> void:
	## Cheap F5 probe — print BlockPostureTable + current posture / last resolve.
	print(get_block_posture_debug_text())
	print(
		"CombatSystem face_guard: enable=%s guard=%s posture=%.0f/%.0f break_left=%.2fs stagger_left=%.2fs" % [
			str(enable_face_guard),
			String(guard_face),
			posture,
			BlockPostureTable.MAX_POSTURE,
			posture_break_left,
			stagger_left,
		]
	)


func get_posture_break_stagger_debug_text() -> String:
	## Document break → CombatTags stagger link for Lead / Godot sparring feel.
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Posture break → CombatTags stagger ===")
	lines.append(
		"link: posture pool 0 → apply CombatTags %s (reuse existing stagger — no parallel CC)" % [
			String(BlockPostureTable.BREAK_STAGGER_TAG),
		]
	)
	lines.append(
		"durations: break_stun=%.2fs  tag_dur=%.2fs  (aligned; stagger_left driven with break)" % [
			BlockPostureTable.break_stun_sec(),
			CombatTags.duration_sec(BlockPostureTable.BREAK_STAGGER_TAG),
		]
	)
	lines.append(
		"live: enable_face_guard=%s posture=%.0f/%.0f break_left=%.2fs stagger_left=%.2fs last_stagger=%s" % [
			str(enable_face_guard),
			posture,
			BlockPostureTable.MAX_POSTURE,
			posture_break_left,
			stagger_left,
			String(last_stagger_tag) if last_stagger_tag != &"" else "-",
		]
	)
	if _last_posture_break.is_empty():
		lines.append("last break: (none yet)")
	else:
		lines.append(
			"last break: tag=%s dur=%.2fs interrupt=%d break_left=%.2fs stagger_left=%.2fs" % [
				String(_last_posture_break.get("stagger_tag", &"")),
				float(_last_posture_break.get("duration_sec", 0.0)),
				int(_last_posture_break.get("interrupt_strength", 0)),
				float(_last_posture_break.get("posture_break_left", 0.0)),
				float(_last_posture_break.get("stagger_left", 0.0)),
			]
		)
	lines.append("Godot: can_move() false while stagger_left>0; posture_broken signal for feel/VFX")
	lines.append("F5 probe: press F11 — this dump (see systems/combat/README.md)")
	return "\n".join(lines)


func dump_posture_break_stagger() -> void:
	## Cheap F5 probe — posture break → stagger link + live timers.
	print(get_posture_break_stagger_debug_text())


func get_flank_bonus_debug_text() -> String:
	return FlankBonusTable.get_debug_text(_last_flank_resolve)


func dump_flank_bonus_table() -> void:
	## Cheap F5 probe — print FlankBonusTable + last open-side resolve.
	print(get_flank_bonus_debug_text())
	print(
		"CombatSystem flank: enable_face_guard=%s guard=%s last_mult=%.2f" % [
			str(enable_face_guard),
			String(guard_face),
			float(_last_flank_resolve.get("multiplier", 1.0)) if not _last_flank_resolve.is_empty() else 1.0,
		]
	)


## Apply a stagger tag onto this entity (short CC stub countdown).
func apply_stagger_tag(tag: StringName) -> Dictionary:
	var entry: Dictionary = CombatTags.stagger_entry(tag)
	if entry.is_empty():
		return {}
	last_stagger_tag = tag
	last_stagger_interrupt = int(entry.get("interrupt_strength", 0))
	stagger_left = maxf(stagger_left, float(entry.get("duration_sec", 0.0)))
	return entry


func is_staggered() -> bool:
	return stagger_left > 0.0


func _apply_hit_tags(target: CombatSystem, kind: StringName) -> void:
	## Resolve CombatTags for this swing and push onto target (+ session if player).
	if target == null or not is_instance_valid(target):
		return
	var wname: StringName = WEAPON_NAMES[current_weapon]
	var direction: StringName = _last_attack_direction
	var tier: StringName = _last_attack_tier
	if _hitbox:
		direction = StringName(str(_hitbox.get_meta("direction", direction)))
		tier = StringName(str(_hitbox.get_meta("tier", tier)))
	var tags: Array[StringName] = CombatTags.tags_for_hit(wname, kind, direction, tier)
	_last_hit_tags = tags.duplicate()
	_last_hit_tags_weapon = wname
	if tags.is_empty():
		return
	var target_is_player := _combat_owner_is_player(target)
	var ch := _session_character_health() if target_is_player else null
	for tag in tags:
		if CombatTags.is_stagger(tag):
			target.apply_stagger_tag(tag)
			if ch:
				ch.apply_stagger_tag(tag)
		elif CombatTags.is_wound(tag):
			# Soft wound counter is session-level (player). NPCs skip integer wounds.
			if ch:
				ch.apply_wound_tag(tag)


func _combat_owner_is_player(combat: CombatSystem) -> bool:
	if combat == null:
		return false
	var body := combat.get_parent()
	if body == null:
		return false
	if body.is_in_group("player"):
		return true
	# Fallback: player team 0 with CharacterHealth bridge sibling.
	if combat.team == 0 and body.get_node_or_null("HealthCombatBridge") != null:
		return true
	return false


func reset_weapon_pose() -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	if _charge_pose_tween and _charge_pose_tween.is_valid():
		_charge_pose_tween.kill()
	is_charging = false
	charge_time = 0.0
	charge_ratio = 0.0
	if _weapon_visual:
		_weapon_visual.transform = _weapon_rest_transform

func consume_knockback() -> Vector3:
	## Character controllers should add this to velocity each physics frame.
	var v := knockback_vel
	knockback_vel = Vector3.ZERO
	return v


func peek_knockback() -> Vector3:
	return knockback_vel


func _play_hurt_feedback(amount: float, from: Node) -> void:
	_flash_hurt_meshes()
	_apply_knockback_from(from, amount)
	if show_damage_numbers:
		_spawn_damage_number(amount)


func _play_hit_confirm(kind: StringName) -> void:
	# Brief hit-stop so contact reads; charged/heavy gets stronger freeze + juice.
	if _hit_stop_running:
		return
	var charged := kind == &"heavy" and current_weapon == Weapon.HATCHET
	var dur := hit_stop_charged if charged else (hit_stop_heavy if kind == &"heavy" else hit_stop_light)
	if dur <= 0.0:
		return
	_hit_stop_running = true
	var prev := Engine.time_scale
	Engine.time_scale = charged_impact_scale if charged else (0.08 if kind == &"heavy" else 0.12)
	# Small weapon kick on charged contact for readable impact.
	if charged and _weapon_visual:
		var kick := _weapon_visual.position + Vector3(0.0, 0.04, -0.06)
		var tw := create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(_weapon_visual, "position", kick, 0.03).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_weapon_visual, "position", _weapon_rest_transform.origin, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = prev if prev > 0.01 else 1.0
	_hit_stop_running = false


func _flash_hurt_meshes() -> void:
	if _hurt_flash_tween and _hurt_flash_tween.is_valid():
		_hurt_flash_tween.kill()
	_clear_hurt_flash()
	var meshes := _collect_visual_meshes()
	if meshes.is_empty():
		return
	var flash := StandardMaterial3D.new()
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.albedo_color = Color(1.0, 0.45, 0.35, 0.85)
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mesh in meshes:
		mesh.material_overlay = flash
		_mesh_overlays.append(mesh)
	_hurt_flash_tween = create_tween()
	_hurt_flash_tween.tween_interval(hurt_flash_secs)
	_hurt_flash_tween.tween_callback(_clear_hurt_flash)


func _clear_hurt_flash() -> void:
	for mesh in _mesh_overlays:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_mesh_overlays.clear()


func _collect_visual_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _owner_body == null:
		return out
	var visual := _owner_body.get_node_or_null("Visual")
	if visual == null:
		return out
	_gather_meshes(visual, out)
	return out


func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, out)


func _apply_knockback_from(from: Node, amount: float) -> void:
	if _owner_body == null:
		return
	var origin := _owner_body.global_position
	var src_pos := origin + Vector3(0.0, 0.0, 1.0)
	if from is Node3D:
		src_pos = (from as Node3D).global_position
	var dir := origin - src_pos
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_owner_body.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()
	var strength := knockback_light
	if amount >= 22.0:
		strength = knockback_heavy
	elif amount >= 16.0:
		strength = lerpf(knockback_light, knockback_heavy, 0.5)
	# Scale slightly by damage so lights nudge, heavies shove.
	strength *= clampf(amount / 14.0, 0.7, 1.35)
	knockback_vel += dir * strength + Vector3(0.0, 1.1, 0.0) * (0.35 if amount >= 22.0 else 0.15)


func _spawn_damage_number(amount: float) -> void:
	if _owner_body == null:
		return
	var label := Label3D.new()
	label.text = "%d" % int(round(amount))
	label.font_size = 48
	label.modulate = Color(1.0, 0.85, 0.35, 1.0)
	label.outline_modulate = Color(0.1, 0.05, 0.0, 1.0)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.0045
	var parent_node: Node = _owner_body.get_parent()
	var anchor := _owner_body.global_position + Vector3(
		randf_range(-0.15, 0.15), 1.55, randf_range(-0.1, 0.1)
	)
	if parent_node:
		parent_node.add_child(label)
	else:
		_owner_body.add_child(label)
	label.global_position = anchor
	var tw := label.create_tween()
	var end_pos := label.global_position + Vector3(0.0, 0.85, 0.0)
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", end_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(label.queue_free)

