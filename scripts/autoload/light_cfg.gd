extends Node
## Fuente única de verdad de los "knobs" de iluminación (panel tecla L en el juego).
## Persiste en user://light_knobs.json. El panel de debug
## (lighting_debug.gd) edita estos valores; player/antorchas/proyectiles los leen.
## Emite `changed` para actualización en vivo.

signal changed

const SAVE_PATH := "user://light_knobs.json"

## Definición de cada knob: min, max, def, label, group. El panel se autogenera
## desde acá, así que agregar un knob = una línea.
const DEFS := {
	# --- Ambiente (CanvasModulate) --- (defaults = tuning aprobado por Felipe)
	"amb_r": {"min": 0.0, "max": 1.0, "def": 0.32, "label": "Ambient R", "group": "Ambiente"},
	"amb_g": {"min": 0.0, "max": 1.0, "def": 0.27, "label": "Ambient G", "group": "Ambiente"},
	"amb_b": {"min": 0.0, "max": 1.0, "def": 0.32, "label": "Ambient B", "group": "Ambiente"},
	"foot_ambient": {"min": 0.0, "max": 1.0, "def": 0.76, "label": "Ambiente entidades (foot)", "group": "Ambiente"},
	# --- Luz del jugador ---
	"player_energy": {"min": 0.0, "max": 4.0, "def": 1.76, "label": "Jugador energía", "group": "Jugador"},
	"player_radius": {"min": 0.1, "max": 1.5, "def": 0.506, "label": "Jugador radio", "group": "Jugador"},
	"player_height": {"min": 0.0, "max": 64.0, "def": 29.44, "label": "Jugador altura", "group": "Jugador"},
	"player_warmth": {"min": 0.0, "max": 1.0, "def": 1.0, "label": "Jugador calidez (0=blanca)", "group": "Jugador"},
	# --- Antorchas (L1) ---
	"torch_energy": {"min": 0.0, "max": 4.0, "def": 2.56, "label": "Antorcha energía", "group": "Antorchas"},
	"torch_radius": {"min": 0.2, "max": 2.5, "def": 0.798, "label": "Antorcha radio", "group": "Antorchas"},
	"torch_height": {"min": 0.0, "max": 64.0, "def": 26.24, "label": "Antorcha altura", "group": "Antorchas"},
	"torch_warmth": {"min": 0.0, "max": 1.0, "def": 0.66, "label": "Antorcha calidez (0=blanca)", "group": "Antorchas"},
	"torch_glow": {"min": 1.0, "max": 3.0, "def": 1.6, "label": "Antorcha brillo llama", "group": "Antorchas"},
	"wall_relief": {"min": 0.4, "max": 1.0, "def": 1.0, "label": "Muro: luz en plano (1=igual que piso)", "group": "Antorchas"},
	"wall_light": {"min": 1.0, "max": 4.0, "def": 2.0, "label": "Muro: fuerza de luz (boost+cap)", "group": "Antorchas"},
	# --- Direccionalidad de cara de muro iso (que la cara apague la luz del lado opuesto) ---
	"wall_face_z":     {"min": 0.0, "max": 2.0, "def": 0.6, "label": "Cara: lift de altura (bajo=back más oscuro)", "group": "Muros (luz)"},
	"wall_face_floor": {"min": 0.0, "max": 1.0, "def": 0.2, "label": "Cara: luz mín. de cara trasera (1=sin direccional)", "group": "Muros (luz)"},
	# --- Antorchas: posición/montaje sobre el borde de muro iso (tuning en vivo) ---
	"torch_flame_x":     {"min": -60.0,  "max": 60.0,  "def": 0.0,   "label": "Antorcha llama X", "group": "Antorchas (posición)"},
	"torch_flame_y":     {"min": -110.0, "max": 20.0,  "def": -40.0, "label": "Antorcha llama Y (− sube)", "group": "Antorchas (posición)"},
	"torch_light_inset": {"min": 0.0,    "max": 120.0, "def": 44.0,  "label": "Antorcha luz hacia la sala", "group": "Antorchas (posición)"},
	# --- Post-proceso (shader de pantalla) ---
	"exposure": {"min": 0.3, "max": 3.0, "def": 1.0, "label": "Exposición/Brillo (1=normal)", "group": "Post"},
	"saturation": {"min": 0.0, "max": 2.0, "def": 1.0, "label": "Saturación (1=normal)", "group": "Post"},
	# --- Sombras de muro (occluder nativo) ---
	"shadow_smooth": {"min": 0.0, "max": 8.0, "def": 2.72, "label": "Sombra muro suavidad", "group": "Sombras"},
	# --- Sombra proyectada de billboards (silueta del personaje) ---
	"cast_light_ht": {"min": 30.0, "max": 220.0, "def": 50.9, "label": "Proy. altura luz (zL)", "group": "Sombras"},
	"cast_max_len": {"min": 8.0, "max": 220.0, "def": 63.12, "label": "Proy. largo máx", "group": "Sombras"},
	"cast_alpha": {"min": 0.0, "max": 1.0, "def": 0.98, "label": "Proy. opacidad", "group": "Sombras"},
	"cast_falloff": {"min": 0.0, "max": 4.0, "def": 1.36, "label": "Proy. caída dist", "group": "Sombras"},
	"cast_width": {"min": 0.3, "max": 2.0, "def": 1.201, "label": "Proy. ancho", "group": "Sombras"},
	"cast_lift": {"min": -30.0, "max": 30.0, "def": -1.2, "label": "Proy. subir ancla (px)", "group": "Sombras"},
	"cast_blur": {"min": 0.0, "max": 8.0, "def": 2.0, "label": "Proy. difusión", "group": "Sombras"},
	"cast_blur_grow": {"min": 0.0, "max": 8.0, "def": 1.36, "label": "Proy. difusión hacia punta", "group": "Sombras"},
	"cast_tip_fade": {"min": 0.2, "max": 4.0, "def": 0.542, "label": "Proy. pérdida hacia punta", "group": "Sombras"},
	"cast_base_fade": {"min": 0.0, "max": 0.6, "def": 0.0, "label": "Proy. difumin. en la base", "group": "Sombras"},
	"cast_width_grow": {"min": 0.0, "max": 3.0, "def": 0.0, "label": "Proy. ensanche hacia la punta", "group": "Sombras"},
	# Sombra de contacto (circular, fija debajo — no depende de antorchas)
	"contact_size": {"min": 0.2, "max": 3.0, "def": 1.656, "label": "Contacto tamaño", "group": "Sombras"},
	"contact_alpha": {"min": 0.0, "max": 1.0, "def": 1.0, "label": "Contacto opacidad", "group": "Sombras"},
	"contact_flat": {"min": 0.2, "max": 1.0, "def": 0.432, "label": "Contacto achatado (1=redondo)", "group": "Sombras"},
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
