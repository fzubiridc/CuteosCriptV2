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

const GRID_SIZE := Vector2i(48, 48)   # grande con margen → la sala iso no se clipea
const ROOM_ORIGIN := Vector2i(24, 6)
const ROOM_WIDTH := 12    # eje u (SE) → largo del DIVISOR (la fila NE cruza por acá)
const ROOM_DEPTH := 14    # eje v (SW) → profundidad (lugar para caminar a los dos lados)
# Ejes iso en cell-space (mismos que dungeon_gen): +u=SE, +v=SW. Para calcular el divisor.
const ISO_A := Vector2(128, 64)
const ISO_B := Vector2(-128, 64)
# Divisor de prueba: 0 = línea de VACÍO (muro doble cara); 1 = fila NE interna + CUTAWAY (transparencia
# por legibilidad, estilo D2/BG3: el muro se fadea SOLO cuando te tapa, no se ocluye).
const DIVIDER_MODE := 3       # 0=vacío  1=NE+cutaway+puerta  2=multi-divisor NE  3=ESPEJO (divisores NW "/")
# Diagnóstico (modo 2): varios divisores [v_row, u_start, u_end) con largos/posiciones distintos para
# UBICAR el artefacto del óvalo. Unos tocan el NW (u_start=0), otros no; unos largos, otros cortos.
const TEST_DIVIDERS := [
	[2, 0, 6],     # toca NW (u=0), CORTO
	[5, 3, 12],    # NO toca NW (u=3), LARGO, toca SE
	[8, 0, 12],    # toca NW y SE (FULL)
	[11, 4, 9],    # FLOTANTE (no toca NW ni SE), corto
]
# ESPEJO (modo 3): divisores de muros NW corriendo por el eje v (línea "/", SW↔NE). [u_col, v_start, v_end)
const TEST_DIVIDERS_NW := [
	[3, 0, 8],     # toca el perímetro en v=0
	[8, 2, 14],    # toca el perímetro en v=13
	[5, 4, 10],    # FLOTANTE
]
const CUTAWAY_ALPHA := 0.25   # opacidad del muro interno cuando te tapa (player detrás)
const DIV_SKIP_PERIMETER := true   # NO renderizar el muro del divisor sobre la celda de perímetro NW
								   # (u=0): evita el DOBLE óvalo de la superposición NE-divisor + NW-perímetro.
const DIV_SPAN_EXT := 1.0     # celdas que se EXTIENDE el span del divisor más allá de cada punta (mata
							  # el abanico del óvalo en el extremo). Subir si todavía se ve; bajar si ensucia el NW/SE.

@onready var dungeon: Dungeon = $Dungeon
@onready var player: Player = $Player
@onready var status_label: Label = $UI/Panel/Margin/Status

var _room_cells: Array = []
var _inside := true
var _divider_holders: Array[Node2D] = []   # muros del divisor NE interno (modo 1), para el cutaway
var _dividers: Array = []                   # records {holders, axis (0=eje v/NE, 1=eje u/NW), line} → cutaway por-divisor
# Puerta del divisor (en el hueco u_gap): CERRADA bloquea + CLICK para abrir (swap sprite + sin colisión).
var _door_holder: Node2D = null
var _door_coll: CollisionShape2D = null
var _door_open := false
var _door_closed_tex: Texture2D = null
var _door_open_tex: Texture2D = preload("res://assets/iso/walls/variations/OpenDoorNE.png")
var _door_origin := Vector2.ZERO


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
	if DIVIDER_MODE == 0:
		_carve_divider()   # divisor de VACÍO + hueco → muro doble cara, gratis
	dungeon.rooms = [_bbox(_room_cells)]
	dungeon._wall_segments = dungeon._build_wall_segments()
	dungeon._paint_iso()
	dungeon._build_iso_nav()
	dungeon._build_iso_boundaries()
	if DIVIDER_MODE == 1:
		_place_ne_divider_cutaway()   # fila NE interna + cutaway (transparencia por legibilidad)
	if DIVIDER_MODE == 2:
		_place_test_dividers()        # varios divisores NE → diagnóstico del artefacto del óvalo
	if DIVIDER_MODE == 3:
		_place_test_dividers_nw()     # ESPEJO: divisores NW ("/") → verificar que el fix aplica igual
	_place_test_torches()
	dungeon.regenerated.emit()
	_report()


