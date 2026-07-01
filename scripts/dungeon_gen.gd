extends RefCounted
class_name DungeonGen
## PROCGEN de la mazmorra ISOMÉTRICA, extraído de dungeon.gd (movimiento mecánico, misma lógica).
## Arma el grid lógico (piso/vacío) + el grafo de salas (MST+loops) + roles por BFS, y deja
## spawn/exit listos. El RENDER (pintado iso, muros, nav, luz, niebla) sigue viviendo en Dungeon.
## Toda referencia a estado/consts/exports/métodos del nodo Dungeon va prefijada con `d.`.

var d: Dungeon

func _init(dungeon: Dungeon) -> void:
	d = dungeon

# ---------------------------------------------------------------------------
# Generación de la grilla
# ---------------------------------------------------------------------------
func gen_grid() -> void:
	d.rooms.clear()
	d._gen_room_cells = []
	d._room_specs = []   # geometría iso por sala (origin/w/d) → la usan los divisores internos
	d.grid = []
	for y in d.MAP_H:
		var row: Array = []
		row.resize(d.MAP_W)
		row.fill(0)
		d.grid.append(row)

	# Ocupación (celdas talladas + margen cardinal de 1) para test de solape entre paralelogramos:
	# el bbox de un rombo iso solapa a sus vecinos, así que NO sirve Rect2i.intersects — se testea celda a celda.
	var occupied := {}
	for i in _room_count_for_depth():
		for attempt in 30:
			var w := Rng.range_i(d.iso_room_width.x, d.iso_room_width.y)
			var dd := Rng.range_i(d.iso_room_depth.x, d.iso_room_depth.y)
			# Origen en una banda interior segura; el chequeo de bordes + reintentos descarta los malos.
			var origin := Vector2i(Rng.range_i(dd + 1, d.MAP_W - w - 2), Rng.range_i(1, d.MAP_H - w - dd - 2))
			var cells := _iso_room_cells(origin, w, dd)
			var ok := true
			for c in cells:
				if c.x < 1 or c.y < 1 or c.x >= d.MAP_W - 1 or c.y >= d.MAP_H - 1 or occupied.has(c):
					ok = false
					break
			if not ok:
				continue
			for c in cells:
				d.grid[c.y][c.x] = 1
				occupied[c] = true
				occupied[c + Vector2i(1, 0)] = true
				occupied[c + Vector2i(-1, 0)] = true
				occupied[c + Vector2i(0, 1)] = true
				occupied[c + Vector2i(0, -1)] = true
			d._gen_room_cells.append(cells)
			d.rooms.append(_cells_bbox(cells))
			d._room_specs.append({"origin": origin, "w": w, "d": dd})
			break
	# Conexión por GRAFO (MST + algunos loops) en vez de cadena lineal sala-a-sala.
	_connect_rooms()
	if not d.USE_DOORS:
		_remove_thin_walls()   # en modo puertas se saltea: abriría muros entre salas vecinas (rompe el aislamiento)
		if not DEBUG_NO_SMOOTH:
			_smooth_double_corners()   # ≥1 tile recto entre esquinas: ningún muro toca dos esquinas
	if DEBUG_CORNERS:
		_debug_dump_corners()
	_build_regions()   # ETAPA 1: capa semántica region_id (salas + corredores), base de muros/puertas por frontera

## ETAPA 1 (region_id): grilla semántica paralela a `grid`. -1 = EMPTY (no piso); 0..R-1 = salas (de
## `_gen_room_cells`); R.. = componentes conexas de CORREDOR (flood-fill del piso que no es sala). Es la base
## para derivar muros y puertas por FRONTERA DE REGIÓN (region != region_vecino). Por ahora solo metadata:
## NO cambia el render todavía (eso es Etapa 2).
func _build_regions() -> void:
	var MW: int = d.MAP_W
	var MH: int = d.MAP_H
	d.region_id = []
	for y in MH:
		var row: Array = []
		row.resize(MW)
		row.fill(-1)
		d.region_id.append(row)
	# Salas → región = índice de sala (solo celdas que son piso, para que region==-1 ⟺ no-piso).
	for i in d._gen_room_cells.size():
		for c in d._gen_room_cells[i]:
			if c.y >= 0 and c.y < MH and c.x >= 0 and c.x < MW and int((d.grid[c.y] as Array)[c.x]) == 1:
				d.region_id[c.y][c.x] = i
	# Corredores → cada componente conexa de piso-sin-región es una región nueva.
	var WS = d.WallSegment
	var sides := [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]
	var next_id: int = d._gen_room_cells.size()
	for y in MH:
		for x in MW:
			if int((d.grid[y] as Array)[x]) != 1 or int((d.region_id[y] as Array)[x]) != -1:
				continue
			var stack: Array = [Vector2i(x, y)]
			d.region_id[y][x] = next_id
			while not stack.is_empty():
				var cc: Vector2i = stack.pop_back()
				for s in sides:
					var n: Vector2i = WS.neighbor(cc, s)
					if n.y >= 0 and n.y < MH and n.x >= 0 and n.x < MW and int((d.grid[n.y] as Array)[n.x]) == 1 and int((d.region_id[n.y] as Array)[n.x]) == -1:
						d.region_id[n.y][n.x] = next_id
						stack.append(n)
			next_id += 1

