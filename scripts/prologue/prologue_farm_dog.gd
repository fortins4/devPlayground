extends OpeningStrayDogChore
class_name PrologueFarmDog
## Raid day, evening (steps 1–3): the household's own dog in the yard — met before the dawn so its
## barking and the yelp at first light (step 4, heard only) mean something. The stray's hound mesh
## and four-legged gait (OpeningStrayDogChore) in its own coat: black, with a white chest, muzzle
## and stockings (the stray is a dun-brown hound). Ambient only: no prompt, no interaction, no
## name tag. It lies by the house door; gets up and trots after Cian when he is about the yard
## (or after the herd-hand when he goes down off the bank); goes once to sniff at the neighbours'
## boy. It is gone from the night fade on (RaidSequence calls `night_gone`): at dawn it is a
## sound at the gate and then nothing (Decision 15), never seen.
## Lying: a settled dog's pose, not a fold of the standing rig — chest and belly down on the earth,
## the hindquarters rolled onto the left hip with both hind legs folded out to the right, the
## forelegs straight out in front (elbows on the ground, paws flat), tail laid round on the ground;
## head up and watching while someone is close, down on its paws when the yard is quiet.
## Moving: it steers round the yard's props (stool, quern, sack, sieve, tie post, trough, house
## wall, the pen, a cow). The way is planned on a coarse grid over the yard (A*, with a cost for
## passing close to anything so it keeps room to swing its body), and every step is checked with
## a footprint box the size of the dog shape-cast against the colliders and the dressing that has
## none; it never takes a step that would put it into a prop. It turns on the spot into its lying
## heading before it settles. No physics body of its own.

const HouseI := preload("res://scripts/prologue/prologue_house_interior.gd")
const LIE_AT := Vector3(-5.9, 0.0, 2.7)
const LIE_YAW := 2.6
const FOLLOW_GAP := 2.4
const WALK_V := 1.3
const TROT_V := 2.6
const YARD_R := 13.0
const RATH_C := Vector3(0.5, 0.0, 3.0)
## Footprint used for avoidance (nose to tail-root, flank to flank, plus a hand's clearance).
const FOOT := Vector3(0.44, 0.5, 1.08)
const FOOT_Y := 0.3
const FOOT_FWD := 0.1
const GRID_CELL := 0.2
const GRID_N := 150
const GRID_O := Vector3(-14.5, 0.0, -12.0) ## the grid's NW corner: the ráth yard and the house
const GRID_BODY_R := 0.3
const TURN_RATE := 4.0 ## rad/s when turning on the spot to settle
## Yard dressing with no collider (radius m): the meal stool, the sack and the sieve by the quern,
## the herd-hand's supper set down by the stool.
const DRESSING := [[Vector3(-4.5, 0.0, 2.8), 0.36], [Vector3(-4.75, 0.0, 5.0), 0.3], [Vector3(-3.55, 0.0, 5.05), 0.26], [Vector3(-4.5, 0.0, 3.35), 0.2]]
## Head up while someone is this close.
const WATCH_R := 5.0

enum Mode { LYING, FOLLOWING, SNIFFING, GONE }

var _mode: Mode = Mode.LYING
var _raid: Node = null
var _boy: Node3D = null
var _hh: Node3D = null
var _lead: Node3D = null
var _sniffed: bool = false
var _sniff_t: float = 0.0
var _lie_w: float = 1.0
var _mode_t: float = 0.0
var _ever_followed: bool = false
## Lying rig: the parts moved between standing and lying (rest = the stray's standing build).
var _trunk: MeshInstance3D = null
var _chest: MeshInstance3D = null
var _head: Node3D = null
var _tail: Node3D = null
var _paws: Array = []
var _rest: Dictionary = {}
var _head_up: float = 1.0
var _foot_shape: BoxShape3D = null
var _exclude: Array[RID] = []
var _commit_t: float = 0.0
var _commit_dir: float = 1.0
var _stuck_t: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _stuck_yaw: float = 0.0
## Yard grid for planning (cost per cell, −1 = the body cannot stand there).
var _grid: PackedFloat32Array = PackedFloat32Array()
var _path: Array = []
var _path_goal: Vector3 = Vector3.INF
var _replan_t: float = 0.0
var _min_clear: float = INF


