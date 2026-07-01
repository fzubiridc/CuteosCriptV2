extends RefCounted
class_name DungeonDividers
## DIVISORES INTERNOS de sala: un muro (fila NE o columna NW) que parte una sala en dos sub-cuartos
## adyacentes (UN solo room_id → el reveal full-room queda intacto). Idea de Felipe ("sala grande con
## muro al medio = dos cuartos"), validada vs Diablo 2 / BG3. Extraído del sandbox `closed_room_test`.
##
## Separa TRES verdades (estilo D2/BG3):
##  - SPRITE (visual): muro en su capa normal (IsoWallsBack, z=-1) con SPAN POR-INSTANCIA
##    (`use_manual_span` en `wall_face.gdshader`) → sin el artefacto de óvalo en las uniones T.
##  - COLISIÓN (gameplay): tira fina alineada a la arista del muro en `d._iso_bounds`.
##  - CUTAWAY (legibilidad): el muro se FADEA cuando el player queda detrás (no se ocluye, no toca z-order).
## Puerta opcional en el hueco: sprite cerrada/abierta + colisión togglable (click para abrir).
##
## Todo lo del nodo Dungeon va con `d.`; los ejes/consts propios en `self`. Lazy como gen/decor/fog.

const CUTAWAY_ALPHA := 0.5   # opacidad del muro de divisor cuando te tapa (más alto = menos transparente)
const DOOR_NEAR := 70.0            # radio para abrir la puerta con CLIC DERECHO (hay que estar cerca)
const ISO_A := Vector2(128, 64)    # +u = SE (cell-space, mismos ejes que dungeon_gen)
const ISO_B := Vector2(-128, 64)   # +v = SW
const WallSegment := preload("res://scripts/wall_segment.gd")

var d: Dungeon
var _dividers: Array = []   # {holders:Array, orient:int(0=NE/eje u,1=NW/eje v), line:float, base:Vector2}
var _doors: Array = []      # {holder, coll, open:bool, closed_tex, open_tex, origin:Vector2}
var _region_door_holders: Array = []   # puertas de FRONTERA DE REGIÓN (no dividers): holders para liberar en regen
var _wall_marks: Array = []   # {cell, side} de cada muro de divisor colocado → para dibujarlos en el minimapa

func _init(dungeon: Dungeon) -> void:
	d = dungeon

## Libera todos los muros de divisor (sprites). La colisión vive en `_iso_bounds`, que se reconstruye
## solo en cada generate() → no hace falta liberarla acá. Llamar antes de recolocar (regen).
func clear() -> void:
	for rec in _dividers:
		for h in rec["holders"]:
			if is_instance_valid(h):
				h.queue_free()
	for h in _region_door_holders:
		if is_instance_valid(h):
			h.queue_free()
	_region_door_holders.clear()
	_wall_marks.clear()
	_dividers.clear()
	_doors.clear()

## Coloca un divisor en una sala.
##   origin: celda ORIGEN de la sala (base de los ejes u/v, como en carve_iso_room).
##   orient: 0 = muros NE (corren por el eje u, en la fila v=line); 1 = muros NW (corren por eje v, columna u=line).
##   line:   índice de la fila (orient 0) o columna (orient 1) donde va el divisor.
##   start, length: rango a lo largo del eje (en celdas).
##   gap:    índice (en [start, start+length)) del hueco/puerta; -1 = divisor sólido sin puerta.
## Compat: planifica y renderiza un divisor de una (lo usa quien no necesite el paso de conectividad).
func add_divider(origin: Vector2i, orient: int, line: int, start: int, length: int, gap: int = -1) -> void:
	render_divider(plan_divider(origin, orient, line, start, length, gap))

