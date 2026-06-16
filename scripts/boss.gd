extends CharacterBody2D
class_name Boss
## Jefe. Máquina de patrones (chase/charge/burst/spread/summon) + enrage al 50%.
## F8e: sprite real — bucle usa sheets rugby animadas (idle/run); liche y
## golem_anciano usan su PNG estático. Fallback a Polygon2D si no hay set.

const TILE := 16.0
const PROJECTILE := preload("res://scenes/projectile.tscn")
const ENEMY := preload("res://scenes/enemy.tscn")
const PAT_DUR := {"chase": 2.5, "charge": 1.8, "burst": 3.2, "spread": 3.0, "summon": 4.5}
const BOSS_SETS := {"bucle": "boss", "liche": "liche", "golem_anciano": "golem_anciano"}

var boss_key := "liche"
var boss_name := "Jefe"
var patterns: Array = ["chase"]
var max_hp := 500
var hp := 500
var damage := 16
var speed := 50.0
var size := 16.0
var proj_spd := 150.0
var minion := ""
var use_sprite := false

var pat_idx := 0
var pat_t := 0.0
var sub_t := 0.0
var enraged := false
var flash_t := 0.0
var base_color := Color(0.9, 0.25, 0.5)

var charge_phase := ""
var charge_timer := 0.0
var charge_dir := Vector2.ZERO

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var visual: Polygon2D = $Visual
@onready var sprite: AnimatedSprite2D = $Sprite

func setup_boss(key: String) -> void:
	boss_key = key
	var d: Dictionary = Data.BOSSES.get(key, {})
	boss_name = String(d.get("name", "Jefe"))
	max_hp = int(d.get("hp", 500))
	damage = int(d.get("dmg", 16))
	speed = float(d.get("spd", 50)) * float(Data.BALANCE.speed_mul)
	size = float(d.get("size", 16))
	proj_spd = float(d.get("proj_spd", 150))
	minion = String(d.get("minion", ""))
	patterns = d.get("patterns", ["chase"])
	hp = max_hp
	_apply_visual()
	_start_pattern()
	GameState.boss_spawned.emit(self)
	GameState.boss_hp_changed.emit(hp, max_hp)

func _ready() -> void:
	agent.path_desired_distance = 4.0
	agent.target_desired_distance = 8.0

func _apply_visual() -> void:
	var sh := CircleShape2D.new()
	sh.radius = size
	$Shape.shape = sh
	FootShadow.attach(self, size * 0.85, size * 2.6)
	if sprite.material == null:   # foot-light: unshaded, tintado por LightField
		var fm := CanvasItemMaterial.new()
		fm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = fm
		visual.material = fm
	var sprite_set: String = BOSS_SETS.get(boss_key, "")
	if sprite_set != "":
		var sf = load("res://assets/boss/%s_frames.tres" % sprite_set)
		if sf != null:
			sprite.sprite_frames = sf
			var fh := 54.0
			var t0 = sf.get_frame_texture("idle", 0)
			if t0 != null:
				fh = float(t0.get_height())
			var s := (size * 2.8) / fh
			sprite.scale = Vector2(s, s)
			sprite.visible = true
			visual.visible = false
			use_sprite = true
			sprite.play("idle")
	if not use_sprite:
		visual.visible = true
		visual.color = base_color
		visual.polygon = PackedVector2Array([
			Vector2(-size, -size), Vector2(size, -size),
			Vector2(size, size), Vector2(-size, size)])

func _base_tint() -> Color:
	if use_sprite:
		return Color(1.0, 0.6, 0.5) if enraged else Color.WHITE
	return base_color

func _set_tint(c: Color) -> void:
	if use_sprite:
		sprite.modulate = c
	else:
		visual.color = c

func _start_pattern() -> void:
	pat_t = float(PAT_DUR.get(patterns[pat_idx], 2.5))
	if enraged:
		pat_t /= 1.4
	sub_t = 0.0
	charge_phase = ""

func _next_pattern() -> void:
	pat_idx = (pat_idx + 1) % patterns.size()
	_start_pattern()

func _enrage_mul() -> float:
	return 1.4 if enraged else 1.0

func _spd() -> float:
	return speed * (1.3 if enraged else 1.0)

