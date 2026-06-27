extends Area2D
class_name Door   # class_name para preload/tipado estático desde main.gd
## Puerta = portal entre salas (USE_DOORS). Se ENTRA con CLICK DERECHO con el mouse sobre ella y
## estando PEGADO (hover → prompt + beacon). YA NO teleporta al pararse. El VISUAL es el tile de
## puerta en la cara del muro (dungeon._door_faces); este nodo es la zona de hover/click + beacon +
## prompt. La detección del mouse es MANUAL (rect local), y el PROMPT vive en un CanvasLayer de UI
## (no lo afecta la luz del mundo ni el zoom de cámara, y se dibuja sobre todo).

static var _cd_until_ms := 0

# Zona de hover/click en coords LOCALES (cubre el tile de puerta, que sobresale hacia arriba sobre la
# celda del piso). Generosa a propósito; ajustable si no coincide con el tile según la cara.
const HIT_RECT := Rect2(-55, -116, 110, 132)
const NEAR_DIST := 100.0   # hay que estar PEGADO (≤ esto, px) a la puerta para que aparezca y entre

var target_pos := Vector2.ZERO
var _hover := false
var _ui: CanvasLayer
var _prompt: Label
var _beacon: PointLight2D

func _ready() -> void:
	add_to_group("door")        # para que main._build_floor lo limpie al regenerar el piso
	collision_layer = 0
	collision_mask = 0
	# Beacon de luz: la puerta brilla para ubicarla en la oscuridad; sube al pasar el mouse (hover).
	_beacon = PointLight2D.new()
	_beacon.texture = load("res://assets/fx/light_pool.tres")
	_beacon.color = Color(1.0, 0.74, 0.42)
	_beacon.energy = 1.2
	_beacon.texture_scale = 0.4
	add_child(_beacon)
	# Prompt en una CAPA DE UI (CanvasLayer) → NO lo afecta la luz del mundo ni el zoom de cámara, y
	# se dibuja sobre todo. font_size = tamaño REAL en pantalla (sin zoom). Se posiciona cada frame.
	_ui = CanvasLayer.new()
	_ui.layer = 100
	add_child(_ui)
	_prompt = Label.new()
	_prompt.text = "Entrar (clic der.)"
	_prompt.add_theme_color_override("font_color", Color(1, 1, 1))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.visible = false
	_ui.add_child(_prompt)

## ¿El jugador está PEGADO a la puerta? (gate para mostrar el prompt y para entrar).
func _player_near() -> bool:
	var pl := GameState.player as Node2D
	return pl != null and pl.global_position.distance_to(global_position) <= NEAR_DIST

## Hover MANUAL (jugador pegado + mouse sobre el rect). Al haber hover, proyecta la puerta a coords
## de PANTALLA y centra el prompt encima (la capa de UI no sigue la cámara, hay que ubicarlo a mano).
func _process(_dt: float) -> void:
	var hov := _player_near() and HIT_RECT.has_point(to_local(get_global_mouse_position()))
	if hov:
		var sp: Vector2 = get_viewport().get_canvas_transform() * (global_position + Vector2(0, -70))
		_prompt.position = sp + Vector2(-_prompt.size.x * 0.5, -8)
	if hov == _hover:
		return
	_hover = hov
	_prompt.visible = hov
	_beacon.energy = 2.4 if hov else 1.2

## Click DERECHO con el mouse sobre la puerta (y pegado) → entrar; consume el evento.
func _unhandled_input(event: InputEvent) -> void:
	if not _hover:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_enter()
		get_viewport().set_input_as_handled()

func _enter() -> void:
	if Time.get_ticks_msec() < _cd_until_ms or not _player_near():
		return
	_cd_until_ms = Time.get_ticks_msec() + 700   # anti doble-disparo (y no reentrar a la de vuelta)
	var pl := GameState.player as Node2D
	if pl == null:
		return
	pl.global_position = target_pos
	pl.reset_physics_interpolation()
