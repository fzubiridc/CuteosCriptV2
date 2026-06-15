extends Node2D
## Escena principal. Loop de pisos (F10): genera la mazmorra, ubica al jugador,
## siembra enemigos/jefe por zona, y maneja descenso → próximo piso → victoria.
## Persistencia: carga/continúa la run desde user:// y la guarda en cada piso.

const ENEMY := preload("res://scenes/enemy.tscn")
const BOSS := preload("res://scenes/boss.tscn")

@onready var dungeon: Dungeon = $Dungeon
@onready var player: CharacterBody2D = $Player

var _exit: Area2D
var _exit_open := false

func _ready() -> void:
	GameState.boss_died.connect(_on_boss_died)
	if SaveSystem.has_run():
		var save := SaveSystem.load_run()
		var r: Dictionary = save.get("run", {})
		if not r.is_empty():
			GameState.run = r
		_build_floor(int(GameState.run.get("seed", -1)))
		if save.has("player"):
			player.load_save(save["player"])
	else:
		GameState.reset_run()
		_build_floor()
	GameState.set_mode(GameState.Mode.PLAY)
	SaveSystem.save_run(GameState.run, player)   # checkpoint al entrar

var _autosave_t := 0.0

func _unhandled_input(event: InputEvent) -> void:
	# ESC durante la partida → vuelve al menú (con SALIR). Guarda la run primero.
	if event.is_action_pressed("ui_cancel") and GameState.mode == GameState.Mode.PLAY:
		SaveSystem.save_run(GameState.run, player)
		get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")

func _process(delta: float) -> void:
	if GameState.mode == GameState.Mode.PLAY:
		GameState.run["time"] = float(GameState.run.get("time", 0.0)) + delta
		_autosave_t += delta
		if _autosave_t >= 8.0:
			_autosave_t = 0.0
			SaveSystem.save_run(GameState.run, player)

# ---------------------------------------------------------------------------
# Construcción de un piso
# ---------------------------------------------------------------------------
func _build_floor(seed_val: int = -1) -> void:
	for n in get_children():
		if n is Enemy or n is Boss or n is Pickup or n is Projectile:
			n.queue_free()
	if seed_val < 0:
		Rng.randomize_seed()
		GameState.run["seed"] = Rng.seed_value
	else:
		Rng.set_seed(seed_val)
		GameState.run["seed"] = seed_val

	dungeon.generate()
	player.global_position = dungeon.get_spawn_point()
	player.reset_physics_interpolation()

	var zone: Dictionary = Data.ZONES[int(GameState.run.get("zone_idx", 0))]
	var is_boss_floor: bool = int(GameState.run.get("floor_in_zone", 0)) >= int(zone.floors) - 1
	_spawn_enemies(zone)
	_make_exit()
	if is_boss_floor:
		_close_exit()
		_spawn_boss(String(zone.boss))
	else:
		_open_exit()

func next_floor() -> void:
	if not _exit_open:
		return
	var r := GameState.run
	r["depth"] = int(r.get("depth", 1)) + 1
	r["floor_in_zone"] = int(r.get("floor_in_zone", 0)) + 1
	var zone: Dictionary = Data.ZONES[int(r.get("zone_idx", 0))]
	if r["floor_in_zone"] >= int(zone.floors):
		r["floor_in_zone"] = 0
		r["zone_idx"] = int(r.get("zone_idx", 0)) + 1
	if int(r["zone_idx"]) >= Data.ZONES.size():
		_win()
		return
	GameState.floor_changed.emit(int(r["depth"]))
	_build_floor()
	SaveSystem.save_run(GameState.run, player)

func _win() -> void:
	GameState.set_mode(GameState.Mode.WIN)
	SaveSystem.record(GameState.run, player, true)
	SaveSystem.clear_run()

# ---------------------------------------------------------------------------
# Salida (portal al próximo piso)
# ---------------------------------------------------------------------------
func _make_exit() -> void:
	if _exit and is_instance_valid(_exit):
		_exit.queue_free()
	_exit = Area2D.new()
	_exit.collision_layer = 0
	_exit.collision_mask = 2   # detecta al jugador (capa 2)
	var shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 9.0
	shape.shape = circ
	_exit.add_child(shape)
	# Visual: portal violeta aditivo + luz emisiva.
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/fx/light_radial.tres")
	spr.modulate = Color(0.7, 0.45, 1.0, 0.9)
	spr.scale = Vector2(0.12, 0.12)
	spr.z_index = 30
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	spr.material = m
	_exit.add_child(spr)
	var lt := PointLight2D.new()
	lt.texture = load("res://assets/fx/light_pool.tres")
	lt.color = Color(0.6, 0.4, 1.0)
	lt.energy = 1.6
	lt.texture_scale = 0.5
	_exit.add_child(lt)
	var last: Rect2i = dungeon.rooms[dungeon.rooms.size() - 1]
	_exit.global_position = dungeon.to_global(dungeon.map_to_local(last.get_center()))
	_exit.body_entered.connect(func(b: Node) -> void:
		if b is Player:
			next_floor.call_deferred())   # fuera del flush de física
	add_child(_exit)

func _open_exit() -> void:
	_exit_open = true
	if _exit and is_instance_valid(_exit):
		_exit.visible = true
		_exit.set_deferred("monitoring", true)

func _close_exit() -> void:
	_exit_open = false
	if _exit and is_instance_valid(_exit):
		_exit.visible = false
		_exit.set_deferred("monitoring", false)

func _on_boss_died() -> void:
	_open_exit()
	_spawn_merchant()

func _spawn_merchant() -> void:
	if _exit == null or not is_instance_valid(_exit):
		return
	var m := Merchant.new()
	add_child(m)
	m.global_position = _exit.global_position + Vector2(-34, 16)
	m.reset_physics_interpolation()
	GameState.floater(m.global_position + Vector2(0, -22), "Un mercader apareció...", Color("c7b8e8"))

# ---------------------------------------------------------------------------
# Spawns
# ---------------------------------------------------------------------------
func _spawn_boss(key: String) -> void:
	var room: Rect2i = dungeon.rooms[dungeon.rooms.size() - 1]
	var b := BOSS.instantiate()
	add_child(b)
	b.setup_boss(key)
	b.global_position = dungeon.to_global(dungeon.map_to_local(room.get_center()))
	b.reset_physics_interpolation()

func _spawn_enemies(zone: Dictionary) -> void:
	var pool: Array = zone.enemies
	var dens := float(zone.get("density", 1.0))
	for i in range(1, dungeon.rooms.size()):
		if Rng.chance(clampf(0.55 * dens + 0.12, 0.0, 0.92)):
			var room: Rect2i = dungeon.rooms[i]
			var e := ENEMY.instantiate()
			add_child(e)
			e.setup_type(Rng.pick(pool), Rng.chance(float(Data.BALANCE.elite_chance)))
			var center_world := dungeon.to_global(dungeon.map_to_local(room.get_center()))
			e.global_position = center_world
			e.home_pos = center_world
			e.home_rect = Rect2(Vector2(room.position) * Dungeon.TILE, Vector2(room.size) * Dungeon.TILE)
			e.reset_physics_interpolation()