func _ready() -> void:
	add_to_group("prologue_farm_dog")
	coat = Color(0.11, 0.1, 0.09)
	coat_dark = Color(0.86, 0.84, 0.78)
	coat_muzzle = Color(0.9, 0.88, 0.82)
	_build_dog()
	_dog.name = "FarmDog"
	# No name tag: the stray's label goes (its bark label stays, unused).
	for c in _dog.get_children():
		if c is Label3D and (c as Label3D).name != "Bark":
			c.queue_free()
	_rig_for_lying()
	_dog.global_position = _grounded(LIE_AT)
	_dog.rotation.y = LIE_YAW
	_last_pos = _dog.global_position
	_foot_shape = BoxShape3D.new()
	_foot_shape.size = FOOT
	call_deferred("_bind")


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_raid = get_tree().get_first_node_in_group("raid_sequence")
	var ground := get_tree().current_scene.find_child("Ground", true, false) if get_tree().current_scene else null
	if ground == null:
		var r := get_parent()
		while r and r.get_parent() and not (r.get_parent() is Window):
			r = r.get_parent()
		ground = r.find_child("Ground", true, false) if r else null
	if ground is CollisionObject3D:
		_exclude = [(ground as CollisionObject3D).get_rid()]


func set_cast(boy: Node3D, herd_hand: Node3D) -> void:
	_boy = boy
	_hh = herd_hand


func mode_name() -> String:
	return ["lying", "following", "sniffing", "gone"][int(_mode)]


func is_present() -> bool:
	return _mode != Mode.GONE and _dog != null and _dog.is_visible_in_tree()


func dog_node() -> Node3D:
	return _dog


## The night fade: the dog is not seen again.
func night_gone() -> void:
	_mode = Mode.GONE
	if _dog:
		_dog.visible = false
	set_process(false)
	print("PROLOGUE_FARM_DOG_GONE")


# No prompt, no E, never a chore.
func interact_prompt() -> String:
	return ""


func is_active() -> bool:
	return false


func try_interact() -> bool:
	return false


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _process(delta: float) -> void:
	if _mode == Mode.GONE or _dog == null:
		return
	_mode_t += delta
	var dp := _dog.global_position
	match _mode:
		Mode.LYING:
			# Back to its place by the door first, then settle there.
			if _flat(dp - LIE_AT) > 0.05:
				_move_toward(LIE_AT, WALK_V * delta)
			else:
				_turn_to(LIE_YAW, delta)
			# Up when Cian (or the herd-hand coming down) is about the yard away from the door.
			var lead := _pick_lead()
			if lead and _mode_t > 2.0:
				_lead = lead
				_ever_followed = true
				_set_mode(Mode.FOLLOWING)
			elif _boy and is_instance_valid(_boy) and not _sniffed and _flat(_boy.global_position - dp) < 6.0 and _mode_t > 1.0:
				_set_mode(Mode.SNIFFING)
		Mode.FOLLOWING:
			if _lead == null or not is_instance_valid(_lead) or _pick_lead() == null:
				# Back to lie by the door.
				if _move_toward(LIE_AT, WALK_V * delta):
					_set_mode(Mode.LYING)
			else:
				var lp := _lead.global_position
				var d := _flat(lp - dp)
				if d > FOLLOW_GAP:
					_move_toward(lp, (TROT_V if d > 5.0 else WALK_V) * delta)
				if _boy and is_instance_valid(_boy) and not _sniffed and _flat(_boy.global_position - dp) < 3.5:
					_set_mode(Mode.SNIFFING)
		Mode.SNIFFING:
			if _boy == null or not is_instance_valid(_boy):
				_set_mode(Mode.LYING)
			else:
				var bp := _boy.global_position
				if _flat(bp - dp) > 0.75:
					_move_toward(bp, WALK_V * delta)
				else:
					_sniff_t += delta
					if _sniff_t > 2.2:
						_sniffed = true
						print("PROLOGUE_FARM_DOG_SNIFFED_BOY")
						_set_mode(Mode.LYING)
	_tick_gait(delta)
	# Down only once it is on its spot and turned into its lying heading.
	var settled := _mode == Mode.LYING and _flat(_dog.global_position - LIE_AT) < 0.2 and absf(wrapf(_dog.rotation.y - LIE_YAW, -PI, PI)) < 0.15
	_lie_w = move_toward(_lie_w, 1.0 if settled else 0.0, delta * 1.6)
	var near := false
	for who in [_player, _boy, _hh]:
		if who and is_instance_valid(who) and (who as Node3D).is_visible_in_tree() and _flat((who as Node3D).global_position - _dog.global_position) < WATCH_R:
			near = true
	_head_up = move_toward(_head_up, 1.0 if near else 0.0, delta * 0.8)
	_pose_lying(smoothstep(0.0, 1.0, _lie_w), smoothstep(0.0, 1.0, _head_up))
	_dog.position.y = _grounded(_dog.global_position).y
	_note_clearance()


