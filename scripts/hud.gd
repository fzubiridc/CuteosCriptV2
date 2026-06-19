extends CanvasLayer
## HUD: barras de vida/maná/XP, stats, barra de jefe, panel de mejora,
## inventario, pausa y pantalla de muerte.

const BAR_W := 220.0

@onready var xp_fill: ColorRect = $XPFill
@onready var stats: Label = $StatsLabel
@onready var boss_ui: Control = $BossUI
@onready var boss_bar: ProgressBar = $BossUI/BossBar
@onready var boss_name: Label = $BossUI/BossName
@onready var up_panel: Control = $UpgradePanel
@onready var up_title: Label = $UpgradePanel/Title
@onready var up_btns: Array = [$UpgradePanel/Up1, $UpgradePanel/Up2, $UpgradePanel/Up3]
@onready var inv_panel: Control = $InventoryPanel
@onready var inv_equip: Label = $InventoryPanel/EquipLabel
@onready var inv_bag: VBoxContainer = $InventoryPanel/BagList
@onready var pause_panel: Control = $PausePanel
@onready var death_panel: Control = $DeathPanel
@onready var death_sub: Label = $DeathPanel/DSub
@onready var death_title: Label = $DeathPanel/DTitle
@onready var life_preview_fill: TextureRect = $LifeManaPreview/LifeFill
@onready var mana_preview_fill: TextureRect = $LifeManaPreview/ManaFill
@onready var life_preview_value: Label = $LifeManaPreview/LifeValue
@onready var mana_preview_value: Label = $LifeManaPreview/ManaValue

var _choices: Array = []
var _shop_panel: Control
var _shop_merchant = null
var _shop_just_opened := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	boss_ui.visible = false
	up_panel.visible = false
	inv_panel.visible = false
	pause_panel.visible = false
	death_panel.visible = false
	GameState.boss_spawned.connect(_on_boss_spawn)
	GameState.boss_hp_changed.connect(_on_boss_hp)
	GameState.boss_died.connect(_on_boss_died)
	GameState.level_up.connect(_on_level_up)
	GameState.player_died.connect(_on_death)
	GameState.mode_changed.connect(_on_mode)
	for i in 3:
		up_btns[i].pressed.connect(_pick.bind(i))
	$PausePanel/BtnResume.pressed.connect(_toggle_pause)
	$PausePanel/BtnRestartP.pressed.connect(_restart)
	$DeathPanel/BtnRestartD.pressed.connect(_restart)
	_layout_responsive()
	_build_inventory_hd()

# ---------------- Inventario HD (kit assets_hd, según el mockup) ----------------
const INV_DESIGN := Vector2(1580, 1040)   # lienzo de diseño (mago izq + bolsa der)
const BAG_COLS := 5
const BAG_ROWS := 5
const INV_BAG_CAP := BAG_COLS * BAG_ROWS  # 25 casillas (5 × 5, grilla cuadrada)
const BAG_CELL := 112                      # lado de cada casilla de la bolsa
const BAG_GAP := 12
const EQUIP_SLOT := 122                     # slots de equipo ≥ celdas de la bolsa
const HD := "res://assets/ui_hd/"

var _bag_grid: GridContainer
var _bag_count: Label
var _doll_left: VBoxContainer
var _doll_right: VBoxContainer

# Animación idle del mago + plataforma rúnica animada en el inventario.
var _hero_tex: TextureRect
var _hero_frames: Array = []
var _hero_i := 0
var _hero_t := 0.0
var _plat_tex: TextureRect
var _plat_frames: Array = []
var _plat_i := 0
var _plat_t := 0.0

