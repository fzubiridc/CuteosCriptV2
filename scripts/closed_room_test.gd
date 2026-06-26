extends Node2D
## Prueba DETERMINISTA del modelo "muro = borde de celda" con habitación ISOMÉTRICA.
## Construye UNA sola habitación cerrada de 6×12 tiles tallada con carve_iso_room
## (paralelogramo iso, lados rectos). Verifica:
## - piso en paralelogramo iso regular (dos lados de 6, dos de 12);
## - cuatro paredes rectas + exactamente cuatro esquinas;
## - colisión alineada (el jugador no atraviesa los bordes);
## - transparencia conjunta de las fachadas S/E al entrar.
## Al construir, imprime al log: offset de filas par/impar (map_to_local) y los conteos.

const WallSegment := preload("res://scripts/wall_segment.gd")

const GRID_SIZE := Vector2i(20, 24)
const ROOM_ORIGIN := Vector2i(9, 3)
const ROOM_WIDTH := 6     # eje u (SE) → genera los dos lados de 12
const ROOM_DEPTH := 12    # eje v (SW) → genera los dos lados de 6

@onready var dungeon: Dungeon = $Dungeon
@onready var player: Player = $Player
@onready var status_label: Label = $UI/Panel/Margin/Status

var _room_cells: Array = []
var _inside := true


func _ready() -> void:
	GameState.set_mode(GameState.Mode.PLAY)
	_build_closed_room()
	_teleport(true)
	LightField.mark_dirty()
	# Panel de knobs (tecla L) — no estaba en esta escena; lo agrego para tunear las antorchas acá.
	var dbg := CanvasLayer.new()
	dbg.name = "LightingDebug"
	dbg.set_script(load("res://scripts/lighting_debug.gd"))
	add_child(dbg)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_inside = not _inside
		_teleport(_inside)
		get_viewport().set_input_as_handled()


func _build_closed_room() -> void:
	dungeon._ensure_iso()
	# Etapa 1: offset exacto de filas pares/impares vía map_to_local (antes de tallar).
	_log("[isotest] map_to_local (offset de filas):")
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(0, 3)]:
		_log("  cell %s -> %s" % [c, dungeon.map_to_local(c)])
	dungeon.grid = []
	for y in GRID_SIZE.y:
		var row: Array = []
		row.resize(GRID_SIZE.x)
		row.fill(0)
		dungeon.grid.append(row)

	# Habitación iso 6×12 (paralelogramo de lados rectos), no un Rect2i cartesiano.
	_room_cells = dungeon.carve_iso_room(ROOM_ORIGIN, ROOM_WIDTH, ROOM_DEPTH)

	# Toda la sala = room_id 0 (para el reveal de fachada). Rooms se deja como el bbox
	# cartesiano que cubre las celdas (sólo lo usa el reveal; el piso real son _room_cells).
	dungeon.rooms = [_bbox(_room_cells)]
	dungeon._room_of = {}
	for c in _room_cells:
		dungeon._room_of[c] = 0
	dungeon._wall_segments = dungeon._build_wall_segments()
	dungeon._paint_iso()
	dungeon._build_iso_nav()
	dungeon._build_iso_boundaries()
	_place_test_torches()
	dungeon.regenerated.emit()
	_report()


## Coloca 1-2 antorchas sobre paredes TRASERAS (NW/NE) para tunear su posición en vivo
## desde el Inspector remoto del nodo Dungeon (grupo "Antorchas (tuning en vivo)").
func _place_test_torches() -> void:
	var back: Array = []
	for seg in dungeon._wall_segments:
		if seg.side == WallSegment.Side.NW or seg.side == WallSegment.Side.NE:
			back.append(seg)
	if back.is_empty():
		return
	dungeon.spawn_wall_torch(back[0].interior_cell, back[0].side)
	if back.size() > 4:
		var mi := int(back.size() * 0.5)
		dungeon.spawn_wall_torch(back[mi].interior_cell, back[mi].side)


## Conteos al log (Etapa 5).
func _report() -> void:
	# Reagrupa los segmentos por celda igual que _paint_walls
	# (pares adyacentes de lados = esquina; lados sueltos = muro recto).
	var sides_of := {}
	for seg in dungeon._wall_segments:
		var c: Vector2i = seg.interior_cell
		if not sides_of.has(c):
			sides_of[c] = {}
		sides_of[c][seg.side] = true
	var corners := 0
	var straights := 0
	for c in sides_of:
		var s: Dictionary = sides_of[c]
		var nw: bool = s.has(WallSegment.Side.NW)
		var ne: bool = s.has(WallSegment.Side.NE)
		var se: bool = s.has(WallSegment.Side.SE)
		var sw: bool = s.has(WallSegment.Side.SW)
		if nw and ne: corners += 1; nw = false; ne = false
		if se and sw: corners += 1; se = false; sw = false
		if nw and sw: corners += 1; nw = false; sw = false
		if ne and se: corners += 1; ne = false; se = false
		straights += int(nw) + int(ne) + int(se) + int(sw)
	_log("[isotest] celdas de piso=%d  segmentos=%d  muros rectos=%d  esquinas=%d" % [
		_room_cells.size(), dungeon._wall_segments.size(), straights, corners])
	_flush_report()


# El buffer de logs del juego del MCP no actualiza entre runs → además del print, acumulo
# el reporte y lo vuelco a user://isotest_report.txt para leerlo de disco con certeza.
var _report_lines: PackedStringArray = []
func _log(line: String) -> void:
	print(line)
	_report_lines.append(line)
func _flush_report() -> void:
	var f := FileAccess.open("user://isotest_report.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_report_lines))
		f.close()


func _bbox(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var mn: Vector2i = cells[0]
	var mx: Vector2i = cells[0]
	for c in cells:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2i(mn, mx - mn + Vector2i.ONE)


func _teleport(inside: bool) -> void:
	# inside = centro de la sala; !inside = una esquina interior (para inspeccionar el borde).
	var idx: int = (ROOM_WIDTH / 2) * ROOM_DEPTH + ROOM_DEPTH / 2 if inside else 0
	idx = clampi(idx, 0, maxi(_room_cells.size() - 1, 0))
	var cell: Vector2i = _room_cells[idx] if not _room_cells.is_empty() else ROOM_ORIGIN
	player.global_position = dungeon.to_global(dungeon.map_to_local(cell))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	status_label.text = (
		"CUARTO ISO 6×12 — PRUEBA DETERMINISTA\n"
		+ ("CENTRO: fachadas S/E al 22%." if inside else "ESQUINA: revisá el borde recto.")
		+ "\n\nE: centro/esquina    WASD: caminar"
	)