func ever_followed() -> bool:
	return _ever_followed


func has_sniffed_boy() -> bool:
	return _sniffed


func visible_tags() -> int:
	var n := 0
	for c in _dog.get_children():
		if c is Label3D and (c as Label3D).visible:
			n += 1
	return n


func is_lying() -> bool:
	return _mode == Mode.LYING and _lie_w > 0.9


func lie_weight() -> float:
	return _lie_w


func head_up_weight() -> float:
	return _head_up


## Smokes: the nearest the footprint has come to a prop (m, signed: < 0 = overlap) since asked.
func min_clearance() -> float:
	return _min_clear


func reset_clearance() -> void:
	_min_clear = INF


# ---------------------------------------------------------------- lying rig

## Split the stray's build into the parts a lying dog moves: the trunk box and the chest box stay
## (lowered), the head (with ears, eyes, muzzle) on a neck pivot, the tail on a root pivot. The
## standing look is unchanged (rest positions are the stray's).
func _rig_for_lying() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.5, 0.4)
	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.55, -0.32)
	var kids := _dog.get_children()
	_dog.add_child(_head)
	_dog.add_child(_tail)
	for c in kids:
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var p := mi.position
		if p.is_equal_approx(Vector3(0.0, 0.42, 0.0)):
			_trunk = mi
		elif p.is_equal_approx(Vector3(0.0, 0.48, 0.28)):
			_chest = mi
		elif p.z > 0.4:
			mi.reparent(_head, false)
			mi.position = p - _head.position
		elif p.z < -0.3:
			mi.reparent(_tail, false)
			mi.position = p - _tail.position
	for L in _legs:
		var knee := (L as Dictionary)["knee"] as Node3D
		var paw: MeshInstance3D = null
		for k in knee.get_children():
			if k is MeshInstance3D and ((k as MeshInstance3D).mesh as BoxMesh).size.z > 0.09:
				paw = k
		_paws.append(paw)
		_rest[(L as Dictionary)["hip"]] = ((L as Dictionary)["hip"] as Node3D).position
	for n in [_trunk, _chest, _head, _tail]:
		_rest[n] = (n as Node3D).position
	for paw in _paws:
		if paw:
			_rest[paw] = (paw as Node3D).position


## Lying pose at weight w (0 = the gait's standing / moving pose, 1 = down), head up at h.
## Heights are above the ground under the dog (rig y 0). Hindquarters onto the left hip, so both
## hind legs fold out to the right (+X when the dog faces +Z), the back leaning a little left.
func _pose_lying(w: float, h: float) -> void:
	if _trunk == null:
		return
	_trunk.position = (_rest[_trunk] as Vector3).lerp(Vector3(0.02, 0.2, -0.02), w)
	_trunk.rotation = Vector3(0.0, 0.0, 0.12 * w)  # back leaning a little toward the hip it lies on
	_chest.position = (_rest[_chest] as Vector3).lerp(Vector3(0.0, 0.16, 0.27), w)
	# Head: up and watching (muzzle level, ~0.4 m) or laid on the forepaws (chin on them).
	var head_lie := Vector3(0.0, 0.16, 0.42).lerp(Vector3(0.0, 0.31, 0.42), h)
	_head.position = (_rest[_head] as Vector3).lerp(head_lie, w)
	_head.rotation = Vector3(lerpf(0.3, -0.04, h) * w, 0.0, 0.0)
	# Tail laid on the ground, swept round toward the folded hind legs.
	_tail.position = (_rest[_tail] as Vector3).lerp(Vector3(0.05, 0.07, -0.34), w)
	_tail.rotation = Vector3(-0.2 * w, -0.85 * w, 0.0)
	for i in _legs.size():
		var L: Dictionary = _legs[i]
		var hip := L["hip"] as Node3D
		var knee := L["knee"] as Node3D
		var stand_hip := Basis(Vector3.RIGHT, hip.rotation.x)
		var knee_x := knee.rotation.x
		var lie_pos: Vector3
		var lie_hip: Basis
		var lie_knee: float
		if bool(L["front"]):
			# Elbow on the ground under the shoulder, forearm and paw flat out in front.
			lie_pos = Vector3(0.11 * signf((_rest[hip] as Vector3).x), 0.2, 0.42)
			lie_hip = Basis(Vector3.RIGHT, 0.6)
			lie_knee = -(PI * 0.5 + 0.6)
		elif (_rest[hip] as Vector3).x > 0.0:
			# Right hind: the upper one — thigh along the flank, hock folded back, out to the right.
			lie_pos = Vector3(0.25, 0.16, -0.24)
			lie_hip = Basis(Vector3.BACK, 1.25) * Basis(Vector3.RIGHT, -1.2)
			lie_knee = 2.6
		else:
			# Left hind: the one lain on — tucked under, its hock showing beside the other.
			lie_pos = Vector3(0.14, 0.055, -0.32)
			lie_hip = Basis(Vector3.BACK, 1.5) * Basis(Vector3.RIGHT, -0.7)
			lie_knee = 1.7
		hip.position = (_rest[hip] as Vector3).lerp(lie_pos, w)
		hip.basis = Basis(stand_hip.get_rotation_quaternion().slerp(lie_hip.get_rotation_quaternion(), w))
		knee.rotation = Vector3(lerpf(knee_x, lie_knee, w), 0.0, 0.0)
		var paw := _paws[i] as MeshInstance3D
		if paw and bool(L["front"]):
			# Paw flat on the ground pointing forward (its sole was under it standing).
			paw.position = (_rest[paw] as Vector3).lerp(Vector3(0.0, -UPPER_LEN + 0.0, 0.0), w)
			paw.rotation = Vector3(PI * 0.5 * w, 0.0, 0.0)


