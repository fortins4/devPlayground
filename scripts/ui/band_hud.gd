extends CanvasLayer
## Lightweight band count HUD for the ringfort muster slice.


func _ready() -> void:
	_refresh()
	var tree := get_tree()
	if tree:
		# Poll gently — CattleEconomy is owned by ringfort, not an autoload.
		var timer := Timer.new()
		timer.wait_time = 0.35
		timer.timeout.connect(_refresh)
		add_child(timer)
		timer.start()


func _refresh() -> void:
	var label := $Root/BandLabel as Label
	if label == null:
		return
	var ringfort := get_tree().get_first_node_in_group("ringfort") if get_tree() else null
	if ringfort == null:
		label.text = "Band — (walk west to ringfort)"
		return
	var cattle = ringfort.get_node_or_null("CattleEconomy")
	var runtime: Node = ringfort.get_node_or_null("BandRuntime")
	var size: int = 0
	var herd: int = 0
	var conf: float = 0.0
	if cattle:
		size = int(cattle.get_band_size())
		herd = int(cattle.get_herd_size())
		conf = float(cattle.get_skirmish_confidence())
	var mode: String = "FOLLOW"
	if runtime and runtime.has_method("is_following") and not runtime.is_following():
		mode = "HOLD"
	label.text = "Band %d/3 · %s · cattle %d · skirmish %.0f%%" % [
		size, mode, herd, conf * 100.0
	]
