extends Node2D
## Número de daño flotante estilo RPG: "pop" de escala al aparecer, sube con ease-out,
## dispersión horizontal random (anti-apilado), hold opaco y fade-out al final. El CRÍTICO
## es más grande, dorado y con overshoot. Todo por tweens (no depende de la física).

const RISE := 56.0                          # px que sube en su vida
const LIFE := 0.85                          # s totales
const FADE := 0.3                           # s de fade al final (antes: hold opaco)
const SCATTER_X := 25.0                     # dispersión horizontal random
const CRIT_GOLD := Color(1.0, 0.82, 0.25)   # oro del crítico (si no se pasa color propio)

@onready var label: Label = $Label

func _ready() -> void:
	# Se anima por tween en coords locales; con interpolación de física parpadearía desde (0,0).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## pos = mundo. is_crit → más grande, dorado (si color queda en blanco) y pop con overshoot.
func setup(pos: Vector2, text: String, color: Color = Color.WHITE, is_crit := false) -> void:
	global_position = pos + Vector2(randf_range(-SCATTER_X, SCATTER_X), 0.0)
	label.text = text
	# Outline negro → despega el número del fondo oscuro/movido (legibilidad).
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	if is_crit:
		label.modulate = CRIT_GOLD if color == Color.WHITE else color
		label.add_theme_font_size_override("font_size", 12)   # ~1.5× del 8 base
		rotation = deg_to_rad(randf_range(-6.0, 6.0))
	else:
		label.modulate = color
		rotation = deg_to_rad(randf_range(-3.0, 3.0))
	_animate(is_crit)

func _animate(is_crit: bool) -> void:
	# Pop de escala: normal 0.6→1.0; crit 0→1.3→1.0 con overshoot (TRANS_BACK).
	var pop := create_tween()
	if is_crit:
		scale = Vector2.ZERO
		pop.tween_property(self, "scale", Vector2(1.3, 1.3), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "scale", Vector2.ONE, 0.10).set_ease(Tween.EASE_OUT)
	else:
		scale = Vector2(0.6, 0.6)
		pop.tween_property(self, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	# Subida con ease-out (impulso fuerte y desacelera).
	var rise := create_tween()
	rise.tween_property(self, "position:y", position.y - RISE, LIFE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Hold opaco y fade en el último tramo.
	var fade := create_tween()
	fade.tween_interval(LIFE - FADE)
	fade.tween_property(self, "modulate:a", 0.0, FADE)
	fade.tween_callback(queue_free)