# ---------------------------------------------------------------- moving round the props

## Turn on the spot toward `yaw` (rad), clear of props.
func _turn_to(yaw: float, delta: float) -> void:
	var cur := _dog.rotation.y
	var d := wrapf(yaw - cur, -PI, PI)
	if absf(d) < 0.01:
		return
	var nxt := cur + clampf(d, -TURN_RATE * delta, TURN_RATE * delta)
	if _footprint_clear(_dog.global_position, nxt):
		_dog.rotation = Vector3(0.0, nxt, 0.0)


## Step toward `target` round the props, facing the way it goes. True on arrival.
## The way is planned on a coarse yard grid (cells the dog's body can stand in, a cost for passing
## close to anything), so it goes round the stool / quern cluster with room to swing its body
## instead of nosing into the gap; each frame the actual step (a small turn and / or a step on, or
## half a step back out of a tight spot) is the one that keeps its whole footprint clear and best
## follows the planned line.
func _move_toward(target: Vector3, step: float) -> bool:
	var pos := _dog.global_position
	var to := target - pos
	to.y = 0.0
	var d := to.length()
	if d <= maxf(step, 0.01):
		if _footprint_clear(target, _dog.rotation.y):
			_dog.global_position = _grounded(target)
			return true
		return false
	var aim := _path_aim(pos, target)
	var pick := atan2(aim.x - pos.x, aim.z - pos.z)  # model front is +Z: yaw with sin = x, cos = z
	var cur := _dog.rotation.y
	var max_turn := maxf(step * 3.2, 0.06)  # no faster than a dog turns at a walk / trot
	var here := footprint_clearance(pos, cur)
	var floor_c := 0.0 if here > 0.0 else here  # already touching: anything not worse
	var best_cost := INF
	var best_p := pos
	var best_y := cur
	var turn_need := wrapf(pick - cur, -PI, PI)
	for f in [0.0, -0.5, 0.5, -1.0, 1.0]:
		var yy: float = cur + clampf(turn_need, -max_turn, max_turn) if f == 0.0 else cur + max_turn * float(f)
		# Stuck turning one way: keep going round the other way until it is free.
		if _commit_t > 0.0 and f != 0.0 and signf(float(f)) != _commit_dir:
			continue
		for sp in [step, step * 0.5, 0.0, -step * 0.4]:
			if sp == 0.0 and absf(yy - cur) < 1e-4:
				continue
			var np: Vector3 = pos + Vector3(sin(yy), 0.0, cos(yy)) * float(sp)
			var cl := footprint_clearance(np, yy)
			if cl < floor_c or (floor_c == 0.0 and cl <= 0.0):
				continue
			var gain := (_flat(aim - pos) - _flat(aim - np)) / maxf(step, 1e-4)  # 1 = a full step nearer
			var err := absf(wrapf(pick - yy, -PI, PI))
			if _commit_t > 0.0:
				err = 0.0 if signf(yy - cur) == _commit_dir else 1.0
			var cost := err - 0.5 * gain + (0.4 if float(sp) < 0.0 else 0.0)
			if cost < best_cost:
				best_cost = cost
				best_p = np
				best_y = yy
	_commit_t = maxf(0.0, _commit_t - get_process_delta_time())
	# Watch for no headway (a turn it cannot make in the space it is in).
	_stuck_t += get_process_delta_time()
	if _flat(pos - _stuck_ref) > 0.15 or absf(wrapf(cur - _stuck_yaw, -PI, PI)) > 0.6:
		_stuck_ref = pos
		_stuck_yaw = cur
		_stuck_t = 0.0
	elif _stuck_t > 0.8 and _commit_t <= 0.0:
		_commit_dir = -signf(turn_need) if turn_need != 0.0 else 1.0
		_commit_t = 1.6
		_stuck_t = 0.0
	if best_cost == INF:
		return false  # boxed in: stand and wait (calm); it clears as the lead moves
	_dog.global_position = _grounded(best_p)
	_dog.rotation = Vector3(0.0, best_y, 0.0)
	return false


