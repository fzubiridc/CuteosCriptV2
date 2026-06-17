extends Area2D
class_name Pickup
## Objeto recogible: moneda (sprite real por tier), XP/corazón/poción/ítem (gema
## glow tintada). Visual unshaded + halo emisivo aditivo + bob, para que se vean
## en la oscuridad. Se recoge por contacto.

static var _gem: Texture2D
static var _xp_flame_cache := {}    # color → Array de frames (compartido)

# Colores de llamita de XP disponibles (se elige uno al azar por drop). Sumar acá
# "red"/"blue" cuando estén: {"dir": <subcarpeta>, "prefix": <prefijo de archivo>}.
const XP_FLAMES := {
	"green":  {"dir": "green",  "prefix": "llamita_32_"},
	"yellow": {"dir": "yellow", "prefix": "llamita_amarilla_32_"},
	"red":    {"dir": "red",    "prefix": "llamita_roja_32_"},
}

var kind := "coin"
var value := 1
var item_data: Dictionary = {}

@onready var visual: Polygon2D = $Visual

var _icon: Sprite2D
var _glow: Sprite2D
var _t := 0.0
var _flame_frames: Array = []
var _flame_i := 0
var _flame_t := 0.0

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
	match kind:
		"coin":
			var tier := 1
			if value >= 25: tier = 4
			elif value >= 12: tier = 3
			elif value >= 5: tier = 2
			_icon.texture = load("res://assets/pickups/coin_t%d.png" % tier)
			_icon.scale = Vector2(0.2, 0.2)   # 80px → ~16
			_icon.modulate = Color.WHITE
		"heart":   # poción ROJA real (vida)
			_icon.texture = load("res://assets/pickups/heart.png")
			_icon.scale = Vector2(1.1, 1.1)
			_icon.modulate = Color(1.15, 1.05, 1.0)   # leve realce para que no quede opaca
			col = Color(1.0, 0.32, 0.30)
		"potion":  # poción AZUL real
			_icon.texture = load("res://assets/pickups/potion.png")
			_icon.scale = Vector2(1.1, 1.1)
			_icon.modulate = Color(1.0, 1.05, 1.15)
			col = Color(0.4, 0.6, 1.0)
		"xp":
			col = Color(0.45, 1.0, 0.55)
			var colors: Array = XP_FLAMES.keys()
			var c: String = colors[Rng.range_i(0, colors.size() - 1)]   # color al azar
			_flame_frames = _get_xp_flames(c)
			if not _flame_frames.is_empty():
				_icon.texture = _flame_frames[0]   # llamita animada (color random)
				_icon.scale = Vector2(0.28, 0.28)   # bien chica
				_icon.modulate = Color.WHITE        # color real de la llama
			else:
				_icon.texture = _get_gem()
				_icon.scale = Vector2(0.7, 0.7)
				_icon.modulate = col
		_:        # ítem dropeado
			col = Color(Items.rarity_data(item_data.get("rarity", "comun")).color)
			if kind == "item" and String(item_data.get("slot", "")) == "arma":
				# Arma: su sprite REAL (staff del tier de material), acostado en el piso.
				_icon.texture = _staff_tex_for(item_data)
				_icon.scale = Vector2(0.5, 0.5)
				_icon.rotation = deg_to_rad(40)
				_icon.modulate = Color.WHITE
			else:
				# Armadura/accesorio: gema tintada por rareza (no hay sprite propio).
				_icon.texture = _get_gem()
				_icon.scale = Vector2(0.7, 0.7)
				_icon.modulate = col
	_glow.modulate = Color(col.r, col.g, col.b, 0.45)
	_glow.scale = Vector2(0.13, 0.13)
	if kind == "heart" or kind == "potion":   # frasco oscuro → más glow para que lea
		_glow.modulate.a = 0.6
		_glow.scale = Vector2(0.17, 0.17)
	elif kind == "xp":                          # llama chica → halo chico
		_glow.scale = Vector2(0.07, 0.07)

func _process(delta: float) -> void:
	_t += delta
	var bob := sin(_t * 3.0) * 1.5
	_icon.position.y = -bob - 2.0
	_glow.position.y = -bob * 0.5
	_glow.modulate.a = 0.35 + 0.18 * sin(_t * 4.0)
	if not _flame_frames.is_empty():   # llamita de XP: cicla frames
		_flame_t += delta
		if _flame_t >= 0.07:
			_flame_t = 0.0
			_flame_i = (_flame_i + 1) % _flame_frames.size()
			_icon.texture = _flame_frames[_flame_i]

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
func _mat(blend: CanvasItemMaterial.BlendMode) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = blend
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

## Frames de la llamita de XP de un color (cacheados). Fallback a carga cruda si el
## editor todavía no importó los PNG (copiados en caliente).
static func _get_xp_flames(color: String) -> Array:
	if _xp_flame_cache.has(color):
		return _xp_flame_cache[color]
	var frames: Array = []
	var cfg: Dictionary = XP_FLAMES.get(color, {})
	if not cfg.is_empty():
		for i in 13:
			var p: String = "res://assets/pickups/xp/%s/%s%02d.png" % [cfg.dir, cfg.prefix, i + 1]
			var t := load(p) as Texture2D
			if t == null:
				var img := Image.load_from_file(ProjectSettings.globalize_path(p))
				if img != null:
					t = ImageTexture.create_from_image(img)
			if t != null:
				frames.append(t)
	_xp_flame_cache[color] = frames
	return frames

## Staff (arma) según el tier de material del ítem — mismo criterio que el player.
func _staff_tex_for(idata: Dictionary) -> Texture2D:
	var mat_id: String = idata.get("material", "madera")
	var idx := 0
	for i in Data.MATERIALS.size():
		if Data.MATERIALS[i].id == mat_id:
			idx = i
			break
	idx = clampi(idx, 0, 8)
	return load("res://assets/hero/staffs/staff%d.png" % (idx + 1))

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
