extends Area2D
class_name Chest
## Cofre (ref pixi): sprite animado de apertura (chest_common/gold, 4 frames de 32px).
## El jugador se acerca y aprieta [E] → abre, suelta loot + sfx 'chest'. Queda abierto.

static var _cache := {}

var gold := false
var _opened := false
var _near := false
var _spr: AnimatedSprite2D
var _prompt: Label

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # detecta al jugador (capa 2)
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	shape.shape = c
	add_child(shape)

	_spr = AnimatedSprite2D.new()
	_spr.sprite_frames = _get_frames(gold)
	_spr.animation = "chest"
	_spr.frame = 0                  # cerrado
	# iso: cofre de 64px → ~0.8; top-down: 32px → 0.55
	var s := 0.8 if Dungeon.ISO else 0.55
	_spr.scale = Vector2(s, s)
	if Dungeon.ISO:
		_spr.position = Vector2(0, -10)   # apoyar sobre la celda (centro del sprite arriba del piso)
	add_child(_spr)

	_prompt = Label.new()
	_prompt.text = "[E] Abrir"
	_prompt.position = Vector2(-22, -28)
	_prompt.add_theme_color_override("font_color", Color("ffe08a"))
	_prompt.add_theme_font_size_override("font_size", 11)
	var pm := CanvasItemMaterial.new()
	pm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_prompt.material = pm
	_prompt.visible = false
	_prompt.z_index = 40
	add_child(_prompt)

	body_entered.connect(func(b: Node) -> void:
		if b is Player and not _opened:
			_near = true
			_prompt.visible = true)
	body_exited.connect(func(b: Node) -> void:
		if b is Player:
			_near = false
			_prompt.visible = false)

func _process(_delta: float) -> void:
	if _near and not _opened and Input.is_action_just_pressed("interact"):
		_open()

func _open() -> void:
	_opened = true
	_near = false
	_prompt.visible = false
	Audio.play("chest")
	_spr.play("chest")   # 0 → 3 (no loop): animación de apertura
	var sc := get_tree().current_scene
	var depth := int(GameState.run.get("depth", 1))
	# Loot garantizado: monedas + un ítem (el dorado da más oro + ítem raro mínimo).
	var piles := Rng.range_i(3, 5) if gold else Rng.range_i(2, 3)
	for i in piles:
		GameState._drop(sc, global_position + GameState._roff(14.0), "coin", Rng.range_i(3, 7) if gold else Rng.range_i(2, 4))
	var item: Dictionary = Items.make_item_min_rare(depth) if gold else Items.make_item(depth)
	GameState._drop_item(sc, global_position + GameState._roff(10.0), item)

## SpriteFrames del cofre (común/dorado), compartido. Fallback a carga cruda.
const ISO_CHEST_FRAMES := 17   # chest_iso_sheet.png = 17 frames de 64px (cerrado→abierto)

static func _get_frames(g: bool) -> SpriteFrames:
	var iso: bool = Dungeon.ISO
	var key := ("iso_" if iso else "") + ("gold" if g else "common")
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	sf.add_animation("chest")
	sf.set_animation_loop("chest", false)
	sf.set_animation_speed("chest", 14.0)
	if iso:
		# Cofre iso animado (un solo sheet por ahora; común y dorado comparten).
		var sheet := _load_sheet("res://assets/iso/chests/chest_iso_sheet.png")
		if sheet != null:
			@warning_ignore("integer_division")
			var fw := sheet.get_width() / ISO_CHEST_FRAMES
			var fh := sheet.get_height()
			for i in ISO_CHEST_FRAMES:
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(i * fw, 0, fw, fh)
				sf.add_frame("chest", at)
	else:
		var sheet := _load_sheet("res://assets/props/chest_%s.png" % key)
		if sheet != null:
			@warning_ignore("integer_division")
			var fw := sheet.get_width() / 4
			var fh := sheet.get_height()
			for i in 4:
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(i * fw, 0, fw, fh)
				sf.add_frame("chest", at)
	_cache[key] = sf
	return sf

static func _load_sheet(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	return tex
