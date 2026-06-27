extends CanvasLayer
## Panel de tuning de luz en vivo (tecla L) + aplicación de los knobs a la escena.
## Lee de LightCfg y aplica a CanvasModulate (Ambient), Player/Light y Env
## (WorldEnvironment). Las antorchas/proyectiles se autoactualizan vía LightCfg.changed.

const PLAYER_LIGHT_COLOR := Color(1.0, 0.60, 0.24)  # 0xff9a3c, cálida (Pixi)

var _panel: Control
var _value_labels: Dictionary = {}
var _post: ColorRect   # post-proceso de pantalla (saturación/exposición en 2D)

func _ready() -> void:
	layer = 5
	_setup_post()
	_build_ui()
	LightCfg.changed.connect(_apply)
	# Aplicar después de que la escena esté lista (Ambient/Env existen).
	call_deferred("_apply")

## ColorRect a pantalla completa con shader de saturación/exposición. Va de primero
## (índice 0) así el panel de tuning queda por encima sin teñirse.
func _setup_post() -> void:
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/post_fx.gdshader")
	_post.material = mat
	add_child(_post)
	move_child(_post, 0)

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return   # panel de tuning (tecla L) solo en debug/editor; el post-FX (_setup_post) corre SIEMPRE
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_panel.visible = not _panel.visible

# ---------------------------------------------------------------------------
# Aplicar knobs a la escena
# ---------------------------------------------------------------------------
func _apply() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var amb := scene.get_node_or_null("Ambient") as CanvasModulate
	if amb:
		amb.color = LightCfg.ambient_color()
	var pl := scene.get_node_or_null("Player/Light") as PointLight2D
	if pl == null:
		# iso: el player puede estar anidado (p.ej. World/Player). Buscar recursivo.
		var _p := scene.find_child("Player", true, false)
		if _p:
			pl = _p.get_node_or_null("Light") as PointLight2D
	if pl:
		pl.color = Color(1, 1, 1).lerp(PLAYER_LIGHT_COLOR, LightCfg.get_v("player_warmth"))
		pl.energy = LightCfg.get_v("player_energy")
		pl.texture_scale = LightCfg.get_v("player_radius")
		pl.height = LightCfg.get_v("player_height")
		pl.shadow_filter_smooth = LightCfg.get_v("shadow_smooth")
	# Saturación + exposición van por shader de pantalla (en 2D el Environment no las aplica).
	if _post and _post.material is ShaderMaterial:
		var m := _post.material as ShaderMaterial
		m.set_shader_parameter("saturation", LightCfg.get_v("saturation"))
		m.set_shader_parameter("exposure", LightCfg.get_v("exposure"))

# ---------------------------------------------------------------------------
# UI autogenerada desde LightCfg.DEFS
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(480, 0)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 560)
	_panel.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "LUZ — knobs (L para ocultar)"
	vb.add_child(title)

	var reset_btn := Button.new()
	reset_btn.text = "Reset a defaults"
	reset_btn.pressed.connect(func() -> void:
		LightCfg.reset()
		_refresh_sliders())
	vb.add_child(reset_btn)

	var last_group := ""
	for k in LightCfg.DEFS.keys():
		var d: Dictionary = LightCfg.DEFS[k]
		if d["group"] != last_group:
			last_group = d["group"]
			var gh := Label.new()
			gh.text = "— " + str(d["group"]) + " —"
			vb.add_child(gh)
		vb.add_child(_make_row(k, d))

func _make_row(key: String, d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = str(d["label"])
	name_lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_lbl)

	var slider := HSlider.new()
	slider.min_value = d["min"]
	slider.max_value = d["max"]
	slider.step = (float(d["max"]) - float(d["min"])) / 100.0
	slider.value = LightCfg.get_v(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120, 0)
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % LightCfg.get_v(key)
	val_lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(val_lbl)
	_value_labels[key] = val_lbl

	slider.value_changed.connect(func(v: float) -> void:
		LightCfg.set_v(key, v)
		val_lbl.text = "%.2f" % v)
	slider.set_meta("knob", key)
	return row

## Resincroniza los sliders tras un reset.
func _refresh_sliders() -> void:
	for k in _value_labels.keys():
		_value_labels[k].text = "%.2f" % LightCfg.get_v(k)
	# actualizar posición de los HSlider
	for row in _all_sliders(self):
		if row.has_meta("knob"):
			row.value = LightCfg.get_v(row.get_meta("knob"))

func _all_sliders(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_all_sliders(c))
	return out
