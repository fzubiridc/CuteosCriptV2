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
const FONT_TITLE_PATH := "res://assets/fonts/Cinzel_Variable.ttf"
const FONT_NARRATIVE_PATH := "res://assets/fonts/EB_Garamond_Variable.ttf"
const TITLE_LABEL_SETTINGS_PATH := "res://assets/fonts/title_label_settings.tres"
const SECTION_HEADER_LABEL_SETTINGS_PATH := "res://assets/fonts/section_header_label_settings.tres"
const NARRATIVE_LABEL_SETTINGS_PATH := "res://assets/fonts/narrative_label_settings.tres"
const DIALOGUE_LABEL_SETTINGS_PATH := "res://assets/fonts/dialogue_label_settings.tres"
const BOOK_TEXT_LABEL_SETTINGS_PATH := "res://assets/fonts/book_text_label_settings.tres"

static var _cached: Theme
static var _font_pixel: FontFile
static var _font_body: FontFile
static var _font_title: FontFile
static var _font_narrative: FontFile
static var _settings_title: LabelSettings
static var _settings_section_header: LabelSettings
static var _settings_narrative: LabelSettings
static var _settings_dialogue: LabelSettings
static var _settings_book_text: LabelSettings

static func font_pixel() -> FontFile:
	if _font_pixel == null:
		_font_pixel = load(FONT_PIXEL_PATH)
	return _font_pixel

static func font_body() -> FontFile:
	if _font_body == null:
		_font_body = load(FONT_BODY_PATH)
	return _font_body

static func font_title() -> FontFile:
	if _font_title == null:
		_font_title = load(FONT_TITLE_PATH)
	return _font_title

static func font_narrative() -> FontFile:
	if _font_narrative == null:
		_font_narrative = load(FONT_NARRATIVE_PATH)
	return _font_narrative

static func title_settings() -> LabelSettings:
	if _settings_title == null:
		_settings_title = load(TITLE_LABEL_SETTINGS_PATH)
	return _settings_title

static func section_header_settings() -> LabelSettings:
	if _settings_section_header == null:
		_settings_section_header = load(SECTION_HEADER_LABEL_SETTINGS_PATH)
	return _settings_section_header

static func narrative_settings() -> LabelSettings:
	if _settings_narrative == null:
		_settings_narrative = load(NARRATIVE_LABEL_SETTINGS_PATH)
	return _settings_narrative

static func dialogue_settings() -> LabelSettings:
	if _settings_dialogue == null:
		_settings_dialogue = load(DIALOGUE_LABEL_SETTINGS_PATH)
	return _settings_dialogue

static func book_text_settings() -> LabelSettings:
	if _settings_book_text == null:
		_settings_book_text = load(BOOK_TEXT_LABEL_SETTINGS_PATH)
	return _settings_book_text

static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	# Fuente base retro (VT323 se lee chico, así que va con cuerpo grande).
	t.default_font = font_body()
	t.default_font_size = 20
	_add_typography_roles(t)

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

	# Tooltip al hover (item) → fuente más chica que el default 20 (se veía enorme).
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_font("font", "TooltipLabel", font_body())

	_cached = t
	return t

static func _add_typography_roles(t: Theme) -> void:
	t.set_type_variation("FontTitle", "Label")
	t.set_font("font", "FontTitle", font_title())
	t.set_font_size("font_size", "FontTitle", 32)
	t.set_color("font_color", "FontTitle", HEADER_TXT)
	t.set_color("font_outline_color", "FontTitle", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "FontTitle", 3)

	t.set_type_variation("DisplayTitle", "Label")
	t.set_font("font", "DisplayTitle", font_title())
	t.set_font_size("font_size", "DisplayTitle", 42)
	t.set_color("font_color", "DisplayTitle", GOLD)
	t.set_color("font_outline_color", "DisplayTitle", Color(0, 0, 0, 0.92))
	t.set_constant("outline_size", "DisplayTitle", 4)

	t.set_type_variation("FontSectionHeader", "Label")
	t.set_font("font", "FontSectionHeader", font_title())
	t.set_font_size("font_size", "FontSectionHeader", 24)
	t.set_color("font_color", "FontSectionHeader", GOLD)
	t.set_color("font_outline_color", "FontSectionHeader", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "FontSectionHeader", 3)

	for role in ["FontNarrativeBody", "FontDialogue", "FontBookText", "FontItemDescription"]:
		t.set_type_variation(role, "Label")
		t.set_font("font", role, font_narrative())
		t.set_font_size("font_size", role, 22)
		t.set_color("font_color", role, PARCHMENT)
		t.set_color("font_outline_color", role, Color(0, 0, 0, 0.8))
		t.set_constant("outline_size", role, 2)

	t.set_type_variation("FontSmallUI", "Label")
	t.set_font("font", "FontSmallUI", font_body())
	t.set_font_size("font_size", "FontSmallUI", 20)
	t.set_color("font_color", "FontSmallUI", PARCHMENT)

	t.set_type_variation("RichNarrativeBody", "RichTextLabel")
	t.set_font("normal_font", "RichNarrativeBody", font_narrative())
	t.set_font_size("normal_font_size", "RichNarrativeBody", 22)
	t.set_color("default_color", "RichNarrativeBody", PARCHMENT)

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
static func title_label(text: String, size: int = 32, color: Color = HEADER_TXT) -> Label:
	var l := Label.new()
	l.text = text
	apply_title(l, size, color)
	return l

static func section_header_label(text: String, size: int = 24, color: Color = GOLD) -> Label:
	var l := Label.new()
	l.text = text
	apply_section_header(l, size, color)
	return l

static func narrative_label(text: String, size: int = 22, color: Color = PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	apply_narrative(l, size, color)
	return l

static func apply_title(label: Label, size := -1, color: Color = HEADER_TXT) -> void:
	_apply_label_settings(label, title_settings(), size, color)

static func apply_section_header(label: Label, size := -1, color: Color = GOLD) -> void:
	_apply_label_settings(label, section_header_settings(), size, color)

static func apply_narrative(label: Label, size := -1, color: Color = PARCHMENT) -> void:
	_apply_label_settings(label, narrative_settings(), size, color)

static func apply_dialogue(label: Label, size := -1, color: Color = PARCHMENT) -> void:
	_apply_label_settings(label, dialogue_settings(), size, color)

static func apply_book_text(label: Label, size := -1, color: Color = Color("2b2118")) -> void:
	_apply_label_settings(label, book_text_settings(), size, color)

static func apply_item_description(label: Label, size := -1, color: Color = PARCHMENT) -> void:
	_apply_label_settings(label, narrative_settings(), size, color)

static func apply_small_ui(label: Label, size := -1, color: Color = PARCHMENT) -> void:
	label.add_theme_font_override("font", font_body())
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

static func apply_rich_narrative(label: RichTextLabel, size := 22, color: Color = PARCHMENT) -> void:
	label.add_theme_font_override("normal_font", font_narrative())
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_color_override("default_color", color)

static func _apply_label_settings(label: Label, settings: LabelSettings, size: int, color: Color) -> void:
	label.label_settings = settings.duplicate()
	if size > 0:
		label.label_settings.font_size = size
	label.label_settings.font_color = color

static func px_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_pixel())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	return l
