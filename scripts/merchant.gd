extends Area2D
class_name Merchant
## Mercader (referencia Pixi): aparece tras matar al jefe de un piso, junto a la
## salida. El jugador se acerca y aprieta [E] → abre la tienda. Sprite placeholder
## (cultista) + glow violeta; se re-skinea con imagen propia más adelante.

var stock: Dictionary = {}
var _near := false
var _prompt: Label

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # detecta al jugador (capa 2)
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 18.0
	shape.shape = c
	add_child(shape)

	var spr := AnimatedSprite2D.new()
	var sf := _get_frames()
	spr.sprite_frames = sf
	var fh := 63.0
	var t0 = sf.get_frame_texture("idle", 0)
	if t0:
		fh = float(t0.get_height())
	var s := (9.75 * 2.6) / fh   # mitad + 30%
	spr.scale = Vector2(s, s)
	spr.play("idle")
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	spr.material = mat
	add_child(spr)

	var lt := PointLight2D.new()
	lt.texture = load("res://assets/fx/light_pool.tres")
	lt.color = Color(0.6, 0.42, 1.0)
	lt.energy = 1.5
	lt.texture_scale = 0.5
	add_child(lt)

	_prompt = Label.new()
	_prompt.text = "[E] Mercader"
	_prompt.position = Vector2(-26, -34)
	_prompt.add_theme_color_override("font_color", Color("c7b8e8"))
	_prompt.add_theme_font_size_override("font_size", 11)
	var pm := CanvasItemMaterial.new()
	pm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_prompt.material = pm
	_prompt.visible = false
	_prompt.z_index = 40
	add_child(_prompt)

	body_entered.connect(func(b: Node) -> void:
		if b is Player:
			_near = true
			_prompt.visible = true)
	body_exited.connect(func(b: Node) -> void:
		if b is Player:
			_near = false
			_prompt.visible = false)

func _process(_delta: float) -> void:
	if _near and Input.is_action_just_pressed("interact"):
		var hud := get_tree().current_scene.get_node_or_null("HUD")
		if hud and hud.has_method("open_shop"):
			hud.open_shop(self)

## SpriteFrames del mercader (idle, 4 frames) desde el sheet. Fallback a carga cruda.
static var _frames: SpriteFrames

static func _get_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 5.0)
	sf.set_animation_loop("idle", true)
	for i in 4:   # 4 frames sueltos exportados (merchant_0001..0004, 64×64)
		var path := "res://assets/mobs/merchant_%04d.png" % (i + 1)
		var t := load(path) as Texture2D
		if t == null:
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null:
				t = ImageTexture.create_from_image(img)
		if t != null:
			sf.add_frame("idle", t)
	_frames = sf
	return sf
