extends Area2D
class_name Projectile
## Proyectil genérico (jugador y enemigos). Modelo 2.5D (z = altura visual).
## El del MAGO usa la animación real del pixi: orbe = `power` (4 frames, rotado a la
## dirección, ~90ms/frame, se difumina al final) e impacto = explosión `powerboom`.
## Los enemigos usan el orbe glow generado. Estela + luz + sfx cast/boom.

static var _orb: Texture2D
static var _power_frames: Array = []
static var _boom_frames: SpriteFrames

const BOLT_KB := 140.0   # empuje del bolt al pegarle a un mob
const FRIENDLY_COL := Color(0.55, 0.9, 1.0)   # azul del orbe del jugador: viaje + impacto + disco (congruente)

var velocity := Vector2.ZERO
var damage := 12
var life := 1.2
var friendly := true
var z_height := 0.0

@onready var visual: Polygon2D = $Visual
@onready var glow: PointLight2D = $Glow

var _orb_sprite: Sprite2D
var _trail: CPUParticles2D
var _use_power := false
var _t := 0.0

# Descenso-a-objetivo (bolt del jugador): la altura visual baja LINEAL de _z0 a 0 a lo
# largo de _land px → el orbe va en RECTA de la punta al piso en el punto clickeado, donde
# converge con su luz. Los enemigos NO lo usan (_arc=false → vuelan recto a z constante).
var _arc := false
var _z0 := 0.0
var _traveled := 0.0
var _land := 1.0

# Anti doble-impacto: si el raycast de muro y body_entered caen en el MISMO frame, el FX/daño
# se dispararían dos veces. Al primer impacto seteamos _dead y ambos handlers cortan.
var _dead := false
# Escala del charco elíptico de piso (LightCfg.floor_scale()). Se usa cada frame en el glow,
# así que la cacheamos y solo la recomputamos cuando cambian los knobs (señal LightCfg.changed),
# en vez de llamar floor_scale() ~por frame.
var _floor_scale := Vector2.ONE

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_floor_scale = LightCfg.floor_scale()
	LightCfg.changed.connect(_on_light_cfg_changed)
	if visual:
		visual.visible = false
	_orb_sprite = Sprite2D.new()
	_orb_sprite.z_index = 40
	add_child(_orb_sprite)
	# Estela: partículas que quedan en el mundo y se desvanecen detrás del orbe.
	_trail = CPUParticles2D.new()
	_trail.texture = _get_orb()
	_trail.amount = 12
	_trail.lifetime = 0.26
	_trail.local_coords = false
	_trail.spread = 0.0
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.0
	_trail.gravity = Vector2.ZERO
	_trail.scale_amount_min = 0.10
	_trail.scale_amount_max = 0.16
	_trail.z_index = 38
	_trail.material = FxMaterials.add_unshaded()
	add_child(_trail)

## Knob de iluminación cambiado (tecla L) → recachear la escala del charco de piso.
func _on_light_cfg_changed() -> void:
	_floor_scale = LightCfg.floor_scale()

