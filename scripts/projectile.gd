extends Area2D
class_name Projectile
## Proyectil genérico (jugador y enemigos). Modelo 2.5D (z = altura visual).
## Los muros los frena un raycast (sin solapamiento); a las criaturas las
## detecta el Area2D según `friendly`.

var velocity := Vector2.ZERO
var damage := 12
var life := 1.2
var friendly := true
var z_height := 0.0

@onready var visual: Polygon2D = $Visual

func setup(pos: Vector2, dir: Vector2, dmg: int, is_friendly := true, spd := 260.0) -> void:
	global_position = pos
	velocity = dir.normalized() * spd
	damage = dmg
	friendly = is_friendly
	collision_mask = 4 if friendly else 2   # capa 3 (enemigos) vs capa 2 (jugador)
	if visual:
		visual.position = Vector2(0, -z_height)
		visual.color = Color(0.6, 0.95, 1.0) if friendly else Color(1.0, 0.55, 0.25)
	reset_physics_interpolation()

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := velocity * delta
	# Raycast contra el mundo (capa 1): frena en la superficie del muro.
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