## PRUEBA del DIVISOR: línea de VACÍO a media profundidad (v_mid) cruzando la sala de lado a lado,
## con un HUECO (puerta) en el medio. El sistema de muros dibuja el muro de las dos mitades hacia el
## divisor (muro de doble cara, gratis); la barrera bloquea el vacío y el hueco es caminable.
func _carve_divider() -> void:
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	var v_mid := ROOM_DEPTH / 2     # la línea del divisor (a media profundidad)
	var u_gap := ROOM_WIDTH / 2     # el hueco (puerta) en el medio del divisor
	for u in ROOM_WIDTH:
		if u == u_gap:
			continue                # dejar piso → se puede pasar
		var cell: Vector2i = dungeon.local_to_map(base + ISO_A * u + ISO_B * v_mid)
		if cell.y >= 0 and cell.y < dungeon.grid.size() and cell.x >= 0 and cell.x < dungeon.grid[cell.y].size():
			dungeon.grid[cell.y][cell.x] = 0   # vacío → el muro se forma solo a los lados
		dungeon._room_of.erase(cell)
		_room_cells.erase(cell)


## ENFOQUE A — "transparencia por legibilidad" (D2/BG3). El muro interno queda en su capa NORMAL
## (IsoWallsBack, z=-1, debajo del player) → CERO y-sort. Cuando el player queda DETRÁS (al norte del
## divisor) el muro lo taparía mal; en vez de ocluir, lo FADEAMOS a CUTAWAY_ALPHA y ves al personaje a
## través (estilo Diablo). La VERDAD de gameplay sigue siendo real: el diamante de colisión frena igual.
func _place_ne_divider_cutaway() -> void:
	for h in _divider_holders:
		if is_instance_valid(h):
			h.queue_free()
	_divider_holders.clear()
	_dividers.clear()
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	var v_mid := ROOM_DEPTH / 2
	var u_gap := ROOM_WIDTH / 2
	for u in ROOM_WIDTH:
		if u == u_gap:
			continue   # hueco → piso normal (sin muro)
		var cell: Vector2i = dungeon.local_to_map(base + ISO_A * u + ISO_B * v_mid)
		# Muro en su capa normal (z=-1), material foot-lit. Se ilumina vía el span inyectado de abajo.
		var holder := dungeon._spawn_wall_sprite(cell, dungeon.SRC_WALL_NE, false)
		_divider_holders.append(holder)
		var co := dungeon.map_to_local(cell)
		# COLISIÓN (verdad de gameplay) ALINEADA al borde NE del muro (no toda la celda): una tira fina
		# sobre la arista top→right. Así el player camina hasta el muro de los dos lados y solo NO cruza.
		if dungeon._iso_bounds != null and is_instance_valid(dungeon._iso_bounds):
			var cs := CollisionShape2D.new()
			var edge := ConvexPolygonShape2D.new()
			var t := Vector2(0, -64)                  # top de la celda
			var r := Vector2(128, 0)                  # right → arista NE = t..r
			var n := Vector2(-0.447, 0.894) * 8.0     # normal de la arista hacia el interior, medio grosor
			edge.points = PackedVector2Array([t + n, r + n, r - n, t - n])
			cs.shape = edge
			cs.position = co
			dungeon._iso_bounds.add_child(cs)
	# ILUMINACIÓN (fix T-junction): cada muro del divisor lleva SU PROPIO span (por-instancia) → el shader
	# usa ESE span, no adivina con la lista global → sin competencia con el muro NW en la unión. NO se mete
	# en _wall_spans_all (así el perímetro tampoco lo ve).
	var c0 := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * 0 + ISO_B * v_mid))
	var cl := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * (ROOM_WIDTH - 1) + ISO_B * v_mid))
	var span_a := dungeon.to_global(c0 + Vector2(0, -64))
	var span_b := dungeon.to_global(cl + Vector2(128, 0))
	for h in _divider_holders:
		_apply_divider_span(h, span_a, span_b)
	_spawn_divider_door(base, v_mid, u_gap, span_a, span_b)
	# Cutaway: la fila NE + la puerta fadean cuando el player está al norte de esta línea (v < v_mid-0.5).
	var rec_holders: Array = _divider_holders.duplicate()
	if is_instance_valid(_door_holder):
		rec_holders.append(_door_holder)
	_dividers.append({"holders": rec_holders, "axis": 0, "line": float(v_mid)})


