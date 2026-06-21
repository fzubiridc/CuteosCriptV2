extends AnimatedSprite2D
class_name SkyDragon
## Dragón lejano que vuela por el cielo del fondo (detrás de la torre, cerca de
## la luna) y de tanto en tanto escupe fuego. Va en el CanvasLayer del cielo, así
## que se ve "a lo lejos" por afuera de la torre y por las ventanas.
## Flight = vuelo (loop). Special = vuelo escupiendo fuego (one-shot).

const FLIGHT := "res://assets/bg/dragon/Flight.png"
const SPECIAL := "res://assets/bg/dragon/Special.png"
const FRAME := 256
const DRAGON_SCALE := 0.20     # lejos = chico
var tint := Color(0.30, 0.40, 0.62)     # silueta; main lo setea según noche/eclipse
const DRIFT := 50.0            # px/s (vuela hacia la derecha)
const AMP_Y := 40.0           # amplitud del bamboleo vertical (curvas)
const FIRE_EVERY := 7.0        # s entre llamaradas
const FIRE_OFFSET := Vector2(0, 80)   # baja el cuerpo en "fire" para que NO salte (tuneá el 80)

var _t := 0.0
var _time := 0.0
var _base_y := 120.0
var _xmin := 0.0
var _xmax := 1280.0
var _prev_pos := Vector2.ZERO

func _ready() -> void:
	scale = Vector2(DRAGON_SCALE, DRAGON_SCALE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	modulate = tint
	z_index = 1
	sprite_frames = _build_frames()
	var vp := get_viewport().get_visible_rect().size
	_xmin = -FRAME * DRAGON_SCALE
	_xmax = vp.x + FRAME * DRAGON_SCALE
	_base_y = vp.y * 0.20
	position = Vector2(vp.x * 0.30, _base_y)       # cerca de la luna (arriba-izq)
	_prev_pos = position
	play("fly")
	animation_finished.connect(_on_done)

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	_add(sf, "fly", load(FLIGHT), 12, 14.0, true)
	_add(sf, "fire", load(SPECIAL), 12, 12.0, false)
	if sf.has_animation("default"):
		sf.remove_animation("default")
	return sf

func _add(sf: SpriteFrames, anim: String, tex: Texture2D, count: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * FRAME, 0, FRAME, FRAME)
		sf.add_frame(anim, at)

func _on_done() -> void:
	if animation == "fire":
		offset = Vector2.ZERO
		play("fly")

func _process(dt: float) -> void:
	_time += dt
	position.x += DRIFT * dt
	# trayectoria ondulada: suma de 2 senos desfasados → curvas no perfectas
	position.y = _base_y + sin(_time * 0.6) * AMP_Y + sin(_time * 1.7 + 1.2) * (AMP_Y * 0.4)
	var vel := position - _prev_pos          # apuntar hacia donde va
	if vel.length() > 0.001:
		rotation = vel.angle()
	if position.x > _xmax:
		position.x = _xmin
	_prev_pos = position
	_t += dt
	if animation == "fly" and _t >= FIRE_EVERY:
		_t = 0.0
		offset = FIRE_OFFSET
		play("fire")
