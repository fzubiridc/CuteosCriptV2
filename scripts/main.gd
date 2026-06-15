extends Node2D
## Escena principal. Genera la mazmorra, ubica al jugador y siembra enemigos.

const ENEMY := preload("res://scenes/enemy.tscn")
const BOSS := preload("res://scenes/boss.tscn")

@onready var dungeon: Dungeon = $Dungeon
@onready var player: CharacterBody2D = $Player

## TEMPORAL: spawnea una horda alrededor del jugador para testear (floaters, etc.).
## Poner en false para volver al spawn normal por salas.
const DEBUG_HORDE := false
## TEMPORAL: spawnea un jefe (liche) en la última sala para testear F5.
const DEBUG_BOSS := true

func _ready() -> void:
	dungeon.generate()
	player.global_position = dungeon.get_spawn_point()
	player.reset_physics_interpolation()
	if DEBUG_HORDE:
		_spawn_horde()
	else:
		_spawn_enemies()
	if DEBUG_BOSS:
		_spawn_boss()
	GameState.set_mode(GameState.Mode.PLAY)

func _spawn_boss() -> void:
	var room: Rect2i = dungeon.rooms[dungeon.rooms.size() - 1]
	var b := BOSS.instantiate()
	add_child(b)
	b.setup_boss("bucle")
	b.global_position = dungeon.to_global(dungeon.map_to_local(room.get_center()))
	b.reset_physics_interpolation()

func _spawn_horde() -> void:
	var pool: Array = Data.ZONES[0].enemies
	var center: Vector2 = player.global_position
	var big := Rect2(center - Vector2(160, 160), Vector2(320, 320))
	for i in 12:
		var e := ENEMY.instantiate()
		add_child(e)
		e.setup_type(Rng.pick(pool), false)
		var ang := TAU * i / 12.0
		e.global_position = center + Vector2(cos(ang), sin(ang)) * 60.0
		e.home_pos = e.global_position
		e.home_rect = big
		e.reset_physics_interpolation()

func _spawn_enemies() -> void:
	# Un enemigo (~70%) en el centro de cada sala salvo la de inicio.
	var zone: Dictionary = Data.ZONES[int(GameState.run.get("zone_idx", 0))]
	var pool: Array = zone.enemies
	for i in range(1, dungeon.rooms.size()):
		if Rng.chance(0.7):
			var room: Rect2i = dungeon.rooms[i]
			var e := ENEMY.instantiate()
			add_child(e)
			e.setup_type(Rng.pick(pool), Rng.chance(float(Data.BALANCE.elite_chance)))
			var center_world := dungeon.to_global(dungeon.map_to_local(room.get_center()))
			e.global_position = center_world
			e.home_pos = center_world
			# Rect de la sala en coordenadas de mundo (para el aggro por zona).
			e.home_rect = Rect2(Vector2(room.position) * Dungeon.TILE, Vector2(room.size) * Dungeon.TILE)
			e.reset_physics_interpolation()
