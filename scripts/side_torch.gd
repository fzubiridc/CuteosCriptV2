extends PointLight2D
## Antorcha complementaria para muros laterales. Usa el mismo light pool,
## sombras, bloom y controles de LightCfg que la antorcha frontal.

const FRAMES := 8
const FRAME_PX := 64
const WARM := Color(1.0, 0.60, 0.24)
const SHEET_LEFT := preload("res://assets/fx/torch_side/torch_side_left_anim.png")
const SHEET_RIGHT := preload("res://assets/fx/torch_side/torch_side_right_anim.png")

static var _shared_left: SpriteFrames
static var _shared_right: SpriteFrames

var wall_side: StringName = &"left"
var seed_off := 0.0
var _base_energy := 2.25
var _sprite: AnimatedSprite2D
## Separa el centro físico de la luz de su montaje visual en el muro.
var light_offset := Vector2.ZERO

func _ready() -> void:
	texture = load("res://assets/fx/light_pool.tres")
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_PCF5

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _get_frames(wall_side)
	_sprite.scale = Vector2(0.30, 0.30)
	# La luz está 6 px más abajo que antes, pero el sprite conserva su montaje.
	_sprite.position = Vector2(0, -1) - light_offset
	_sprite.z_index = 6
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_sprite.material = mat
	add_child(_sprite)
	_sprite.play("burn")
	_sprite.frame = int(seed_off) % FRAMES

	_apply_cfg()
	LightCfg.changed.connect(_apply_cfg)

static func _get_frames(side: StringName) -> SpriteFrames:
	if side == &"right" and _shared_right != null:
		return _shared_right
	if side != &"right" and _shared_left != null:
		return _shared_left

	var sf := SpriteFrames.new()
	sf.add_animation("burn")
	sf.set_animation_speed("burn", 10.0)
	sf.set_animation_loop("burn", true)
	var sheet_tex: Texture2D = SHEET_RIGHT if side == &"right" else SHEET_LEFT
	var sheet := sheet_tex.get_image()
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

	if side == &"right":
		_shared_right = sf
	else:
		_shared_left = sf
	return sf

func _apply_cfg() -> void:
	_base_energy = LightCfg.get_v("torch_energy")
	energy = _base_energy
	texture_scale = LightCfg.get_v("torch_radius")
	height = LightCfg.get_v("torch_height")
	shadow_filter_smooth = LightCfg.get_v("shadow_smooth")
	color = Color(1, 1, 1).lerp(WARM, LightCfg.get_v("torch_warmth"))
	if _sprite:
		var g := LightCfg.get_v("torch_glow")
		_sprite.modulate = Color(g, g * 0.72, g * 0.42, 1.0)
