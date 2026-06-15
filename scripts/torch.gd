extends PointLight2D
## Antorcha de pared: luz cálida con parpadeo de 2 frecuencias (flicker estilo
## Pixi) + sprite de antorcha ANIMADO (torch_anim.png, 8 frames). Lee energía/
## radio/altura de LightCfg → se autotunea en vivo desde el panel (tecla L).

const FRAMES := 8
const FRAME_PX := 64

static var _shared: SpriteFrames

var seed_off := 0.0
var _base_energy := 2.25
var _sprite: AnimatedSprite2D

func _ready() -> void:
	texture = load("res://assets/fx/light_pool.tres")
	color = Color(1.0, 0.60, 0.24)   # 0xff9a3c cálida
	shadow_enabled = true
	shadow_filter = 1                # PCF5 suave
	# Sprite animado de la antorcha (unshaded → se ve siempre, como auto-iluminado).
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _get_frames()
	_sprite.scale = Vector2(0.3, 0.3)
	_sprite.position = Vector2(0, -6)
	_sprite.z_index = 6
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = mat
	add_child(_sprite)
	_sprite.play("burn")
	_sprite.frame = int(seed_off) % FRAMES   # desfasar el ciclo entre antorchas
	_apply_cfg()
	LightCfg.changed.connect(_apply_cfg)

## SpriteFrames compartido (se arma una vez para todas las antorchas).
static func _get_frames() -> SpriteFrames:
	if _shared != null:
		return _shared
	var sf := SpriteFrames.new()
	sf.add_animation("burn")
	sf.set_animation_speed("burn", 10.0)
	sf.set_animation_loop("burn", true)
	var sheet_tex := load("res://assets/fx/torch_anim.png") as Texture2D
	var sheet: Image = sheet_tex.get_image()
	if sheet.is_compressed():
		sheet.decompress()
	if sheet.get_format() != Image.FORMAT_RGBA8:
		sheet.convert(Image.FORMAT_RGBA8)
	var cols := sheet.get_width() / FRAME_PX
	for i in FRAMES:
		var fx := (i % cols) * FRAME_PX
		var fy := (i / cols) * FRAME_PX
		var fimg := sheet.get_region(Rect2i(fx, fy, FRAME_PX, FRAME_PX))
		sf.add_frame("burn", ImageTexture.create_from_image(fimg))
	_shared = sf
	return sf

func _apply_cfg() -> void:
	_base_energy = LightCfg.get_v("torch_energy")
	texture_scale = LightCfg.get_v("torch_radius")
	height = LightCfg.get_v("torch_height")
	shadow_filter_smooth = LightCfg.get_v("shadow_smooth")

func _process(_delta: float) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	var flick := 0.82 + sin(t * 7.0 + seed_off) * 0.12 + sin(t * 17.0 + seed_off * 1.7) * 0.05
	energy = _base_energy * flick
