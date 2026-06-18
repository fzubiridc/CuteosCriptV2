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

func _ready() -> void:
	body_entered.connect(_on_body_entered)
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
	_trail.material = _add_mat()
	add_child(_trail)

func setup(pos: Vector2, dir: Vector2, dmg: int, is_friendly := true, spd := 260.0, tint := Color(0, 0, 0, 0)) -> void:
	global_position = pos
	velocity = dir.normalized() * spd
	damage = dmg
	friendly = is_friendly
	collision_mask = 4 if friendly else 2   # capa 3 (enemigos) vs capa 2 (jugador)
	var col := tint
	if col.a <= 0.0:
		col = Color(0.55, 0.9, 1.0) if friendly else Color(1.0, 0.55, 0.25)
	_use_power = friendly
	if _orb_sprite:
		_orb_sprite.position = Vector2(0, -z_height)
		if _use_power:
			# Orbe = animación `power` del pixi (arte propio, rotado a la dirección).
			_orb_sprite.texture = _get_power_frames()[0]
			_orb_sprite.material = _mix_mat()
			_orb_sprite.modulate = Color.WHITE
			_orb_sprite.scale = Vector2(0.6, 0.6)     # 40px → 24px (S = size/20, pixi)
			_orb_sprite.rotation = velocity.angle()
		else:
			_orb_sprite.texture = _get_orb()
			_orb_sprite.material = _add_mat()
			_orb_sprite.modulate = col * 1.8
			_orb_sprite.scale = Vector2(0.42, 0.42)
	if _trail:
		_trail.position = Vector2(0, -z_height)   # estela a la altura visual del orbe
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
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	_t += delta
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
	if not hit.is_empty():
		global_position = hit.position
		_impact()
		queue_free()
		return
	global_position += step
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if friendly and body is Enemy:
		body.take_damage(damage, velocity.normalized() * BOLT_KB)   # empuje
		_impact()
		queue_free()
	elif friendly and body is Boss:
		body.take_damage(damage)   # el jefe no recibe knockback
		_impact()
		queue_free()
	elif not friendly and body is Player:
		body.take_damage(damage, global_position)
		queue_free()

## Impacto del orbe del mago: sfx 'boom' + explosión `powerboom` (queda en la escena).
func _impact() -> void:
	if not friendly:
		return
	Audio.play("boom", -6.0)
	var boom := AnimatedSprite2D.new()
	boom.sprite_frames = _get_boom_frames()
	boom.animation = "boom"
	boom.scale = Vector2(0.85, 0.85)
	boom.z_index = 41
	boom.material = _mix_mat()
	boom.global_position = global_position + Vector2(0, -z_height)
	boom.play("boom")
	boom.animation_finished.connect(boom.queue_free)
	get_parent().add_child(boom)
	# Luz de explosión: flash que se retiene un poco y se apaga (brasa).
	var lt := PointLight2D.new()
	lt.texture = load("res://assets/fx/light_radial.tres")
	lt.color = Color(0.55, 0.6, 1.0)
	lt.energy = 3.2
	lt.texture_scale = 0.7
	lt.global_position = global_position + Vector2(0, -z_height)
	get_parent().add_child(lt)
	var tw := lt.create_tween()
	tw.tween_property(lt, "energy", 1.4, 0.10)                              # flash → brasa
	tw.tween_property(lt, "energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)     # se apaga
	tw.tween_callback(lt.queue_free)

# ---------------------------------------------------------------------------
func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

func _mix_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED   # arte con glow propio
	return m

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
