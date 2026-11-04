extends Node
## Open-world hunger (F5 main only; the F4 prologue scene has no ExileHunger node, so it is never
## touched). Cian is an exile living off the wood edge in May 1169: hunger creeps up while he is
## awake, a night's fast on the ground costs some more, and foraged greens take the edge off.
##
## Rules (camp + hunger pass):
##   1. `hunger` runs 0 (fed) .. 1 (starving). Awake it rises AWAKE_RATE per second
##      (~13 real minutes from fed to the bite threshold).
##   2. From BITE (0.6) up, his pace falls linearly to STARVE_SCALE (0.72) at 1.0 — walk, trot
##      and sprint all scale through player_controller.move_speed_scale. Slowdown only: no damage,
##      no death, no meter. One first-use tip the first time it bites.
##   3. Sleep ↔ hunger: a full night's sleep at camp adds NIGHT_FAST (0.2) — you wake hungrier,
##      never fed by sleeping — but sleeping is the only thing that regrows the forage (one pick
##      per plant per day).
##   4. Eating a forageable lowers hunger by its own amount (sorrel little, bramble shoots more).

const AWAKE_RATE := 0.6 / 780.0
const BITE := 0.6
const STARVE_SCALE := 0.72
const NIGHT_FAST := 0.2

@export var player_path: NodePath = ^"../Player"
@export var enabled: bool = true
## Smoke / capture: multiply the awake rate.
@export var rate_scale: float = 1.0

var hunger: float = 0.15

signal hunger_bit


func _ready() -> void:
	add_to_group("exile_hunger")


func _player() -> Node:
	return get_node_or_null(player_path)


func pace_scale() -> float:
	if hunger <= BITE:
		return 1.0
	return lerpf(1.0, STARVE_SCALE, clampf((hunger - BITE) / (1.0 - BITE), 0.0, 1.0))


func is_biting() -> bool:
	return hunger > BITE


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	set_hunger(hunger + AWAKE_RATE * rate_scale * delta)


func set_hunger(v: float) -> void:
	var was := is_biting()
	hunger = clampf(v, 0.0, 1.0)
	var p := _player()
	if p and "move_speed_scale" in p:
		p.move_speed_scale = pace_scale()
	if is_biting() and not was:
		hunger_bit.emit()
		var tips := get_tree().get_first_node_in_group("exile_tips")
		if tips:
			tips.tip_once(&"hunger", "Hunger is slowing you. Forage at the wood edge.")


func eat(amount: float) -> void:
	set_hunger(hunger - amount)


func on_slept() -> void:
	set_hunger(hunger + NIGHT_FAST)
