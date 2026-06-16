class_name UiTheme
extends RefCounted
## Theme de UI medieval/oscuro armado por código, en la paleta del juego (oro +
## madera oscura, cálido como la luz de antorcha). IMAGE-READY: cada StyleBox sale
## de un helper, así cambiar a marcos NinePatch (tus imágenes) después = swappear
## el helper por un StyleBoxTexture, sin tocar el resto.

const GOLD := Color("ffd84f")
const PARCHMENT := Color("f1e6cc")               # texto claro cálido
const PANEL_BG := Color(0.30, 0.225, 0.15, 1.0)  # madera clara, opaca, inconfundible
const BTN_BG := Color(0.24, 0.18, 0.12, 1.0)
const BTN_HI := Color(0.40, 0.29, 0.13, 1.0)     # hover
const BTN_DN := Color(0.12, 0.09, 0.06, 1.0)     # pressed
const BORDER := Color(0.82, 0.64, 0.28)          # marco dorado marcado
const BORDER_HI := GOLD

static var _cached: Theme

static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font_size = 16
	# Paneles (PanelContainer / Panel) → marco dorado sobre madera oscura.
	var panel := _panel_box(PANEL_BG, BORDER, 4)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# Botones.
	t.set_stylebox("normal", "Button", _btn_box(BTN_BG, BORDER))
	t.set_stylebox("hover", "Button", _btn_box(BTN_HI, BORDER_HI))
	t.set_stylebox("pressed", "Button", _btn_box(BTN_DN, BORDER_HI))
	t.set_stylebox("disabled", "Button", _btn_box(Color(0.10, 0.09, 0.08, 0.7), Color(0.30, 0.28, 0.26)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.44))
	t.set_font_size("font_size", "Button", 16)
	# Labels (color + outline para leerse sobre cualquier fondo).
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 3)
	_cached = t
	return t

static func _panel_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.border_blend = true
	s.set_corner_radius_all(10)
	s.set_content_margin_all(18)
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 14
	return s

static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
