extends Node2D
## SANDBOX de PROPS: un cuarto cerrado con props colocados A MANO para probar la oclusión (pararte
## DETRÁS de una biblioteca y que te tape OPACA), el tamaño y la colisión. Usa el MISMO render que el
## juego (`DungeonProps.spawn_at`) → lo que ves acá es lo que ves en partida.
## Requiere que los PNG de assets/iso/props/ estén importados (enfocá el editor una vez) y props.json.

const GRID_SIZE := Vector2i(40, 40)
const ROOM_ORIGIN := Vector2i(18, 8)
const ROOM_WIDTH := 9      # eje u (SE)
const ROOM_DEPTH := 10     # eje v (SW)
# Ejes iso en cell-space (mismos que dungeon_gen): +u = SE, +v = SW.
const ISO_A := Vector2(128, 64)
const ISO_B := Vector2(-128, 64)

# Props a colocar: [substring del path en el catálogo, u, v]. Distribuidos con lugar para caminar
# alrededor de cada uno (pasar por delante y por detrás).
const PROPS := [
	["bookcaseBooks_S", 2, 3],          # biblioteca alta (probá pasar por detrás)
	["bookcaseWideBooks_S", 6, 3],      # biblioteca ancha
	["longTableChairs_S", 4, 5],        # mesa larga con sillas, al medio
	["candleStandDouble_S", 2, 7],      # candelabro alto y fino
	["displayCaseBooks_S", 7, 6],       # vitrina
	["floorCarpet_S", 4, 7],            # alfombra (chata: te parás encima, no te tapa)
]

@onready var dungeon: Dungeon = $Dungeon
@onready var player: Player = $Player
@onready var status_label: Label = $UI/Panel/Margin/Status

var _room_cells: Array = []

func _ready() -> void:
	GameState.set_mode(GameState.Mode.PLAY)
	_build_room()
	_place_props()
	_place_torches()
	_teleport()
	_add_body_markers()
	LightField.mark_dirty()

## Línea CYAN a la altura de los pies, del ANCHO DE LA COLISIÓN: esa es la "comparativa" del cuerpo que
## usa la oclusión X-aware (en vez de un punto). Hija del player → lo sigue.
func _add_body_markers() -> void:
	var feet := player.get_node_or_null("Feet") as Node2D
	var fy: float = feet.position.y if feet else 0.0
	var hw: float = dungeon._props._player_halfwidth(player) if dungeon._props else 15.0   # mismo ancho que el test
	var l := Line2D.new()
	l.points = PackedVector2Array([Vector2(-hw, fy), Vector2(hw, fy)])
	l.width = 2.0
	l.default_color = Color(0.35, 1.0, 1.0)
	l.z_index = 1000
	player.add_child(l)

func _marker_at(local_pos: Vector2, col: Color) -> void:
	for seg in [[Vector2(-7, 0), Vector2(7, 0)], [Vector2(0, -7), Vector2(0, 7)]]:
		var l := Line2D.new()
		l.points = PackedVector2Array([local_pos + seg[0], local_pos + seg[1]])
		l.width = 1.5
		l.default_color = col
		l.z_index = 1000
		player.add_child(l)

func _build_room() -> void:
	dungeon._ensure_iso()
	dungeon.grid = []
	for y in GRID_SIZE.y:
		var row: Array = []
		row.resize(GRID_SIZE.x)
		row.fill(0)
		dungeon.grid.append(row)
	_room_cells = dungeon.carve_iso_room(ROOM_ORIGIN, ROOM_WIDTH, ROOM_DEPTH)
	dungeon.rooms = [_bbox(_room_cells)]
	dungeon._room_of = {}
	for c in _room_cells:
		dungeon._room_of[c] = 0
	dungeon._wall_segments = dungeon._build_wall_segments()
	dungeon._paint_iso()
	dungeon._build_iso_nav()
	dungeon._build_iso_boundaries()
	dungeon.regenerated.emit()

## Celda de la sala en coords iso (u,v) desde el origen.
func _cell(u: int, v: int) -> Vector2i:
	var base := dungeon.map_to_local(ROOM_ORIGIN)
	return dungeon.local_to_map(base + ISO_A * u + ISO_B * v)

func _place_props() -> void:
	dungeon._ensure_props()
	var n := 0
	for spec in PROPS:
		var prop := _find_prop(String(spec[0]))
		if prop.is_empty():
			push_warning("[props_test] no encontré en el catálogo: %s (¿importaste los PNG?)" % spec[0])
			continue
		dungeon._props.spawn_at(_cell(int(spec[1]), int(spec[2])), prop)
		n += 1
	status_label.text = (
		"CUARTO DE PRUEBA — PROPS (%d colocados)\n" % n
		+ "WASD: caminar.  Pasá DETRÁS de una biblioteca → te tapa OPACA.  Adelante → la tapás vos.\n"
		+ "La alfombra es chata: te parás encima sin que te tape."
	)

func _find_prop(substr: String) -> Dictionary:
	for p in PropCatalog.props:
		if substr in String(p.path):
			return p
	return {}

## Antorchas en la pared trasera para iluminar el cuarto (3 repartidas).
func _place_torches() -> void:
	var backs: Array = []
	for seg in dungeon._wall_segments:
		if seg.side == dungeon.WallSegment.Side.NW or seg.side == dungeon.WallSegment.Side.NE:
			backs.append(seg)
	if backs.is_empty():
		return
	for i in [0, backs.size() / 2, backs.size() - 1]:
		var seg = backs[clampi(i, 0, backs.size() - 1)]
		dungeon.spawn_wall_torch(seg.interior_cell, seg.side)

func _teleport() -> void:
	var cell := _cell(ROOM_WIDTH / 2, ROOM_DEPTH - 1)   # adelante (sur) → caminás hacia los props
	player.global_position = dungeon.to_global(dungeon.map_to_local(cell))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()

## DEBUG VISUAL: corre la oclusión X-aware y tiñe ROJO a los props que te están tapando (estás detrás
## de su huella a tu columna X). BLANCO los que tenés adelante. Caminá alrededor: el rojo debería seguir
## el borde inclinado real de la huella, no una línea horizontal.
func _process(_dt: float) -> void:
	if dungeon == null or not is_instance_valid(player) or dungeon._props == null:
		return
	dungeon._props.update_occlusion(player)
	var pz: int = player.z_index
	var best = null
	var bestd := 1.0e20
	var n_behind := 0
	for e in dungeon._prop_holders:
		var h = e.get("holder")
		if not is_instance_valid(h):
			continue
		var behind: bool = h.z_index > pz
		if behind:
			n_behind += 1
		h.modulate = Color(1.0, 0.5, 0.5) if behind else Color.WHITE
		var dd: float = h.global_position.distance_to(player.global_position)
		if dd < bestd:
			bestd = dd
			best = h
	var nm := "?"
	if best:
		for ch in best.get_children():
			if ch is Sprite2D and ch.texture:
				nm = ch.texture.resource_path.get_file()
				break
	status_label.text = (
		"OCLUSIÓN X-AWARE  ·  props ROJOS = te están tapando (estás detrás de su huella)\n"
		+ "te tapan ahora: %d   ·   más cercano: %s (z=%d, player z=%d)\n" % [n_behind, nm, best.z_index if best else 0, pz]
		+ "caminá alrededor: el límite debería seguir el borde inclinado de la huella"
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
