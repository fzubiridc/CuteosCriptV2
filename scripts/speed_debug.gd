extends CanvasLayer
## Panel de tuning de velocidad en vivo (tecla V). Modela a lighting_debug.gd:
## sliders que escriben directo sobre los knobs del Player (GameState.player), así
## se ajusta el movimiento mientras se juega sin parar ni tocar el Inspector.

const DEFS := [
	{"key": "base_speed",      "label": "Velocidad base",      "min": 30.0, "max": 200.0, "fmt": "%.0f"},
	{"key": "walk_anim_speed", "label": "Cadencia caminata",   "min": 0.20, "max": 1.50,  "fmt": "%.2f"},
	{"key": "walk_speed_ref",  "label": "Vel. ref. cadencia",  "min": 50.0, "max": 150.0, "fmt": "%.0f"},
]

var _panel: Control
var _rows: Array = []   # [{key, slider, label, fmt}]

func _ready() -> void:
	layer = 6   # por encima del panel de luz (5)
	_build_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_from_player()

func _player() -> Node:
	return GameState.player

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(360, 0)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "VELOCIDAD — knobs (V para ocultar)"
	vb.add_child(title)

	for d in DEFS:
		vb.add_child(_make_row(d))

func _make_row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = str(d["label"])
	name_lbl.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_lbl)

	var slider := HSlider.new()
	slider.min_value = d["min"]
	slider.max_value = d["max"]
	slider.step = (float(d["max"]) - float(d["min"])) / 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(120, 0)
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(48, 0)
	row.add_child(val_lbl)

	var key: String = d["key"]
	var fmt: String = d["fmt"]
	slider.value_changed.connect(func(v: float) -> void:
		var p := _player()
		if p != null:
			p.set(key, v)
		val_lbl.text = fmt % v)

	_rows.append({"key": key, "slider": slider, "label": val_lbl, "fmt": fmt})
	return row

## Sincroniza sliders + labels con los valores actuales del Player (al abrir el panel).
func _refresh_from_player() -> void:
	var p := _player()
	for r in _rows:
		var v: float = float(p.get(r["key"])) if p != null else float(r["slider"].value)
		r["slider"].set_value_no_signal(v)
		r["label"].text = str(r["fmt"]) % v