func _physics_process(delta: float) -> void:
	var lc := LightField.sample(global_position)
	sprite.self_modulate = lc
	visual.self_modulate = lc
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		if flash_t == 0.0:
			_set_tint(_base_tint())

	var player := GameState.player
	if player == null:
		return
	var ppos: Vector2 = player.global_position

	pat_t -= delta
	match patterns[pat_idx]:
		"charge": _do_charge(delta, ppos)
		"burst": _do_burst(delta, ppos)
		"spread": _do_spread(delta, ppos)
		"summon": _do_summon(delta, ppos)
		_: _do_chase(delta, ppos)

	if use_sprite:
		var moving := velocity.length() > 5.0
		var anim := "run" if moving else "idle"
		if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
			sprite.play(anim)
		if absf(velocity.x) > 1.0:
			sprite.flip_h = velocity.x < 0.0

	if global_position.distance_to(ppos) < size + 9.0:
		player.take_damage(damage, global_position)

	if pat_t <= 0.0 and charge_phase == "":
		_next_pattern()

func _move_to(target: Vector2, spd: float) -> void:
	agent.target_position = target
	var next := agent.get_next_path_position()
	var dir := next - global_position
	if global_position.distance_to(target) > 8.0 and dir.length() > 1.0:
		velocity = dir.normalized() * spd
	else:
		velocity = Vector2.ZERO
	move_and_slide()

func _do_chase(_delta: float, ppos: Vector2) -> void:
	_move_to(ppos, _spd())

func _do_charge(delta: float, ppos: Vector2) -> void:
	if charge_phase == "":
		charge_phase = "telegraph"
		charge_timer = 0.55
		_set_tint(Color(1, 1, 0.4))
	charge_timer -= delta
	match charge_phase:
		"telegraph":
			velocity = Vector2.ZERO
			move_and_slide()
			if charge_timer <= 0.0:
				charge_dir = (ppos - global_position).normalized()
				charge_phase = "dash"
				charge_timer = 0.45
				_set_tint(_base_tint())
		"dash":
			velocity = charge_dir * _spd() * 4.5
			move_and_slide()
			if charge_timer <= 0.0 or get_slide_collision_count() > 0:
				charge_phase = "recover"
				charge_timer = 0.4
		"recover":
			velocity = Vector2.ZERO
			move_and_slide()
			if charge_timer <= 0.0:
				charge_phase = ""
				_next_pattern()

func _do_burst(delta: float, _ppos: Vector2) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	sub_t -= delta
	if sub_t <= 0.0:
		sub_t = 1.1 / _enrage_mul()
		var count := 12
		for i in count:
			var ang := TAU * i / count
			_fire(Vector2(cos(ang), sin(ang)))

func _do_spread(delta: float, ppos: Vector2) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	sub_t -= delta
	if sub_t <= 0.0:
		sub_t = 0.65 / _enrage_mul()
		var base := (ppos - global_position).normalized()
		for a in [-0.28, 0.0, 0.28]:
			_fire(base.rotated(a))

func _do_summon(delta: float, ppos: Vector2) -> void:
	_move_to(ppos, _spd() * 0.5)
	sub_t -= delta
	if sub_t <= 0.0 and minion != "":
		sub_t = 2.2
		var count := 0
		for c in get_parent().get_children():
			if c is Enemy:
				count += 1
		if count < 8:
			var e := ENEMY.instantiate()
			get_parent().add_child(e)
			e.setup_type(minion, false)
			e.global_position = global_position + Vector2(Rng.range_f(-30, 30), Rng.range_f(-30, 30))
			e.home_pos = e.global_position
			e.home_rect = Rect2(global_position - Vector2(220, 220), Vector2(440, 440))
			e.aggro = true
			e.reset_physics_interpolation()

func _fire(dir: Vector2) -> void:
	var p := PROJECTILE.instantiate()
	get_parent().add_child(p)
	p.setup(global_position, dir, damage, false, proj_spd)

func take_damage(amount: int) -> void:
	hp -= amount
	flash_t = 0.08
	_set_tint(Color(2.2, 2.2, 2.2) if use_sprite else Color(1, 1, 1))
	GameState.floater(global_position, str(amount), Color(1, 0.8, 0.4))
	GameState.boss_hp_changed.emit(hp, max_hp)
	if not enraged and hp <= max_hp * 0.5:
		enraged = true
		base_color = Color(1.0, 0.4, 0.2)
	if hp <= 0:
		_die()

func _die() -> void:
	GameState.run["kills"] = int(GameState.run.get("kills", 0)) + 1
	GameState.drop_loot(global_position, 120, true)
	GameState.boss_died.emit()
	queue_free()
