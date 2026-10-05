extends RefCounted
## Scripted "player" for the opening cattle drive smoke / capture. It only does what a player
## can: stand behind cattle with the goad drawn (proximity pressure) and prod laggards with
## the same apply_goad(from, forward) call CombatSystem makes on a goad hit. Movement is a
## teleport-follow (no input sim), so this proves the herd AI + lane geometry are completable.

const BEHIND_DIST := 2.4
const PROD_COOLDOWN := 0.9
const RETARGET_SECS := 0.5

var director: Node
var player: Node3D
var prods: int = 0
var _target: Node3D = null
var _retarget_t: float = 0.0
var _prod_t: float = 0.0


func _init(p_director: Node, p_player: Node3D) -> void:
	director = p_director
	player = p_player


func tick(delta: float) -> void:
	_retarget_t -= delta
	_prod_t -= delta
	var cows: Array = director.call("get_cows")
	var live: Array = []
	for c in cows:
		if not bool(c.get("delivered")):
			live.append(c)
	if live.is_empty():
		return
	if _target == null or bool(_target.get("delivered")) or _retarget_t <= 0.0:
		_retarget_t = RETARGET_SECS
		_target = _pick_target(live)
	var cow := _target
	var goal: Vector3 = cow.call("_next_path_target")
	var dir := goal - cow.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.BACK
	dir = dir.normalized()
	var pos := cow.global_position - dir * BEHIND_DIST
	pos.y = player.global_position.y
	player.global_position = pos
	player.look_at(pos + dir, Vector3.UP)
	player.set("velocity", Vector3.ZERO)
	var fresh := float(cow.call("drive_freshness")) if cow.has_method("drive_freshness") else 1.0
	if (fresh < 0.55 or bool(cow.get("bogged")) or not bool(cow.get("driven"))) and _prod_t <= 0.0:
		_prod_t = PROD_COOLDOWN
		prods += 1
		cow.call("apply_goad", player.global_position, dir, 1.0, &"light")


func _pick_target(live: Array) -> Node3D:
	## Laggard first: stalest drive, then farthest from home along the lane.
	var home: Vector3 = director.call("home_center")
	var best: Node3D = null
	var best_score: float = -INF
	for c in live:
		var fresh := float(c.call("drive_freshness")) if c.has_method("drive_freshness") else 0.0
		var score: float = (1.0 - fresh) * 100.0 + c.global_position.distance_to(home) * 0.5
		if bool(c.get("bogged")):
			score += 200.0
		if score > best_score:
			best_score = score
			best = c
	return best
