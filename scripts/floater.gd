extends Node2D
## Número de daño flotante. Sube y se desvanece. Se mueve en _process
## (no física) → suave sin depender de la interpolación de física.

@export var rise_speed := 22.0
var life := 0.8
var max_life := 0.8

@onready var label: Label = $Label

func _ready() -> void:
	# Se anima en _process; con la interpolación de física activa parpadearía
	# desde el origen del mundo (0,0) al aparecer. La apagamos para este nodo.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func setup(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	global_position = pos
	label.text = text
	label.modulate = color

func _process(delta: float) -> void:
	position.y -= rise_speed * delta
	life -= delta
	modulate.a = clampf(life / max_life, 0.0, 1.0)
	if life <= 0.0:
		queue_free()
