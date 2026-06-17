class_name UiTheme
extends RefCounted
## Theme de UI medieval armado por código. AHORA con texturas reales (kit pixel-art
## 9-slice del handoff) vía StyleBoxTexture: paneles y botones salen de los PNG en
## res://assets/ui/. El inventario usa el kit HD (res://assets/ui_hd/) aparte.
## Fuentes: Press Start 2P (títulos/etiquetas) + VT323 (cuerpo), ambas OFL.

# --- Paleta (la del mockup HD) ---
const GOLD := Color("ffd84f")          # oro brillante
const GOLD_DIM := Color("d1a347")      # oro borde
const PARCHMENT := Color("f1e6cc")     # texto claro
const HEADER_TXT := Color("f8ebc6")    # texto del header ornado
const MUTED := Color("8a8496")         # texto apagado (frío)
const MUTED_WARM := Color("9b9079")    # texto apagado (cálido)
const COUNT := Color("cdbf9b")         # contadores

# --- Rutas de assets ---
const DIR := "res://assets/ui/"
const DIR_HD := "res://assets/ui_hd/"
const FONT_PIXEL_PATH := "res://assets/ui/fonts/PressStart2P-Regular.ttf"
const FONT_BODY_PATH := "res://assets/ui/fonts/VT323-Regular.ttf"

static var _cached: Theme
static var _font_pixel: FontFile
static var _font_body: FontFile

static func font_pixel() -> FontFile:
	if _font_pixel == null:
		_font_pixel = load(FONT_PIXEL_PATH)
	return _font_pixel

static func font_body() -> FontFile:
	if _font_body == null:
		_font_body = load(FONT_BODY_PATH)
	return _font_body

static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	# Fuente base retro (VT323 se lee chico, así que va con cuerpo grande).
	t.default_font = font_body()
	t.default_font_size = 20

	# Paneles → marco de madera/oro (panel_frame.png, 96×96, 9-slice 28).
	var panel := _tex_box(DIR + "panel_frame.png", 28, 28, 28, 28, 26)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# Botones → 3 estados (button_*.png, 64×24, 9-slice 10 lat / 8 vert).
	t.set_stylebox("normal", "Button", _btn_box("button_normal.png"))
	t.set_stylebox("hover", "Button", _btn_box("button_hover.png"))
	t.set_stylebox("pressed", "Button", _btn_box("button_pressed.png"))
	t.set_stylebox("disabled", "Button", _btn_box("button_normal.png", 0.45))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD_DIM)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.44))

	# Labels: color cálido + outline para leerse sobre cualquier fondo.
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 4)

	_cached = t
	return t

## StyleBoxTexture genérico con márgenes de textura (9-slice) y de contenido.
static func _tex_box(path: String, ml: int, mt: int, mr: int, mb: int, content := 12) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.set_texture_margin(SIDE_LEFT, ml)
	s.set_texture_margin(SIDE_TOP, mt)
	s.set_texture_margin(SIDE_RIGHT, mr)
	s.set_texture_margin(SIDE_BOTTOM, mb)
	s.set_content_margin_all(content)
	return s

static func _btn_box(file: String, alpha := 1.0) -> StyleBoxTexture:
	var s := _tex_box(DIR + file, 10, 8, 10, 8, 10)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if alpha < 1.0:
		s.modulate_color = Color(1, 1, 1, alpha)
	return s

## StyleBoxTexture cuadrado (mismo margen 9-slice en los 4 lados) — para usar como
## fondo de un Button/Panel (p.ej. casillas con slot_equip).
static func ninepatch_box(path: String, margin: int) -> StyleBoxTexture:
	return _tex_box(path, margin, margin, margin, margin, 0)

## NinePatch reutilizable (para banner/divider del kit pixel y paneles del HD).
static func ninepatch(path: String, ml: int, mt: int, mr: int, mb: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(path)
	n.patch_margin_left = ml
	n.patch_margin_top = mt
	n.patch_margin_right = mr
	n.patch_margin_bottom = mb
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n

## Label con la fuente pixel (Press Start 2P) — para títulos/etiquetas.
static func px_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_pixel())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	return l
