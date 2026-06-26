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
## Separa el centro físico de la luz de su montaje visual sobre el muro.
## Dungeon define ambos vía set_mount() antes de add_child() y al tunear en vivo.
var light_offset := Vector2.ZERO   # la luz (root) se mete hacia la sala por este vector
var flame_mount := Vector2(0, -17) # offset visual de la llama sobre la cara del muro

const WARM := Color(1.0, 0.60, 0.24)   # 0xff9a3c, máxima calidez

func _ready() -> void:
	texture = load("res://assets/fx/light_pool.tres")
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_PCF5   # PCF5 suave
	# Sprite animado de la antorcha (unshaded → se ve siempre, como auto-iluminado).
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _get_frames()
	_sprite.scale = Vector2(0.3, 0.3)
	_sprite.position = flame_mount - light_offset
	_sprite.z_index = 6
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = mat
	add_child(_sprite)
	_sprite.play("burn")
	_sprite.frame = int(seed_off) % FRAMES   # desfasar el ciclo entre antorchas
	_apply_cfg()
	LightCfg.changed.connect(_apply_cfg)

## Dungeon setea el montaje (llama sobre la cara, luz metida a la sala). Habilita el tuning en vivo.
func set_mount(flame: Vector2, light: Vector2) -> void:
	flame_mount = flame
	light_offset = light
	if _sprite:
		_sprite.position = flame_mount - light_offset

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
	@warning_ignore("integer_division")
	var cols := sheet.get_width() / FRAME_PX
	for i in FRAMES:
		var fx := (i % cols) * FRAME_PX
		@warning_ignore("integer_division")
		var fy := (i / cols) * FRAME_PX
		var fimg := sheet.get_region(Rect2i(fx, fy, FRAME_PX, FRAME_PX))
		sf.add_frame("burn", ImageTexture.create_from_image(fimg))
	_shared = sf
	return sf

func _apply_cfg() -> void:
	_base_energy = LightCfg.get_v("torch_energy")
	energy = _base_energy   # luz estable (sin parpadeo)
	texture_scale = LightCfg.get_v("torch_radius")
	height = LightCfg.get_v("torch_height")
	shadow_filter_smooth = LightCfg.get_v("shadow_smooth")
	color = Color(1, 1, 1).lerp(WARM, LightCfg.get_v("torch_warmth"))   # calidez tuneable
	# Boost cálido del sprite de la llama (>1 → glowea con el bloom HDR = fuego real).
	if _sprite:
		var g: float = LightCfg.get_v("torch_glow")
		_sprite.modulate = Color(g, g * 0.72, g * 0.42, 1.0)
