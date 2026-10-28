extends Node
## Minimal-UI pass (2026-10-28): grounded play shows no floating place / object / name captions
## and no always-on HUD strips. What stays: close-range E prompts on things you can use, spoken
## lines (Bark), the cattle's lowing, and transient first-use tips / dialogue in the opening HUD
## flash line (that HUD quiets its own objective / controls / banner / counter).
##
## One node per playable scene (main F5, opening F4). Every Label3D under the scene that is not on
## the keep list is held invisible, every frame, after every other script has run (late
## process_priority), so a system that re-shows its caption (awareness meters, raid status, cow
## "drove" tags, damage numbers) never reaches a drawn frame. The systems keep their text, state and
## logic; only the drawing goes. Whole HUD layers named in QUIET_LAYERS are hidden the same way.

## Proximity / speech labels that stay (each owner script already shows them only when in range
## or while someone speaks).
const KEEP_LABELS := [
	&"Bark",          # someone speaking (Máire, villagers, the dogs)
	&"Lowing",        # the bogged cow's lowing
	&"PromptLabel",   # horse "E Mount", muster point, cattle-raid start (in the start zone)
	&"Prompt",        # corpse "Hold E — Drag body" (in range / while dragging)
	&"HidePrompt",    # bog zone "Release E — Hide body in bog" (while dragging into it)
]
## Always-on HUD layers that read as chrome: the HP / guard / controls wall, the band tally, the
## raid line + heat alerts, the heat readout.
const QUIET_LAYERS := [&"CombatHUD", &"BandHUD", &"CattleRaidHUD", &"HeatHUDLayer"]

@export var enabled: bool = true

var _labels: Array[Label3D] = []
var _layers: Array[CanvasLayer] = []


func _ready() -> void:
	add_to_group("minimal_ui")
	process_priority = 10000
	process_physics_priority = 10000
	var root := _scene_root()
	for l in root.find_children("*", "Label3D", true, false):
		_consider(l)
	for c in root.find_children("*", "CanvasLayer", true, false):
		_consider(c)
	get_tree().node_added.connect(_on_node_added)
	_apply()


func _scene_root() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_parent()


func _on_node_added(n: Node) -> void:
	if n is Label3D or n is CanvasLayer:
		_consider(n)


func _consider(n: Node) -> void:
	if n is Label3D:
		if not is_kept(n as Label3D) and not _labels.has(n):
			_labels.append(n as Label3D)
	elif n is CanvasLayer:
		if QUIET_LAYERS.has(StringName(n.name)) and not _layers.has(n):
			_layers.append(n as CanvasLayer)


static func is_kept(lb: Label3D) -> bool:
	return KEEP_LABELS.has(StringName(lb.name))


func _process(_delta: float) -> void:
	_apply()


func _physics_process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if not enabled:
		return
	for i in range(_labels.size() - 1, -1, -1):
		var l := _labels[i]
		if not is_instance_valid(l):
			_labels.remove_at(i)
		elif l.visible:
			l.visible = false
	for i in range(_layers.size() - 1, -1, -1):
		var c := _layers[i]
		if not is_instance_valid(c):
			_layers.remove_at(i)
		elif c.visible:
			c.visible = false


## Smoke: every Label3D in the scene a player could read right now, minus the kept prompts/speech.
func visible_captions() -> Array:
	var out: Array = []
	for l in _scene_root().find_children("*", "Label3D", true, false):
		var lb := l as Label3D
		if lb.is_visible_in_tree() and lb.text.strip_edges() != "" and not is_kept(lb):
			out.append("%s: %s" % [lb.name, lb.text.replace("\n", " / ")])
	return out