## FASE PLAN (no spawnea nada): hace crecer el divisor hasta topar muro en ambos extremos y devuelve
## su geometría — celdas del tramo, celda de la puerta, side de la arista. El render y el chequeo de
## conectividad (ensure_connectivity) trabajan sobre estos planes ANTES de materializar, así una
## abertura de reparación = simplemente NO colocar ese muro (no hace falta borrar nada después).
func plan_divider(origin: Vector2i, orient: int, line: int, start: int, length: int, gap: int = -1) -> Dictionary:
	var base := d.map_to_local(origin)
	# El divisor CRECE hasta toparse muro en ambos extremos: no asume el ancho prístino de la sala
	# (corredores y _remove_thin_walls pudieron disolver el perímetro → un extremo flotaría en piso).
	# Semilla = celda media de la línea (interior de sala = piso); se extiende ± mientras haya piso y
	# frena al primer vacío/borde → cada punta topa un muro perpendicular (perímetro, otra zona o borde).
	# La puerta se recoloca a una celda interna (nunca en una punta) para preservar el contacto en T.
	var mid := start + int(length / 2.0)
	if _is_floor(_cell(base, orient, line, mid)):
		var seed_reg := _region_at(_cell(base, orient, line, mid))
		var lo := mid
		while _is_floor(_cell(base, orient, line, lo - 1)) and _region_at(_cell(base, orient, line, lo - 1)) == seed_reg:
			lo -= 1
		var hi := mid
		while _is_floor(_cell(base, orient, line, hi + 1)) and _region_at(_cell(base, orient, line, hi + 1)) == seed_reg:
			hi += 1
		start = lo
		length = hi - lo + 1
		if length >= 3:
			gap = Rng.range_i(start + 1, start + length - 2)
	var cells: Array = []
	for i in range(start, start + length):
		cells.append(_cell(base, orient, line, i))
	var door_cell := Vector2i(-9999, -9999)
	if gap >= start and gap < start + length:
		door_cell = _cell(base, orient, line, gap)
	var side: int = WallSegment.Side.NE if orient == 0 else WallSegment.Side.NW
	return {"orient": orient, "line": line, "base": base, "side": side,
		"cells": cells, "door_cell": door_cell, "extra_gaps": {}}

## FASE RENDER: materializa un plan (sprites + colisión + nav + puerta). Omite la celda de la puerta
## (lleva sprite de puerta) y las `extra_gaps` (aberturas de conectividad → hueco vacío, se pasa libre).
func render_divider(plan: Dictionary) -> void:
	var orient: int = plan["orient"]
	var base: Vector2 = plan["base"]
	var line: int = plan["line"]
	var cells: Array = plan["cells"]
	var door_cell: Vector2i = plan["door_cell"]
	var extra_gaps: Dictionary = plan["extra_gaps"]
	var side: int = int(plan["side"])
	if cells.is_empty():
		return
	var src: int = d.SRC_WALL_NE if orient == 0 else d.SRC_WALL_NW
	# Arista base de la celda según orientación (cell-local). NE = top→right; NW = top→left.
	var e0 := Vector2(0, -64)                                          # top (común)
	var e1: Vector2 = Vector2(128, 0) if orient == 0 else Vector2(-128, 0)
	var nrm: Vector2 = (Vector2(-0.447, 0.894) if orient == 0 else Vector2(0.447, 0.894)) * 8.0
	var holders: Array = []
	for cell in cells:
		if cell == door_cell or extra_gaps.has(cell):
			continue
		if _has_wall_on_edge(cell, side):
			continue   # ya hay muro perimetral acá → comparte el existente (no duplica sprite/colisión)
		holders.append(d._spawn_wall_sprite(cell, src, false))
		_add_wall_collision(cell, orient, e0, e1, nrm)   # usa wall_ne / wall_nw del JSON, igual que el perímetro
		_nav_solid(cell, true)   # los mobs no atraviesan el muro del divisor
		_wall_marks.append({"cell": cell, "side": side})   # para dibujar el divisor en el minimapa
	# Span PROPIO (global, todo el tramo) por-instancia → sin competencia con el perímetro en las uniones.
	var ca := d.map_to_local(cells[0])
	var cb := d.map_to_local(cells[cells.size() - 1])
	var span_a := d.to_global(ca + e0)
	var span_b := d.to_global(cb + e1)
	for h in holders:
		_apply_span(h, span_a, span_b)
	# Puerta en el hueco (si lo hay).
	if door_cell.x != -9999:
		var dh := _add_door(door_cell, src, span_a, span_b, e0, e1, nrm)
		if dh != null:
			holders.append(dh)
	_dividers.append({"holders": holders, "orient": orient, "line": float(line), "base": base})

