class_name SpellLibrary
extends RefCounted
## Lee tools/rig/spells.json (lo escribe la tool web "Hechizos") y arma un ElementProfile por
## vara. Modo "external": el FX (estela ribbon + particulas) se SUMA al bolt existente de la
## vara, sin pisar su arte. Si una vara no esta configurada en la tool -> get_profile() = null
## -> el proyectil se comporta como hoy. Ver docs/spell_fx_plan.md y tools/spell_tool.html.

const JSON_PATH := "res://tools/rig/spells.json"
const SPELL_DIR := "res://assets/fx/spells/"

static var _data: Dictionary = {}
static var _loaded := false


## Fuerza releer el json (util si se edita en caliente desde la tool).
static func reload() -> void:
	_loaded = false
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	if not FileAccess.file_exists(JSON_PATH):
		return
	var txt := FileAccess.get_file_as_string(JSON_PATH)
	var j: Variant = JSON.parse_string(txt)
	if j is Dictionary:
		_data = j


static func _col(v: Variant, dflt: Color) -> Color:
	if typeof(v) == TYPE_STRING and (v as String).begins_with("#"):
		return Color.html(v)
	return dflt


## ElementProfile de la vara (idx 0-based) o null si no esta configurada en la tool.
static func get_profile(staff_idx: int) -> ElementProfile:
	_ensure()
	var key := str(staff_idx)
	if not _data.has(key) or typeof(_data[key]) != TYPE_DICTIONARY:
		return null
	var c: Dictionary = _data[key]
	var p := ElementProfile.new()
	p.id = StringName("staff%d" % (staff_idx + 1))
	p.core_mode = "external"   # el nucleo es el bolt de la vara (NO pisar arte)

	var cols: Dictionary = c.get("colors", {})
	p.color_core = _col(cols.get("core"), Color(1, 1, 1))
	p.color_mid = _col(cols.get("mid"), Color(0.6, 0.8, 1.0))
	p.color_tail = _col(cols.get("tail"), Color(0.1, 0.2, 0.5))
	p.color_accent = _col(cols.get("accent"), Color(0, 0, 0, 0))

	var part: Dictionary = c.get("part", {})
	p.amount = int(part.get("amount", 28))
	p.lifetime = float(part.get("life", 0.45))
	p.spread_deg = float(part.get("spread", 30.0))
	p.turbulence = float(part.get("turb", 0.0))
	p.gravity = Vector2(0.0, float(part.get("grav", 0.0)))
	p.orbit_velocity = float(part.get("orbit", 0.0))
	p.particle_scale = float(c.get("sTrail", 1.0))
	p.bolt_scale = float(c.get("sViaje", 1.0))
	p.impact_scale = float(c.get("sImpacto", 1.0))
	p.bolt_fps = float(c.get("fpsViaje", 0.0))
	p.impact_fps = float(c.get("fpsImpacto", 0.0))
	var au: Dictionary = c.get("aura", {})
	p.aura_enabled = bool(au.get("on", false))
	p.aura_boost = float(au.get("boost", 1.4))

	var lg: Dictionary = c.get("light", {})
	p.light_color = _col(lg.get("color"), p.color_mid)
	p.light_energy = float(lg.get("energy", 1.3))
	p.light_radius_scale = float(lg.get("radius", 1.0))

	var rb: Dictionary = c.get("ribbon", {})
	p.ribbon_enabled = bool(rb.get("on", true))
	p.ribbon_width = float(rb.get("width", 10.0))

	var ptex := SPELL_DIR + "staff%d/particle.png" % (staff_idx + 1)
	if ResourceLoader.exists(ptex):
		p.particle_texture = load(ptex)
	return p
