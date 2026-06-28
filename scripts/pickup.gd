extends Area2D
class_name Pickup
## Objeto recogible: moneda (sprite real por tier), XP/corazón/poción/ítem (gema
## glow tintada). Visual unshaded + halo emisivo aditivo + bob, para que se vean
## en la oscuridad. Se recoge por contacto.

static var _gem: Texture2D
static var _xp_flame_cache := {}    # color → Array de frames (compartido)

# Colores de llamita de XP disponibles (se elige uno al azar por drop). Para sumar variantes:
# {"dir": <subcarpeta>, "prefix": <prefijo de archivo>}.
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
var _z := 0.0          # altura visual del saltito de spawn
var _vz := 0.0         # velocidad vertical del saltito
var _flame_frames: Array = []
var _flame_i := 0
var _flame_t := 0.0
var _hover := false           # mouse sobre el ítem (para info + click derecho)
var _info: Control            # tooltip de info del ítem (en CanvasLayer, screen-space)

const XP_MAGNET_R := 48.0     # rango del imán de XP
const ITEM_HOVER_R := 13.0    # radio de hover del ítem

func _ready() -> void:
	body_entered.connect(_on_body)
	if visual:
		visual.visible = false
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
	_vz = 92.0   # saltito al salir del mob (sube y cae)
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

func _process(delta: float) -> void:
	# Saltito de spawn: sube y cae; al tocar el piso queda quieto (sin flotar).
	if _vz != 0.0 or _z > 0.0:
		_vz -= 560.0 * delta
		_z += _vz * delta
		if _z <= 0.0:
			_z = 0.0
			_vz = 0.0
		_icon.position.y = -_z - 2.0
	if not _flame_frames.is_empty():   # llamita de XP: cicla frames
		_flame_t += delta
		if _flame_t >= 0.07:
			_flame_t = 0.0
			_flame_i = (_flame_i + 1) % _flame_frames.size()
			_icon.texture = _flame_frames[_flame_i]
	if kind == "xp":
		# Imán: cuando el jugador está cerca, la XP se arrima (más rápido cuanto más cerca).
		var pl = GameState.player
		if pl != null and is_instance_valid(pl):
			var d := global_position.distance_to(pl.global_position)
			if d < XP_MAGNET_R:
				var spd: float = lerpf(60.0, 280.0, 1.0 - d / XP_MAGNET_R)
				global_position = global_position.move_toward(pl.global_position, spd * delta)
	elif kind == "item":
		# Hover con el mouse → muestra info; se levanta con click derecho.
		var over := get_global_mouse_position().distance_to(global_position) < ITEM_HOVER_R
		if over and not _hover:
			_hover = true
			_show_info()
		elif not over and _hover:
			_hover = false
			_hide_info()
		if _hover and _info != null:
			_info.position = get_viewport().get_mouse_position() + Vector2(14, -8)

func _on_body(body: Node) -> void:
	if not (body is Player):
		return
	if kind == "item":
		return   # los ítems se levantan con click derecho, no por contacto
	match kind:
		"coin": body.add_coins(value)
		"xp": body.gain_xp(value)
		"heart": body.heal(value)
		"potion": body.potions += 1
	var snd: String = {"coin": "coin", "heart": "heal", "potion": "heal"}.get(kind, "")
	if snd != "":
		Audio.play(snd)
	queue_free()

## Click derecho sobre un ítem en hover → levantarlo.
func _unhandled_input(event: InputEvent) -> void:
	if kind != "item" or not _hover:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pl = GameState.player
		if pl != null and is_instance_valid(pl):
			pl.pick_up_item(item_data)
			Audio.play("equip")
			get_viewport().set_input_as_handled()
			queue_free()

## Tooltip de info (screen-space, sigue al mouse). Nombre + rareza + stats.
func _show_info() -> void:
	if _info != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var rd: Dictionary = Items.rarity_data(item_data.get("rarity", "comun"))
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.05, 0.08, 0.92)
	box.set_border_width_all(1)
	box.border_color = Color(rd.color)
	box.set_corner_radius_all(2)
	box.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", box)
	layer.add_child(panel)
	var lbl := Label.new()
	lbl.text = "%s [%s]\n%s" % [item_data.get("name", "ítem"), rd.name, Items.describe(item_data)]
	UiTheme.apply_item_description(lbl, 20, Color(rd.color))
	panel.add_child(lbl)
	_info = panel

func _hide_info() -> void:
	if _info != null:
		_info.get_parent().queue_free()   # libera el CanvasLayer entero
		_info = null

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