# ---------------------------------------------------------------- yard grid

## Where to head for now: a point ~0.9 m on along the planned way (replanned as the goal moves).
func _path_aim(pos: Vector3, target: Vector3) -> Vector3:
	_ensure_grid()
	_replan_t -= get_process_delta_time()
	if _path.is_empty() or _replan_t <= 0.0 or _flat(target - _path_goal) > 0.5:
		_path = _plan(pos, target)
		_path_goal = target
		_replan_t = 0.5
	while _path.size() > 1 and _flat((_path[0] as Vector3) - pos) < 0.9:
		_path.remove_at(0)
	if _path.is_empty():
		return target
	return _path[0]


func _ensure_grid() -> void:
	if not _grid.is_empty() or _dog == null or not _dog.is_inside_tree():
		return
	var n := GRID_N * GRID_N
	_grid.resize(n)
	var ss := _dog.get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = GRID_BODY_R
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = sph
	qp.collision_mask = 1
	qp.exclude = _exclude
	var blocked := PackedByteArray()
	blocked.resize(n)
	for iz in GRID_N:
		for ix in GRID_N:
			var w := _cell_world(ix, iz)
			var hit := false
			for it in DRESSING:
				if _flat(w - (it[0] as Vector3)) < float(it[1]) + GRID_BODY_R:
					hit = true
			if not hit:
				qp.transform = Transform3D(Basis.IDENTITY, Vector3(w.x, Terrain.surface_y(w.x, w.z) + 0.32, w.z))
				hit = not ss.intersect_shape(qp, 1).is_empty()
			blocked[iz * GRID_N + ix] = 1 if hit else 0
	# Cost: blocked, else extra for being within ~0.6 m of anything (room to swing the body).
	for iz in GRID_N:
		for ix in GRID_N:
			var i := iz * GRID_N + ix
			if blocked[i] == 1:
				_grid[i] = -1.0
				continue
			var near := 0
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					var jx := ix + dx
					var jz := iz + dz
					if jx < 0 or jz < 0 or jx >= GRID_N or jz >= GRID_N or blocked[jz * GRID_N + jx] == 1:
						near = maxi(near, 4 - maxi(absi(dx), absi(dz)))
			_grid[i] = 1.0 + 1.5 * float(near)


func _cell_world(ix: int, iz: int) -> Vector3:
	return Vector3(GRID_O.x + (float(ix) + 0.5) * GRID_CELL, 0.0, GRID_O.z + (float(iz) + 0.5) * GRID_CELL)


func _world_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - GRID_O.x) / GRID_CELL)), 0, GRID_N - 1), clampi(int(floor((p.z - GRID_O.z) / GRID_CELL)), 0, GRID_N - 1))


func _nearest_free(c: Vector2i) -> Vector2i:
	if _grid[c.y * GRID_N + c.x] > 0.0:
		return c
	for r in range(1, 8):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var z := c.y + dz
				if x >= 0 and z >= 0 and x < GRID_N and z < GRID_N and _grid[z * GRID_N + x] > 0.0:
					return Vector2i(x, z)
	return c


