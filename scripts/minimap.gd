extends CanvasLayer
class_name Minimap
## AUTOMAP estilo Diablo II: wireframe ISO de las aristas de pared exploradas (LÍNEAS, no relleno).
##   · Radar circular en la esquina sup. derecha (sigue al jugador, siempre visible).
##   · Mapa completo overlay translúcido sobre el juego (tecla "map").
## Ambos los dibuja un MinimapWire a partir de Dungeon.get_wall_edges() (aristas en world-local).
## La niebla = Dungeon.cell_seen (fuente de verdad): solo se dibujan las aristas de celdas ya vistas.
## Markers: jugador (siempre al centro del radar) y salida.

const WIRE := preload("res://scripts/minimap_wire.gd")   # preload (no class_name global) → robusto al orden de carga

const REVEAL_RADIUS := 7          # tiles cuyas aristas se revelan alrededor del jugador
const MINI_VIEW := 200            # tamaño del recuadro del radar (px) — rombo iso más grande
const RADAR_ZOOM := 0.045         # world → px en el radar (menos = se ve más mapa)
const COL_WALL := Color(0.86, 0.79, 0.58, 0.95)   # crema/ámbar (líneas de pared, estilo D2)
const WALL_W := 1.0

var _dungeon: Dungeon
var _player: Node2D
var _edges_by_cell: Dictionary = {}   # cell → Array de PackedVector2Array([a, b]) (world-local del dungeon)
var _door_edges: Array = []           # aristas de puerta (divisor + región) → línea roja si ya fueron vistas
var _seen: Dictionary = {}            # cell → true (ya volcada a _pts)
var _pts: PackedVector2Array = PackedVector2Array()   # aristas reveladas (pares a, b consecutivos)
var _exit_cell := Vector2i(-1, -1)
var _last_cell := Vector2i(-99999, -99999)
var _full_center := Vector2.ZERO      # centro world del bbox del piso (para encuadrar el mapa M)
var _full_zoom := 0.05

var _mini_box: Control
var _mini_wire: WIRE
var _full_root: Control
var _full_wire: WIRE
var _title: Label

func setup(dungeon: Dungeon, player: Node2D) -> void:
	_dungeon = dungeon
	_player = player
	if not _dungeon.regenerated.is_connected(_on_regenerated):
		_dungeon.regenerated.connect(_on_regenerated)
	_rebuild_edges()
	_reset()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_build_ui()

func _build_ui() -> void:
	# --- Radar (esquina sup. derecha): jugador SIEMPRE al centro, el wireframe se desliza ---
	_mini_box = Control.new()
	_mini_box.anchor_left = 1.0
	_mini_box.anchor_right = 1.0
	_mini_box.offset_left = -MINI_VIEW - 12
	_mini_box.offset_right = -12
	_mini_box.offset_top = 12
	_mini_box.offset_bottom = 12 + MINI_VIEW
	add_child(_mini_box)
	# Fondo + anillo dorado (shader): recorta a círculo y pinta el aro ornamental.
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.02, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = -3; bg.offset_top = -3; bg.offset_right = 3; bg.offset_bottom = 3
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circ_bg := ShaderMaterial.new()
	circ_bg.shader = preload("res://shaders/minimap_circle.gdshader")
	circ_bg.set_shader_parameter("draw_ring", 1.0)
	circ_bg.set_shader_parameter("box_size", Vector2(MINI_VIEW + 6, MINI_VIEW + 6))
	bg.material = circ_bg
	_mini_box.add_child(bg)
	# Wire del radar: dibuja en local [0, MINI_VIEW]; el material lo recorta a círculo (draw_ring=0).
	_mini_wire = WIRE.new()
	_mini_wire.color = COL_WALL
	_mini_wire.width = WALL_W
	_mini_wire.origin = Vector2(MINI_VIEW, MINI_VIEW) * 0.5
	_mini_wire.zoom = RADAR_ZOOM
	_mini_wire.cull = MINI_VIEW * 0.5 + 8.0
	var circ_map := ShaderMaterial.new()
	circ_map.shader = preload("res://shaders/minimap_circle.gdshader")
	circ_map.set_shader_parameter("draw_ring", 0.0)
	circ_map.set_shader_parameter("box_size", Vector2(MINI_VIEW, MINI_VIEW))
	_mini_wire.material = circ_map
	_mini_box.add_child(_mini_wire)

	# --- Mapa completo (tecla "map"): overlay translúcido SOBRE el juego ---
	_full_root = Control.new()
	_full_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.visible = false
	add_child(_full_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.02, 0.5)   # translúcido: se ve el juego detrás (estilo automap D2)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_root.add_child(dim)
	_full_wire = WIRE.new()
	_full_wire.color = Color(COL_WALL.r, COL_WALL.g, COL_WALL.b, 0.88)
	_full_wire.width = WALL_W
	_full_root.add_child(_full_wire)
	_title = Label.new()
	_title.text = "MAPA  ·  [M] cerrar"
	_title.add_theme_color_override("font_color", Color("ffd84f"))
	_title.add_theme_font_size_override("font_size", 18)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.offset_top = 18
	_full_root.add_child(_title)

