extends Node2D
class_name Campfire
## Fogata de leña ardiendo: sprite animado (assets/fx/campfire_anim, 13 frames, unshaded) + luz
## cálida con parpadeo sutil + crepitar POSICIONAL (fire_constant, más fuerte al acercarse, se
## pausa de lejos). Va en el PISO. Instanciá campfire.tscn donde quieras una hoguera.

const FRAMES := 13
const FPS := 11.0
const WARM := Color(1.0, 0.62, 0.28)

static var _shared: SpriteFrames

var seed_off := 0.0          # desfasa el parpadeo/ciclo entre fogatas (set antes de add_child)
var _sprite: AnimatedSprite2D
var _light: PointLight2D
var _t := 0.0

func _ready() -> void:
	# Sprite animado (unshaded → auto-iluminado, como el fuego de las antorchas).
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _get_frames()
	_sprite.scale = Vector2(0.6, 0.6)   # los frames son 128px; ajustá a gusto
	_sprite.z_index = 6
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = mat
	add_child(_sprite)
	_sprite.play("burn")
	_sprite.frame = int(seed_off) % FRAMES   # desfasar el ciclo entre fogatas
	# Luz cálida del fuego (parpadeo sutil en _process; el sprite ya da el movimiento de la llama).
	_light = PointLight2D.new()
	_light.texture = load("res://assets/fx/light_pool.tres")
	_light.color = WARM
	_light.energy = 1.8
	_light.texture_scale = 0.5
	_light.shadow_enabled = true
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(_light)
	# Crepitar POSICIONAL (más fuerte al acercarse), mismo sistema que las antorchas.
	Audio.loop_at(self, "res://assets/sfx/fire_constant.mp3", -7.0, 460.0)

func _process(delta: float) -> void:
	_t += delta
	if _light:
		_light.energy = 1.8 + sin(_t * 7.0 + seed_off) * 0.18   # parpadeo sutil

## SpriteFrames compartido (se arma una vez para todas las fogatas).
static func _get_frames() -> SpriteFrames:
	if _shared != null:
		return _shared
	var sf := SpriteFrames.new()
	sf.add_animation("burn")
	sf.set_animation_speed("burn", FPS)
	sf.set_animation_loop("burn", true)
	for i in FRAMES:
		var t := load("res://assets/fx/campfire_anim/frame_%03d.png" % i) as Texture2D
		if t != null:
			sf.add_frame("burn", t)
	_shared = sf
	return sf