## Construye una sola vez el inventario HD por código dentro de InventoryPanel,
## ocultando el layout viejo. _populate_inventory llena la grilla y el paper-doll.
func _build_inventory_hd() -> void:
	inv_panel.theme = UiTheme.get_theme()
	if inv_panel.has_node("HD"):
		return
	for n in ["BG", "Title", "EquipLabel", "BagTitle", "BagList", "Hint", "Frame"]:
		var old := inv_panel.get_node_or_null(n)
		if old:
			(old as CanvasItem).visible = false

	var hd := Control.new()
	hd.name = "HD"
	hd.set_anchors_preset(Control.PRESET_FULL_RECT)
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_panel.add_child(hd)

	# Fondo: oscurecido (bloquea clicks) + textura de madera sutil.
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.015, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	hd.add_child(dim)
	var wood := TextureRect.new()
	wood.texture = load(HD + "wood_tile.png")
	wood.stretch_mode = TextureRect.STRETCH_TILE
	wood.set_anchors_preset(Control.PRESET_FULL_RECT)
	wood.modulate = Color(1, 1, 1, 0.10)
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hd.add_child(wood)

	# Lienzo de diseño centrado y escalado para caber en pantalla.
	var canvas := Control.new()
	canvas.name = "Canvas"
	canvas.size = INV_DESIGN
	canvas.pivot_offset = INV_DESIGN * 0.5
	canvas.anchor_left = 0.5; canvas.anchor_right = 0.5
	canvas.anchor_top = 0.5; canvas.anchor_bottom = 0.5
	canvas.offset_left = -INV_DESIGN.x * 0.5; canvas.offset_right = INV_DESIGN.x * 0.5
	canvas.offset_top = -INV_DESIGN.y * 0.5; canvas.offset_bottom = INV_DESIGN.y * 0.5
	var vp := inv_panel.get_viewport_rect().size
	var s: float = minf(vp.x / INV_DESIGN.x, vp.y / INV_DESIGN.y) * 0.98
	canvas.scale = Vector2(s, s)
	hd.add_child(canvas)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 26)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	canvas.add_child(col)

	# --- Header ornado con título ---
	var head_wrap := CenterContainer.new()
	col.add_child(head_wrap)
	var head := Control.new()
	head.custom_minimum_size = Vector2(640, 640.0 * 306.0 / 1979.0)   # aspecto real
	head_wrap.add_child(head)
	var head_tex := TextureRect.new()
	head_tex.texture = load(HD + "header_ornate.png")
	head_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	head_tex.stretch_mode = TextureRect.STRETCH_SCALE
	head_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	head_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_tex)
	var head_lbl := UiTheme.px_label("INVENTARIO", 22, UiTheme.HEADER_TXT)
	head_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	head_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(head_lbl)

	# --- Cuerpo: equipo/mago (izq) + bolsa (der) ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(body)

	body.add_child(_build_equip_panel())
	body.add_child(_build_bag_panel())

## Panel de la bolsa (panel_sq) con header, divisor y grilla 5×5.
## panel_sq es CUADRADO: lo mantengo cuadrado para que el marco NO se deforme.
## La grilla (cuadrada) va centrada dentro del área de madera.
func _build_bag_panel() -> Control:
	const INSET := 88
	const HEADER_H := 64
	var grid_h := BAG_ROWS * BAG_CELL + (BAG_ROWS - 1) * BAG_GAP
	var side := HEADER_H + grid_h + 2 * INSET   # panel cuadrado (lado = alto necesario)
	var panel := Control.new()
	panel.custom_minimum_size = Vector2(side, side)
	var tex := TextureRect.new()
	tex.texture = load(HD + "panel_sq.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tex)

	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		inset.add_theme_constant_override(m, INSET)
	panel.add_child(inset)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	inset.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UiTheme.px_label("BOLSA", 13, UiTheme.GOLD))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_bag_count = Label.new()
	_bag_count.add_theme_font_override("font", UiTheme.font_body())
	_bag_count.add_theme_font_size_override("font_size", 22)
	_bag_count.add_theme_color_override("font_color", UiTheme.COUNT)
	head.add_child(_bag_count)

	vb.add_child(_divider())

	var grid_wrap := CenterContainer.new()
	grid_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(grid_wrap)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLS
	_bag_grid.add_theme_constant_override("h_separation", BAG_GAP)
	_bag_grid.add_theme_constant_override("v_separation", BAG_GAP)
	grid_wrap.add_child(_bag_grid)
	return panel