## Agrupa las aristas del piso por celda (para revelar por niebla) y calcula el encuadre del mapa M.
func _rebuild_edges() -> void:
	_edges_by_cell = {}
	if _dungeon == null:
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	# Muros de perímetro/sala/sub-cuarto (WallSegment) + muros de DIVISOR (sprites aparte). Ambos como líneas.
	var all_edges: Array = _dungeon.get_wall_edges()
	all_edges.append_array(_dungeon.get_divider_edges())
	for e in all_edges:
		var c: Vector2i = e["cell"]
		if not _edges_by_cell.has(c):
			_edges_by_cell[c] = []
		_edges_by_cell[c].append(PackedVector2Array([e["a"], e["b"]]))
		mn = mn.min(e["a"]).min(e["b"])
		mx = mx.max(e["a"]).max(e["b"])
	_door_edges = _dungeon.get_door_edges()
	if mn.x == INF:
		return
	_full_center = (mn + mx) * 0.5
	var span := mx - mn
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1152, 648)
	_full_zoom = minf(vp.x * 0.82 / maxf(span.x, 1.0), vp.y * 0.82 / maxf(span.y, 1.0))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		_full_root.visible = not _full_root.visible
		if _full_root.visible:
			_refresh_full()

func _on_regenerated() -> void:
	_rebuild_edges()
	_reset()

func _reset() -> void:
	_seen = {}
	_pts = PackedVector2Array()
	_last_cell = Vector2i(-99999, -99999)
	_exit_cell = Vector2i(-1, -1)
	if _dungeon != null:
		_exit_cell = _dungeon.get_exit_cell()
		if _exit_cell.x < 0 and not _dungeon.rooms.is_empty():
			_exit_cell = _dungeon.rooms[_dungeon.rooms.size() - 1].get_center()
	if _mini_wire != null:
		_mini_wire.pts = _pts
		_mini_wire.queue_redraw()

func _process(_dt: float) -> void:
	if _dungeon == null or not is_instance_valid(_dungeon) or _player == null or not is_instance_valid(_player):
		return
	if _edges_by_cell.is_empty() and not _dungeon.grid.is_empty():
		# El piso pudo generarse después del setup (orden de _ready); reintenta una vez.
		_rebuild_edges()
	var cell := _dungeon.local_to_map(_dungeon.to_local(_player.global_position))
	if cell != _last_cell:
		_last_cell = cell
		_reveal(cell)
	# Radar: el wireframe se desliza, el jugador queda clavado al centro.
	var pw := _dungeon.to_local(_player.global_position)
	_mini_wire.pts = _pts
	_mini_wire.center = pw
	_mini_wire.player_w = pw
	_mini_wire.exit_w = _exit_world()
	_mini_wire.door_pts = _seen_door_pts()
	_mini_wire.queue_redraw()
	if _full_root.visible:
		_refresh_full()

## Vuelca a _pts las aristas de las celdas recién vistas (las marca Dungeon.cell_seen) en un radio.
func _reveal(c: Vector2i) -> void:
	var r2 := REVEAL_RADIUS * REVEAL_RADIUS
	for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy > r2:
				continue
			var cc := c + Vector2i(dx, dy)
			if _seen.has(cc) or not _edges_by_cell.has(cc):
				continue
			if not _dungeon.is_seen_cell(cc):
				continue
			_seen[cc] = true
			for ab in _edges_by_cell[cc]:
				_pts.append(ab[0])
				_pts.append(ab[1])

func _refresh_full() -> void:
	var vp := get_viewport().get_visible_rect().size
	_full_wire.pts = _pts
	_full_wire.center = _full_center
	_full_wire.origin = vp * 0.5
	_full_wire.zoom = _full_zoom
	_full_wire.player_w = _dungeon.to_local(_player.global_position)
	_full_wire.exit_w = _exit_world()
	_full_wire.door_pts = _seen_door_pts()
	_full_wire.queue_redraw()

## Aristas (pares a,b) de las puertas YA VISTAS (respeta la niebla) → línea roja en el minimapa.
func _seen_door_pts() -> PackedVector2Array:
	var out := PackedVector2Array()
	for e in _door_edges:
		if _dungeon.is_seen_cell(e["cell"]):
			out.append(e["a"])
			out.append(e["b"])
	return out

## World-local de la salida si ya fue vista; INF (oculto) si no.
func _exit_world() -> Vector2:
	if _exit_cell.x >= 0 and _dungeon.is_seen_cell(_exit_cell):
		return _dungeon.map_to_local(_exit_cell)
	return Vector2(INF, INF)
