extends Node2D
## SANDBOX de CUTAWAY / Z-ORDER dinámico. Sala grande ABIERTA con:
##   · Dos SUB-CUARTOS chicos (3x3 y 2x2) plantados en el MEDIO → los podés RODEAR por los 4 lados para
##     probar detrás/delante de cada cara (fachada SE/SW y trasera NW/NE), adentro y afuera al norte.
##   · Un DIVISOR con puerta (mismo sistema real).
## Sin procgen ni RNG → reproducible. Correlo con "Play Scene" (F6) sobre cutaway_test.tscn. F3 = contador.

const WallSegment := preload("res://scripts/wall_segment.gd")

const ORIGIN := Vector2i(16, 6)
const RW := 15   # ancho sala (eje u, SE)
const RD := 15   # profundidad (eje v, SW)

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
	dungeon.grid = []
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
	dungeon.edge_features = {}
	# Dos sub-cuartos chicos, en el MEDIO (no en esquina) → se pueden rodear por los 4 lados.
	_mark_subroom(3, 3, 3)
	_mark_subroom(9, 8, 2)
	dungeon._wall_segments = dungeon._build_wall_segments()
	dungeon._paint_iso()
	dungeon._build_iso_nav()
	dungeon._build_iso_boundaries()
	dungeon._install_wall_collisions()
	# Un divisor con puerta (sistema real), en una fila libre al sur de los sub-cuartos.
	dungeon._dividers.add_divider(ORIGIN, 0, 12, 0, RW, 7)
	dungeon._place_region_doors()   # puertas de los sub-cuartos + indexa profundidad/cutaway
	# Niebla: el _process del Dungeon corre el cutaway solo si _fog existe.
	dungeon._ensure_fog()
	dungeon._fog.init_visibility()
	dungeon.regenerated.emit()
	# Spawn en la parte SUR de la sala (detrás de la fachada S → arranca viendo el cutaway funcionar).
	var c0 := dungeon.local_to_map(dungeon.map_to_local(ORIGIN) + Vector2(128, 64) * 7 + Vector2(-128, 64) * 11)
	player.global_position = dungeon.to_global(dungeon.map_to_local(c0))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	status_label.text = (
		"CUTAWAY / Z-ORDER — rodeá los sub-cuartos (3x3 y 2x2) y el divisor.\n"
		+ "Probá: detrás/delante de cada muro, adentro, afuera al norte. F3 = contador de perf."
	)

## Marca un sub-cuarto de sz×sz en (u0,v0) del espacio iso de la sala: su frontera interior con la sala →
## aristas "wall" en edge_features (+ 1 "door"). Los muros y la puerta emergen del pipeline normal.
func _mark_subroom(u0: int, v0: int, sz: int) -> void:
	var base := dungeon.map_to_local(ORIGIN)
	var ax := Vector2(128, 64)
	var bx := Vector2(-128, 64)
	var sides := [WallSegment.Side.NW, WallSegment.Side.NE, WallSegment.Side.SE, WallSegment.Side.SW]
	var subset := {}
	for u in range(u0, u0 + sz):
		for v in range(v0, v0 + sz):
			subset[dungeon.local_to_map(base + ax * u + bx * v)] = true
	var door_done := false
	for c in subset:
		for s in sides:
			var n: Vector2i = WallSegment.neighbor(c, s)
			if not dungeon._seg_is_floor(n, dungeon.MAP_W, dungeon.MAP_H):
				continue   # hacia el perímetro/vacío → ya es muro; no tocar
			if subset.has(n):
				continue   # interior del sub-cuarto
			if not door_done:
				dungeon.edge_features[dungeon._edge_key(c, s)] = "door"
				door_done = true
			else:
				dungeon.edge_features[dungeon._edge_key(c, s)] = "wall"

func _bbox(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var mn: Vector2i = cells[0]
	var mx: Vector2i = cells[0]
	for c in cells:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2i(mn, mx - mn + Vector2i.ONE)
