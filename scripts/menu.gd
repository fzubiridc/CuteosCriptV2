extends Control
## Menú de inicio. Replica la composición de la versión Pixi: título flotante,
## récords, tarjeta animada del Archimago y acción de continuar separada.

const GOLD := Color("ffd84f")
const TEXT := Color("d8d2c8")
const MUTED := Color("a8a2b8")
const PANEL := Color("16131c")
const PANEL_ALT := Color("2a2336")
const BORDER := Color("3a3346")

const PORTRAIT_FRAMES := 4
const PORTRAIT_SECONDS := 0.22

var _title: Label
var _portrait: TextureRect
var _portrait_frame := 0
var _portrait_textures: Array[Texture2D] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_start_portrait_animation()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("0b0a0f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	center.add_child(content)

	_build_title(content)
	content.add_child(_label("un roguelike de fantasía medieval", MUTED, 14, 2))

	var records := SaveSystem.get_records()
	if not records.is_empty():
		var total_kills := int(records.get("kills", records.get("best_kills", 0)))
		var record_text := "Runs: %d · Criaturas eliminadas: %d · Victorias: %d" % [
			int(records.get("runs", 0)), total_kills, int(records.get("wins", 0))]
		content.add_child(_label(record_text, GOLD, 14, 1))

	content.add_child(_label("El Archimago espera su condena:", MUTED, 14, 2))
	content.add_child(_spacer(4))

	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 16)
	content.add_child(choices)
	choices.add_child(_class_card(records))

	if SaveSystem.has_run():
		var continue_button := _button("CONTINUAR RUN GUARDADA", _on_continue)
		continue_button.custom_minimum_size = Vector2(360, 374)
		choices.add_child(continue_button)


func _build_title(parent: VBoxContainer) -> void:
	var title_wrap := Control.new()
	title_wrap.custom_minimum_size = Vector2(0, 58)
	parent.add_child(title_wrap)

	_title = Label.new()
	_title.text = "LA CÁRCEL DEL CUTEO"
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", _spaced_font(6))
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_color_override("font_shadow_color", Color("4a2a10"))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 3)
	title_wrap.add_child(_title)

	var tween := create_tween().set_loops()
	tween.tween_property(_title, "position:y", -6.0, 1.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_title, "position:y", 0.0, 1.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _class_card(records: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(210, 374)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _panel_style(PANEL, BORDER))
	card.add_theme_stylebox_override("hover", _panel_style(PANEL, GOLD))
	card.add_theme_stylebox_override("pressed", _panel_style(Color("110e16"), GOLD))
	card.add_theme_stylebox_override("focus", _panel_style(PANEL, BORDER))
	card.pressed.connect(_on_new)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(128, 152)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_portrait)

	body.add_child(_label("El Archimago", GOLD, 16, 1))
	var description := _label("Viejo, lento y absolutamente letal.\nSu energyblast revienta lo que toca.", MUTED, 11, 0)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(180, 38)
	body.add_child(description)
	body.add_child(_stat_line("Vida", "100"))
	body.add_child(_stat_line("Velocidad", "78"))
	body.add_child(_stat_line("Crítico", "8%"))

	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _line_style())
	body.add_child(separator)
	var best_depth := maxi(1, int(records.get("best_depth", 0)))
	body.add_child(_stat_line("Mejor", "piso %d" % best_depth))
	body.add_child(_spacer(4))
	body.add_child(_label("▶ ENTRAR A LA CÁRCEL", GOLD, 14, 1))
	return card


func _start_portrait_animation() -> void:
	for frame in PORTRAIT_FRAMES:
		var source := load("res://assets/hero/mage/idle/south_%d.png" % frame) as Texture2D
		if source == null:
			continue
		var crop := AtlasTexture.new()
		crop.atlas = source
		crop.region = Rect2(28, 18, 64, 76)
		_portrait_textures.append(crop)
	if _portrait_textures.is_empty():
		return
	_portrait.texture = _portrait_textures[0]
	var timer := Timer.new()
	timer.wait_time = PORTRAIT_SECONDS
	timer.autostart = true
	timer.timeout.connect(_advance_portrait)
	add_child(timer)


func _advance_portrait() -> void:
	_portrait_frame = (_portrait_frame + 1) % _portrait_textures.size()
	_portrait.texture = _portrait_textures[_portrait_frame]


func _stat_line(stat_name: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(stat_name, TEXT, 11, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _label(value, TEXT, 11, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _label(text: String, color: Color, font_size: int, spacing := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if spacing > 0:
		label.add_theme_font_override("font", _spaced_font(spacing))
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _spaced_font(2))
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_stylebox_override("normal", _panel_style(PANEL_ALT, BORDER))
	button.add_theme_stylebox_override("hover", _panel_style(PANEL_ALT, GOLD))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("221c2e"), GOLD))
	button.add_theme_stylebox_override("focus", _panel_style(PANEL_ALT, BORDER))
	button.pressed.connect(callback)
	return button


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.75)
	style.shadow_size = 18
	return style


func _line_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BORDER
	style.content_margin_top = 1
	return style


func _spaced_font(pixels: int) -> FontVariation:
	var variation := FontVariation.new()
	var monospace := SystemFont.new()
	monospace.font_names = PackedStringArray(["Courier New", "Courier", "monospace"])
	variation.base_font = monospace
	variation.spacing_glyph = pixels
	return variation


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _on_new() -> void:
	SaveSystem.clear_run()
	GameState.reset_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