## Celdas (sin escribir grid) de una sala iso lógica width×depth desde `origin`. Compute-only para
## el test de solape del procgen; carve_iso_room hace lo mismo pero además escribe el piso.
func _iso_room_cells(origin: Vector2i, width: int, depth: int) -> Array:
	var cells: Array = []
	var base := d.map_to_local(origin)
	for u in width:
		for v in depth:
			cells.append(d.local_to_map(base + ISO_AXIS_A * u + ISO_AXIS_B * v))
	return cells

func _cells_bbox(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var mn: Vector2i = cells[0]
	var mx: Vector2i = cells[0]
	for c in cells:
		mn = mn.min(c)
		mx = mx.max(c)
	return Rect2i(mn, mx - mn + Vector2i.ONE)

## Abre a piso cualquier muro con piso en lados OPUESTOS (elimina muros "hoja" /
## grosor 0 / pilares sueltos). 4 pasadas, como el dungeon.js de Pixi.
func _remove_thin_walls() -> void:
	for _pass in 4:
		var open: Array = []
		for ty in range(1, d.MAP_H - 1):
			for tx in range(1, d.MAP_W - 1):
				if d.grid[ty][tx] != 0:
					continue
				var horiz: bool = d.grid[ty][tx - 1] == 1 and d.grid[ty][tx + 1] == 1
				var vert: bool = d.grid[ty - 1][tx] == 1 and d.grid[ty + 1][tx] == 1
				if horiz or vert:
					open.append(Vector2i(tx, ty))
		for c in open:
			d.grid[c.y][c.x] = 1

## REGLA "≥1 tile recto entre giros del muro" (las W/S/C/escaleras que no queremos). La métrica CORRECTA son
## los TRAMOS RECTOS de muro = spans colineales del mismo lado (`_wall_span1`): un span de largo 1 = un tile
## recto aislado entre dos giros = la violación. Diagnóstico: ~90% de los spans-1 están en los CORREDORES
## (las salas iso ya son rectas). Suavizado DIRIGIDO por la métrica (hill-climbing): por cada span-1, prueba
## abrir/rellenar las celdas que lo tocan y SOLO acepta la edición si BAJA el total de spans-1 — así nunca
## empeora (un tallado ciego sí empeoraba). Guard: no rellena celdas de SALA (no las reforma) ni nada que
## orfane una región (flood desde la región mayor). Medido en vivo: 39 → 2 spans-1 (–95%).
func _smooth_double_corners() -> void:
	var WS = d.WallSegment
	var MW: int = d.MAP_W
	var MH: int = d.MAP_H
	var sides := [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]
	var grid: Array = d.grid
	# --- Precómputo (sin method-calls en los loops O(F)): normal/offset de línea por lado; delta de vecino y
	# lado-opuesto por paridad de fila (TileSet STACKED); map_to_local por celda ---
	var nrmv: Array = []          # normal de la línea por lado
	var e0d: Array = []           # e[0]·normal por lado (parte constante del offset de línea)
	for s in sides:
		var e := d._wall_edge_for_side(s)
		var dir: Vector2 = ((e[1] as Vector2) - (e[0] as Vector2)).normalized()
		var nv := Vector2(-dir.y, dir.x)
		nrmv.append(nv)
		e0d.append((e[0] as Vector2).dot(nv))
	var ndelta := [[], []]        # ndelta[paridad][lado] = delta Vector2i al vecino
	var backside := [[], []]      # backside[paridad][lado] = lado del vecino cuyo neighbor() devuelve c
	for par in 2:
		var probe := Vector2i(5, 4 + par)
		var dlr: Array = []
		var bsr: Array = []
		for si in 4:
			var n: Vector2i = WS.neighbor(probe, sides[si])
			dlr.append(n - probe)
			var b := -1
			for s2 in 4:
				if WS.neighbor(n, sides[s2]) == probe:
					b = s2
					break
			bsr.append(b)
		ndelta[par] = dlr
		backside[par] = bsr
	var lb: Array = []            # map_to_local por celda (aplanado y*MW+x)
	lb.resize(MW * MH)
	for y in MH:
		var yb := y * MW
		for x in MW:
			lb[yb + x] = d.map_to_local(Vector2i(x, y))
	# Celdas de SALA del piso ACTUAL (de _gen_room_cells, ya poblado en gen_grid — NO usar _room_of, que se
	# asigna recién después de gen_grid). El suavizado NO debe reformar salas: si no, los divisores (que crecen
	# hasta topar muro según la geometría original de la sala) quedan descalzados y no van de muro a muro.
	var roomset := {}
	for rcells in d._gen_room_cells:
		for rc in rcells:
			roomset[rc] = true
	# --- Tracker incremental: gcount[clave de línea]=#aristas, L[0]=#spans de largo 1 (todo inline) ---
	var gcount := {}
	var L := [0]
	for y in MH:
		var grow: Array = grid[y]
		var yb := y * MW
		var ndp: Array = ndelta[y & 1]
		for x in MW:
			if int(grow[x]) != 1:
				continue
			var lbc: Vector2 = lb[yb + x]
			for si in 4:
				var dd: Vector2i = ndp[si]
				var ny := y + dd.y
				var nx := x + dd.x
				if ny >= 0 and ny < MH and nx >= 0 and nx < MW and int((grid[ny] as Array)[nx]) == 1:
					continue
				var k := si * 1000000 + int(round((lbc.dot(nrmv[si]) + float(e0d[si])) / 3.0)) + 500000
				var old: int = int(gcount.get(k, 0))
				if old == 1:
					L[0] -= 1
				gcount[k] = old + 1
				if old + 1 == 1:
					L[0] += 1
	# Togglea c (piso↔muro) tocando solo las aristas de c + las de sus vecinos que miran a c. Su propio inverso.
	var toggle := func(c: Vector2i) -> void:
		var ndp: Array = ndelta[c.y & 1]
		var bsp: Array = backside[c.y & 1]
		var aff: Array = [[c, 0], [c, 1], [c, 2], [c, 3]]
		for si in 4:
			var b: int = bsp[si]
			if b >= 0:
				var dd: Vector2i = ndp[si]
				aff.append([Vector2i(c.x + dd.x, c.y + dd.y), b])
		for e in aff:                                  # saca las aristas-muro que existen AHORA
			var ec: Vector2i = e[0]
			if ec.x < 0 or ec.x >= MW or ec.y < 0 or ec.y >= MH or int((grid[ec.y] as Array)[ec.x]) != 1:
				continue
			var es: int = e[1]
			var dd: Vector2i = (ndelta[ec.y & 1] as Array)[es]
			var ny := ec.y + dd.y
			var nx := ec.x + dd.x
			if ny >= 0 and ny < MH and nx >= 0 and nx < MW and int((grid[ny] as Array)[nx]) == 1:
				continue
			var k := es * 1000000 + int(round(((lb[ec.y * MW + ec.x] as Vector2).dot(nrmv[es]) + float(e0d[es])) / 3.0)) + 500000
			var old: int = int(gcount.get(k, 0))
			if old <= 0:
				continue
			if old == 1:
				L[0] -= 1
			if old - 1 == 1:
				L[0] += 1
			if old - 1 == 0:
				gcount.erase(k)
			else:
				gcount[k] = old - 1
		grid[c.y][c.x] = (0 if int((grid[c.y] as Array)[c.x]) == 1 else 1)
		for e in aff:                                  # mete las que existen tras el flip
			var ec: Vector2i = e[0]
			if ec.x < 0 or ec.x >= MW or ec.y < 0 or ec.y >= MH or int((grid[ec.y] as Array)[ec.x]) != 1:
				continue
			var es: int = e[1]
			var dd: Vector2i = (ndelta[ec.y & 1] as Array)[es]
			var ny := ec.y + dd.y
			var nx := ec.x + dd.x
			if ny >= 0 and ny < MH and nx >= 0 and nx < MW and int((grid[ny] as Array)[nx]) == 1:
				continue
			var k := es * 1000000 + int(round(((lb[ec.y * MW + ec.x] as Vector2).dot(nrmv[es]) + float(e0d[es])) / 3.0)) + 500000
			var old: int = int(gcount.get(k, 0))
			if old == 1:
				L[0] -= 1
			gcount[k] = old + 1
			if old + 1 == 1:
				L[0] += 1
	# Celdas de piso con un span de largo 1 (candidatos del pase) — inline.
	var span1cells := func() -> Array:
		var out: Array = []
		for y in MH:
			var grow: Array = grid[y]
			var yb := y * MW
			var ndp: Array = ndelta[y & 1]
			for x in MW:
				if int(grow[x]) != 1:
					continue
				var lbc: Vector2 = lb[yb + x]
				for si in 4:
					var dd: Vector2i = ndp[si]
					var ny := y + dd.y
					var nx := x + dd.x
					if ny >= 0 and ny < MH and nx >= 0 and nx < MW and int((grid[ny] as Array)[nx]) == 1:
						continue
					var k := si * 1000000 + int(round((lbc.dot(nrmv[si]) + float(e0d[si])) / 3.0)) + 500000
					if int(gcount.get(k, 0)) == 1:
						out.append([Vector2i(x, y), si])
		return out
	# Piso alcanzable desde anchor — flood INLINE (sin method-calls) para el guard de conectividad de los rellenos.
	var reach_fast := func(anchor: Vector2i) -> int:
		var seen := {anchor: true}
		var stack: Array = [anchor]
		var cnt := 0
		while not stack.is_empty():
			var cc: Vector2i = stack.pop_back()
			cnt += 1
			var ndp2: Array = ndelta[cc.y & 1]
			for si in 4:
				var dd: Vector2i = ndp2[si]
				var nyc := cc.y + dd.y
				var nxc := cc.x + dd.x
				if nyc >= 0 and nyc < MH and nxc >= 0 and nxc < MW and int((grid[nyc] as Array)[nxc]) == 1:
					var nc := Vector2i(nxc, nyc)
					if not seen.has(nc):
						seen[nc] = true
						stack.append(nc)
		return cnt
	var anchor := _largest_region_anchor()        # ancla estable (celda de la región mayor); 1 sola vez
	# --- Hill-climbing: acepta un toggle SOLO si baja L[0]; conteo O(1) por toggle; guard de conectividad ---
	for _pass in 6:
		if L[0] == 0 or anchor.x < 0:
			break
		var s1: Array = span1cells.call()
		if s1.is_empty():
			break
		var cands := {}
		for oe in s1:
			var cell: Vector2i = oe[0]
			var dd: Vector2i = (ndelta[cell.y & 1] as Array)[oe[1]]
			cands[cell] = true
			cands[Vector2i(cell.x + dd.x, cell.y + dd.y)] = true   # vecino exterior (candidato a tallar)
		var reach: int = reach_fast.call(anchor)
		var cur: int = L[0]
		var improved := false
		for cand in cands:
			var c: Vector2i = cand
			if c.y < 1 or c.y >= MH - 1 or c.x < 1 or c.x >= MW - 1:
				continue
			var was_floor: bool = int((grid[c.y] as Array)[c.x]) == 1
			if was_floor:
				if roomset.has(c):
					continue                               # no rellenar celda de sala
			else:
				var ndp3: Array = ndelta[c.y & 1]          # tallar muro lindero a sala la expandiría → no
				var near_room := false
				for si in 4:
					var dd3: Vector2i = ndp3[si]
					if roomset.has(Vector2i(c.x + dd3.x, c.y + dd3.y)):
						near_room = true
						break
				if near_room:
					continue
			toggle.call(c)
			var ok: bool = L[0] < cur
			if ok and was_floor and int(reach_fast.call(anchor)) < reach - 1:
				ok = false                                 # el relleno desconectaría una región
			if ok:
				cur = L[0]
				reach = (reach - 1) if was_floor else int(reach_fast.call(anchor))
				improved = true
			else:
				toggle.call(c)                             # revierte (incremental)
		if not improved:
			break

func _floor_at(c: Vector2i) -> bool:
	return c.y >= 0 and c.y < d.grid.size() and c.x >= 0 and c.x < d.grid[c.y].size() and int(d.grid[c.y][c.x]) == 1

## Tramos rectos de muro de largo 1. Devuelve [cantidad, lista de [interior_cell, side]]. Un span = aristas-muro
## colineales del mismo lado (agrupadas por lado + línea perpendicular); largo 1 = tramo recto aislado entre
## dos giros = una W/S/C/escalón.
func _wall_span1() -> Array:
	var WS = d.WallSegment
	var sides := [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]
	var groups := {}
	for ty in range(d.MAP_H):
		for tx in range(d.MAP_W):
			if int(d.grid[ty][tx]) != 1:
				continue
			var c := Vector2i(tx, ty)
			var base := d.map_to_local(c)
			for s in sides:
				if _floor_at(WS.neighbor(c, s)):
					continue
				var e := d._wall_edge_for_side(s)
				if e.size() < 2:
					continue
				var a: Vector2 = base + e[0]
				var b: Vector2 = base + e[1]
				var dd := b - a
				if dd.length() < 0.001:
					continue
				var dn := dd.normalized()
				var nrm := Vector2(-dn.y, dn.x)
				var off := roundf(a.dot(nrm) / 3.0)
				var key := "%d_%d" % [int(s), int(off)]
				if not groups.has(key):
					groups[key] = []
				groups[key].append([c, s])
	var cnt := 0
	var offs: Array = []
	for k in groups:
		if groups[k].size() == 1:
			cnt += 1
			offs.append(groups[k][0])
	return [cnt, offs]

## Celdas de piso alcanzables (vecindad iso) desde `anchor`.
func _reach_count(anchor: Vector2i) -> int:
	var WS = d.WallSegment
	var sides := [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]
	var seen := {anchor: true}
	var stack: Array = [anchor]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for s in sides:
			var n: Vector2i = WS.neighbor(c, s)
			if _floor_at(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size()

## Una celda cualquiera de la mayor región de piso conexa (ancla estable para el guard de conectividad).
func _largest_region_anchor() -> Vector2i:
	var WS = d.WallSegment
	var sides := [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]
	var visited := {}
	var best := Vector2i(-1, -1)
	var best_sz := 0
	for ty in range(d.MAP_H):
		for tx in range(d.MAP_W):
			var c := Vector2i(tx, ty)
			if int(d.grid[ty][tx]) != 1 or visited.has(c):
				continue
			var st: Array = [c]
			visited[c] = true
			var sz := 0
			var first := c
			while not st.is_empty():
				var cc: Vector2i = st.pop_back()
				sz += 1
				for s in sides:
					var n: Vector2i = WS.neighbor(cc, s)
					if _floor_at(n) and not visited.has(n):
						visited[n] = true
						st.append(n)
			if sz > best_sz:
				best_sz = sz
				best = first
	return best

## DEBUG: vuelca el grid + esquinas + offenders a user://corner_debug.txt para estudiar la topología.
## Leyenda: '#'=muro/vacío  '.'=piso (0 esquinas)  'o'=1 esquina (codo limpio)  '2'=2+ esquinas  '!'=OFFENDER
## (una arista-muro toca 2 esquinas). Después de cada celda offender se listan sus coords abajo.
const DEBUG_CORNERS := false   # poné true para volcar user://corner_debug.txt (estudio de topología)
var DEBUG_NO_SMOOTH := false   # toggle en vivo (d._gen.DEBUG_NO_SMOOTH) para A/B del suavizado dirigido de spans
func _debug_dump_corners() -> void:
	var WS = d.WallSegment
	var minx := d.MAP_W; var maxx := 0; var miny := d.MAP_H; var maxy := 0
	for y in d.MAP_H:
		for x in d.MAP_W:
			if int(d.grid[y][x]) == 1:
				minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	# Pase 1: marca qué celdas de piso son esquina (≥1 vértice con 2 lados-muro adyacentes).
	var is_corner := {}
	for y in d.MAP_H:
		for x in d.MAP_W:
			if int(d.grid[y][x]) != 1: continue
			var c := Vector2i(x, y)
			var wnw := not _floor_at(WS.neighbor(c, WS.Side.NW))
			var wne := not _floor_at(WS.neighbor(c, WS.Side.NE))
			var wse := not _floor_at(WS.neighbor(c, WS.Side.SE))
			var wsw := not _floor_at(WS.neighbor(c, WS.Side.SW))
			if (wnw and wne) or (wne and wse) or (wse and wsw) or (wnw and wsw):
				is_corner[c] = true
	var lines: PackedStringArray = []
	lines.append("floor bbox (x,y): (%d,%d)-(%d,%d)" % [minx, miny, maxx, maxy])
	lines.append("leyenda: '#'muro  '.'piso  'o'esquina-sola-OK  'X'esquina con OTRA esquina pegada (BAD)")
	var cross: Array = []
	for y in range(miny, maxy + 1):
		var row := ""
		for x in range(minx, maxx + 1):
			if int(d.grid[y][x]) != 1:
				row += "#"; continue
			var c := Vector2i(x, y)
			if not is_corner.has(c):
				row += "."; continue
			# ¿alguna celda de piso vecina (iso, por los lados sin muro) es TAMBIÉN esquina? → cruzada (BAD)
			var adj := false
			for side in [WS.Side.NW, WS.Side.NE, WS.Side.SE, WS.Side.SW]:
				var n := WS.neighbor(c, side)
				if _floor_at(n) and is_corner.has(n):
					adj = true; break
			if adj:
				cross.append(c); row += "X"
			else:
				row += "o"
		lines.append(row)
	lines.append("esquinas-sola total: %d   esquinas CRUZADAS (BAD): %d" % [is_corner.size(), cross.size()])
	for o in cross:
		lines.append("  %s" % o)
	var f := FileAccess.open("user://corner_debug.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines)); f.close()
	print("[corner_debug] -> user://corner_debug.txt  cruzadas=%d  bbox=(%d,%d)-(%d,%d)" % [cross.size(), minx, miny, maxx, maxy])

func carve_room(r: Rect2i) -> void:
	for yy in range(r.position.y, r.position.y + r.size.y):
		for xx in range(r.position.x, r.position.x + r.size.x):
			d.grid[yy][xx] = 1

# Ejes VISUALES locales del rombo (map_to_local del TileSet iso 256x128): +u baja a la
# derecha (SE), +v baja a la izquierda (SW). Un paralelogramo generado por estos ejes se ve
# como un rectángulo isométrico de lados rectos (sin serrucho).
const ISO_AXIS_A := Vector2(128, 64)    # +u → SE
const ISO_AXIS_B := Vector2(-128, 64)   # +v → SW

## Talla una habitación rectangular en sentido ISOMÉTRICO: un paralelogramo de width×depth
## tiles de piso. En vez de asumir que un Rect2i cartesiano produce un rectángulo iso (no lo
## hace: el grid es STACKED/offset → serrucho), recorre el espacio LOCAL desde map_to_local(origin)
## sumando los ejes visuales A/B y vuelve a celda con local_to_map. Resultado: 4 lados rectos
## (dos de width, dos de depth) y exactamente 4 esquinas. Devuelve las celdas talladas.
## NO modifica luz/arte: sólo escribe piso en `grid` (clamp a los límites del grid actual).
func carve_iso_room(origin: Vector2i, width: int, depth: int) -> Array:
	var cells: Array = []
	for cell in _iso_room_cells(origin, width, depth):
		if cell.y >= 0 and cell.y < d.grid.size() and cell.x >= 0 and cell.x < d.grid[cell.y].size():
			d.grid[cell.y][cell.x] = 1
			cells.append(cell)
	return cells

## Corredor en L ISOMÉTRICO entre dos salas: dos tramos rectos por los ejes VISUALES del rombo
## (ISO_AXIS_A = SE, ISO_AXIS_B = SW) en vez de fila/columna cartesiana — la cartesiana, en un grid
## STACKED, se ve como escalera dentada. ANCHO = 2 TILES (cada paso talla la celda + su vecina por el
## eje perpendicular). REGLA DE PASILLOS: nunca < 2 (los muros altos taparían un pasillo de 1 tile).
## Solo modo clásico; en USE_DOORS no se talla nada (salas aisladas).
func _connect(a: Vector2i, b: Vector2i) -> void:
	var aw := d.map_to_local(a)
	var delta := d.map_to_local(b) - aw
	# Descompone el vector entre centros en pasos (u, v) de los ejes iso: delta = u·A + v·B.
	var un := int(round(delta.x / 256.0 + delta.y / 128.0))
	var vn := int(round(delta.y / 128.0 - delta.x / 256.0))
	if Rng.chance(0.5):
		_carve_iso_leg(_carve_iso_leg(aw, ISO_AXIS_A, ISO_AXIS_B, un), ISO_AXIS_B, ISO_AXIS_A, vn)
	else:
		_carve_iso_leg(_carve_iso_leg(aw, ISO_AXIS_B, ISO_AXIS_A, vn), ISO_AXIS_A, ISO_AXIS_B, un)

## Talla un tramo recto iso: |n|+1 celdas desde `start_world` a lo largo de `axis` (el signo de n da la
## dirección), + la celda vecina por `perp` para el ancho 2. Devuelve el world del extremo (codo de la L).
func _carve_iso_leg(start_world: Vector2, axis: Vector2, perp: Vector2, n: int) -> Vector2:
	var step := 1 if n >= 0 else -1
	for k in range(abs(n) + 1):
		var w := start_world + axis * (step * k)
		_carve_cell(d.local_to_map(w))
		_carve_cell(d.local_to_map(w + perp))
	return start_world + axis * n

func _carve_cell(c: Vector2i) -> void:
	if c.y >= 0 and c.y < d.grid.size() and c.x >= 0 and c.x < d.grid[c.y].size():
		d.grid[c.y][c.x] = 1

## Conecta las salas con un Árbol de Expansión Mínima (Prim) sobre sus centros +
## ~15% de aristas cortas extra → grafo con algunos ciclos (no una cadena lineal:
## el jugador puede dar la vuelta). Garantiza conectividad total (el MST cubre todas
## las salas). Llena `_room_graph` (adyacencia) para los roles por BFS de fases futuras.
func _connect_rooms() -> void:
	d._room_graph = []
	var n := d.rooms.size()
	for _i in n:
		d._room_graph.append([])
	if n < 2:
		return
	var centers: Array = []
	for r in d.rooms:
		centers.append(r.get_center())

	# --- MST (Prim): en cada paso suma la sala más cercana al árbol ya formado.
	var in_tree := {0: true}
	var edges: Array = []
	while in_tree.size() < n:
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in in_tree:
			for b in n:
				if in_tree.has(b):
					continue
				var dd: float = (Vector2(centers[a]) - Vector2(centers[b])).length_squared()
				if dd < best_d:
					best_d = dd
					best_a = a
					best_b = b
		if best_b < 0:
			break
		edges.append([best_a, best_b])
		in_tree[best_b] = true

	# --- Loops: K aristas cortas extra que NO estén ya en el árbol → ciclos.
	var extra := int(ceil(n * 0.15))
	if extra > 0:
		var cand: Array = []
		for a in n:
			for b in range(a + 1, n):
				if _has_edge(edges, a, b):
					continue
				cand.append([(Vector2(centers[a]) - Vector2(centers[b])).length_squared(), a, b])
		cand.sort_custom(func(x, y): return x[0] < y[0])
		for i in mini(extra, cand.size()):
			edges.append([cand[i][1], cand[i][2]])

	# --- Registrar adyacencia (siempre) + tallar corredores (solo modo clásico).
	for e in edges:
		if not d.USE_DOORS:
			_connect(centers[e[0]], centers[e[1]])
		d._room_graph[e[0]].append(e[1])
		d._room_graph[e[1]].append(e[0])

func _has_edge(edges: Array, a: int, b: int) -> bool:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false

## Modo USE_DOORS: por cada arista DIRIGIDA (a→b) del grafo, una puerta en a (en su borde mirando a b)
## que teletransporta JUSTO AL LADO de la puerta de vuelta de b (lado de adentro). Devuelve
## [{from: celda de a, to: celda de aterrizaje en b}].
##
## FIX 3 (caras opuestas): el grafo es no dirigido, así que cada conexión (a,b) genera DOS specs:
##   a→b  cuya puerta vive en `from_cell = _room_cell_nearest(a, b_center)` (borde de a que MIRA a b)
##   b→a  cuya puerta vive en `_room_cell_nearest(b, a_center)`            (borde de b que MIRA a a)
## Como `from_cell` se deriva de la DIRECCIÓN entre salas (a→b vs b→a son opuestas), las caras de las
## dos puertas del par quedan automáticamente en lados OPUESTOS (NE↔SW, NW↔SE, etc. — la cara final la
## resuelve dungeon._compute_door_faces vía neighbor()). Así, al cruzar, salís por una cara y entrás
## por la opuesta: coherente espacialmente.
##
## FIX 1 (spawn pegado a la puerta destino): `land` ES exactamente la celda de la puerta de vuelta de b
## (b→a usa `_room_cell_nearest(b, a_center)` = mismo cálculo). Aterrizamos UNA sola celda hacia adentro
## de b desde esa puerta → caés justo al lado de ella, del lado de adentro, no en el centro de la sala.
func get_door_specs() -> Array:
	var specs: Array = []
	if d._room_graph.size() != d.rooms.size() or d._gen_room_cells.size() != d.rooms.size():
		return specs
	for a in d.rooms.size():
		var a_center := Vector2(d.rooms[a].get_center())
		for b in d._room_graph[a]:
			var b_center := Vector2(d.rooms[b].get_center())
			var from_cell := _room_cell_nearest(a, b_center)        # borde de a hacia b (cara que mira a b)
			var land := _room_cell_nearest(b, a_center)             # celda de la puerta de vuelta de b (mira a a)
			# FIX 1: aterrizar SÓLO ~1 celda hacia el interior de b desde su puerta → spawn pegado a la
			# puerta de destino (lado de adentro), no en el centro ni encima de la puerta de vuelta.
			var inward := b_center - Vector2(land)
			if inward.length() > 0.01:
				inward = inward.normalized() * 1.0
			var to_cell := _room_cell_nearest(b, Vector2(land) + inward)
			# Salvaguarda: si por geometría el aterrizaje cayó sobre la misma puerta de vuelta, empujá una
			# celda más adentro (evita reentrar a la puerta apenas spawneás).
			if to_cell == land:
				to_cell = _room_cell_nearest(b, Vector2(land) + inward * 2.0)
			specs.append({"from": from_cell, "to": to_cell})
	return specs

## Celda de PISO real de la sala i más cercana a un punto `target` (en coords de celda).
func _room_cell_nearest(i: int, target: Vector2) -> Vector2i:
	if i < 0 or i >= d._gen_room_cells.size() or (d._gen_room_cells[i] as Array).is_empty():
		return d.rooms[i].get_center() if (i >= 0 and i < d.rooms.size()) else Vector2i.ZERO
	var best: Vector2i = d._gen_room_cells[i][0]
	var bestd := INF
	for c in d._gen_room_cells[i]:
		var dd: float = (Vector2(c) - target).length_squared()
		if dd < bestd:
			bestd = dd
			best = c
	return best

## Fase 3: cantidad de salas escalada por profundidad (más profundo → más salas).
func _room_count_for_depth() -> int:
	var depth := int(GameState.run.get("depth", 1))
	return clampi(d.ROOM_COUNT + (depth - 1) * 2, d.ROOM_COUNT, 34)

## Fase 2: asigna un ROL a cada sala con BFS sobre `_room_graph` y setea spawn/exit.
##   entry    = sala cercana a un borde del mapa (se siente "entrada")
##   boss     = la más lejana de la entrada (en saltos del grafo) → descenso real
##   treasure = hojas del grafo (grado ≤1) → premio por desviarse
##   merchant = sala de grado alto a mitad de camino entrada→jefe
##   combat   = resto
## No-op si no hay grafo (mapas fijos / test) → main.gd cae al comportamiento por índice.
func assign_roles() -> void:
	d.room_roles = {}
	var n := d.rooms.size()
	if n == 0 or d._room_graph.size() != n or d._gen_room_cells.size() != n:
		return
	if n == 1:
		d.room_roles[0] = "entry"
		d.spawn_cell = room_center_cell(0)
		return
	var entry := _pick_entry_room()
	d.room_roles[entry] = "entry"
	var dist := _bfs_rooms(entry)
	# Jefe = sala más lejana (en saltos) de la entrada.
	var boss := entry
	var bestd := -1
	for i in n:
		var dd: int = dist.get(i, -1)
		if dd > bestd:
			bestd = dd
			boss = i
	d.room_roles[boss] = "boss"
	# Tesoro = hojas del grafo libres.
	for i in n:
		if not d.room_roles.has(i) and d._room_graph[i].size() <= 1:
			d.room_roles[i] = "treasure"
	# Mercader = sala de grado alto cerca del punto medio entrada→jefe.
	var mid := maxi(1, bestd / 2)
	var merchant := -1
	var merchant_score := -2147483647
	for i in n:
		if d.room_roles.has(i):
			continue
		var dd: int = dist.get(i, 999)
		var score: int = d._room_graph[i].size() * 10 - absi(dd - mid)
		if score > merchant_score:
			merchant_score = score
			merchant = i
	if merchant >= 0:
		d.room_roles[merchant] = "merchant"
	# Resto = combate.
	for i in n:
		if not d.room_roles.has(i):
			d.room_roles[i] = "combat"
	# Spawn en la entrada; salida en la sala del jefe (la más profunda).
	d.spawn_cell = room_center_cell(entry)
	d.exit_cell = room_center_cell(boss)

## BFS sobre el grafo de salas: índice de sala → distancia en saltos desde `start`.
func _bfs_rooms(start: int) -> Dictionary:
	var dist := {start: 0}
	var q: Array = [start]
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		for nb in d._room_graph[cur]:
			if not dist.has(nb):
				dist[nb] = int(dist[cur]) + 1
				q.append(nb)
	return dist

## Sala cuyo centro está más cerca de un borde del mapa → "entrada".
func _pick_entry_room() -> int:
	var best := 0
	var bestd := 1 << 30
	for i in d.rooms.size():
		var c := d.rooms[i].get_center()
		var edge: int = mini(mini(c.x, d.MAP_W - c.x), mini(c.y, d.MAP_H - c.y))
		if edge < bestd:
			bestd = edge
			best = i
	return best

## Celda de PISO real de la sala i más cercana a su centro (el centro del bbox puede ser muro).
func room_center_cell(i: int) -> Vector2i:
	if i < 0 or i >= d._gen_room_cells.size() or (d._gen_room_cells[i] as Array).is_empty():
		return d.rooms[i].get_center() if (i >= 0 and i < d.rooms.size()) else Vector2i.ZERO
	var target := Vector2(d.rooms[i].get_center())
	var best: Vector2i = d._gen_room_cells[i][0]
	var bestd := INF
	for c in d._gen_room_cells[i]:
		var dd: float = (Vector2(c) - target).length_squared()
		if dd < bestd:
			bestd = dd
			best = c
	return best

func carve_h(x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		d.grid[y][x] = 1
		if y + 1 < d.MAP_H:
			d.grid[y + 1][x] = 1

func carve_v(y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		d.grid[y][x] = 1
		if x + 1 < d.MAP_W:
			d.grid[y][x + 1] = 1
