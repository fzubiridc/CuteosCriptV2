extends Node2D
## Número de daño / texto flotante estilo RPG. Vive en una CanvasLayer (nivel UI), NO en el
## mundo → NO lo oscurece el CanvasModulate ni las luces de la escena (los números se ven SIEMPRE
## claros). Sigue al punto del mundo (`_anchor`) convirtiéndolo a pantalla cada frame. Anima por
## tween: "pop" de escala, sube con ease-out, dispersión horizontal, hold opaco y fade. El CRÍTICO
## es más grande, dorado y con overshoot.

const RISE := 56.0                          # px que sube en su vida (en pantalla)
const LIFE := 0.85                          # s totales
const FADE := 0.3                           # s de fade al final
const SCATTER_X := 25.0                     # dispersión horizontal random
const CRIT_GOLD := Color(1.0, 0.82, 0.25)   # oro del crítico (si no se pasa color propio)

@onready var label: Label = $Label

var _anchor := Vector2.ZERO   # punto del MUNDO al que sigue (posición del mob)
var _rise := 0.0              # cuánto subió (animado por tween)
var _scatter_x := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

## pos = MUNDO. is_crit → más grande, dorado (si color queda en blanco) y pop con overshoot.
func setup(pos: Vector2, text: String, color: Color = Color.WHITE, is_crit := false) -> void:
	_anchor = pos
	_scatter_x = randf_range(-SCATTER_X, SCATTER_X)
	label.text = text
	# Outline negro → despega el número del fondo (legibilidad).
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	if is_crit:
		label.modulate = CRIT_GOLD if color == Color.WHITE else color
		label.add_theme_font_size_override("font_size", 12)   # ~1.5× del 8 base
		rotation = deg_to_rad(randf_range(-6.0, 6.0))
	else:
		label.modulate = color
		rotation = deg_to_rad(randf_range(-3.0, 3.0))
	_update_screen_pos()
	_animate(is_crit)

## Posición en PANTALLA del punto del mundo (la cámara la da get_canvas_transform), + la subida.
func _update_screen_pos() -> void:
	var t := get_viewport().get_canvas_transform()
	position = t * _anchor + Vector2(_scatter_x, -_rise)

func _process(_dt: float) -> void:
	_update_screen_pos()

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
	# Subida con ease-out (el _process la aplica sobre la posición de pantalla).
	var rise := create_tween()
	rise.tween_property(self, "_rise", RISE, LIFE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Hold opaco y fade en el último tramo.
	var fade := create_tween()
	fade.tween_interval(LIFE - FADE)
	fade.tween_property(self, "modulate:a", 0.0, FADE)
	fade.tween_callback(queue_free)
