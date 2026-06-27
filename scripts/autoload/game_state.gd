extends Node
## Estado global del juego y bus de señales.
## Reemplaza el objeto `state` del original (main.js). Los sistemas se
## comunican por señales, no leyendo flags globales sueltos.

const FLOATER := preload("res://scenes/floater.tscn")
const PICKUP := preload("res://scenes/pickup.tscn")

enum Mode { LOADING, MENU, PLAY, DEAD, WIN }

var mode: Mode = Mode.LOADING
var player: Node = null

## Metadatos de la run en curso (equivalente a `run` en el original).
var run: Dictionary = {}

# --- Señales (eventos del juego) ---
# Bus de eventos: las señales las emiten otras clases (enemy, boss, player…),
# por eso GDScript las marca "unused" dentro de ESTA clase. Es esperado.
@warning_ignore_start("unused_signal")
signal mode_changed(new_mode: Mode)
signal player_damaged(amount: int)
signal player_died
signal enemy_killed(enemy: Node)
signal loot_dropped(loot: Node)
signal floor_changed(depth: int)
signal coins_changed(total: int)
signal xp_changed(xp: int, level: int)
signal boss_spawned(boss: Node)
signal boss_hp_changed(current: int, maximum: int)
signal boss_died
signal level_up(choices: Array)
signal shop_requested(merchant)   # el mercader pide abrir la tienda; el HUD escucha
@warning_ignore_restore("unused_signal")

func _ready() -> void:
	reset_run()

func set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	mode_changed.emit(m)

## Crea un número flotante en el mundo (daño, avisos).
func floater(pos: Vector2, text: String, color: Color = Color.WHITE, is_crit := false) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var f := FLOATER.instantiate()
	scene.add_child(f)
	f.setup(pos, text, color, is_crit)

## Suelta loot al morir una criatura. xp_amount = orbe de XP garantizado.
func drop_loot(pos: Vector2, xp_amount: int, is_boss := false) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_drop(scene, pos, "xp", xp_amount)
	var depth := int(run.get("depth", 1))
	if is_boss:
		_drop(scene, pos, "heart", int(Data.BALANCE.heart_heal))
		for i in 8:
			_drop(scene, pos + _roff(28.0), "coin", Rng.range_i(3, 6))
		_drop_item(scene, pos + _roff(20.0), Items.make_item_min_rare(depth))
	else:
		if Rng.chance(float(Data.BALANCE.drop_coin)):
			_drop(scene, pos + _roff(10.0), "coin", Rng.range_i(1, 4))
		if Rng.chance(float(Data.BALANCE.drop_heart)):
			_drop(scene, pos + _roff(10.0), "heart", int(Data.BALANCE.heart_heal))
		if Rng.chance(float(Data.BALANCE.drop_potion)):
			_drop(scene, pos + _roff(10.0), "potion", 1)
		if Rng.chance(float(Data.BALANCE.drop_item)):
			_drop_item(scene, pos + _roff(10.0), Items.make_item(depth))

func _drop(scene: Node, pos: Vector2, kind: String, value: int) -> void:
	# Diferido: el pickup es un Area2D y al entrar al árbol enciende su monitoring;
	# si el drop ocurre dentro del paso de física (muerte de enemigo en una colisión)
	# Godot tira "Can't change this state while flushing queries". call_deferred lo
	# corre después del flush.
	_spawn_pickup_deferred.call_deferred(scene, PICKUP.instantiate(), pos, kind, value, {})

func _drop_item(scene: Node, pos: Vector2, item: Dictionary) -> void:
	_spawn_pickup_deferred.call_deferred(scene, PICKUP.instantiate(), pos, "item", 0, item)

func _spawn_pickup_deferred(scene: Node, p: Node, pos: Vector2, kind: String, value: int, item: Dictionary) -> void:
	if not is_instance_valid(scene) or not is_instance_valid(p):
		return
	scene.add_child(p)
	p.setup(pos, kind, value, item)

func _roff(r: float) -> Vector2:
	return Vector2(Rng.range_f(-r, r), Rng.range_f(-r, r))

func reset_run() -> void:
	run = {
		"zone_idx": 0,
		"floor_in_zone": 0,
		"depth": 1,
		"kills": 0,
		"time": 0.0,
		"run_seed": Rng.range_i(1, 0x7FFFFFFF),   # semilla maestra: cada piso deriva de (run_seed, depth)
	}