func setup(pos: Vector2, dir: Vector2, dmg: int, is_friendly := true, spd := 260.0, tint := Color(0, 0, 0, 0)) -> void:
	global_position = pos
	velocity = dir.normalized() * spd
	damage = dmg
	friendly = is_friendly
	collision_mask = 4 if friendly else 2   # capa 3 (enemigos) vs capa 2 (jugador)
	var col := tint
	if col.a <= 0.0:
		col = FRIENDLY_COL if friendly else Color(1.0, 0.55, 0.25)
	_use_power = friendly
	# z_height = altura en px de MUNDO (gap pies→punta). El orbe y la estela son hijos
	# de este Area2D, que en ISO lleva scale=1.6 (orbe más grande). Si dejáramos el offset
	# en (0,-z_height), esa escala lo multiplicaría → el orbe saldría 1.6× arriba de la
	# punta ("de arriba"). Dividir por scale.y cancela la escala en el eje vertical, así
	# el orbe sale EXACTO de la punta y conserva su tamaño 1.6×. (boom/luz en _impact usan
	# global_position sobre nodos NO escalados → ahí z_height va directo.)
	var voff := Vector2(0.0, -z_height / scale.y)
	if _orb_sprite:
		_orb_sprite.position = voff
		if _use_power:
			# Orbe = animación `power` del pixi (arte propio, rotado a la dirección).
			_orb_sprite.texture = _get_power_frames()[0]
			_orb_sprite.material = FxMaterials.mix_unshaded()
			_orb_sprite.modulate = Color.WHITE
			_orb_sprite.scale = Vector2(0.6, 0.6)     # 40px → 24px (S = size/20, pixi)
			_orb_sprite.rotation = velocity.angle()
		else:
			_orb_sprite.texture = _get_orb()
			_orb_sprite.material = FxMaterials.add_unshaded()
			_orb_sprite.modulate = col * 1.8
			_orb_sprite.scale = Vector2(0.42, 0.42)
	if _trail:
		_trail.position = voff   # misma altura visual que el orbe (compensada por scale)
		if friendly:
			# Chispas arcanas del pixi: azul → violeta que se desvanece.
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			ramp.colors = PackedColorArray([
				Color(0.49, 0.78, 1.0, 0.85), Color(0.69, 0.31, 1.0, 0.6),
				Color(0.69, 0.31, 1.0, 0.0)])
			_trail.color_ramp = ramp
			_trail.color = Color(1, 1, 1, 1)
		else:
			_trail.color = Color(col.r, col.g, col.b, 0.7)
	if glow:
		glow.color = col
		glow.texture_scale = 0.42   # ilumina el piso a su paso (ref. pixi)
		glow.energy = 1.5
		if glow.texture == null:
			glow.texture = load("res://assets/fx/light_radial.tres")
		# Reflejo en el piso ELÍPTICO: mismo achatado que la sombra de contacto del
		# jugador (LightCfg "contact_flat", cast_shadow.gd). Tuneás ese knob → cambian
		# los dos juntos. scale local (el padre lleva 1.6 uniforme → conserva la proporción).
		glow.scale = _floor_scale   # cacheado (se actualiza por señal LightCfg.changed)
	reset_physics_interpolation()

## Descenso recto a objetivo: el orbe baja LINEAL de z0 (gap pies→punta, en el spawn) a 0
## a lo largo de land_dist px, tocando el piso en el punto clickeado. Llamar DESPUÉS de setup().
func set_arc(z0: float, land_dist: float) -> void:
	_arc = true
	_z0 = z0
	_land = maxf(land_dist, 1.0)
	z_height = z0

func _physics_process(delta: float) -> void:
	_t += delta
	if glow:
		glow.scale = _floor_scale   # cacheado; se recachea por señal al mover los knobs (tecla L)
	if _arc:
		# Altura visual baja LINEAL con la distancia → el orbe describe una RECTA de la punta
		# al piso (z=0) en el objetivo, donde converge con su luz/sombra (que va en el piso).
		var at: float = clampf(_traveled / _land, 0.0, 1.0)
		z_height = _z0 * (1.0 - at)
		var voff := Vector2(0.0, -z_height / scale.y)
		if _orb_sprite: _orb_sprite.position = voff
		if _trail: _trail.position = voff
	if _use_power and _orb_sprite:
		var frames := _get_power_frames()
		if not frames.is_empty():
			_orb_sprite.texture = frames[int(_t * 1000.0 / 90.0) % frames.size()]
		_orb_sprite.rotation = velocity.angle()
		var f: float = clampf(life * 3.5, 0.0, 1.0)   # difumina en el último tramo
		_orb_sprite.modulate.a = f
		var sh: float = 0.85 + f * 0.15
		_orb_sprite.scale = Vector2(0.6, 0.6) * sh
	var step := velocity * delta
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, 1)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and not _dead:
		_dead = true
		global_position = hit.position
		_impact(true)   # raycast (mask=1) = muro/geometría → suma el disco azul sobre la pared
		queue_free()
		return
	global_position += step
	if _arc:
		_traveled += step.length()
		if _traveled >= _land:   # tocó el piso en el objetivo → explota igual que un impacto
			z_height = 0.0       # a ras de piso (donde convergió el orbe con su luz)
			_impact()
			queue_free()
			return
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _dead:   # ya impactó este frame (raycast de muro u otro body) → no dupliques FX/daño
		return
	if friendly and body is Enemy:
		_dead = true
		body.take_damage(damage, velocity.normalized() * BOLT_KB)   # empuje
		_impact()
		queue_free()
	elif friendly and body is Boss:
		_dead = true
		body.take_damage(damage)   # el jefe no recibe knockback
		_impact()
		queue_free()
	elif not friendly and body is Player:
		_dead = true
		body.take_damage(damage, global_position)
		queue_free()