## Puerta en el HUECO del divisor: CERRADA (DoorNE) con colisión que bloquea; CLICK → ABRE (OpenDoorNE)
## y saca la colisión (pasás). La verdad de gameplay (colisión) se togglea; el sprite es solo visual. La
## ilumina el span continuo del divisor (que cubre el hueco), así que no hace falta span propio.
func _spawn_divider_door(base: Vector2, v_mid: int, u_gap: int, span_a: Vector2, span_b: Vector2) -> void:
	if is_instance_valid(_door_holder):
		_door_holder.queue_free()
	_door_open = false
	var cell: Vector2i = dungeon.local_to_map(base + ISO_A * u_gap + ISO_B * v_mid)
	var co := dungeon.map_to_local(cell)
	var door_src := int(dungeon._door_src.get(dungeon.SRC_WALL_NE, dungeon.SRC_WALL_NE))
	_door_closed_tex = dungeon._wall_tex.get(door_src)
	_door_origin = dungeon._wall_origin.get(door_src, Vector2.ZERO)
	_door_holder = dungeon._spawn_wall_sprite(cell, door_src, false)   # sprite cerrada, en su capa normal
	# Colisión CERRADA: misma tira fina alineada al borde NE que los muros del divisor.
	if dungeon._iso_bounds != null and is_instance_valid(dungeon._iso_bounds):
		_door_coll = CollisionShape2D.new()
		var edge := ConvexPolygonShape2D.new()
		var t := Vector2(0, -64)
		var r := Vector2(128, 0)
		var n := Vector2(-0.447, 0.894) * 8.0
		edge.points = PackedVector2Array([t + n, r + n, r - n, t - n])
		_door_coll.shape = edge
		_door_coll.position = co
		dungeon._iso_bounds.add_child(_door_coll)
	# Área CLICKEABLE sobre la puerta (input_pickable). El rect cubre el alto del sprite.
	var area := Area2D.new()
	area.input_pickable = true
	var acs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200, 260)
	acs.shape = rect
	acs.position = Vector2(0, -90)   # subir para cubrir el sprite de puerta (que crece hacia arriba)
	area.add_child(acs)
	_door_holder.add_child(area)
	area.input_event.connect(_on_door_input)
	_apply_divider_span(_door_holder, span_a, span_b)   # la puerta usa el span del divisor (su mismo NE)


## Click izquierdo sobre la puerta → togglea abierta/cerrada.
func _on_door_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_door()


## Abre/cierra: swap del sprite (DoorNE ↔ OpenDoorNE) + togglea la colisión (abierta = pasás).
func _toggle_door() -> void:
	_door_open = not _door_open
	if is_instance_valid(_door_holder) and _door_holder.get_child_count() > 0:
		var spr := _door_holder.get_child(0) as Sprite2D
		if spr != null:
			spr.texture = _door_open_tex if _door_open else _door_closed_tex
			spr.offset = -_door_origin
	if is_instance_valid(_door_coll):
		_door_coll.disabled = _door_open


