extends RefCounted
class_name DungeonProps
## ESPARCE props del catálogo (PropCatalog → props.json) por el piso, para previsualizar los assets iso.
## Cada prop es un contenedor en `Main` (mismo Y-sort que el PLAYER) → el motor ordena prop y player por
## profundidad real: si te parás DETRÁS de una mesa/biblioteca, te tapa OPACA; si estás adelante, la tapás
## vos. (A diferencia de los muros, los props son sólidos: NO se transparentan.) El orden contra muros es el
## bucket grueso de las capas (traseros detrás, fachada delante), correcto para muebles apoyados en pared.
##   - celda de PISO libre (no spawn/exit), anclado al punto elegido (centro/borde de muro) + escala/offset por-asset
##   - igualan la escala de render del Dungeon (gs=0.5) para calzar con los tiles
##   - si tiene polígono de colisión: StaticBody2D (capa 1, como muros) + marca la celda SÓLIDA en el nav
## Toda referencia al nodo Dungeon va prefijada con `d.`.

var d: Dungeon

func _init(dungeon: Dungeon) -> void:
	d = dungeon

const MAX_PROPS := 40           # tope por piso (no saturar)
const FLOOR_FRACTION := 0.06    # ~6% de las celdas de piso libres
const MIN_PROPS := 8            # mínimo visible si hay lugar
const SPAWN_MARGIN := 3         # celdas de manhattan alrededor del spawn que se dejan libres
const FLOOR_DECAL_Z := -9       # z de props sin huella (decal de piso): sobre el piso (-10), bajo todo lo demás

func place_props() -> void:
	# Limpieza: liberar los props del piso anterior.
	for e in d._prop_holders:
		var old = e.get("holder")
		if is_instance_valid(old):
			old.queue_free()
	d._prop_holders = []

	if d.get_parent() == null:
		return
	var pool := PropCatalog.enabled_props()
	if pool.is_empty():
		return
	var valid := _free_floor_cells()
	if valid.is_empty():
		return

	var target: int = mini(MAX_PROPS, int(round(float(valid.size()) * FLOOR_FRACTION)))
	target = maxi(target, mini(MIN_PROPS, valid.size()))

	var used := {}
	var placed := 0
	var attempts := 0
	var cap := target * 8
	while placed < target and attempts < cap:
		attempts += 1
		var cell: Vector2i = valid[Rng.range_i(0, valid.size() - 1)]
		if used.has(cell):
			continue
		used[cell] = true
		var prop: Dictionary = PropCatalog.pick_weighted(pool)
		if prop.is_empty() or prop.tex == null:
			continue
		spawn_at(cell, prop)
		placed += 1

## Celdas de piso transitable, sin spawn/exit ni su margen.
func _free_floor_cells() -> Array:
	var cells: Array = []
	if not d._gen_room_cells.is_empty():
		for room in d._gen_room_cells:
			for c in room:
				cells.append(c)
	else:
		for y in d.grid.size():
			var row: Array = d.grid[y]
			for x in row.size():
				if int(row[x]) == 1:
					cells.append(Vector2i(x, y))
	var valid: Array = []
	for c in cells:
		if c == d.spawn_cell or c == d.exit_cell:
			continue
		if d.spawn_cell.x >= 0 and (abs(c.x - d.spawn_cell.x) + abs(c.y - d.spawn_cell.y)) < SPAWN_MARGIN:
			continue
		if c.y < 0 or c.y >= d.grid.size():
			continue
		var row: Array = d.grid[c.y]
		if c.x < 0 or c.x >= row.size() or int(row[c.x]) != 1:
			continue
		valid.append(c)
	return valid

