extends Node
## Spawnea mobs sobre las celdas REALES del piso procedural (no posiciones fijas).
## Corre deferred → después de que iso_procgen pintó el Floor. Los mobs van bajo
## World (y-sorted) para ordenarse con muros/player y recibir la foot-light.

const ENEMY := preload("res://scenes/enemy.tscn")
const MOB_TYPES := ["rata", "slime", "zombi", "orco", "murcielago"]

@export var mob_count := 8
@export var floor_path: NodePath = ^"../../Floor"
@export var min_dist_from_player := 120.0   # no spawnear arriba del player

func _ready() -> void:
	_spawn.call_deferred()

func _spawn() -> void:
	var floor_layer := get_node_or_null(floor_path) as TileMapLayer
	if floor_layer == null:
		push_warning("[mobspawner] no encontré el Floor en %s" % floor_path)
		return
	var cells := floor_layer.get_used_cells()
	if cells.is_empty():
		return
	var player := get_node_or_null(^"../Player") as Node2D
	var ppos := player.global_position if player else Vector2.INF
	var spawned := 0
	var tries := 0
	while spawned < mob_count and tries < mob_count * 20:
		tries += 1
		var cell: Vector2i = cells[randi() % cells.size()]
		var wpos := floor_layer.to_global(floor_layer.map_to_local(cell))
		if ppos != Vector2.INF and wpos.distance_to(ppos) < min_dist_from_player:
			continue
		var e: Enemy = ENEMY.instantiate()
		get_parent().add_child(e)
		e.global_position = wpos
		e.home_pos = wpos
		e.home_rect = Rect2(wpos - Vector2(180, 180), Vector2(360, 360))
		e.setup_type(MOB_TYPES[spawned % MOB_TYPES.size()])
		spawned += 1
	print("[mobspawner] %d mobs sobre el piso" % spawned)
