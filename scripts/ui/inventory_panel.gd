extends Control
class_name InventoryPanel
## Inventario HD (kit assets_hd, según el mockup). Extraído de hud.gd (refactor 1:1).
##
## El inventario se CONSTRUYE DENTRO del nodo InventoryPanel que ya trae la escena
## (main.tscn: HUD/InventoryPanel), porque _layout_responsive() del HUD lo re-ancla por
## nombre y la build oculta los hijos viejos (BG/Title/...). Mover ese nodo a otra
## identidad rompería el layout, así que este script es un CONTROLADOR liviano: el HUD
## lo instancia como hijo suyo y le pasa el nodo real con setup(panel). Toda la lógica,
## el estado y el toggle del inventario viven acá; el HUD solo coordina.

# ---------------- Inventario HD (kit assets_hd, según el mockup) ----------------
const INV_DESIGN := Vector2(1580, 1040)   # lienzo de diseño (mago izq + bolsa der)
const BAG_COLS := 5
const BAG_ROWS := 5
const INV_BAG_CAP := BAG_COLS * BAG_ROWS  # 25 casillas (5 × 5, grilla cuadrada)
const BAG_CELL := 112                      # lado de cada casilla de la bolsa
const BAG_GAP := 12
const EQUIP_SLOT := 122                     # slots de equipo ≥ celdas de la bolsa
const HD := "res://assets/ui_hd/"

# Nodo InventoryPanel real de la escena (se construye adentro; el HUD lo inyecta).
var inv_panel: Control

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

func _ready() -> void:
	# El árbol se pausa al abrir el inventario; necesitamos animar el mago igual
	# (el HUD original corría con PROCESS_MODE_ALWAYS).
	process_mode = Node.PROCESS_MODE_ALWAYS

## El HUD inyecta el nodo InventoryPanel de la escena y dispara la build una sola vez.
func setup(panel: Control) -> void:
	inv_panel = panel
	_build_inventory_hd()

func _process(_delta: float) -> void:
	_animate_hero(_delta)

## ¿El inventario está visible? (el HUD lo consulta para arbitrar pausa/teclas).
func is_open() -> bool:
	return inv_panel != null and inv_panel.visible

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
	var head_lbl := UiTheme.title_label("INVENTARIO", 30, UiTheme.HEADER_TXT)
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
	head.add_child(UiTheme.section_header_label("BOLSA", 18, UiTheme.GOLD))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_bag_count = Label.new()
	UiTheme.apply_small_ui(_bag_count, 22, UiTheme.COUNT)
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
	vb.add_child(UiTheme.section_header_label("EQUIPO", 18, UiTheme.GOLD))
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

# ---------------- Inventario ----------------
func toggle() -> void:
	if inv_panel.visible:
		inv_panel.visible = false
		get_tree().paused = false
	else:
		_populate_inventory()
		inv_panel.visible = true
		GameState.last_pause_src = "inventory"
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
	UiTheme.apply_small_ui(lbl, 16, UiTheme.MUTED_WARM)
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
