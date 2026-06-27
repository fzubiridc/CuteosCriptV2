extends CanvasLayer
## Contador de FPS de debug (esquina sup-izq). Toggle con F3.

var _label: Label

func _ready() -> void:
	layer = 128                      # siempre arriba de todo
	_label = Label.new()
	_label.position = Vector2(8, 5)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	visible = false                  # arranca oculto; se muestra con F3

func _process(_dt: float) -> void:
	_label.text = "FPS %d" % Engine.get_frames_per_second()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_F3:
		visible = not visible