## Columna de equipo: paper-doll con 6 slots alrededor del sprite del personaje.
func _build_equip_panel() -> Control:
	const CENTER := Vector2(330, 480)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(UiTheme.px_label("EQUIPO", 13, UiTheme.GOLD))
	vb.add_child(_divider())

	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 18)
	doll.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(doll)

	_doll_left = VBoxContainer.new()
	_doll_left.add_theme_constant_override("separation", 16)
	doll.add_child(_doll_left)

	# Centro: mago idle (animado) parado sobre la plataforma rúnica + glow azul.
	var centercol := VBoxContainer.new()
	centercol.add_theme_constant_override("separation", 16)
	doll.add_child(centercol)
	var center := Control.new()
	center.custom_minimum_size = CENTER
	center.clip_contents = true   # recorta lo que se salga del recuadro
	centercol.add_child(center)
	var cbg := Panel.new()
	cbg.add_theme_stylebox_override("panel", _doll_bg())
	cbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(cbg)

	# Glow azul radial aditivo, debajo de la plataforma.
	var glow := TextureRect.new()
	glow.texture = load("res://assets/fx/light_radial.tres")
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.modulate = Color(0.30, 0.62, 1.0, 0.9)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = 0.5; glow.anchor_right = 0.5
	glow.anchor_top = 1.0; glow.anchor_bottom = 1.0
	glow.offset_left = -215; glow.offset_right = 215
	glow.offset_top = -205; glow.offset_bottom = -8
	var gmat := CanvasItemMaterial.new()
	gmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gmat
	center.add_child(glow)

	# Plataforma rúnica ANIMADA (21 frames, ya viene isométrica) a los pies del mago.
	_plat_frames.clear()
	for i in 21:
		_plat_frames.append(_raw_tex("res://assets/propias/plataformarunica/Plataforma_%04d.png" % (i + 1)))
	_plat_tex = TextureRect.new()
	_plat_tex.texture = _plat_frames[0]
	_plat_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plat_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_plat_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plat_tex.anchor_left = 0.5; _plat_tex.anchor_right = 0.5
	_plat_tex.anchor_top = 1.0; _plat_tex.anchor_bottom = 1.0
	_plat_tex.offset_left = -190; _plat_tex.offset_right = 190
	_plat_tex.offset_top = -300; _plat_tex.offset_bottom = 24
	center.add_child(_plat_tex)

	# Mago idle animado (cicla 4 frames en _process), parado sobre la plataforma.
	_hero_frames.clear()
	for i in 4:
		_hero_frames.append(load("res://assets/hero/mage/idle/south_%d.png" % i))
	_hero_tex = TextureRect.new()
	_hero_tex.texture = _hero_frames[0]
	_hero_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hero_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_tex.pivot_offset = CENTER * 0.5
	_hero_tex.scale = Vector2(2.2, 2.2)   # tamaño del mago
	center.add_child(_hero_tex)

	var below := CenterContainer.new()
	centercol.add_child(below)
	below.add_child(_equip_slot("", null))   # 9º slot: vacío por ahora

	_doll_right = VBoxContainer.new()
	_doll_right.add_theme_constant_override("separation", 16)
	doll.add_child(_doll_right)
	return vb

## Carga una textura leyendo el PNG crudo (sirve aunque Godot no lo haya importado;
## la plataforma se pegó al proyecto y el editor importa recién al recuperar foco).
func _raw_tex(res_path: String) -> Texture2D:
	var tex := load(res_path) as Texture2D
	if tex != null:
		return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

func _doll_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.065, 0.04, 0.85)
	s.set_border_width_all(2)
	s.border_color = Color(0.42, 0.32, 0.18)
	s.set_corner_radius_all(2)
	return s

func _divider() -> TextureRect:
	var d := TextureRect.new()
	d.texture = load(HD + "divider.png")
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.stretch_mode = TextureRect.STRETCH_SCALE
	d.custom_minimum_size = Vector2(0, 14)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

# ---------------- Layout responsive (HUD diseñado a 1152×648 → centrado a cualquier res) ----------------
func _layout_responsive() -> void:
	const DCX := 576.0   # centro del diseño original (1152/2, 648/2)
	const DCY := 324.0
	for pname in ["UpgradePanel", "PausePanel", "DeathPanel", "InventoryPanel"]:
		var panel := get_node_or_null(pname) as Control
		if panel == null:
			continue
		_full_rect(panel)
		for child in panel.get_children():
			if child is Control:
				if child.name == "BG":
					_full_rect(child)
				else:
					_center_rel(child, DCX, DCY)
	var bui := get_node_or_null("BossUI") as Control
	if bui:
		_full_rect(bui)
		for child in bui.get_children():
			if child is Control:
				_center_rel(child, DCX, DCY)

func _full_rect(c: Control) -> void:
	c.anchor_left = 0.0; c.anchor_top = 0.0; c.anchor_right = 1.0; c.anchor_bottom = 1.0
	c.offset_left = 0.0; c.offset_top = 0.0; c.offset_right = 0.0; c.offset_bottom = 0.0

