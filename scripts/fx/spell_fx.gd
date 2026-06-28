class_name SpellFX
extends Node2D
## Componente reusable de FX de hechizo. Lee un ElementProfile y arma sus 4 capas
## por codigo: nucleo (Sprite2D additive), estela (Line2D), lluvia (GPUParticles2D),
## luz (PointLight2D). Ver docs/spell_fx_plan.md.

const PARTICLES_DIR := "res://assets/fx/particles/"

@export var profile: ElementProfile

var _core: Sprite2D
var _aura: Sprite2D
var _ribbon: Line2D
var _particles: GPUParticles2D
var _light: PointLight2D
var _pts: PackedVector2Array = PackedVector2Array()
var _vel: Vector2 = Vector2.ZERO
var _base_scale: float = 1.0


func _ready() -> void:
	if profile != null:
		apply(profile)


func set_velocity(v: Vector2) -> void:
	_vel = v


func apply(p: ElementProfile) -> void:
	profile = p
	for c in get_children():
		c.queue_free()
	_pts = PackedVector2Array()
	_base_scale = profile.core_scale

	# Luz que viaja (en modo external la pone el proyectil → no duplicar)
	if profile.core_mode != "external":
		_light = PointLight2D.new()
		_light.texture = _load_tex("core_glow.png")
		_light.color = profile.light_color
		_light.energy = profile.light_energy
		_light.texture_scale = 2.0 * profile.light_radius_scale
		add_child(_light)

	# Lluvia de particulas
	_particles = GPUParticles2D.new()
	_particles.texture = _particle_texture()
	_particles.amount = maxi(1, profile.amount)
	_particles.lifetime = profile.lifetime
	_particles.local_coords = false
	_particles.material = FxMaterials.add_unshaded()
	_particles.process_material = _build_process_material()
	_particles.z_index = 37
	add_child(_particles)

	# Estela / ribbon
	if profile.ribbon_enabled:
		_ribbon = Line2D.new()
		_ribbon.top_level = true
		_ribbon.width = profile.ribbon_width
		_ribbon.width_curve = profile.ribbon_width_curve if profile.ribbon_width_curve != null else _default_width_curve()
		_ribbon.gradient = _ribbon_gradient()
		_ribbon.joint_mode = Line2D.LINE_JOINT_ROUND
		_ribbon.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_ribbon.end_cap_mode = Line2D.LINE_CAP_ROUND
		_ribbon.material = FxMaterials.add_unshaded()
		_ribbon.z_index = 38
		add_child(_ribbon)

	# Nucleo (hibrido). external = lo pone el proyectil (su bolt) → solo estela + particulas.
	if profile.core_mode == "external":
		_core = null   # el nucleo es el bolt del proyectil (su arte ya trae su glow) → sin aura
	elif profile.core_mode == "sprite" and profile.core_texture != null:
		# aura glow additive detras del arte
		_aura = Sprite2D.new()
		_aura.texture = _load_tex("core_glow.png")
		_aura.material = FxMaterials.add_unshaded()
		_aura.modulate = _hdr(profile.color_mid, profile.core_hdr_boost * 0.7)
		_aura.scale = Vector2.ONE * _base_scale * 1.7
		_aura.z_index = 39
		add_child(_aura)
		# arte con blend normal (no se tine, se ve tal cual)
		_core = Sprite2D.new()
		_core.texture = profile.core_texture
		_core.material = FxMaterials.mix_unshaded()
		_core.modulate = Color(1, 1, 1, 1)
		_core.scale = Vector2.ONE * _base_scale
		_core.z_index = 40
		add_child(_core)
	else:
		_core = Sprite2D.new()
		_core.texture = _load_tex("core_glow.png")
		_core.material = FxMaterials.add_unshaded()
		var body := profile.color_mid.lerp(Color(1, 1, 1), 0.35)
		_core.modulate = _hdr(body, profile.core_hdr_boost)
		_core.scale = Vector2.ONE * _base_scale
		_core.z_index = 40
		add_child(_core)


func _process(delta: float) -> void:
	if profile == null:
		return
	# Estela: empuja posiciones en espacio-mundo
	if _ribbon != null and is_instance_valid(_ribbon):
		_pts.append(global_position)
		while _pts.size() > maxi(2, profile.ribbon_points):
			_pts.remove_at(0)
		_ribbon.points = _pts
	# Nucleo: orienta + squash&stretch por velocidad
	if _core != null and is_instance_valid(_core):
		if _vel.length() > 1.0:
			_core.rotation = _vel.angle()
		var s := _base_scale
		if profile.stretch_by_velocity > 0.0:
			var k := clampf(_vel.length() / 320.0, 0.0, 1.0) * profile.stretch_by_velocity
			_core.scale = Vector2(s * (1.0 + k), s * (1.0 - 0.4 * k))
		else:
			_core.scale = Vector2.ONE * s
	# Luz: flicker opcional
	if _light != null and is_instance_valid(_light) and profile.light_flicker > 0.0:
		var f := 1.0 - profile.light_flicker * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02))
		_light.energy = profile.light_energy * f


# ---------- helpers ----------
func _hdr(c: Color, boost: float) -> Color:
	return Color(c.r * boost, c.g * boost, c.b * boost, 1.0)


func _load_tex(fname: String) -> Texture2D:
	return load(PARTICLES_DIR + fname) as Texture2D


func _particle_texture() -> Texture2D:
	if profile.particle_texture != null:
		return profile.particle_texture
	return _load_tex("spark.png")


func _core_texture() -> Texture2D:
	if profile.core_mode == "sprite" and profile.core_texture != null:
		return profile.core_texture
	return _load_tex("core_glow.png")


func _ribbon_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(profile.color_tail.r, profile.color_tail.g, profile.color_tail.b, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, profile.color_mid)
	return g


func _default_width_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.12))
	c.add_point(Vector2(1.0, 1.0))
	return c


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 2.5
	m.spread = profile.spread_deg
	m.direction = Vector3(0, 0, 0)
	m.gravity = Vector3(profile.gravity.x, profile.gravity.y, 0.0)
	m.initial_velocity_min = profile.speed_min
	m.initial_velocity_max = profile.speed_max
	m.scale_min = 0.4 * profile.particle_scale
	m.scale_max = 1.1 * profile.particle_scale
	m.scale_curve = _scale_curve_tex()
	m.color_ramp = _ramp_tex()
	if profile.turbulence > 0.0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = profile.turbulence
		m.turbulence_noise_scale = 1.5
	if profile.orbit_velocity != 0.0:
		m.orbit_velocity_min = profile.orbit_velocity
		m.orbit_velocity_max = profile.orbit_velocity
	return m


func _ramp_tex() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, profile.color_core)
	g.set_offset(1, 1.0)
	g.set_color(1, Color(profile.color_tail.r, profile.color_tail.g, profile.color_tail.b, 0.0))
	g.add_point(0.35, profile.color_mid)
	if profile.color_accent.a > 0.0:
		g.add_point(0.62, profile.color_accent)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _scale_curve_tex() -> CurveTexture:
	var c: Curve
	if profile.scale_curve != null:
		c = profile.scale_curve
	else:
		c = Curve.new()
		c.add_point(Vector2(0.0, 0.5))
		c.add_point(Vector2(0.18, 1.0))
		c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t