## DIAGNÓSTICO (modo 2): coloca los divisores de TEST_DIVIDERS (distintos largos/posiciones) para ver
## DÓNDE aparece el artefacto del óvalo. Sin cutaway ni colisión (opacos; caminás a través para mirar).
func _place_test_dividers() -> void:
	for h in _divider_holders:
		if is_instance_valid(h):
			h.queue_free()
	_divider_holders.clear()
	_dividers.clear()
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	for d in TEST_DIVIDERS:
		_spawn_one_divider(base, int(d[0]), int(d[1]), int(d[2]))


## Un divisor de muros NE en la fila v_row, de u_start a u_end (exclusivo). Cada muro lleva SU PROPIO
## span (por-instancia) → el shader no compite con el del perímetro en la unión (mata el artefacto T).
func _spawn_one_divider(base: Vector2, v_row: int, u_start: int, u_end: int) -> void:
	var holders: Array[Node2D] = []
	for u in range(u_start, u_end):
		var cell: Vector2i = dungeon.local_to_map(base + ISO_A * u + ISO_B * v_row)
		var h := dungeon._spawn_wall_sprite(cell, dungeon.SRC_WALL_NE, false)
		_divider_holders.append(h)
		holders.append(h)
	var ca := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * u_start + ISO_B * v_row))
	var cb := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * (u_end - 1) + ISO_B * v_row))
	var span_a := dungeon.to_global(ca + Vector2(0, -64))
	var span_b := dungeon.to_global(cb + Vector2(128, 0))
	for hh in holders:
		_apply_divider_span(hh, span_a, span_b)
	_dividers.append({"holders": holders, "axis": 0, "line": float(v_row)})   # NE → cutaway por v


## Asigna a un sprite de muro su PROPIO span base (global) vía uniform POR-INSTANCIA → el shader usa ESE
## span en vez de adivinar con la lista global (mata la competencia de spans en las uniones en T).
func _apply_divider_span(holder: Node2D, span_a: Vector2, span_b: Vector2) -> void:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var ci := holder.get_child(0) as CanvasItem
	if ci == null:
		return
	ci.set_instance_shader_parameter("use_manual_span", true)
	ci.set_instance_shader_parameter("manual_span_a", span_a)
	ci.set_instance_shader_parameter("manual_span_b", span_b)


## ESPEJO (modo 3): divisores de muros NW por el eje v. Verifica que el fix por-instancia aplica a la
## orientación espejo ("/"). Mismo principio que el NE pero con la arista NW (left↔top).
func _place_test_dividers_nw() -> void:
	for h in _divider_holders:
		if is_instance_valid(h):
			h.queue_free()
	_divider_holders.clear()
	_dividers.clear()
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	for d in TEST_DIVIDERS_NW:
		_spawn_one_divider_nw(base, int(d[0]), int(d[1]), int(d[2]))


## Un divisor de muros NW en la columna u_col, de v_start a v_end (exclusivo). Span propio (borde NW =
## top↔left) + colisión alineada a esa arista. Cada muro lleva su span → fix T-junction agnóstico a la dir.
func _spawn_one_divider_nw(base: Vector2, u_col: int, v_start: int, v_end: int) -> void:
	var holders: Array[Node2D] = []
	for v in range(v_start, v_end):
		var cell: Vector2i = dungeon.local_to_map(base + ISO_A * u_col + ISO_B * v)
		var h := dungeon._spawn_wall_sprite(cell, dungeon.SRC_WALL_NW, false)
		_divider_holders.append(h)
		holders.append(h)
		if dungeon._iso_bounds != null and is_instance_valid(dungeon._iso_bounds):
			var co := dungeon.map_to_local(cell)
			var cs := CollisionShape2D.new()
			var edge := ConvexPolygonShape2D.new()
			var l := Vector2(-128, 0)
			var t := Vector2(0, -64)
			var n := Vector2(0.447, 0.894) * 8.0   # normal de la arista NW hacia el interior
			edge.points = PackedVector2Array([l + n, t + n, t - n, l - n])
			cs.shape = edge
			cs.position = co
			dungeon._iso_bounds.add_child(cs)
	var ca := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * u_col + ISO_B * v_start))
	var cb := dungeon.map_to_local(dungeon.local_to_map(base + ISO_A * u_col + ISO_B * (v_end - 1)))
	var span_a := dungeon.to_global(ca + Vector2(0, -64))     # top de la primera celda
	var span_b := dungeon.to_global(cb + Vector2(-128, 0))    # left de la última
	for hh in holders:
		_apply_divider_span(hh, span_a, span_b)
	_dividers.append({"holders": holders, "axis": 1, "line": float(u_col)})   # NW → cutaway por u


