extends Control
## Menú de inicio (referencia del Pixi: título dorado flotante, subtítulo, récords,
## Continuar/Nuevo). UI construida por código (se re-skinea con NinePatch al tener
## las imágenes). Es la escena principal del proyecto → entra a main.tscn.

const GOLD := Color("ffd84f")
const GREY := Color("8a8496")

var _title: Label

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.039, 0.06, 1.0)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5; box.anchor_right = 0.5; box.anchor_top = 0.5; box.anchor_bottom = 0.5
	box.offset_left = -340.0; box.offset_right = 340.0
	box.offset_top = -210.0; box.offset_bottom = 210.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	# Título dorado con sombra marrón y flotación (ref pixi: .title + @keyframes titlefloat).
	# Va dentro de un Control simple (no-container) para poder tweenear su posición:
	# el VBox sí re-posiciona a sus hijos directos en cada layout, el Control no.
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 64)
	box.add_child(wrap)

	_title = Label.new()
	_title.text = "LA CÁRCEL DEL CUTEO"
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 46)
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_color_override("font_shadow_color", Color("4a2a10"))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	wrap.add_child(_title)

	var tw := create_tween().set_loops()
	tw.tween_property(_title, "position:y", -6.0, 1.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "position:y", 0.0, 1.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	box.add_child(_label("un roguelike de fantasía medieval", GREY, 15))

	var rec := SaveSystem.get_records()
	if not rec.is_empty():
		var txt := "Runs: %d · Bajas: %d · Victorias: %d · Mejor piso: %d" % [
			int(rec.get("runs", 0)), int(rec.get("best_kills", 0)),
			int(rec.get("wins", 0)), int(rec.get("best_depth", 0))]
		box.add_child(_label(txt, GOLD, 14))

	box.add_child(_label("El Archimago espera su condena:", GREY, 14))
	box.add_child(_spacer(16))

	if SaveSystem.has_run():
		box.add_child(_button("CONTINUAR RUN GUARDADA", _on_continue))
	box.add_child(_button("▶ ENTRAR A LA CÁRCEL", _on_new))
	box.add_child(_button("SALIR", _on_quit))

func _label(text: String, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b

func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _on_new() -> void:
	SaveSystem.clear_run()
	GameState.reset_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_quit() -> void:
	get_tree().quit()