## Evita PUERTA encimada con un muro: si la puerta de un divisor cae sobre el muro perimetral o sobre
## el muro de OTRO divisor (posible desde que los divisores crecen y se cruzan), la reubica a una celda
## interna LIMPIA del tramo. Si no hay ninguna, deja el divisor sin puerta (ensure_connectivity abrirá un
## hueco si separa regiones). Corre ANTES de ensure_connectivity (la puerta nueva ya cuenta como pasable).
func resolve_overlaps(plans: Array) -> void:
	for pl in plans:
		var dc: Vector2i = pl["door_cell"]
		if dc.x == -9999:
			continue
		var foreign := _foreign_walls(pl, plans)
		if _has_wall_on_edge(dc, int(pl["side"])) or foreign.has(dc):
			pl["door_cell"] = _find_clean_door(pl, foreign)

## Celdas que son MURO de los OTROS divisores (no de `pl`): para detectar cruces de divisores.
func _foreign_walls(pl: Dictionary, plans: Array) -> Dictionary:
	var f := {}
	for other in plans:
		if other == pl:
			continue
		for c in other["cells"]:
			if c != other["door_cell"]:
				f[c] = true
	return f

## Celda interna del tramo (la más cercana al centro) que NO tenga muro perimetral ni de otro divisor.
## (-9999,-9999) si no hay ninguna limpia → el divisor queda sin puerta (lo cubre ensure_connectivity).
func _find_clean_door(pl: Dictionary, foreign: Dictionary) -> Vector2i:
	var cells: Array = pl["cells"]
	var n := cells.size()
	var best := Vector2i(-9999, -9999)
	var bestd := 1 << 30
	var side: int = int(pl["side"])
	for i in range(1, n - 1):
		var c: Vector2i = cells[i]
		if _has_wall_on_edge(c, side) or foreign.has(c):
			continue
		var dd: int = absi(i - n / 2)
		if dd < bestd:
			bestd = dd
			best = c
	return best

## REGLA: ninguna región de piso queda sin salida. Sobre los PLANES (antes de renderizar), hace un
## flood-fill caminable desde `spawn` (los muros de divisor bloquean; las PUERTAS no, el jugador las
## abre) y, por cada región sellada, marca una celda-muro de su frontera como `extra_gaps` → abre un
## hueco que la reconecta. Itera hasta que todo el piso alcanzable desde el spawn queda conectado.
func ensure_connectivity(plans: Array, spawn: Vector2i) -> void:
	if not _is_floor(spawn):
		return
	# Aristas bloqueadas por muros sólidos (no la puerta): pair-key → {plan, cell}.
	var blocked := {}
	for plan in plans:
		for cell in plan["cells"]:
			if cell == plan["door_cell"]:
				continue
			var nb: Vector2i = WallSegment.neighbor(cell, plan["side"])
			blocked[_pair(cell, nb)] = {"plan": plan, "cell": cell}
	var reached := _flood(spawn, blocked)
	var guard := 0
	while guard < 256:
		guard += 1
		var opened := false
		for key in blocked.keys():
			var pr: Array = _unpair(key)
			if reached.has(pr[0]) != reached.has(pr[1]):   # frontera alcanzado ↔ sellado
				var info: Dictionary = blocked[key]
				(info["plan"]["extra_gaps"] as Dictionary)[info["cell"]] = true   # abrir hueco acá
				blocked.erase(key)
				opened = true
				break
		if not opened:
			break
		reached = _flood(spawn, blocked)

## BFS caminable sobre el piso desde `start`, saltando aristas en `blocked`. Devuelve set de celdas alcanzadas.
func _flood(start: Vector2i, blocked: Dictionary) -> Dictionary:
	var reached := {start: true}
	var q: Array = [start]
	var head := 0
	var sides := [WallSegment.Side.NW, WallSegment.Side.NE, WallSegment.Side.SE, WallSegment.Side.SW]
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for s in sides:
			var nb: Vector2i = WallSegment.neighbor(c, s)
			if reached.has(nb) or not _is_floor(nb):
				continue
			if blocked.has(_pair(c, nb)):
				continue
			reached[nb] = true
			q.append(nb)
	return reached

