extends CanvasLayer
## Panel de PRUEBA de varas (tecla J). Fuerza qué vara empuña el Player para ver
## cómo queda cada sprite/rig en el juego, sin depender del material equipado.
## Solo en debug/editor (oculto en release). Modela a speed_debug.gd / lighting_debug.gd.

var _panel: Control
var _lbl: Label
var _idx: int = -1   # -1 = normal (según material equipado); 0..N-1 = vara forzada

func _ready() -> void:
	layer = 7   # por encima de los otros paneles debug
	_build_ui()

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return   # panel de varas (tecla J): solo en debug/editor, oculto en release
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_sync()

func _player():
	return GameState.player

func _count() -> int:
	var p = _player()
	return int(p.debug_staff_count()) if p != null else 0

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(12, 120)   # debajo de los paneles de luz/velocidad
	_panel.custom_minimum_size = Vector2(290, 0)
	add_child(_panel)

	var vb := VBoxContainer.new()
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "VARAS — probar (J para ocultar)"
	vb.add_child(title)

	_lbl = Label.new()
	vb.add_child(_lbl)

	var row := HBoxContainer.new()
	vb.add_child(row)

	var b_prev := Button.new(); b_prev.text = "◀ ant";  row.add_child(b_prev)
	var b_next := Button.new(); b_next.text = "sig ▶";  row.add_child(b_next)
	var b_norm := Button.new(); b_norm.text = "normal"; row.add_child(b_norm)

	b_prev.pressed.connect(func() -> void: _step(-1))
	b_next.pressed.connect(func() -> void: _step(1))
	b_norm.pressed.connect(func() -> void: _apply(-1))

func _step(d: int) -> void:
	var n := _count()
	if n <= 0:
		return
	if _idx < 0:
		_idx = 0 if d > 0 else n - 1
	else:
		_idx = (_idx + d + n) % n
	_apply(_idx)

func _apply(i: int) -> void:
	_idx = i
	var p = _player()
	if p != null:
		p.debug_set_staff(i)
	_sync()

func _sync() -> void:
	var n := _count()
	if _idx < 0:
		_lbl.text = "modo: normal (según material)"
	else:
		_lbl.text = "vara %d / %d   ·   staff%d.png" % [_idx + 1, n, _idx + 1]