## A* on the grid (8-way); returns world points from just after the start to the goal.
func _plan(from: Vector3, to: Vector3) -> Array:
	var s := _nearest_free(_world_cell(from))
	var g := _nearest_free(_world_cell(to))
	var si := s.y * GRID_N + s.x
	var gi := g.y * GRID_N + g.x
	var gcost := {si: 0.0}
	var came := {}
	var open := [[0.0, si]]
	var closed := {}
	var found := false
	var guard := 0
	while not open.is_empty() and guard < 12000:
		guard += 1
		var bi := 0
		for k in open.size():
			if float(open[k][0]) < float(open[bi][0]):
				bi = k
		var curi: int = open[bi][1]
		open.remove_at(bi)
		if closed.has(curi):
			continue
		closed[curi] = true
		if curi == gi:
			found = true
			break
		var cx := curi % GRID_N
		var cz := curi / GRID_N
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx: int = cx + dx
				var nz: int = cz + dz
				if nx < 0 or nz < 0 or nx >= GRID_N or nz >= GRID_N:
					continue
				var ni := nz * GRID_N + nx
				var cell: float = _grid[ni]
				if cell < 0.0 or closed.has(ni):
					continue
				if dx != 0 and dz != 0 and (_grid[cz * GRID_N + nx] < 0.0 or _grid[nz * GRID_N + cx] < 0.0):
					continue  # no corner cutting
				var stepc := (1.4142 if dx != 0 and dz != 0 else 1.0) * cell
				var ng: float = float(gcost[curi]) + stepc
				if not gcost.has(ni) or ng < float(gcost[ni]):
					gcost[ni] = ng
					came[ni] = curi
					var hx: int = absi(nx - g.x)
					var hz: int = absi(nz - g.y)
					open.append([ng + float(maxi(hx, hz)) + 0.4142 * float(mini(hx, hz)), ni])
	var out: Array = []
	if not found:
		return [to]
	var k: int = gi
	while k != si and came.has(k):
		out.push_front(_cell_world(k % GRID_N, k / GRID_N))
		k = came[k]
	if not out.is_empty():
		out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
	else:
		out.append(Vector3(to.x, 0.0, to.z))
	return out


## True if the dog's footprint at `p` facing `yaw` touches no prop.
func _footprint_clear(p: Vector3, yaw: float) -> bool:
	return footprint_clearance(p, yaw) > 0.0


## Signed clearance (m) of the footprint at `p` / `yaw` from the nearest prop: colliders by a
## shape query (≤ 0 if touching), dressing by distance to the box.
func footprint_clearance(p: Vector3, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var fwd := basis * Vector3(0.0, 0.0, FOOT_FWD)
	var c := Vector3(p.x, Terrain.surface_y(p.x, p.z) + FOOT_Y, p.z) + fwd
	var best := 1.0
	for it in DRESSING:
		var q: Vector3 = it[0]
		var r: float = it[1]
		var l := basis.inverse() * Vector3(q.x - c.x, 0.0, q.z - c.z)
		var dx := maxf(absf(l.x) - FOOT.x * 0.5, 0.0)
		var dz := maxf(absf(l.z) - FOOT.z * 0.5, 0.0)
		best = minf(best, Vector2(dx, dz).length() - r)
	if _dog == null or not _dog.is_inside_tree():
		return best
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = _foot_shape
	qp.transform = Transform3D(basis, c)
	qp.collision_mask = 1
	qp.exclude = _exclude
	qp.collide_with_areas = false
	var hits := _dog.get_world_3d().direct_space_state.intersect_shape(qp, 4)
	if not hits.is_empty():
		best = minf(best, -0.01)
	return best


func _note_clearance() -> void:
	if _dog == null or not _dog.is_visible_in_tree():
		return
	_min_clear = minf(_min_clear, footprint_clearance(_dog.global_position, _dog.rotation.y) if _mode != Mode.GONE else INF)


func _set_mode(m: Mode) -> void:
	_mode = m
	_mode_t = 0.0
	_sniff_t = 0.0


## Who it would trot after: Cian when he is in the yard (not in the house) and away from the door, else the herd-hand
## once he is down in the yard; nobody while Cian sits at the meal / is in at the door.
func _pick_lead() -> Node3D:
	if _player and is_instance_valid(_player):
		var pp := _player.global_position
		# Not after him into the house: it waits at its place by the door.
		if _flat(pp - RATH_C) < YARD_R and _flat(pp - LIE_AT) > 4.0 and not HouseI.is_inside(pp, -0.4):
			return _player
	if _hh and is_instance_valid(_hh) and _hh.visible:
		var hp := _hh.global_position
		if _flat(hp - RATH_C) < YARD_R - 1.5 and _flat(hp - LIE_AT) > 4.0 and bool(_hh.call("is_walking")):
			return _hh
	return null


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