## Clave canónica (orden estable) de la arista entre dos celdas.
func _pair(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d,%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d,%d,%d" % [b.x, b.y, a.x, a.y]

func _unpair(key: String) -> Array:
	var p: PackedStringArray = key.split(",")
	return [Vector2i(int(p[0]), int(p[1])), Vector2i(int(p[2]), int(p[3]))]

## Celda del divisor para el índice `i` a lo largo del eje. orient 0: u=i, v=line. orient 1: u=line, v=i.
func _cell(base: Vector2, orient: int, line: int, i: int) -> Vector2i:
	var u: int = i if orient == 0 else line
	var v: int = line if orient == 0 else i
	return d.local_to_map(base + ISO_A * u + ISO_B * v)

## ¿La celda es piso (grid==1)? Fuera del grid = vacío/borde → false (ahí hay muro perpendicular).
func _is_floor(c: Vector2i) -> bool:
	return c.y >= 0 and c.y < d.grid.size() and c.x >= 0 and c.x < d.grid[c.y].size() and d.grid[c.y][c.x] == 1

## Region de una celda (-999 fuera de rango). El divisor frena al cambiar de region.
func _region_at(c: Vector2i) -> int:
	if c.y < 0 or c.y >= d.region_id.size() or c.x < 0 or c.x >= (d.region_id[c.y] as Array).size():
		return -999
	return int(d.region_id[c.y][c.x])

func _has_wall_on_edge(cell: Vector2i, side: int) -> bool:
	for seg in d._wall_segments:
		if seg.interior_cell == cell and int(seg.side) == side:
			return true
	return false

## Asigna a un sprite de muro su span propio vía uniform por-instancia (el shader lo usa directo).
func _apply_span(holder: Node2D, a: Vector2, b: Vector2) -> void:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var ci := holder.get_child(0) as CanvasItem
	if ci == null:
		return
	ci.set_instance_shader_parameter("use_manual_span", true)
	ci.set_instance_shader_parameter("manual_span_a", a)
	ci.set_instance_shader_parameter("manual_span_b", b)

## Colisión del muro del divisor: usa el polígono REAL del muro (wall_ne / wall_nw del JSON, mismo que
## el perímetro). Si la key falta, fallback a la tira fina hardcoded (comportamiento previo).
func _add_wall_collision(cell: Vector2i, orient: int, e0: Vector2, e1: Vector2, nrm: Vector2) -> void:
	if d._iso_bounds == null or not is_instance_valid(d._iso_bounds):
		return
	var key := "wall_ne" if orient == 0 else "wall_nw"
	var polys = d._wall_coll.get(key, null)
	var pos := d.map_to_local(cell)
	if polys != null:
		for poly in polys:
			var cp := CollisionPolygon2D.new()
			cp.polygon = poly
			cp.position = pos
			d._iso_bounds.add_child(cp)
	else:
		var cs := CollisionShape2D.new()
		var fallback := ConvexPolygonShape2D.new()
		fallback.points = PackedVector2Array([e0 + nrm, e1 + nrm, e1 - nrm, e0 - nrm])
		cs.shape = fallback
		cs.position = pos
		d._iso_bounds.add_child(cs)

## Marca/desmarca una celda como SÓLIDA en el nav de mobs (AStar). El player NO usa AStar (anda por
## física), así que esto solo evita que los mobs caminen "a través" del muro del divisor / puerta cerrada.
func _nav_solid(cell: Vector2i, solid: bool) -> void:
	if d._iso_astar != null and d._iso_astar.is_in_boundsv(cell):
		d._iso_astar.set_point_solid(cell, solid)

## Aristas de los muros de DIVISOR para el minimapa: [{cell, a, b}] en coords world-local del dungeon
## (mismo formato que `Dungeon.get_wall_edges`). Los muros de sub-cuarto NO van acá (son WallSegment
## y ya salen por `get_wall_edges`); estos son los divisores, que se pintan como sprites aparte.
func get_wall_edges() -> Array:
	var out: Array = []
	for m in _wall_marks:
		var e: PackedVector2Array = d._wall_edge_for_side(int(m["side"]))
		if e.size() < 2:
			continue
		var base: Vector2 = d.map_to_local(m["cell"])
		out.append({"cell": m["cell"], "a": base + e[0], "b": base + e[1]})
	return out

## Aristas de TODAS las puertas (divisor Y región: ambas pasan por `_add_door` → `_doors`) en el mismo
## formato que las paredes ({cell, a, b}, world-local) → el minimapa las dibuja como LÍNEA ROJA sobre la
## misma geometría del muro (alineada, sin el desfase del punto en el centro de celda). El lado sale de
## `closed_key` (wall_nw/ne/se/sw).
func get_door_edges() -> Array:
	var out: Array = []
	for rec in _doors:
		var side := _side_from_key(String(rec.get("closed_key", "wall_nw")))
		var e: PackedVector2Array = d._wall_edge_for_side(side)
		if e.size() < 2:
			continue
		var base: Vector2 = d.map_to_local(rec["cell"])
		out.append({"cell": rec["cell"], "a": base + e[0], "b": base + e[1]})
	return out

func _side_from_key(k: String) -> int:
	match k:
		"wall_ne": return WallSegment.Side.NE
		"wall_se": return WallSegment.Side.SE
		"wall_sw": return WallSegment.Side.SW
	return WallSegment.Side.NW

## Sufijo de cara ("nw"/"ne"/"se"/"sw") a partir del SRC_WALL_* base → arte de puerta y keys de colisión por lado.
func _src_suffix(base_src: int) -> String:
	if base_src == d.SRC_WALL_NE: return "ne"
	if base_src == d.SRC_WALL_SE: return "se"
	if base_src == d.SRC_WALL_SW: return "sw"
	return "nw"

## Etapa 3 (regiones): puerta REAL en una arista de FRONTERA DE REGIÓN (edge_features == "door"), en
## CUALQUIERA de las 4 caras. Deriva el muro base + la geometría de la arista del rombo (cell-local) y
## reusa `_add_door` (sprite cerrada/abierta + colisión + nav + abrir con clic derecho). El span es el de
## esta única celda (la puerta no forma parte de un run de muro). Devuelve el holder o null.
func spawn_region_door(cell: Vector2i, side: int) -> Node2D:
	var base_src: int = d._base_for_side(side)
	var edge: PackedVector2Array = d._wall_edge_for_side(side)   # 2 vértices cell-local de la arista del rombo
	if edge.size() < 2:
		return null
	var e0: Vector2 = edge[0]
	var e1: Vector2 = edge[1]
	var nrm: Vector2 = (e1 - e0).orthogonal().normalized() * 8.0   # solo fallback (wall_* existe en las 4 caras)
	var pos: Vector2 = d.map_to_local(cell)
	var span_a: Vector2 = d.to_global(pos + e0)
	var span_b: Vector2 = d.to_global(pos + e1)
	var dh := _add_door(cell, base_src, span_a, span_b, e0, e1, nrm)
	if dh != null:
		_region_door_holders.append(dh)   # se libera en clear() (no viven en _dividers)
	return dh

## Puerta en el hueco: sprite CERRADA (DoorNE/NW/SE/SW) + colisión + área clickeable (click → abre/cierra).
func _add_door(cell: Vector2i, base_src: int, span_a: Vector2, span_b: Vector2, e0: Vector2, e1: Vector2, nrm: Vector2) -> Node2D:
	var suf := _src_suffix(base_src)   # "nw"/"ne"/"se"/"sw" según la cara → arte y colisión por lado
	var door_src := int(d._door_src.get(base_src, base_src))
	var closed_tex: Texture2D = d._wall_tex.get(door_src)
	var origin: Vector2 = d._wall_origin.get(door_src, Vector2.ZERO)
	var open_path := "res://assets/iso/walls/variations/OpenDoor%s.png" % suf.to_upper()
	var open_tex: Texture2D = load(open_path)
	var holder := d._spawn_wall_sprite(cell, door_src, false)
	_apply_span(holder, span_a, span_b)
	# Colisión = CollisionPolygon2D (consistente con _install_wall_collisions). Cerrada usa el polígono
	# REAL del muro (wall_ne/wall_nw, dibujado en wall_origin_tool); abierta swappea a open_door_ne/nw,
	# que puede tener MÚLTIPLES polígonos (dos marcos a los costados del hueco). `colls` es la pool de
	# CollisionPolygon2D; crece si la versión abierta necesita más slots que la cerrada.
	var closed_key := "wall_%s" % suf
	var open_key := "open_door_%s" % suf   # SE/SW sin colisión abierta en el JSON → toggle_door cae a "disable all" (pasás)
	var colls: Array[CollisionPolygon2D] = []
	if d._iso_bounds != null and is_instance_valid(d._iso_bounds):
		var fallback := PackedVector2Array([e0 + nrm, e1 + nrm, e1 - nrm, e0 - nrm])
		var closed_polys = d._wall_coll.get(closed_key, [fallback])
		for poly in closed_polys:
			var cp := CollisionPolygon2D.new()
			cp.polygon = poly
			cp.position = d.map_to_local(cell)
			d._iso_bounds.add_child(cp)
			colls.append(cp)
	# Área clickeable sobre el sprite alto.
	var area := Area2D.new()
	area.input_pickable = true
	var acs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200, 260)
	acs.shape = rect
	acs.position = Vector2(0, -90)
	area.add_child(acs)
	holder.add_child(area)
	var idx := _doors.size()
	area.input_event.connect(func(_vp, ev, _si): _on_door_input(idx, ev))
	_nav_solid(cell, true)   # puerta CERRADA bloquea el nav de mobs
	_doors.append({"holder": holder, "colls": colls, "open": false, "closed_tex": closed_tex, "open_tex": open_tex,
		"origin": origin, "cell": cell, "closed_key": closed_key, "open_key": open_key})
	return holder

