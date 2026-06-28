extends Node2D
## Banco de pruebas AISLADO del trail (F1 / FX Lab). Abri esta escena y dale Play (F6).
## NO toca projectile.gd ni el juego. Ver docs/spell_fx_plan.md.

var _fuego: SpellFX
var _arcano: SpellFX
var _t: float = 0.0


func _ready() -> void:
	# Fondo oscuro (para leer el additive)
	var cl := CanvasLayer.new()
	cl.layer = -10
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.10)
	cl.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Camara centrada
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()

	# Dos trails: fuego + arcano
	_fuego = SpellFX.new()
	_fuego.profile = _profile_fuego()
	add_child(_fuego)

	_arcano = SpellFX.new()
	_arcano.profile = _profile_arcano()
	add_child(_arcano)

	# Glow / bloom al final (si fallara, los trails igual se ven)
	_setup_glow()


func _process(delta: float) -> void:
	_t += delta
	_move(_fuego, Vector2(cos(_t * 1.3) * 240.0, sin(_t * 0.9) * 130.0), delta)
	_move(_arcano, Vector2(sin(_t * 1.05) * 240.0, cos(_t * 1.6) * 130.0), delta)


func _move(fx: SpellFX, target: Vector2, delta: float) -> void:
	if fx == null:
		return
	var prev := fx.global_position
	fx.global_position = target
	fx.set_velocity((target - prev) / maxf(delta, 0.0001))


func _setup_glow() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.1
	env.set_glow_level(1, 0.7)
	env.set_glow_level(2, 0.5)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.2)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _profile_fuego() -> ElementProfile:
	var p := ElementProfile.new()
	p.id = &"fuego"
	p.color_core = Color(1.0, 0.92, 0.66)
	p.color_mid = Color(1.0, 0.46, 0.12)
	p.color_tail = Color(0.42, 0.10, 0.02)
	p.core_hdr_boost = 1.4
	p.core_mode = "sprite"
	p.core_texture = load("res://assets/fx/projectiles/fireball.png")
	p.core_scale = 0.9
	p.amount = 48
	p.lifetime = 0.6
	p.spread_deg = 55.0
	p.speed_min = 6.0
	p.speed_max = 30.0
	p.gravity = Vector2(0.0, -75.0)
	p.turbulence = 2.4
	p.ribbon_width = 11.0
	p.light_color = Color(1.0, 0.5, 0.18)
	p.light_energy = 1.5
	p.stretch_by_velocity = 0.6
	p.light_flicker = 0.35
	return p


func _profile_arcano() -> ElementProfile:
	var p := ElementProfile.new()
	p.id = &"arcano"
	p.color_core = Color(0.92, 0.86, 1.0)
	p.color_mid = Color(0.69, 0.31, 1.0)
	p.color_tail = Color(0.23, 0.06, 0.48)
	p.color_accent = Color(0.45, 0.85, 1.0, 1.0)
	p.core_hdr_boost = 1.4
	p.core_mode = "sprite"
	p.core_texture = load("res://assets/fx/projectiles/arcane_orb.png")
	p.core_scale = 0.95
	p.amount = 38
	p.lifetime = 0.6
	p.spread_deg = 20.0
	p.speed_min = 6.0
	p.speed_max = 22.0
	p.gravity = Vector2.ZERO
	p.turbulence = 0.5
	p.orbit_velocity = 48.0
	p.ribbon_width = 10.0
	p.light_color = Color(0.7, 0.4, 1.0)
	p.light_energy = 1.35
	p.stretch_by_velocity = 0.5
	p.light_flicker = 0.12
	return p
