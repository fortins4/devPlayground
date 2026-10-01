extends Node
## Stamina-based directional combat stub (spears, axes, shield breaks).

signal attack_performed(attacker: Node, kind: StringName)

@export var max_stamina: float = 100.0
var stamina: float = 100.0


func try_attack(kind: StringName = &"light") -> bool:
	var cost := 10.0 if kind == &"light" else 25.0
	if stamina < cost:
		return false
	stamina -= cost
	attack_performed.emit(get_parent(), kind)
	return true
