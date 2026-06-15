extends Area2D
class_name Pickup
## Objeto recogible: moneda (sprite real por tier), XP/corazón/poción/ítem (gema
## glow tintada). Visual unshaded + halo emisivo aditivo + bob, para que se vean
## en la oscuridad. Se recoge por contacto.

static var _gem: Texture2D

var kind := "coin"
var value := 1
var item_data: Dictionary = {}

@onready var visual: Polygon2D = $Visual

var _icon: Sprite2D
var _glow: Sprite2D
var _t := 0.0

func _ready() -> void:
	body_entered.connect(_on_body)
	if visual:
		visual.visible = false
	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/fx/light_radial.tres")
	_glow.z_index = 8
	_glow.material = _mat(CanvasItemMaterial.BLEND_MODE_ADD)
	add_child(_glow)
	_icon = Sprite2D.new()
	_icon.z_index = 9
	_icon.material = _mat(CanvasItemMaterial.BLEND_MODE_MIX)  # unshaded = visible en oscuro
	add_child(_icon)

func setup(pos: Vector2, k: String, v: int, idata: Dictionary = {}) -> void:
	global_position = pos
	kind = k
	value = v
	item_data = idata
	_configure()
	reset_physics_interpolation()

func _configure() -> void:
	var col := Color(1.0, 0.85, 0.3)
	if kind == "coin":
		var tier := 1
		if value >= 25: tier = 4
		elif value >= 12: tier = 3
		elif value >= 5: tier = 2
		_icon.texture = load("res://assets/pickups/coin_t%d.png" % tier)
		_icon.scale = Vector2(0.2, 0.2)   # 80px → ~16
		_icon.modulate = Color.WHITE
	else:
		_icon.texture = _get_gem()
		_icon.scale = Vector2(0.7, 0.7)
		match kind:
			"xp": col = Color(0.45, 1.0, 0.55)
			"heart": col = Color(1.0, 0.32, 0.42)
			"potion": col = Color(0.45, 0.62, 1.0)
			"item": col = Color(Items.rarity_data(item_data.get("rarity", "comun")).color)
		_icon.modulate = col
	_glow.modulate = Color(col.r, col.g, col.b, 0.45)
	_glow.scale = Vector2(0.13, 0.13)

func _process(delta: float) -> void:
	_t += delta
	var bob := sin(_t * 3.0) * 1.5
	_icon.position.y = -bob - 2.0
	_glow.position.y = -bob * 0.5
	_glow.modulate.a = 0.35 + 0.18 * sin(_t * 4.0)

func _on_body(body: Node) -> void:
	if not (body is Player):
		return
	match kind:
		"coin": body.add_coins(value)
		"xp": body.gain_xp(value)
		"heart": body.heal(value)
		"potion": body.potions += 1
		"item": body.pick_up_item(item_data)
	var snd: String = {"coin": "coin", "heart": "heal", "potion": "heal", "item": "equip"}.get(kind, "")
	if snd != "":
		Audio.play(snd)
	queue_free()

# ---------------------------------------------------------------------------
func _mat(blend: int) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = blend
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

## Gema glow: bead redondo con núcleo brillante y borde definido (se tinta por modulate).
static func _get_gem() -> Texture2D:
	if _gem != null:
		return _gem
	var s := 24
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s / 2.0)
			var a := clampf((0.95 - d) / 0.2, 0.0, 1.0)   # sólido adentro, borde suave
			var core := pow(clampf(1.0 - d, 0.0, 1.0), 2.5)
			var b := clampf(0.55 + 0.45 * core, 0.0, 1.0)
			img.set_pixel(x, y, Color(b, b, b, a))
	_gem = ImageTexture.create_from_image(img)
	return _gem
