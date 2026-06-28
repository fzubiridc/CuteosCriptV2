class_name AbilityDefs
extends RefCounted
## Registro data-driven de habilidades asignables a la barra de acción (slots 1-4).
## Cada def: name, desc, cooldown (s), mana, color (para el ícono placeholder), icon (opcional).
## El EFECTO de cada una vive en player.gd (`_cast_ability(id)`), así la lógica de combate
## queda en un solo lugar; este archivo es solo datos + el ícono.
##
## ARTE: si existe res://assets/ui/skills/<id>.png se usa como ícono; si no, se genera una gema
## del color de la habilidad (placeholder para que Felipe lo reemplace — ver art-vs-logic).

const LIST := {
	"meteor": {
		"name": "Meteoro", "color": Color(1.0, 0.5, 0.15),
		"cooldown": 3.0, "mana": 35.0,
		"desc": "Invoca un meteoro de fuego en el cursor (daño en área).",
	},
	"nova": {
		"name": "Nova Arcana", "color": Color(0.5, 0.8, 1.0),
		"cooldown": 6.0, "mana": 32.0,
		"desc": "Descarga de orbes arcanos en todas las direcciones.",
	},
	"heal": {
		"name": "Toque Sanador", "color": Color(0.55, 1.0, 0.65),
		"cooldown": 14.0, "mana": 45.0,
		"desc": "Convierte maná en vida al instante.",
	},
	"blink": {
		"name": "Parpadeo", "color": Color(0.78, 0.6, 1.0),
		"cooldown": 4.0, "mana": 18.0,
		"desc": "Teletransporte veloz hacia el cursor (atraviesa el hueco, no los muros).",
	},
	"frost": {
		"name": "Estallido Glacial", "color": Color(0.6, 0.92, 1.0),
		"cooldown": 8.0, "mana": 40.0,
		"desc": "Onda de hielo que daña y frena a los enemigos cercanos.",
	},
	"dash": {
		"name": "Impulso", "color": Color(0.85, 0.85, 0.95),
		"cooldown": 0.0, "mana": 0.0,   # cooldown/coste reales los maneja el dash clásico (Espacio)
		"desc": "Esquive rápido en la dirección de movimiento.",
	},
}

## Orden por defecto de los 4 slots de la barra (ids de LIST). "" = slot vacío.
const DEFAULT_SLOTS := ["meteor", "nova", "blink", "heal"]

## Ids de todas las habilidades, en orden estable (para el panel de asignación).
static func ids() -> Array:
	return ["meteor", "nova", "frost", "blink", "heal", "dash"]

static func has(id: String) -> bool:
	return LIST.has(id)

static func get_def(id: String) -> Dictionary:
	return LIST.get(id, {})

# --- Íconos -------------------------------------------------------------------
static var _icon_cache := {}

## Ícono de la habilidad: el PNG del autor si existe, o una gema generada del color de la
## habilidad (placeholder). Cacheado por id.
static func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	var path := "res://assets/ui/skills/%s.png" % id
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		tex = _gem(get_def(id).get("color", Color(0.7, 0.7, 0.8)))
	_icon_cache[id] = tex
	return tex

## Gema radial placeholder: núcleo brillante del color + halo, sobre fondo transparente.
static func _gem(col: Color) -> Texture2D:
	var s := 48
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	var maxd := s / 2.0 - 1.0
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / maxd
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var core := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			var rim := smoothstep(0.78, 0.98, d) * 0.7   # aro un poco más claro en el borde
			var rgb := col.lerp(Color.WHITE, core * 0.55 + rim)
			var a := clampf(0.25 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return ImageTexture.create_from_image(img)