## Abrir/cerrar con CLIC DERECHO (la acción de interacción del juego; el izquierdo es ATACAR) estando cerca.
func _on_door_input(idx: int, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	if idx < 0 or idx >= _doors.size():
		return
	var holder = _doors[idx]["holder"]
	var pl := GameState.player as Node2D
	if pl != null and is_instance_valid(holder) and pl.global_position.distance_to(holder.global_position) <= DOOR_NEAR:
		toggle_door(idx)
		d.get_viewport().set_input_as_handled()

## Abre/cierra: swap del sprite (cerrada ↔ abierta) + togglea la colisión (abierta = pasás).
func toggle_door(idx: int) -> void:
	if idx < 0 or idx >= _doors.size():
		return
	var rec: Dictionary = _doors[idx]
	rec["open"] = not bool(rec["open"])
	var holder = rec["holder"]
	if is_instance_valid(holder):
		Audio.play_at("door", holder)   # feedback posicional al abrir/cerrar (divisor y puertas de región)
	if is_instance_valid(holder) and holder.get_child_count() > 0:
		var spr := holder.get_child(0) as Sprite2D
		if spr != null:
			spr.texture = rec["open_tex"] if rec["open"] else rec["closed_tex"]
			spr.offset = -(rec["origin"] as Vector2)
	# Swap de N polígonos. Si la versión target tiene MÁS slots que la pool actual, creamos los faltantes.
	# Si tiene MENOS, los sobrantes los deshabilitamos (no los borramos, para reusar al ciclar).
	var colls: Array = rec["colls"]
	var want_key: String = rec["open_key"] if rec["open"] else rec["closed_key"]
	var want_polys = d._wall_coll.get(want_key, null)
	if want_polys != null:
		while colls.size() < want_polys.size():
			var cp_new := CollisionPolygon2D.new()
			cp_new.position = d.map_to_local(rec["cell"])
			if d._iso_bounds != null and is_instance_valid(d._iso_bounds):
				d._iso_bounds.add_child(cp_new)
			colls.append(cp_new)
		for i in want_polys.size():
			(colls[i] as CollisionPolygon2D).polygon = want_polys[i]
			(colls[i] as CollisionPolygon2D).disabled = false
		for i in range(want_polys.size(), colls.size()):
			(colls[i] as CollisionPolygon2D).disabled = true
	else:
		# Fallback (open_door_* todavía no dibujado): disable todas → pasás por toda la celda (igual que antes).
		for cp in colls:
			(cp as CollisionPolygon2D).disabled = bool(rec["open"])
	_nav_solid(rec["cell"], not bool(rec["open"]))   # abierta = el nav de mobs pasa por el hueco

## CUTAWAY por-divisor (llamar cada frame). Cada divisor fadea SOLO si el player está detrás de SU línea
## (más allá de la arista base, -0.5). NE testea la coord v; NW testea la u.
func update_cutaway(player: Node2D) -> void:
	if _dividers.is_empty() or player == null or not is_instance_valid(player):
		return
	var feet := player.get_node_or_null("Feet") as Node2D
	var anchor: Vector2 = feet.global_position if feet != null else player.global_position
	var world := d.to_local(anchor)
	for rec in _dividers:
		var p: Vector2 = world - (rec["base"] as Vector2)
		var v := (p.y / 64.0 - p.x / 128.0) * 0.5
		var u := (p.y / 64.0 + p.x / 128.0) * 0.5
		var coord: float = v if int(rec["orient"]) == 0 else u
		var target: float = CUTAWAY_ALPHA if coord < float(rec["line"]) - 0.5 else 1.0
		for h in rec["holders"]:
			if is_instance_valid(h):
				h.modulate.a = lerpf(h.modulate.a, target, 0.18)
