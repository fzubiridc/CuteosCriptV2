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

const CUTAWAY_ALPHA := 0.25
const DOOR_NEAR := 70.0            # radio para abrir la puerta con CLIC DERECHO (hay que estar cerca)
const ISO_A := Vector2(128, 64)    # +u = SE (cell-space, mismos ejes que dungeon_gen)
const ISO_B := Vector2(-128, 64)   # +v = SW

var d: Dungeon
var _dividers: Array = []   # {holders:Array, orient:int(0=NE/eje u,1=NW/eje v), line:float, base:Vector2}
var _doors: Array = []      # {holder, coll, open:bool, closed_tex, open_tex, origin:Vector2}

func _init(dungeon: Dungeon) -> void:
	d = dungeon

## Libera todos los muros de divisor (sprites). La colisión vive en `_iso_bounds`, que se reconstruye
## solo en cada generate() → no hace falta liberarla acá. Llamar antes de recolocar (regen).
func clear() -> void:
	for rec in _dividers:
		for h in rec["holders"]:
			if is_instance_valid(h):
				h.queue_free()
	_dividers.clear()
	_doors.clear()

## Coloca un divisor en una sala.
##   origin: celda ORIGEN de la sala (base de los ejes u/v, como en carve_iso_room).
##   orient: 0 = muros NE (corren por el eje u, en la fila v=line); 1 = muros NW (corren por eje v, columna u=line).
##   line:   índice de la fila (orient 0) o columna (orient 1) donde va el divisor.
##   start, length: rango a lo largo del eje (en celdas).
##   gap:    índice (en [start, start+length)) del hueco/puerta; -1 = divisor sólido sin puerta.
func add_divider(origin: Vector2i, orient: int, line: int, start: int, length: int, gap: int = -1) -> void:
	var base := d.map_to_local(origin)
	var src: int = d.SRC_WALL_NE if orient == 0 else d.SRC_WALL_NW
	# Arista base de la celda según orientación (cell-local). NE = top→right; NW = top→left.
	var e0 := Vector2(0, -64)                                          # top (común)
	var e1: Vector2 = Vector2(128, 0) if orient == 0 else Vector2(-128, 0)
	var nrm: Vector2 = (Vector2(-0.447, 0.894) if orient == 0 else Vector2(0.447, 0.894)) * 8.0
	var holders: Array = []
	for i in range(start, start + length):
		if i == gap:
			continue
		var cell := _cell(base, orient, line, i)
		holders.append(d._spawn_wall_sprite(cell, src, false))
		_add_edge_collision(cell, e0, e1, nrm)
		_nav_solid(cell, true)   # los mobs no atraviesan el muro del divisor
	# Span PROPIO (global, toda la fila) por-instancia → sin competencia con el perímetro en las uniones.
	var ca := d.map_to_local(_cell(base, orient, line, start))
	var cb := d.map_to_local(_cell(base, orient, line, start + length - 1))
	var span_a := d.to_global(ca + e0)
	var span_b := d.to_global(cb + e1)
	for h in holders:
		_apply_span(h, span_a, span_b)
	# Puerta en el hueco (si lo hay).
	if gap >= start and gap < start + length:
		var dh := _add_door(_cell(base, orient, line, gap), src, span_a, span_b, e0, e1, nrm)
		if dh != null:
			holders.append(dh)
	_dividers.append({"holders": holders, "orient": orient, "line": float(line), "base": base})

## Celda del divisor para el índice `i` a lo largo del eje. orient 0: u=i, v=line. orient 1: u=line, v=i.
func _cell(base: Vector2, orient: int, line: int, i: int) -> Vector2i:
	var u: int = i if orient == 0 else line
	var v: int = line if orient == 0 else i
	return d.local_to_map(base + ISO_A * u + ISO_B * v)

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

## Tira de colisión fina alineada a la arista del muro (no la celda entera) en el StaticBody del perímetro.
func _add_edge_collision(cell: Vector2i, e0: Vector2, e1: Vector2, nrm: Vector2) -> void:
	if d._iso_bounds == null or not is_instance_valid(d._iso_bounds):
		return
	var cs := CollisionShape2D.new()
	var poly := ConvexPolygonShape2D.new()
	poly.points = PackedVector2Array([e0 + nrm, e1 + nrm, e1 - nrm, e0 - nrm])
	cs.shape = poly
	cs.position = d.map_to_local(cell)
	d._iso_bounds.add_child(cs)

## Marca/desmarca una celda como SÓLIDA en el nav de mobs (AStar). El player NO usa AStar (anda por
## física), así que esto solo evita que los mobs caminen "a través" del muro del divisor / puerta cerrada.
func _nav_solid(cell: Vector2i, solid: bool) -> void:
	if d._iso_astar != null and d._iso_astar.is_in_boundsv(cell):
		d._iso_astar.set_point_solid(cell, solid)

## Puerta en el hueco: sprite CERRADA (DoorNE/NW) + colisión + área clickeable (click → abre/cierra).
func _add_door(cell: Vector2i, base_src: int, span_a: Vector2, span_b: Vector2, e0: Vector2, e1: Vector2, nrm: Vector2) -> Node2D:
	var door_src := int(d._door_src.get(base_src, base_src))
	var closed_tex: Texture2D = d._wall_tex.get(door_src)
	var origin: Vector2 = d._wall_origin.get(door_src, Vector2.ZERO)
	var open_path := "res://assets/iso/walls/variations/OpenDoorNE.png" if base_src == d.SRC_WALL_NE else "res://assets/iso/walls/variations/OpenDoorNW.png"
	var open_tex: Texture2D = load(open_path)
	var holder := d._spawn_wall_sprite(cell, door_src, false)
	_apply_span(holder, span_a, span_b)
	var coll: CollisionShape2D = null
	if d._iso_bounds != null and is_instance_valid(d._iso_bounds):
		coll = CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = PackedVector2Array([e0 + nrm, e1 + nrm, e1 - nrm, e0 - nrm])
		coll.shape = poly
		coll.position = d.map_to_local(cell)
		d._iso_bounds.add_child(coll)
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
	_doors.append({"holder": holder, "coll": coll, "open": false, "closed_tex": closed_tex, "open_tex": open_tex, "origin": origin, "cell": cell})
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
	if is_instance_valid(holder) and holder.get_child_count() > 0:
		var spr := holder.get_child(0) as Sprite2D
		if spr != null:
			spr.texture = rec["open_tex"] if rec["open"] else rec["closed_tex"]
			spr.offset = -(rec["origin"] as Vector2)
	if rec["coll"] != null and is_instance_valid(rec["coll"]):
		(rec["coll"] as CollisionShape2D).disabled = rec["open"]
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
