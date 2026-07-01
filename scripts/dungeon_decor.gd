extends RefCounted
class_name DungeonDecor
## DECORACIÓN de la mazmorra ISOMÉTRICA (antorchas + fogatas), extraída de dungeon.gd
## (movimiento mecánico, misma lógica). Coloca antorchas de pared (luz + sombras proyectadas)
## y fogatas en el centro de algunas salas. Toda referencia a estado/consts/exports/métodos del
## nodo Dungeon va prefijada con `d.`; los autoloads/builtins (LightCfg, LightField, Vector2i…) no.

var d: Dungeon

func _init(dungeon: Dungeon) -> void:
	d = dungeon

# ---------------------------------------------------------------------------
# Antorchas
# ---------------------------------------------------------------------------
## Inset desde el montaje visual hasta el lado interior del oclusor ISO.
## La llama compensa este vector en torch.gd/side_torch.gd, por lo que solo
## se mueve el centro físico de PointLight2D.
const ISO_TORCH_LIGHT_INSET := Vector2(43, 10)
const ISO_SIDE_TORCH_LIGHT_INSET := 65.0

## Anclaje de antorchas de pared al BORDE de muro iso (no a la celda top-down). La posición
## (llama + inset de luz) se tunea EN VIVO desde el panel L (LightCfg, grupo "Antorchas (posición)").
var _torches: Array = []          # antorchas de pared ancladas por borde {node, cell, side} → tuneables en vivo
var _torch_cfg_cache: Array = []  # detecta cambios de los knobs de posición de LightCfg

## Crea una antorcha de pared anclada al BORDE `side` de `interior_cell` y la registra para tuning
## en vivo. La usa el sandbox (closed_room_test) y, a futuro, place_torches del procgen.
func spawn_wall_torch(interior_cell: Vector2i, side: int) -> Node:
	var parent := d.get_parent()
	var holder := parent.get_node_or_null("Torches")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Torches"
		parent.add_child(holder)
	var t := PointLight2D.new()
	t.set_script(load("res://scripts/torch.gd"))
	t.seed_off = _torches.size() * 1.7
	holder.add_child(t)
	_torches.append({"node": t, "cell": interior_cell, "side": side})
	_position_torch(t, interior_cell, side)
	LightField.mark_dirty()
	return t

