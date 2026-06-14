extends CharacterBody2D
class_name Enemy
## Enemigo data-driven (F4). Tipo/stats desde Data.ENEMIES. Tres IAs:
## chaser (persigue), erratic (zigzag), shooter (mantiene distancia y dispara).
## Aggro híbrido: despierta por sala o proximidad, persigue, leash a casa.

const TILE := 16.0
const PROJECTILE := preload("res://scenes/projectile.tscn")

# Stats (las setea setup_type desde Data.ENEMIES):
var type_key := "rata"
var ai := "chaser"
var max_hp := 30
var damage := 8
var speed := 60.0
var size := 8.0
var atk_range := 0.0
var fire_cd := 1.5
var proj_spd := 150.0
var elite := false
var base_color := Color(0.85, 0.3, 0.35)

# Aggro (asignados por main.gd):
var home_pos := Vector2.ZERO
var home_rect := Rect2()

var hp := 30
var aggro := false
var hit_cd := 0.0
var flash_t := 0.0
var fire_t := 0.0
var wander_t := 0.0
var wander_target := Vector2.ZERO
var wobble := 0.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	wander_target = home_pos
	agent.path_desired_distance = 4.0
	agent.target_desired_distance = 6.0

func setup_type(key: String, is_elite := false) -> void:
	type_key = key
	var d: Dictionary = Data.ENEMIES.get(key, {})
	ai = String(d.get("ai", "chaser"))
	max_hp = int(d.get("hp", 30))
	damage = int(d.get("dmg", 8))
	speed = float(d.get("spd", 60)) * float(Data.BALANCE.speed_mul)
	size = float(d.get("size", 8))
	atk_range = float(d.get("range", 0.0))
	fire_cd = float(d.get("fire_cd", 1.5))
	proj_spd = float(d.get("proj_spd", 150.0))
	elite = is_elite
	if elite:
		max_hp = int(max_hp * 1.5)
		damage = int(damage * 1.3)
		size *= 1.3
	hp = max_hp
	_apply_visual()

func _apply_visual() -> void:
	base_color = _ai_color()
	if visual:
		visual.color = base_color
		visual.polygon = PackedVector2Array([
			Vector2(-size, -size), Vector2(size, -size),
			Vector2(size, size), Vector2(-size, size)])
	var sh := CircleShape2D.new()
	sh.radius = size
	$Shape.shape = sh

func _ai_color() -> Color:
	var c := Color(0.85, 0.3, 0.35)        # chaser: rojo
	match ai:
		"erratic": c = Color(0.7, 0.4, 0.9)   # morado
		"shooter": c = Color(0.95, 0.6, 0.2)  # naranja
	if elite:
		c = c.lerp(Color(1.0, 0.95, 0.5), 0.4)
	return c

func _physics_process(delta: float) -> void:
	hit_cd = maxf(0.0, hit_cd - delta)
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		if flash_t == 0.0:
			visual.color = base_color

	var player := GameState.player
	if player == null:
		return
	var ppos: Vector2 = player.global_position
	var to_player := global_position.distance_to(ppos)

	_update_aggro(ppos, to_player)

	var target_pos := home_pos
	var move_speed := speed * float(Data.BALANCE.wander_speed)
	if aggro:
		move_speed = speed
		if ai == "shooter":
			target_pos = _shooter_target(ppos, to_player)
			_shooter_fire(delta, ppos, to_player)
		else:
			target_pos = ppos
	else:
		target_pos = _wander_point(delta)

	agent.target_position = target_pos
	var next := agent.get_next_path_position()
	var dir := next - global_position
	if global_position.distance_to(target_pos) > 6.0 and dir.length() > 1.0:
		velocity = dir.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

	# Zigzag para los erratic.
	if aggro and ai == "erratic" and velocity.length() > 1.0:
		wobble += delta * 9.0
		var perp := Vector2(-velocity.y, velocity.x).normalized()
		velocity += perp * sin(wobble) * move_speed * 0.6

	move_and_slide()

	# Daño por contacto (solo despierto y pegado).
	if aggro and to_player < size + 8.0 and hit_cd <= 0.0:
		hit_cd = 0.8
		player.take_damage(damage, global_position)

func _update_aggro(ppos: Vector2, to_player: float) -> void:
	if aggro:
		if home_pos.distance_to(ppos) > float(Data.BALANCE.leash_tiles) * TILE and not home_rect.has_point(ppos):
			aggro = false
	elif home_rect.has_point(ppos) or to_player < float(Data.BALANCE.aggro_radius) * TILE * 0.55:
		aggro = true

func _wander_point(delta: float) -> Vector2:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = Rng.range_f(1.5, 3.0)
		if home_rect.has_area():
			wander_target = Vector2(
				Rng.range_f(home_rect.position.x, home_rect.end.x),
				Rng.range_f(home_rect.position.y, home_rect.end.y))
		else:
			wander_target = home_pos
	return wander_target

func _shooter_target(ppos: Vector2, to_player: float) -> Vector2:
	var ideal := atk_range * 0.65
	if to_player < ideal * 0.85:
		return global_position + (global_position - ppos).normalized() * 60.0  # retroceder
	elif to_player > ideal * 1.15:
		return ppos  # acercarse
	return global_position  # mantener distancia

func _shooter_fire(delta: float, ppos: Vector2, to_player: float) -> void:
	fire_t = maxf(0.0, fire_t - delta)
	if to_player <= atk_range and fire_t <= 0.0:
		fire_t = fire_cd
		var p := PROJECTILE.instantiate()
		get_parent().add_child(p)
		p.setup(global_position, (ppos - global_position).normalized(), damage, false, proj_spd)

func take_damage(amount: int) -> void:
	hp -= amount
	aggro = true   # pegarle lo despierta
	flash_t = 0.08
	visual.color = Color(1, 1, 1)
	GameState.floater(global_position, str(amount), Color(1, 0.9, 0.5))
	if hp <= 0:
		_die()

func _die() -> void:
	GameState.run["kills"] = int(GameState.run.get("kills", 0)) + 1
	GameState.drop_loot(global_position, maxi(2, max_hp / 4))
	GameState.enemy_killed.emit(self)
	queue_free()
