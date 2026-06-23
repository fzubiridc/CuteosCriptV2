extends Node
## TEMPORAL: hace caminar al player en circulo solo (simula input) para sacar
## screenshots con scroll. BORRAR despues.

var _t := 0.0

func _process(dt: float) -> void:
	_t += dt
	_drive("move_right", "move_left", cos(_t * 1.1))
	_drive("move_down", "move_up", sin(_t * 1.1))

func _drive(pos_action: String, neg_action: String, v: float) -> void:
	if v >= 0.0:
		Input.action_press(pos_action, v)
		Input.action_release(neg_action)
	else:
		Input.action_press(neg_action, -v)
		Input.action_release(pos_action)