## Posiciona la antorcha: la LUZ (root) metida hacia la sala (INWARD_NORMAL*inset) y la LLAMA
## sobre la cara del muro (knobs torch_flame_x/y), ambas desde el punto medio del borde.
func _position_torch(t: Node, cell: Vector2i, side: int) -> void:
	var anchor := d.to_global(d.map_to_local(cell) + _edge_midpoint(side))
	var flame := Vector2(LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"))
	var light_off: Vector2 = d.WallSegment.INWARD_NORMAL[side] * LightCfg.get_v("torch_light_inset")
	t.set("light_offset", light_off)
	t.set("position", anchor + light_off)
	if t.has_method("set_mount"):
		t.call("set_mount", flame, light_off)

## Punto medio del borde de muro, en coords de celda iso (rombo 256×128 centrado).
func _edge_midpoint(side: int) -> Vector2:
	match side:
		d.WallSegment.Side.NW: return Vector2(-64, -32)
		d.WallSegment.Side.NE: return Vector2(64, -32)
		d.WallSegment.Side.SE: return Vector2(64, 32)
		d.WallSegment.Side.SW: return Vector2(-64, 32)
	return Vector2.ZERO

## Reposiciona las antorchas ancladas si cambiaste los @export (Remote inspector durante Play).
func tune_torches_live() -> void:
	if _torches.is_empty():
		return
	var c := [LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"), LightCfg.get_v("torch_light_inset")]
	if c == _torch_cfg_cache:
		return
	_torch_cfg_cache = c
	for e in _torches:
		if is_instance_valid(e.node):
			_position_torch(e.node, e.cell, e.side)

## Antorchas de pared ISO: ancladas al BORDE real de muro (`spawn_wall_torch`), no a un rect cartesiano.
## El código viejo usaba `d.rooms` (Rect2i = BBOX) + wall_row/left/right cartesianos → en salas iso
## (paralelogramos, `carve_iso_room`) los muros no coinciden con el bbox y las antorchas caían mal ubicadas
## o en vacío. Ahora tomamos los `_wall_segments` reales (la fuente lógica de muros), los agrupamos por sala
## y colocamos hasta PER_ROOM antorchas ESPACIADAS por sala. Bonus: `spawn_wall_torch` las registra en
## `_torches` → quedan tuneables en vivo por el panel L (las viejas eran PointLight2D crudos, no tuneables).
func place_torches() -> void:
	var parent := d.get_parent()
	var holder := parent.get_node_or_null("Torches")
	if holder != null:
		for c in holder.get_children():
			c.queue_free()
	_torches.clear()          # reconstruimos el registro (spawn_wall_torch reappendea)
	_torch_cfg_cache = []
	if d._wall_segments.is_empty():
		return
	# Agrupar segmentos de muro por SALA. Preferimos los muros TRASEROS (NW/NE): quedan detrás del player
	# (no los tapa el cutaway) — mismo criterio que el "top wall" del código viejo. Fallback a cualquiera.
	var back_by_room := {}
	var any_by_room := {}
	for seg in d._wall_segments:
		var rid: int = d._room_of.get(seg.interior_cell, -1)
		if rid < 0:
			continue   # corredores/divisores: sin antorchas para no saturar el mapa de luces
		if not any_by_room.has(rid):
			any_by_room[rid] = []
			back_by_room[rid] = []
		any_by_room[rid].append(seg)
		if seg.side == d.WallSegment.Side.NW or seg.side == d.WallSegment.Side.NE:
			back_by_room[rid].append(seg)
	const MAX_TORCHES := 32
	const PER_ROOM := 2
	var idx := 0
	for rid in any_by_room:
		if idx >= MAX_TORCHES:
			break
		var pool: Array = back_by_room[rid] if not back_by_room[rid].is_empty() else any_by_room[rid]
		for seg in _spread_pick(pool, PER_ROOM):
			if idx >= MAX_TORCHES:
				break
			spawn_wall_torch(seg.interior_cell, seg.side)   # ancla iso correcta + registro para tuning en vivo
			idx += 1
	LightField.mark_dirty()   # refrescar la lista de luces para el foot-light

## Elige hasta `n` elementos ESPACIADOS de `arr` (índices repartidos) → antorchas separadas en el perímetro,
## no amontonadas. Si hay `n` o menos, devuelve todos.
func _spread_pick(arr: Array, n: int) -> Array:
	if arr.size() <= n:
		return arr.duplicate()
	var out: Array = []
	for k in n:
		out.append(arr[int(float(k) * arr.size() / float(n))])
	return out

# ---------------------------------------------------------------------------
# Fogatas
# ---------------------------------------------------------------------------
const CAMPFIRE_SCENE := preload("res://scenes/campfire.tscn")   # fogata de leña (sprite anim + luz + sfx); se instancia en place_campfires

## Coloca fogatas (campfire.tscn) en el CENTRO de algunas salas, "cada tanto" (~1 de cada 3) para no
## saturar. La fogata se autoubica en el piso (Node2D) → solo seteo position y seed_off (desfasa la
## llama/sfx). Holder propio "Campfires" bajo el padre, que se LIMPIA al regenerar el piso (igual que
## "Torches"). Salta la sala de spawn (no aparecer sobre el player) y centra en celda CAMINABLE
## (room_center_cell devuelve piso real, no muro/puerta).
func place_campfires() -> void:
	d._ensure_gen()
	var parent := d.get_parent()
	var holder := parent.get_node_or_null("Campfires")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Campfires"
		parent.add_child(holder)
	else:
		for c in holder.get_children():
			c.queue_free()
	# Sala de spawn por celda (robusto en procgen y mapas fijos): la que contiene spawn_cell.
	var spawn_room: int = d._room_of.get(d.spawn_cell, -1)
	var placed := 0
	for room_i in d.rooms.size():
		if room_i == spawn_room:
			continue
		if room_i % 3 != 0:   # densidad moderada: ~1 de cada 3 salas
			continue
		var cell := d._gen.room_center_cell(room_i)   # celda de piso real, centrada en la sala
		var fire := CAMPFIRE_SCENE.instantiate()
		fire.seed_off = placed * 1.7   # desfasa parpadeo/sfx entre fogatas (set antes de add_child)
		fire.position = d.to_global(d.map_to_local(cell))   # a ras de piso, posición iso
		holder.add_child(fire)
		placed += 1
	LightField.mark_dirty()   # las fogatas aportan luz → refrescar el foot-light
