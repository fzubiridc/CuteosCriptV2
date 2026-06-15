extends Node
## Fuente única de verdad de los "knobs" de iluminación (como el panel tecla K
## del renderer Pixi). Persiste en user://light_knobs.json. El panel de debug
## (lighting_debug.gd) edita estos valores; player/antorchas/proyectiles los leen.
## Emite `changed` para actualización en vivo.

signal changed

const SAVE_PATH := "user://light_knobs.json"

## Definición de cada knob: min, max, def, label, group. El panel se autogenera
## desde acá, así que agregar un knob = una línea.
const DEFS := {
	# --- Ambiente (CanvasModulate) ---
	"amb_r": {"min": 0.0, "max": 1.0, "def": 0.46, "label": "Ambient R", "group": "Ambiente"},
	"amb_g": {"min": 0.0, "max": 1.0, "def": 0.44, "label": "Ambient G", "group": "Ambiente"},
	"amb_b": {"min": 0.0, "max": 1.0, "def": 0.55, "label": "Ambient B", "group": "Ambiente"},
	# --- Luz del jugador ---
	"player_energy": {"min": 0.0, "max": 4.0, "def": 2.2, "label": "Jugador energía", "group": "Jugador"},
	"player_radius": {"min": 0.1, "max": 1.5, "def": 0.55, "label": "Jugador radio", "group": "Jugador"},
	"player_height": {"min": 0.0, "max": 64.0, "def": 26.0, "label": "Jugador altura", "group": "Jugador"},
	# --- Antorchas (L1) ---
	"torch_energy": {"min": 0.0, "max": 4.0, "def": 2.25, "label": "Antorcha energía", "group": "Antorchas"},
	"torch_radius": {"min": 0.2, "max": 2.5, "def": 1.1, "label": "Antorcha radio", "group": "Antorchas"},
	"torch_height": {"min": 0.0, "max": 64.0, "def": 27.0, "label": "Antorcha altura", "group": "Antorchas"},
	# --- Post-proceso (WorldEnvironment) ---
	"exposure": {"min": 0.5, "max": 3.0, "def": 1.1, "label": "Exposición", "group": "Post"},
	"bloom_on": {"min": 0.0, "max": 1.0, "def": 1.0, "label": "Bloom on/off", "group": "Post"},
	"bloom_intensity": {"min": 0.0, "max": 3.0, "def": 1.0, "label": "Bloom intensidad", "group": "Post"},
	"bloom_threshold": {"min": 0.0, "max": 2.0, "def": 0.9, "label": "Bloom umbral", "group": "Post"},
	"bloom_strength": {"min": 0.0, "max": 10.0, "def": 4.0, "label": "Bloom blur", "group": "Post"},
	# --- Sombras ---
	"shadow_smooth": {"min": 0.0, "max": 8.0, "def": 2.0, "label": "Sombra suavidad", "group": "Sombras"},
}

var _v: Dictionary = {}

func _ready() -> void:
	_load()

func get_v(k: String) -> float:
	return _v.get(k, DEFS[k]["def"])

func set_v(k: String, val: float) -> void:
	_v[k] = val
	changed.emit()
	_save()

func reset() -> void:
	_v.clear()
	changed.emit()
	_save()

## Color de ambiente listo para CanvasModulate.
func ambient_color() -> Color:
	return Color(get_v("amb_r"), get_v("amb_g"), get_v("amb_b"))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in data.keys():
			if DEFS.has(k):
				_v[k] = float(data[k])

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_v))
