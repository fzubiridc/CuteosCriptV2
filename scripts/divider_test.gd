extends Node2D
## SANDBOX de DIVISOR (sistema REAL): una sala iso cerrada con UN divisor + puerta colocado por
## `DungeonDividers.add_divider` (el mismo `plan_divider` que crece hasta topar muro que usa el juego).
## Objetivo: ver si el divisor con puerta LLEGA a los muros perpendiculares de la sala.
##
## Toggle RUN_SMOOTH: corre o no `_smooth_double_corners` antes de colocar el divisor. El suavizado PROTEGE
## las salas (no rellena celdas de sala ni talla muros lindantes), así que en una sala AISLADA es no-op →
## si el divisor queda IGUAL con/sin suavizado, el problema NO es el suavizado (es el sistema de divisores
## o la interacción con corredores, que esta escena no tiene).

const GRID := Vector2i(44, 40)
const ORIGIN := Vector2i(20, 8)
const RW := 11   # ancho sala (eje u, SE)
const RD := 12   # profundidad (eje v, SW)
const RUN_SMOOTH := false   # ← poné true, recargá la escena y compará

@onready var dungeon: Dungeon = $Dungeon
@onready var player: Player = $Player
@onready var status_label: Label = $UI/Panel/Margin/Status

var _cells: Array = []

func _ready() -> void:
	GameState.set_mode(GameState.Mode.PLAY)
	_build()
	LightField.mark_dirty()

func _build() -> void:
	dungeon._ensure_iso()
	dungeon._ensure_gen()
	dungeon._ensure_dividers()
	dungeon.grid = []   # tamaño REAL del dungeon (MAP_H×MAP_W) — el suavizado itera d.MAP_H/MAP_W, no GRID
	for y in dungeon.MAP_H:
		var row: Array = []
		row.resize(dungeon.MAP_W)
		row.fill(0)
		dungeon.grid.append(row)
	_cells = dungeon.carve_iso_room(ORIGIN, RW, RD)
	dungeon._gen_room_cells = [_cells]
	dungeon._room_specs = [{"origin": ORIGIN, "w": RW, "d": RD}]
	dungeon.rooms = [_bbox(_cells)]
	dungeon._room_of = {}
	for c in _cells:
		dungeon._room_of[c] = 0
	if RUN_SMOOTH:
		dungeon._gen._smooth_double_corners()   # protege salas → debería ser no-op acá
	dungeon._wall_segments = dungeon._build_wall_segments()
	dungeon._paint_iso()
	dungeon._build_iso_nav()
	dungeon._build_iso_boundaries()
	# DIVISOR por el SISTEMA REAL: orient 0 (muros NE) en la fila v=RD/2, crece hasta topar muro, puerta auto.
	dungeon._dividers.add_divider(ORIGIN, 0, int(RD / 2.0), 0, RW, int(RW / 2.0))
	dungeon.regenerated.emit()
	var c0: Vector2i = _cells[int(_cells.size() / 2.0)] if not _cells.is_empty() else ORIGIN
	player.global_position = dungeon.to_global(dungeon.map_to_local(c0))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	status_label.text = (
		"DIVISOR (sistema real) — RUN_SMOOTH=%s\n" % str(RUN_SMOOTH)
		+ "¿El divisor + puerta llega a los muros perpendiculares de la sala?\n"
		+ "Cambiá RUN_SMOOTH en divider_test.gd y recargá para comparar."
	)

func _bbox(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var mn: Vector2i = cells[0]
	var mx: Vector2i = cells[0]
	for c in cells:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2i(mn, mx - mn + Vector2i.ONE)