## Coloca UN prop del catálogo (dict de PropCatalog) en una celda. Público para que el sandbox de prueba
## (props_test) lo reuse con assets/celdas fijas, garantizando el MISMO render que el juego.
func spawn_at(cell: Vector2i, prop: Dictionary) -> void:
	var tex: Texture2D = prop.tex
	var w := tex.get_width()
	var h := tex.get_height()
	# gs = escala de render del Dungeon (0.5). Los props viven en Main (scale 1, mismo y_sort que el player)
	# pero igualan gs para calzar con el arte de los tiles (la tool autorea en el espacio de celda 256).
	var gs: float = d.scale.x
	var coll: Array = prop.collision
	var center: Vector2 = d.to_global(d.map_to_local(cell))   # centro de celda en world
	# Pivote ESTÁTICO (y_sort) = nudge manual `ysort` (cell-local). Es el fallback para props SIN colisión.
	# Con colisión, el orden vs el player lo decide `update_occlusion()` por-frame (X-aware) → z_index dinámico.
	var ys: float = float(prop.get("ysort", 0.0)) * gs
	var container := Node2D.new()
	container.position = center + Vector2(0, ys)
	container.z_index = int(prop.z)
	d.get_parent().add_child(container)

	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = Vector2(-w * 0.5, -h)          # base = bottom-center del sprite
	spr.scale = Vector2(prop.scale * gs, prop.scale * gs)
	spr.position = (PropCatalog.anchor_offset(prop.anchor) + prop.offset) * gs - Vector2(0, ys)
	container.add_child(spr)

	# COLISIÓN (bloquea movimiento + nav).
	if not coll.is_empty():
		var body := StaticBody2D.new()
		body.collision_layer = 1                # misma capa que los muros (player la maskea)
		body.collision_mask = 0
		body.position = Vector2(0, -ys)         # contra-corre el pivote → la colisión queda en la celda real
		container.add_child(body)
		for poly in coll:
			var cp := CollisionPolygon2D.new()
			var pts := PackedVector2Array()
			for p in poly:                      # cell-local (256) → world (×gs) para calzar con el visual
				pts.append(p * gs)
			cp.polygon = pts
			body.add_child(cp)
		# Bloquea el pathfinding: la celda pasa a sólida en el AStar iso.
		if d._iso_astar != null:
			d._iso_astar.set_point_solid(cell, true)

	# Huella de OCLUSIÓN (z-order X-aware) en WORLD: usa `occlusion` si existe (p.ej. el brazo ancho de una
	# lámpara), si no cae a la colisión. Desacoplada del choque → un poste fino puede tapar como objeto ancho.
	var occ: Array = prop.get("occlusion", [])
	var src: PackedVector2Array = occ[0] if not occ.is_empty() else (coll[0] if not coll.is_empty() else PackedVector2Array())
	var world_poly := PackedVector2Array()
	for p in src:
		world_poly.append(center + p * gs)

	# SIN huella (ni colisión ni oclusión) → DECAL DE PISO: z fijo a ras de piso, debajo de las entidades.
	# No participa de la oclusión (update_occlusion lo saltea por poly vacío). Ej.: alfombras, manchas, etc.
	if world_poly.is_empty():
		container.z_index = FLOOR_DECAL_Z

	d._prop_holders.append({"holder": container, "poly": world_poly})

## OCLUSIÓN X-AWARE (por-frame). Para cada prop CON huella: estás "detrás" si, a la altura de tu columna
## X, la huella se extiende al SUR tuyo (sigue el borde inclinado iso, no una línea horizontal). Detrás →
## z por encima del player (te tapa); adelante → por debajo. Los props sin huella quedan en y_sort estático.
func update_occlusion(pl: Node) -> void:
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		return
	var n2 := pl as Node2D
	var feet := n2.get_node_or_null("Feet") as Node2D
	var f: Vector2 = feet.global_position if feet != null else n2.global_position
	var hw := _player_halfwidth(n2)   # medio-ancho de la colisión del cuerpo (la "línea" de comparación)
	var pz: int = n2.z_index
	for e in d._prop_holders:
		var poly: PackedVector2Array = e.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var h = e.get("holder")
		if is_instance_valid(h):
			h.z_index = (pz + 1) if _player_behind(poly, f, hw) else (pz - 1)

const HALFWIDTH_PAD := 7.0   # margen (world) extra a cada lado de la línea de comparación del cuerpo
## Medio-ancho (world) de la colisión del player (RectangleShape2D del nodo "Shape") + margen. Default si no hay.
func _player_halfwidth(n2: Node2D) -> float:
	var sh := n2.get_node_or_null("Shape") as CollisionShape2D
	if sh != null and sh.shape is RectangleShape2D:
		return (sh.shape as RectangleShape2D).size.x * 0.5 * absf(n2.global_scale.x) + HALFWIDTH_PAD
	return 8.0 + HALFWIDTH_PAD

## ¿El jugador está detrás de la huella `poly` (world)? La comparación de su cuerpo es una LÍNEA horizontal
## a la altura de los pies (f.y), del ancho de su colisión [f.x-hw, f.x+hw]. Clipea cada arista a esa ventana
## de X y toma el borde sur (max Y) de la huella ahí; si la línea queda al NORTE de ese borde → detrás.
func _player_behind(poly: PackedVector2Array, f: Vector2, hw: float) -> bool:
	var x0 := f.x - hw
	var x1 := f.x + hw
	var south := -1.0e20
	var covered := false
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var lo := maxf(minf(a.x, b.x), x0)
		var hi := minf(maxf(a.x, b.x), x1)
		if lo > hi:
			continue   # la arista no cruza la ventana de X del cuerpo
		covered = true
		for xx in [lo, hi]:           # max Y de una arista (lineal) en [lo,hi] = en un extremo
			var y: float
			if absf(b.x - a.x) < 0.001:
				y = maxf(a.y, b.y)
			else:
				y = a.y + (xx - a.x) / (b.x - a.x) * (b.y - a.y)
			if y > south:
				south = y
	return covered and f.y < south