## Impacto del orbe del mago: sfx 'boom' + explosión `powerboom` + luz (ilumina el piso).
## TODO el FX sale a la altura REAL del orbe (z_height al impactar) → como el bolt baja en
## recta, pega el muro a distinta altura según dónde lo intercepte, y la explosión cae ahí.
## Contra un MURO (on_wall) suma un disco azul aditivo POR ENCIMA (z alto): las caras de
## muro son UNSHADED y no reciben la luz del impacto, así que sin esto el destello no se
## vería sobre la pared. El disco no toca el muro: se dibuja sobre él (capa superior).
func _impact(on_wall := false) -> void:
	if not friendly:
		return
	Audio.play("boom", -6.0)
	var fx_pos := global_position + Vector2(0.0, -z_height)
	var boom := AnimatedSprite2D.new()
	boom.sprite_frames = _get_boom_frames()
	boom.animation = "boom"
	boom.scale = Vector2(0.85, 0.85)
	boom.z_index = 41
	boom.material = FxMaterials.mix_unshaded()
	boom.global_position = fx_pos
	boom.play("boom")
	boom.animation_finished.connect(boom.queue_free)
	get_parent().add_child(boom)
	# Luz de explosión: flash que se retiene un poco y se apaga (brasa). Ilumina el PISO.
	# Mismo azul que el orbe en viaje (FRIENDLY_COL) y energy MODERADA: con energy alta (3.2)
	# el azul se saturaba a BLANCO; a ~1.6 conserva el tono, congruente con la luz de viaje.
	var fx_col := FRIENDLY_COL
	var lt := PointLight2D.new()
	lt.texture = load("res://assets/fx/light_radial.tres")
	lt.color = fx_col
	lt.energy = 1.6
	lt.texture_scale = 0.7
	lt.scale = LightCfg.floor_scale()   # charco elíptico (vista 3/4), como las demás luces de piso
	lt.global_position = fx_pos
	get_parent().add_child(lt)
	var tw := lt.create_tween()
	tw.tween_property(lt, "energy", 0.9, 0.10)                              # flash → brasa
	tw.tween_property(lt, "energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)     # se apaga
	tw.tween_callback(lt.queue_free)
	# Contra muro: disco azul aditivo por encima (z=42) → se ve sobre la cara unshaded, a la
	# misma altura real que el orbe (donde tocó la pared). Es lo que la luz no puede hacer.
	if on_wall:
		var fl := Sprite2D.new()
		fl.texture = load("res://assets/fx/light_radial.tres")
		fl.material = FxMaterials.add_unshaded()   # ADD + unshaded → suma destello azul sobre la pared
		fl.modulate = Color(fx_col.r, fx_col.g, fx_col.b, 0.9)  # mismo azul que la luz del piso, con transparencia
		fl.z_index = 42                           # capa superior: por delante de la cara del muro
		fl.scale = Vector2(0.6, 0.6)
		fl.global_position = fx_pos
		get_parent().add_child(fl)
		var tf := fl.create_tween()
		tf.tween_property(fl, "modulate:a", 0.0, 0.32).set_ease(Tween.EASE_OUT)
		tf.tween_callback(fl.queue_free)

# ---------------------------------------------------------------------------
## Frames de la animación `power` (orbe del mago), compartidos.
static func _get_power_frames() -> Array:
	if not _power_frames.is_empty():
		return _power_frames
	for i in 4:
		var t := load("res://assets/hero/mage/power/south_%d.png" % i) as Texture2D
		if t != null:
			_power_frames.append(t)
	return _power_frames

## SpriteFrames de la explosión `powerboom` (8 frames, no-loop, ~0.5s), compartido.
static func _get_boom_frames() -> SpriteFrames:
	if _boom_frames != null:
		return _boom_frames
	var sf := SpriteFrames.new()
	sf.add_animation("boom")
	sf.set_animation_loop("boom", false)
	sf.set_animation_speed("boom", 16.0)   # 8 frames en ~0.5s
	for i in 8:
		var t := load("res://assets/hero/mage/powerboom/south_%d.png" % i) as Texture2D
		if t != null:
			sf.add_frame("boom", t)
	_boom_frames = sf
	return _boom_frames

## Orbe glow generado (para proyectiles enemigos): radial con núcleo caliente.
static func _get_orb() -> Texture2D:
	if _orb != null:
		return _orb
	var s := 32
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s / 2.0)
			var v := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			var core := pow(clampf(1.0 - d, 0.0, 1.0), 6.0)
			var b := clampf(v + core * 0.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(b, b, b, 1.0))
	_orb = ImageTexture.create_from_image(img)
	return _orb