## Cutaway: cada frame, si el player está al NORTE del divisor (v < v_mid) el muro lo taparía → fade a
## CUTAWAY_ALPHA; si no, opaco. Lerp suave. (Si fadea el lado equivocado, invertir el `<`.)
func _process(_dt: float) -> void:
	if _dividers.is_empty():
		return
	if player == null or not is_instance_valid(player):
		return
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	var feet := player.get_node_or_null("Feet") as Node2D
	var anchor: Vector2 = feet.global_position if feet != null else player.global_position
	var p := dungeon.to_local(anchor) - base
	var v := (p.y / 64.0 - p.x / 128.0) * 0.5   # coord iso v (eje NE)
	var u := (p.y / 64.0 + p.x / 128.0) * 0.5   # coord iso u (eje NW)
	# Cada divisor fadea SOLO si el player está detrás de SU línea (más allá de la arista base, -0.5).
	# NE (axis 0) testea v; NW (axis 1) testea u. El muro vive a media celda hacia el lado "norte".
	for rec in _dividers:
		var coord: float = v if int(rec["axis"]) == 0 else u
		var target := CUTAWAY_ALPHA if coord < float(rec["line"]) - 0.5 else 1.0
		for h in rec["holders"]:
			if is_instance_valid(h):
				h.modulate.a = lerpf(h.modulate.a, target, 0.18)


## Antorchas de prueba (1 al norte de cada esquina, para iluminar la escena).
func _place_test_torches() -> void:
	# Una antorcha UN TILE AL NORTE de la esquina Este y de la Oeste (no en la esquina misma),
	# para ver cómo cae la luz sobre el pico de la esquina (donde se juntan dos spans de muro).
	if _room_cells.is_empty():
		return
	var east: Vector2i = _room_cells[0]
	var west: Vector2i = _room_cells[0]
	for c in _room_cells:
		var sx := dungeon.map_to_local(c).x
		if sx > dungeon.map_to_local(east).x:
			east = c
		if sx < dungeon.map_to_local(west).x:
			west = c
	_torch_north_of(east)
	_torch_north_of(west)

## Pone una antorcha en la pared trasera (NW/NE) de la celda de la sala que está ~un tile al
## NORTE (arriba en pantalla) de `corner`.
func _torch_north_of(corner: Vector2i) -> void:
	var target := dungeon.map_to_local(corner) + Vector2(0, -128)   # un tile arriba en pantalla
	var best: Vector2i = corner
	var best_d := 1e20
	for c in _room_cells:
		var d := dungeon.map_to_local(c).distance_squared_to(target)
		if d < best_d:
			best_d = d
			best = c
	for cell in [best, corner]:   # la celda al norte; si no tiene pared trasera, cae en la esquina
		for seg in dungeon._wall_segments:
			if seg.interior_cell == cell and (seg.side == WallSegment.Side.NW or seg.side == WallSegment.Side.NE):
				dungeon.spawn_wall_torch(seg.interior_cell, seg.side)
				return


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
		"ESPEJO — divisores NW (\"/\"): ¿el fix por-instancia aplica igual?\n"
		+ ("CENTRO" if inside else "ESQUINA")
		+ ": 3 divisores NW (unos tocan el perímetro, otro flotante). Mirá las uniones — deberían estar limpias."
		+ "\n\nL: panel (probá ancho del óvalo)    E: centro/esquina    WASD: caminar"
	)