## Re-ancla el control al centro de pantalla preservando su posición relativa al
## centro del diseño original → el layout 1152×648 queda centrado a cualquier res.
func _center_rel(c: Control, cx: float, cy: float) -> void:
	var l := c.offset_left; var t := c.offset_top; var r := c.offset_right; var b := c.offset_bottom
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.5; c.anchor_bottom = 0.5
	c.offset_left = l - cx; c.offset_right = r - cx; c.offset_top = t - cy; c.offset_bottom = b - cy

func _process(_delta: float) -> void:
	_animate_hero(_delta)
	# Cerrar tienda con E (con guarda de 1 frame para no cerrarla al abrirla).
	if _shop_panel and is_instance_valid(_shop_panel):
		if _shop_just_opened:
			_shop_just_opened = false
		elif Input.is_action_just_pressed("interact"):
			_close_shop()
	var p = GameState.player
	if p == null:
		return
	var life_ratio := clampf(float(p.hp) / maxf(1.0, p.max_hp()), 0.0, 1.0)
	(life_preview_fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", life_ratio)
	life_preview_value.text = "%d / %d" % [int(ceil(float(p.hp))), int(p.max_hp())]
	var mana_ratio := clampf(p.mana / maxf(1.0, p.max_mana), 0.0, 1.0)
	(mana_preview_fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", mana_ratio)
	mana_preview_value.text = "%d / %d" % [int(round(p.mana)), int(p.max_mana)]
	xp_fill.size.x = BAR_W * clampf(float(p.xp) / maxf(1.0, p.xp_to_next), 0.0, 1.0)
	stats.text = "Nivel %d    Monedas %d    Pociones %d    Daño %d" % [p.level, p.coins, p.potions, p.attack_damage()]

	if up_panel.visible or death_panel.visible:
		return
	if Input.is_action_just_pressed("inventory"):
		_toggle_inventory()
	elif Input.is_action_just_pressed("pause"):
		if inv_panel.visible:
			_toggle_inventory()
		else:
			_toggle_pause()

# ---------------- Jefe ----------------
func _on_boss_spawn(b: Node) -> void:
	boss_ui.visible = true
	boss_name.text = b.boss_name

func _on_boss_hp(current: int, maximum: int) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

func _on_boss_died() -> void:
	boss_ui.visible = false

# ---------------- Mejora de nivel ----------------
func _on_level_up(choices: Array) -> void:
	_choices = choices
	up_title.text = "¡Nivel %d! Elegí una mejora" % GameState.player.level
	for i in 3:
		up_btns[i].text = "%s\n%s" % [choices[i].name, choices[i].desc]
	up_panel.visible = true

func _pick(i: int) -> void:
	GameState.player.apply_upgrade(_choices[i].id)
	up_panel.visible = false
	get_tree().paused = false

# ---------------- Inventario ----------------
func _toggle_inventory() -> void:
	if inv_panel.visible:
		inv_panel.visible = false
		get_tree().paused = false
	else:
		_populate_inventory()
		inv_panel.visible = true
		get_tree().paused = true

func _populate_inventory() -> void:
	var p = GameState.player
	if _bag_count:
		_bag_count.text = "%d / %d" % [p.bag.size(), INV_BAG_CAP]

	# Bolsa: grilla de casillas (las primeras con ítems, el resto vacías).
	for c in _bag_grid.get_children():
		c.queue_free()
	for i in INV_BAG_CAP:
		var it = p.bag[i] if i < p.bag.size() else null
		_bag_grid.add_child(_bag_cell(it, i))

	# Paper-doll: 4 izq (Casco, Coraza, Amuleto, Capa) + 4 der (Arma, Anillo, Botas, vacío).
	for c in _doll_left.get_children():
		c.queue_free()
	for c in _doll_right.get_children():
		c.queue_free()
	var left := [
		["Casco", p.equip.get("casco", null)],
		["Coraza", p.equip.get("coraza", null)],
		["Amuleto", p.equip.get("amuleto", null)],
		["Capa", null],                                  # placeholder por ahora
	]
	var right := [
		["Arma", p.equip.get("arma", null)],
		["Anillo", p.equip.get("anillo", null)],
		["Botas", p.equip.get("botas", null)],
		["", null],                                      # vacío por ahora
	]
	for e in left:
		_doll_left.add_child(_equip_slot(e[0], e[1]))
	for e in right:
		_doll_right.add_child(_equip_slot(e[0], e[1]))

## Una casilla de la bolsa: cuadrícula simple recesada + swatch + click para equipar.
func _bag_cell(it, index: int) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(BAG_CELL, BAG_CELL)
	cell.add_theme_stylebox_override("panel", _bag_slot_box())
	if it == null:
		return cell
	var sw := _swatch(it)
	var pad := int(BAG_CELL * 0.2)
	sw.set_anchors_preset(Control.PRESET_FULL_RECT)
	sw.offset_left = pad; sw.offset_top = pad; sw.offset_right = -pad; sw.offset_bottom = -pad
	cell.add_child(sw)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.tooltip_text = "%s [%s]\n%s" % [it.name, Items.rarity_data(it.rarity).name, Items.describe(it)]
	btn.pressed.connect(_equip_bag.bind(index))
	cell.add_child(btn)
	return cell

## Casilla de bolsa: fondo oscuro con borde dorado-apagado (look recesado del mockup).
func _bag_slot_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("160d06")
	s.set_border_width_all(2)
	s.border_color = Color("7a5d28")
	s.set_corner_radius_all(2)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 3
	return s

## Un slot de equipo del paper-doll: marco + swatch + etiqueta debajo.
func _equip_slot(label_text: String, it) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(EQUIP_SLOT, EQUIP_SLOT)
	var tex := TextureRect.new()
	tex.texture = load(UiTheme.DIR_HD + "slot_equip.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tex)
	if it != null:
		var sw := _swatch(it)
		var pad := int(EQUIP_SLOT * 0.26)
		sw.set_anchors_preset(Control.PRESET_FULL_RECT)
		sw.offset_left = pad; sw.offset_top = pad; sw.offset_right = -pad; sw.offset_bottom = -pad
		frame.add_child(sw)
		frame.tooltip_text = "%s [%s]\n%s" % [it.name, Items.rarity_data(it.rarity).name, Items.describe(it)]
	box.add_child(frame)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", UiTheme.font_body())
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", UiTheme.MUTED_WARM)
	box.add_child(lbl)
	return box

## Cuadrito de color del ítem (según rareza), con bisel claro/oscuro.
func _swatch(it: Dictionary) -> Control:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Items.rarity_data(it.get("rarity", "comun")).color)
	s.set_corner_radius_all(1)
	s.border_width_top = 2; s.border_width_left = 2
	s.border_color = Color(1, 1, 1, 0.22)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _equip_bag(index: int) -> void:
	GameState.player.equip_from_bag(index)
	_populate_inventory()

## Cicla los frames del mago y de la plataforma mientras el inventario está abierto.
func _animate_hero(dt: float) -> void:
	if not inv_panel.visible:
		return
	if _hero_tex and not _hero_frames.is_empty():
		_hero_t += dt
		if _hero_t >= 0.18:
			_hero_t = 0.0
			_hero_i = (_hero_i + 1) % _hero_frames.size()
			_hero_tex.texture = _hero_frames[_hero_i]
	if _plat_tex and not _plat_frames.is_empty():
		_plat_t += dt
		if _plat_t >= 0.06:
			_plat_t = 0.0
			_plat_i = (_plat_i + 1) % _plat_frames.size()
			_plat_tex.texture = _plat_frames[_plat_i]

# ---------------- Pausa ----------------
func _toggle_pause() -> void:
	if pause_panel.visible:
		pause_panel.visible = false
		get_tree().paused = false
	else:
		pause_panel.visible = true
		get_tree().paused = true

# ---------------- Muerte / reinicio ----------------
func _on_death() -> void:
	_show_end("MORISTE", true)

func _on_mode(m: int) -> void:
	# El HUD se muestra en juego/muerte/victoria (la escena lo trae oculto).
	visible = m == GameState.Mode.PLAY or m == GameState.Mode.DEAD or m == GameState.Mode.WIN
	if m == GameState.Mode.WIN:
		_show_end("¡GANASTE!", false)   # main ya registró el récord y limpió el save

func _show_end(title: String, do_record: bool) -> void:
	var p = GameState.player
	var run = GameState.run
	if do_record:
		SaveSystem.record(run, p, false)
		SaveSystem.clear_run()
	death_title.text = title
	var rec := SaveSystem.get_records()
	death_sub.text = "Prof %d · Nivel %d · %d bajas\nRécord: prof %d · %d bajas" % [
		int(run.get("depth", 1)), p.level, int(run.get("kills", 0)),
		int(rec.get("best_depth", 0)), int(rec.get("best_kills", 0))]
	death_panel.visible = true
	get_tree().paused = true

func _restart() -> void:
	get_tree().paused = false
	SaveSystem.clear_run()   # reiniciar = empezar run nueva
	GameState.reset_run()
	GameState.set_mode(GameState.Mode.PLAY)
	get_tree().reload_current_scene()

# ---------------- Tienda / mercader ----------------
func open_shop(merchant) -> void:
	_shop_merchant = merchant
	if merchant.stock.is_empty():
		merchant.stock = Items.make_shop_stock(int(GameState.run.get("depth", 1)))
	_shop_just_opened = true
	get_tree().paused = true
	_build_shop()

func _build_shop() -> void:
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	var p = GameState.player
	var stock = _shop_merchant.stock
	# Pantalla completa: dim de fondo (oscurece el juego + bloquea clicks) + panel.
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	var root := PanelContainer.new()
	root.anchor_left = 0.5; root.anchor_right = 0.5; root.anchor_top = 0.5; root.anchor_bottom = 0.5
	root.offset_left = -320; root.offset_right = 320; root.offset_top = -210; root.offset_bottom = 210
	screen.add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	root.add_child(vb)
	var t := Label.new(); t.text = "MERCADER"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color("ffd84f")); t.add_theme_font_size_override("font_size", 22)
	vb.add_child(t)
	var coins := Label.new(); coins.text = "Tus monedas: ◉ %d" % int(p.coins)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins.add_theme_color_override("font_color", Color("ffd84f"))
	vb.add_child(coins)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for i in stock.items.size():
		row.add_child(_shop_card(stock.items[i], i))
	var heal := Button.new(); heal.text = "⚗ Poción de vida   ◉ %d" % int(stock.heal_price)
	heal.pressed.connect(_buy_heal); vb.add_child(heal)
	if p.bag.size() > 0:
		var sl := Label.new(); sl.text = "VENDER (tu mochila):"
		sl.add_theme_color_override("font_color", Color("8a8496")); vb.add_child(sl)
		var srow := HBoxContainer.new(); srow.add_theme_constant_override("separation", 6)
		vb.add_child(srow)
		for j in p.bag.size():
			var it = p.bag[j]
			if it == null:
				continue
			var sb := Button.new()
			sb.text = "%s  ◉%d" % [String(it.get("name", "ítem")), Items.sell_price(it)]
			sb.pressed.connect(_sell_item.bind(j))
			srow.add_child(sb)
	var close := Button.new(); close.text = "Cerrar  [E]"; close.pressed.connect(_close_shop)
	vb.add_child(close)
	add_child(screen)
	_shop_panel = screen

func _shop_card(it: Dictionary, idx: int) -> Control:
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(160, 0)
	var nm := Label.new(); nm.text = String(it.get("name", "ítem"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_color_override("font_color", Color(Items.rarity_data(it.get("rarity", "comun")).color))
	card.add_child(nm)
	var b := Button.new()
	if it.get("sold", false):
		b.text = "VENDIDO"; b.disabled = true
	else:
		b.text = "◉ %d" % int(it.get("price", 0))
		b.pressed.connect(_buy_item.bind(idx))
	card.add_child(b)
	return card

func _buy_item(idx: int) -> void:
	var stock = _shop_merchant.stock
	var it = stock.items[idx]
	var p = GameState.player
	if it.get("sold", false) or p.coins < int(it.price):
		return
	p.coins -= int(it.price)
	it["sold"] = true
	p.pick_up_item(it)
	Audio.play("coin")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _buy_heal() -> void:
	var stock = _shop_merchant.stock
	var p = GameState.player
	if p.coins < int(stock.heal_price):
		return
	p.coins -= int(stock.heal_price)
	p.potions += 1
	Audio.play("heal")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _sell_item(idx: int) -> void:
	var p = GameState.player
	if idx >= p.bag.size() or p.bag[idx] == null:
		return
	var it = p.bag[idx]
	p.bag.remove_at(idx)
	p.coins += Items.sell_price(it)
	Audio.play("coin")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _close_shop() -> void:
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	_shop_panel = null
	get_tree().paused = false
