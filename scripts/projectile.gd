extends Area2D
class_name Projectile
## Proyectil genérico (jugador y enemigos). Modelo 2.5D (z = altura visual).
## Visual: orbe glow generado (núcleo caliente + halo de color) + estela + luz.
## Los muros los frena un raycast; a las criaturas las detecta el Area2D.

static var _orb: Texture2D

var velocity := Vector2.ZERO
var damage := 12
var life := 1.2
var friendly := true
var z_height := 0.0

@onready var visual: Polygon2D = $Visual
@onready var glow: PointLight2D = $Glow

var _orb_sprite: Sprite2D
var _trail: CPUParticles2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if visual:
		visual.visible = false   # reemplazado por el orbe glow
	# Orbe (aditivo, unshaded → glow propio; el core brillante florece con el bloom).
	_orb_sprite = Sprite2D.new()
	_orb_sprite.texture = _get_orb()
	_orb_sprite.z_index = 40
	_orb_sprite.material = _add_mat()
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
	if _orb_sprite:
		_orb_sprite.position = Vector2(0, -z_height)
		_orb_sprite.scale = Vector2(0.42, 0.42)
		_orb_sprite.modulate = col * 1.8   # >1 → núcleo caliente que florece (HDR/bloom)
	if _trail:
		_trail.color = Color(col.r, col.g, col.b, 0.7)
	if glow:
		glow.color = col
		glow.texture_scale = 0.13
		glow.energy = 1.0
		if glow.texture == null:
			glow.texture = load("res://assets/fx/light_radial.tres")
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	var step := velocity * delta
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step, 1)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		queue_free()
		return
	global_position += step
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if friendly and (body is Enemy or body is Boss):
		body.take_damage(damage)
		queue_free()
	elif not friendly and body is Player:
		body.take_damage(damage, global_position)
		queue_free()

# ---------------------------------------------------------------------------
func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

## Orbe glow compartido: radial blanco→negro con núcleo apretado y caliente.
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
			var core := pow(clampf(1.0 - d, 0.0, 1.0), 6.0)   # núcleo más caliente
			var b := clampf(v + core * 0.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(b, b, b, 1.0))
	_orb = ImageTexture.create_from_image(img)
	return _orb
