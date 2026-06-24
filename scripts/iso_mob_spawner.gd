extends Node
## TEST: spawnea varios mobs configurados en la escena iso, bajo World (y-sorted)
## para que se ordenen con muros/player y los ilumine la antorcha (foot-light).

const ENEMY := preload("res://scenes/enemy.tscn")

const MOBS := [
	{"type": "rata", "pos": Vector2(0, -30)},
	{"type": "slime", "pos": Vector2(-60, 10)},
	{"type": "zombi", "pos": Vector2(70, 15)},
	{"type": "orco", "pos": Vector2(25, -75)},
	{"type": "murcielago", "pos": Vector2(-30, 55)},
]

func _ready() -> void:
	_spawn.call_deferred()

func _spawn() -> void:
	for m in MOBS:
		var e: Enemy = ENEMY.instantiate()
		get_parent().add_child(e)
		e.global_position = m.pos
		e.home_pos = e.global_position
		e.setup_type(m.type)
