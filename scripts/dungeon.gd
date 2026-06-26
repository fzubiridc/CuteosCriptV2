extends TileMapLayer
class_name Dungeon
## Generador procedural de mazmorras (reimaginado de dungeon.js).
## 2.5D estilo Pixi: caras de muro iluminadas + topes oscuros + AO en el piso.
##
## FLAT_MODE (test): apaga la "altura" → solo piso + muro oscuro en ESTA capa
## (como el original, una sola TileMapLayer). Sirve para aislar si la línea fina
## en las uniones piso/muro la causa el sistema de capas de la altura.

const TILE := 16
const MAP_W := 64
const MAP_H := 64
const ROOM_COUNT := 20
const ROOM_MIN := 7
const ROOM_MAX := 13

const SRC_ID := 0
# Atlas por VARIANTES (como Pixi: 8 paredes + 6 pisos, elegidas por hash por celda).
# Filas del atlas: 0=piso, 1=piso+AO, 2=cara(ladrillo), 3=tope(oscuro). Col=variante.
const FLOOR_VARIANTS := 6
const WALL_VARIANTS := 8
const ROW_FLOOR := 0
const ROW_FLOOR_AO := 1
const ROW_FACE := 2
const ROW_TOP := 3

const FACE_SHADER := preload("res://shaders/wall_face.gdshader")

var grid: Array = []
var rooms: Array[Rect2i] = []

## Mapa de PRUEBA fijo (3 cuartos cerrados + corredores) en vez de procgen. Reproducible,
## para verificar luz/oclusión/reveal/oscuridad sin que cambie el layout cada run.
@export var use_test_map := false

## Procgen ISO: tamaños CONFIGURABLES de sala en ejes lógicos (u=ancho/SE, v=profundidad/SW).
## Cada sala se talla como paralelogramo iso (carve_iso_room) → lados rectos, 4 esquinas.
@export var iso_room_width := Vector2i(5, 9)    # rango del eje u (genera los dos lados de profundidad)
@export var iso_room_depth := Vector2i(6, 12)   # rango del eje v (genera los dos lados de ancho)
# Celdas EXACTAS talladas por cada sala iso (paralela a `rooms`, que guarda sólo el bbox). La
# usa _assign_rooms para etiquetar room_id por celda real (el bbox de un paralelogramo solapa vecinos).
var _gen_room_cells: Array = []

## ISO: renderiza el mismo grid como mundo isométrico (piso + muros traseros en
## capa hija) con el tileset iso_pixel, en vez del 2.5D top-down. La generación
## (_gen_grid) y la interfaz (rooms, map_to_local, *_cells) no cambian.
const ISO := true
const NATIVE_WALLS := false  # false = caras de muro UNSHADED (no reciben sombra → sin self-shadow). El PISO
							 # sí es nativo y recibe la sombra del occluder → sombra natural en el piso.
const WALL_SHADOWS := true   # los muros proyectan sombra (occluder) SOBRE EL PISO. Como las caras son
							 # unshaded, no se auto-sombrean. Robusto: sombra natural sin self-shadow.
const WallSegment := preload("res://scripts/wall_segment.gd")
const ISO_TILESET := preload("res://assets/iso/iso_pixel.tres")
# Muros = TILES del TileSet. El texture_origin de cada pieza se afina en el EDITOR de TileSet
# (visual, persiste en el .tres), NO por código. 8 fuentes: cada (pieza de arte, borde) con su
# origin propio. highwall y wall_ne se reusan en 2 fuentes (trasera/delantera) por distinto origin.
const ISO_FLOOR_SRC := 0
const SRC_WALL_NW := 1        # highwall, borde trasero NW
const SRC_WALL_NE := 2        # wall_ne,  borde trasero NE
const SRC_WALL_SE := 3        # highwall, borde delantero SE (fachada)
const SRC_WALL_SW := 4        # wall_ne,  borde delantero SW (fachada)
const SRC_CORNER_TOP := 5     # corner_nw_ne  (NW+NE, trasera ancha)
const SRC_CORNER_BOTTOM := 6  # corner_se_sw  (SE+SW, fachada ancha)
const SRC_CORNER_LEFT := 7    # corner_nw_sw  (NW+SW, alta)
const SRC_CORNER_RIGHT := 8   # corner_ne_se  (NE+SE, alta)
const WALL_SOURCES := [SRC_WALL_NW, SRC_WALL_NE, SRC_WALL_SE, SRC_WALL_SW,
	SRC_CORNER_TOP, SRC_CORNER_BOTTOM, SRC_CORNER_LEFT, SRC_CORNER_RIGHT]
# Fuentes de fachada DELANTERA (S/E): se revelan (semitransparentes) al entrar a la sala.
const FRONT_SOURCES := [SRC_WALL_SE, SRC_WALL_SW, SRC_CORNER_BOTTOM]
var _iso_walls: TileMapLayer        # muros DELANTEROS (fachada S/E) — z=1, ENCIMA del player + reveal
var _iso_walls_back: TileMapLayer   # muros TRASEROS (N/O) — z=-1, DEBAJO del player → el player los tapa
var _iso_astar := AStarGrid2D.new()
var _iso_bounds: StaticBody2D   # barrera de colisión en el perímetro del piso
var _iso_wall_mat_solid: ShaderMaterial # material de las caras de muro (unshaded foot-lit)
# Registro maestro de TODAS las celdas de muro (cell → source). Lo llena _paint_walls.
var _wall_cells: Dictionary = {}
# Datos del tileset precomputados para clonar un tile como Sprite2D (overlay de 3-bordes + reveal).
var _wall_tex: Dictionary = {}      # source → Texture2D
var _wall_origin: Dictionary = {}   # source → Vector2 (texture_origin)
var _wall_segments: Array = []   # Fase 1: lista de WallSegment (muro = lado de celda)
var _corner_sprites: Array = []  # Fase 2: piezas extra de celdas con 3 bordes (Sprite2D permanente)
# Fase 3: reveal por habitación (reemplaza el viejo cutout). Cada celda de piso pertenece
# a una sala (rect de procgen); al entrar, la fachada trasera de esa sala baja a semitransparente
# como CONJUNTO (sin dither, sin per-tile flicker). Estilo Baldur's Gate 3 / Divinity OS2.
const REVEAL_ALPHA := 0.22   # opacidad de la fachada DELANTERA revelada (15-30%), conserva textura/volumen
const ROOM_HYST := 6         # frames que el player debe estar en la sala antes de revelar (anti-flicker)
var _room_of: Dictionary = {}        # cell → room_id (rect de sala; corredores = -1)
var _room_facade: Dictionary = {}    # room_id → Array[Vector2i] (celdas de muro-tile traseras)
var _room_front: Dictionary = {}     # room_id → Array de entradas de fachada delantera (ver _paint_walls):
									 #   {kind=0, cell} = tile-muro (se swapea a sprite al revelar)
									 #   {kind=1, holder} = sprite overlay ya existente (solo tween de alpha)
var _front_src: Dictionary = {}      # cell → source de la pared delantera (para restaurar el tile)
var _room_corners: Dictionary = {}   # room_id → Array[Node2D] (sprites de esquina de esa sala)
var _reveal_sprites: Dictionary = {} # cell → Node2D (tile-muro swapeado a sprite mientras está revelado)
var _reveal_tw: Dictionary = {}      # cell → Tween activo del fade (para cancelarlo en swaps rápidos)
var _active_room: int = -1
var _pending_room: int = -99
var _room_hold: int = 0

# --- Mapa FIJO (autoreado en Tiled) ---
# gid del tileset de diseño (maps/design.tsx, firstgid=1): id+1.
const T_FLOOR := 1
const T_WALL := 2
const T_SPAWN := 3
const T_EXIT := 4
const T_ENEMY := 5
const T_CHEST := 6
const T_TORCH := 7
const T_WINDOW := 8
const MAX_FIXED := 256   # tope duro de tamaño para mapas fijos (guard de perf)
var spawn_cell: Vector2i = Vector2i(-1, -1)
var exit_cell: Vector2i = Vector2i(-1, -1)
var enemy_cells: Array[Vector2i] = []
var chest_cells: Array[Vector2i] = []
var torch_cells: Array[Vector2i] = []
var window_cells: Array[Vector2i] = []

# Caras foot-lit por píxel: por cada variante de muro, textura de ladrillo +
# un ShaderMaterial (wall_face.gdshader) con su normal-map. Los sprites de cara
# usan ese material; dungeon les pasa las luces como uniforms cada frame. Permite
# las 3 (piso + cara iluminados + sombra desde la esquina) con gradiente por
# píxel y relieve, sin que la sombra del occluder oscurezca la cara.
var _face_tex: Array = []
var _face_mats: Array = []
var _face_sprites: Array = []
var _ao_sprites: Array = []         # overlays de AO en uniones piso/muro (oeste/este)
static var _ao_l_tex: Texture2D     # gradiente AO oscuro-a-la-izquierda (cache)
static var _ao_r_tex: Texture2D     # gradiente AO oscuro-a-la-derecha (cache)

## Emitida al terminar de generar un piso (la usa el minimapa para resetear niebla).
signal regenerated

func generate() -> void:
	spawn_cell = Vector2i(-1, -1)
	exit_cell = Vector2i(-1, -1)
	window_cells.clear()
	if ISO:
		_ensure_iso()
		if use_test_map:
			_gen_test_grid()
		else:
			_gen_grid()
		_room_of = _assign_rooms()                # Fase 3: cada celda de piso → su sala (rect)
		_wall_segments = _build_wall_segments()   # Fase 2: segmentos = fuente de verdad del pintado
		_paint_iso()
		_build_iso_nav()
		_build_iso_boundaries()   # colisión en el perímetro → no caminar al vacío
		_place_torches()   # antorchas de sala → luz + sombras proyectadas (map_to_local ya es iso)
		regenerated.emit()
		return
	_ensure_tileset()
	_gen_grid()
	_paint()
	_place_torches()
	_place_windows()
	regenerated.emit()

## Genera un piso FIJO leído de un mapa de Tiled (.tmj) en vez de procedural.
## Reusa el mismo pintado 2.5D + antorchas; el grid sale de la capa "floor" y
## spawn/salida/enemigos/cofres de la capa "markers".
func generate_from_tiled(path: String) -> void:
	spawn_cell = Vector2i(-1, -1)
	exit_cell = Vector2i(-1, -1)
	enemy_cells.clear()
	chest_cells.clear()
	torch_cells.clear()
	window_cells.clear()
	_ensure_tileset()
	if not _load_tiled(path):
		push_error("Mapa Tiled inválido, fallback a procedural: " + path)
		_gen_grid()
	_paint()
	if torch_cells.is_empty():
		_place_torches()        # sin marcadores → auto (como procedural)
	else:
		_place_torches_fixed()  # antorchas en las celdas marcadas
	_place_windows()
	regenerated.emit()

func _load_tiled(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	# .tmj = JSON, .tmx = XML. Detecta por extensión (o por el primer caracter).
	var m: Dictionary
	if path.to_lower().ends_with(".tmx") or text.strip_edges().begins_with("<"):
		m = _parse_tmx(text)
	else:
		m = _parse_tmj(text)
	if m.is_empty():
		return false
	var mw := int(m.get("width", 0))
	var mh := int(m.get("height", 0))
	if mw <= 0 or mh <= 0 or mw > MAX_FIXED or mh > MAX_FIXED:
		push_error("Mapa Tiled fuera de rango: %dx%d (max %dx%d)" % [mw, mh, MAX_FIXED, MAX_FIXED])
		return false
	# El grid toma EXACTAMENTE el tamaño del mapa de Tiled (independiente del 64×64
	# procedural). Arranca todo muro; carvamos el piso desde la capa "floor".
	grid = []
	for y in mh:
		var row: Array = []
		row.resize(mw)
		row.fill(0)
		grid.append(row)
	enemy_cells.clear()
	chest_cells.clear()
	torch_cells.clear()

	var floor_data: Array = m.get("floor", [])
	var mark_data: Array = m.get("markers", [])
	var minx := mw
	var miny := mh
	var maxx := 0
	var maxy := 0
	var any := false
	for y in mh:
		for x in mw:
			var i := y * mw + x
			if i < floor_data.size() and int(floor_data[i]) == T_FLOOR:
				grid[y][x] = 1
				any = true
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
			if i < mark_data.size():
				var mk := int(mark_data[i])
				if mk == T_SPAWN: spawn_cell = Vector2i(x, y)
				elif mk == T_EXIT: exit_cell = Vector2i(x, y)
				elif mk == T_ENEMY: enemy_cells.append(Vector2i(x, y))
				elif mk == T_CHEST: chest_cells.append(Vector2i(x, y))
				elif mk == T_TORCH: torch_cells.append(Vector2i(x, y))
				elif mk == T_WINDOW: window_cells.append(Vector2i(x, y))
	if not any:
		return false
	# "Sala" sintética = bounding box del piso, para el código que itera rooms.
	rooms = [Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)]
	if spawn_cell.x < 0:
		spawn_cell = rooms[0].get_center()
	return true

## Normaliza un mapa de Tiled a { width, height, <capa>: [ints], ... }.
## Soporta ambos formatos: .tmj (JSON) y .tmx (XML, capas en encoding CSV).
func _parse_tmj(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out := {"width": int(parsed.get("width", 0)), "height": int(parsed.get("height", 0))}
	for l in parsed.get("layers", []):
		if l.get("type", "") == "tilelayer":
			out[l.get("name", "")] = l.get("data", [])
	return out

func _parse_tmx(text: String) -> Dictionary:
	var p := XMLParser.new()
	if p.open_buffer(text.to_utf8_buffer()) != OK:
		return {}
	var out := {}
	var cur_layer := ""
	var in_data := false
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var en := p.get_node_name()
				if en == "map":
					out["width"] = int(p.get_named_attribute_value_safe("width"))
					out["height"] = int(p.get_named_attribute_value_safe("height"))
				elif en == "layer":
					cur_layer = p.get_named_attribute_value_safe("name")
				elif en == "data":
					var enc := p.get_named_attribute_value_safe("encoding")
					if enc != "csv":
						push_error("Capa '%s' con encoding '%s' no soportado: guardá las capas en CSV" % [cur_layer, enc])
						in_data = false
					else:
						in_data = cur_layer != ""
			XMLParser.NODE_TEXT:
				if in_data and cur_layer != "":
					out[cur_layer] = _csv_to_ints(p.get_node_data())
			XMLParser.NODE_ELEMENT_END:
				var en2 := p.get_node_name()
				if en2 == "data":
					in_data = false
				elif en2 == "layer":
					cur_layer = ""
	return out

func _csv_to_ints(s: String) -> Array:
	var out: Array = []
	for part in s.split(","):
		var t := part.strip_edges()
		if t != "":
			out.append(int(t))
	return out

func get_spawn_point() -> Vector2:
	if spawn_cell.x >= 0:
		return to_global(map_to_local(spawn_cell))
	if rooms.is_empty():
		return Vector2.ZERO
	return to_global(map_to_local(rooms[0].get_center()))

## Celda de la salida en un mapa fijo, o (-1,-1) si es procedural (usar rooms).
func get_exit_cell() -> Vector2i:
	return exit_cell

# ---------------------------------------------------------------------------
# TileSet (atlas por variantes: 8 paredes + 6 pisos)
# ---------------------------------------------------------------------------
func _ensure_tileset() -> void:
	if tile_set != null:
		return
	var floors: Array = []
	for i in FLOOR_VARIANTS:
		floors.append(_load_tile("res://assets/tiles/torre/floor_%d.png" % i))
	var walls: Array = []
	for i in WALL_VARIANTS:
		walls.append(_load_tile("res://assets/tiles/torre/wall_%d.png" % i))

	# Caras foot-lit por píxel: textura de ladrillo + normal-map por variante,
	# cada una en su ShaderMaterial (luz por píxel + relieve).
	_face_tex.clear()
	_face_mats.clear()
	for i in WALL_VARIANTS:
		var tall := _make_tall_brick(walls[i])   # 16×24: 1.5 ladrillos a escala nativa + banda base
		_face_tex.append(ImageTexture.create_from_image(tall))
		var nrm := ImageTexture.create_from_image(_make_normal(tall, 4.5))
		var mat := ShaderMaterial.new()
		mat.shader = FACE_SHADER
		mat.set_shader_parameter("normal_tex", nrm)
		_face_mats.append(mat)

	var cols := maxi(FLOOR_VARIANTS, WALL_VARIANTS)
	var img := Image.create_empty(TILE * cols, TILE * 4, false, Image.FORMAT_RGBA8)
	for i in FLOOR_VARIANTS:
		img.blit_rect(floors[i], Rect2i(0, 0, TILE, TILE), Vector2i(TILE * i, TILE * ROW_FLOOR))
		img.blit_rect(_make_floor_ao(floors[i]), Rect2i(0, 0, TILE, TILE), Vector2i(TILE * i, TILE * ROW_FLOOR_AO))
	for i in WALL_VARIANTS:
		img.blit_rect(walls[i], Rect2i(0, 0, TILE, TILE), Vector2i(TILE * i, TILE * ROW_FACE))
		img.blit_rect(_make_top(walls[i]), Rect2i(0, 0, TILE, TILE), Vector2i(TILE * i, TILE * ROW_TOP))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.add_navigation_layer()
	ts.add_occlusion_layer()

	var src := TileSetAtlasSource.new()
	src.texture = _canvas_tex(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in FLOOR_VARIANTS:
		src.create_tile(Vector2i(i, ROW_FLOOR))
		src.create_tile(Vector2i(i, ROW_FLOOR_AO))
	for i in WALL_VARIANTS:
		src.create_tile(Vector2i(i, ROW_FACE))
		src.create_tile(Vector2i(i, ROW_TOP))
	# add_source ANTES de tocar tile_data: las capas nav/física/oclusión del
	# TileSet sólo son válidas en los tiles una vez el source está en el set.
	ts.add_source(src, SRC_ID)
	for i in FLOOR_VARIANTS:
		_nav_tile(src.get_tile_data(Vector2i(i, ROW_FLOOR), 0))
		_nav_tile(src.get_tile_data(Vector2i(i, ROW_FLOOR_AO), 0))
	for i in WALL_VARIANTS:
		# Cara + tope: colisión + occluder en TODA la masa de muro. Así la sombra
		# se proyecta desde el contorno del muro contra el piso (el borde del wall
		# tile, "la punta") y NO desde el tope que queda una fila (16px) más arriba.
		_solid_tile(src.get_tile_data(Vector2i(i, ROW_FACE), 0))
		_solid_tile(src.get_tile_data(Vector2i(i, ROW_TOP), 0))

	tile_set = ts

## Variante determinística por celda (hash estilo pixiTileVariant).
func _variant(x: int, y: int, n: int) -> int:
	var h := (x + 101) * 374761393 + (y + 57) * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return posmod(h, n)

func _nav_tile(td: TileData) -> void:
	var nav := NavigationPolygon.new()
	nav.vertices = _square(8.0)
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	td.set_navigation_polygon(0, nav)

func _collide_tile(td: TileData) -> void:
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, _square(8.0))

func _solid_tile(td: TileData) -> void:
	_collide_tile(td)
	var occ := OccluderPolygon2D.new()
	occ.polygon = _square(8.0)
	td.set_occluder(0, occ)

func _square(s: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)
	])

func _make_floor_ao(floor_img: Image) -> Image:
	var ao: Image = floor_img.duplicate()
	var ao_h := 7
	for y in ao_h:
		var t := float(y) / float(ao_h)
		var mul := lerpf(0.42, 1.0, t)
		for x in TILE:
			var c := ao.get_pixel(x, y)
			ao.set_pixel(x, y, Color(c.r * mul, c.g * mul, c.b * mul, c.a))
	return ao

## Cara de muro ALTA (16×24 = 1.5 ladrillos) tileando el ladrillo a escala NATIVA
## (sin estirar), con el ladrillo completo anclado abajo + banda de contacto en la
## base. La media-cara de arriba invade el tile superior → altura real, sin deformar.
const FACE_H := 24
func _make_tall_brick(brick: Image) -> Image:
	var im := Image.create_empty(TILE, FACE_H, false, Image.FORMAT_RGBA8)
	for y in FACE_H:
		var by := posmod(y - (FACE_H - TILE), TILE)   # ladrillo completo anclado abajo
		for x in TILE:
			im.set_pixel(x, y, brick.get_pixel(x, by))
	# banda de contacto oscura en la base (últimos 3px) → asienta el muro en el piso.
	var band := 3
	for y in range(FACE_H - band, FACE_H):
		var t := float(y - (FACE_H - band)) / float(band)
		var mul := lerpf(0.82, 0.55, t)
		for x in TILE:
			var c := im.get_pixel(x, y)
			im.set_pixel(x, y, Color(c.r * mul, c.g * mul, c.b * mul, c.a))
	return im

## Gradiente AO lateral (7px): oscuro pegado al muro → transparente hacia adentro.
func _ao_side_tex(dark_left: bool) -> Texture2D:
	if dark_left and _ao_l_tex != null:
		return _ao_l_tex
	if not dark_left and _ao_r_tex != null:
		return _ao_r_tex
	var w := 7
	var img := Image.create_empty(w, TILE, false, Image.FORMAT_RGBA8)
	for x in w:
		var tt := float(x) / float(w - 1)
		var edge := tt if dark_left else (1.0 - tt)   # 0 en el borde que toca el muro
		var a := lerpf(0.30, 0.0, edge)
		for y in TILE:
			img.set_pixel(x, y, Color(0, 0, 0, a))
	var tex := ImageTexture.create_from_image(img)
	if dark_left:
		_ao_l_tex = tex
	else:
		_ao_r_tex = tex
	return tex

## Sprite de AO en el borde izq/der de un piso que toca un muro lateral.
func _spawn_ao_side(x: int, y: int, dark_left: bool) -> void:
	var spr := Sprite2D.new()
	spr.texture = _ao_side_tex(dark_left)
	spr.centered = false
	var c := map_to_local(Vector2i(x, y))
	spr.position = c + (Vector2(-8, -8) if dark_left else Vector2(1, -8))
	spr.z_as_relative = false
	spr.z_index = -9   # sobre el piso (tilemap z=-10), debajo de entidades (z=0)
	add_child(spr)
	_ao_sprites.append(spr)

## Tope de muro estilo Pixi: base wallDark (saturada, no negra) + textura del
## ladrillo al 30% + capa de sombra → oscuro pero con color y relieve.
func _make_top(brick: Image) -> Image:
	var top := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var base := Color(0.243, 0.243, 0.275)   # wallDark torre (#3e3e46)
	var shadow := Color(0.02, 0.016, 0.04)
	for y in TILE:
		for x in TILE:
			var b := brick.get_pixel(x, y)
			var c := base.lerp(Color(b.r, b.g, b.b), 0.30)   # +30% textura ladrillo
			c = c.lerp(shadow, 0.62)                          # capa de sombra
			top.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	return top

func _darken(src: Image, f: float) -> Image:
	var im: Image = src.duplicate()
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			im.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f, c.a))
	return im

func _canvas_tex(img: Image) -> CanvasTexture:
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(img)
	ct.normal_texture = ImageTexture.create_from_image(_make_normal(img, 4.5))
	ct.specular_color = Color(0.12, 0.11, 0.09)
	ct.specular_shininess = 0.18
	return ct

func _make_normal(src: Image, strength: float) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var nm := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var lxm := src.get_pixel(maxi(x - 1, 0), y).get_luminance()
			var lxp := src.get_pixel(mini(x + 1, w - 1), y).get_luminance()
			var lym := src.get_pixel(x, maxi(y - 1, 0)).get_luminance()
			var lyp := src.get_pixel(x, mini(y + 1, h - 1)).get_luminance()
			var n := Vector3((lxm - lxp) * strength, (lym - lyp) * strength, 1.0).normalized()
			nm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	return nm

func _load_tile(path: String) -> Image:
	# Cargar vía recurso importado (no globalize_path): así funciona en cualquier
	# export, no solo corriendo desde el editor. En web no hay filesystem de OS.
	var tex := load(path) as Texture2D
	var im: Image = tex.get_image() if tex != null else null
	if im == null:
		return Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	if im.is_compressed():
		im.decompress()
	if im.get_format() != Image.FORMAT_RGBA8:
		im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != TILE or im.get_height() != TILE:
		im.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return im

# ---------------------------------------------------------------------------
# Generación de la grilla
# ---------------------------------------------------------------------------
func _gen_grid() -> void:
	rooms.clear()
	_gen_room_cells = []
	grid = []
	for y in MAP_H:
		var row: Array = []
		row.resize(MAP_W)
		row.fill(0)
		grid.append(row)

	# Ocupación (celdas talladas + margen cardinal de 1) para test de solape entre paralelogramos:
	# el bbox de un rombo iso solapa a sus vecinos, así que NO sirve Rect2i.intersects — se testea celda a celda.
	var occupied := {}
	var prev_center := Vector2i.ZERO
	for i in ROOM_COUNT:
		for attempt in 30:
			var w := Rng.range_i(iso_room_width.x, iso_room_width.y)
			var d := Rng.range_i(iso_room_depth.x, iso_room_depth.y)
			# Origen en una banda interior segura; el chequeo de bordes + reintentos descarta los malos.
			var origin := Vector2i(Rng.range_i(d + 1, MAP_W - w - 2), Rng.range_i(1, MAP_H - w - d - 2))
			var cells := _iso_room_cells(origin, w, d)
			var ok := true
			for c in cells:
				if c.x < 1 or c.y < 1 or c.x >= MAP_W - 1 or c.y >= MAP_H - 1 or occupied.has(c):
					ok = false
					break
			if not ok:
				continue
			for c in cells:
				grid[c.y][c.x] = 1
				occupied[c] = true
				occupied[c + Vector2i(1, 0)] = true
				occupied[c + Vector2i(-1, 0)] = true
				occupied[c + Vector2i(0, 1)] = true
				occupied[c + Vector2i(0, -1)] = true
			_gen_room_cells.append(cells)
			var bbox := _cells_bbox(cells)
			var center := bbox.get_center()
			if not rooms.is_empty():
				_connect(prev_center, center)
			rooms.append(bbox)
			prev_center = center
			break
	_remove_thin_walls()

## Celdas (sin escribir grid) de una sala iso lógica width×depth desde `origin`. Compute-only para
## el test de solape del procgen; carve_iso_room hace lo mismo pero además escribe el piso.
func _iso_room_cells(origin: Vector2i, width: int, depth: int) -> Array:
	var cells: Array = []
	var base := map_to_local(origin)
	for u in width:
		for v in depth:
			cells.append(local_to_map(base + ISO_AXIS_A * u + ISO_AXIS_B * v))
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
		for ty in range(1, MAP_H - 1):
			for tx in range(1, MAP_W - 1):
				if grid[ty][tx] != 0:
					continue
				var horiz: bool = grid[ty][tx - 1] == 1 and grid[ty][tx + 1] == 1
				var vert: bool = grid[ty - 1][tx] == 1 and grid[ty + 1][tx] == 1
				if horiz or vert:
					open.append(Vector2i(tx, ty))
		for c in open:
			grid[c.y][c.x] = 1

func _carve_room(r: Rect2i) -> void:
	for yy in range(r.position.y, r.position.y + r.size.y):
		for xx in range(r.position.x, r.position.x + r.size.x):
			grid[yy][xx] = 1

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
		if cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < grid[cell.y].size():
			grid[cell.y][cell.x] = 1
			cells.append(cell)
	return cells

func _connect(a: Vector2i, b: Vector2i) -> void:
	if Rng.chance(0.5):
		_carve_h(a.x, b.x, a.y)
		_carve_v(a.y, b.y, b.x)
	else:
		_carve_v(a.y, b.y, a.x)
		_carve_h(a.x, b.x, b.y)

func _carve_h(x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		grid[y][x] = 1
		if y + 1 < MAP_H:
			grid[y + 1][x] = 1

func _carve_v(y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		grid[y][x] = 1
		if x + 1 < MAP_W:
			grid[y][x + 1] = 1

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
## en vivo. La usa el sandbox (closed_room_test) y, a futuro, _place_torches del procgen.
func spawn_wall_torch(interior_cell: Vector2i, side: int) -> Node:
	var parent := get_parent()
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
	var anchor := to_global(map_to_local(cell) + _edge_midpoint(side))
	var flame := Vector2(LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"))
	var light_off: Vector2 = WallSegment.INWARD_NORMAL[side] * LightCfg.get_v("torch_light_inset")
	t.set("light_offset", light_off)
	t.set("position", anchor + light_off)
	if t.has_method("set_mount"):
		t.call("set_mount", flame, light_off)

## Punto medio del borde de muro, en coords de celda iso (rombo 256×128 centrado).
func _edge_midpoint(side: int) -> Vector2:
	match side:
		WallSegment.Side.NW: return Vector2(-64, -32)
		WallSegment.Side.NE: return Vector2(64, -32)
		WallSegment.Side.SE: return Vector2(64, 32)
		WallSegment.Side.SW: return Vector2(-64, 32)
	return Vector2.ZERO

## Reposiciona las antorchas ancladas si cambiaste los @export (Remote inspector durante Play).
func _tune_torches_live() -> void:
	if _torches.is_empty():
		return
	var c := [LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"), LightCfg.get_v("torch_light_inset")]
	if c == _torch_cfg_cache:
		return
	_torch_cfg_cache = c
	for e in _torches:
		if is_instance_valid(e.node):
			_position_torch(e.node, e.cell, e.side)

func _place_torches() -> void:
	var gw: int = grid[0].size() if not grid.is_empty() else MAP_W
	var gh := grid.size()
	var parent := get_parent()
	var holder := parent.get_node_or_null("Torches")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Torches"
		parent.add_child(holder)
	else:
		for c in holder.get_children():
			c.queue_free()
	var torch_script := load("res://scripts/torch.gd")
	var side_torch_script := load("res://scripts/side_torch.gd")
	var idx := 0
	const MAX_TORCHES := 32
	for room_i in rooms.size():
		var r := rooms[room_i]
		if idx >= MAX_TORCHES:
			break
		var wall_row := r.position.y - 1
		if wall_row < 0:
			continue
		for x in [r.position.x + 2, r.position.x + r.size.x - 3]:
			if idx >= MAX_TORCHES:
				break
			if x < 0 or x >= gw or grid[wall_row][x] != 0:
				continue
			var t := PointLight2D.new()
			t.set_script(torch_script)
			t.seed_off = idx * 1.7
			var light_inset := ISO_TORCH_LIGHT_INSET if ISO else Vector2.ZERO
			t.light_offset = light_inset
			# La LUZ va un poco DENTRO de la sala (fuera del occluder del muro) para
			# que ilumine el piso; si la dejábamos en la cara, el muro bloqueaba su
			# propia luz. El SPRITE de la antorcha se sube en torch.gd para quedar
			# sobre la cara del muro.
			t.position = to_global(map_to_local(Vector2i(x, wall_row))) + Vector2(0, 11) + light_inset
			holder.add_child(t)
			idx += 1

		# Una antorcha lateral en habitaciones alternas. El lado cambia por sala
		# para que ambas variantes aparezcan sin saturar el mapa de luces. Si el
		# lado elegido coincide con un pasillo abierto, prueba el muro opuesto.
		if room_i % 2 == 0 and idx < MAX_TORCHES:
			@warning_ignore("integer_division")
			var preferred: StringName = &"left" if int(room_i / 2) % 2 == 0 else &"right"
			var alternate: StringName = &"right" if preferred == &"left" else &"left"
			var side_choices: Array[StringName] = [preferred, alternate]
			for side in side_choices:
				var wall_x: int = r.position.x - 1 if side == &"left" else r.position.x + r.size.x
				var inner_x: int = wall_x + 1 if side == &"left" else wall_x - 1
				@warning_ignore("integer_division")
				var wall_y: int = r.position.y + r.size.y / 2
				if wall_x < 0 or wall_x >= gw or wall_y < 0 or wall_y >= gh:
					continue
				if grid[wall_y][wall_x] != 0 or grid[wall_y][inner_x] != 1:
					continue
				var side_torch := PointLight2D.new()
				side_torch.set_script(side_torch_script)
				side_torch.wall_side = side
				side_torch.seed_off = idx * 1.7
				var inward := Vector2(11, 6) if side == &"left" else Vector2(-11, 6)
				var side_light_inset := Vector2.ZERO
				if ISO:
					side_light_inset = Vector2(
						ISO_SIDE_TORCH_LIGHT_INSET if side == &"left" else -ISO_SIDE_TORCH_LIGHT_INSET,
						-6
					)
				side_torch.light_offset = side_light_inset
				side_torch.position = to_global(map_to_local(Vector2i(wall_x, wall_y))) + inward + side_light_inset
				holder.add_child(side_torch)
				idx += 1
				break
	LightField.mark_dirty()   # refrescar la lista de luces para el foot-light

## Antorchas en las celdas marcadas (capa "markers" de Tiled). Reemplaza el
## auto-placement cuando el mapa fijo define sus propias antorchas.
func _place_torches_fixed() -> void:
	var parent := get_parent()
	var holder := parent.get_node_or_null("Torches")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Torches"
		parent.add_child(holder)
	else:
		for c in holder.get_children():
			c.queue_free()
	var torch_script := load("res://scripts/torch.gd")
	var idx := 0
	for cell in torch_cells:
		var t := PointLight2D.new()
		t.set_script(torch_script)
		t.seed_off = idx * 1.7
		t.position = to_global(map_to_local(cell)) + Vector2(0, 11)
		holder.add_child(t)
		idx += 1
	LightField.mark_dirty()

# ---------------------------------------------------------------------------
# Ventanas (cielo generado + marco transparente + luz de luna)
# ---------------------------------------------------------------------------
## Cielo nocturno generado EN CÓDIGO, panorámico y en 2 capas para parallax:
## FAR = bandas noche→horizonte + estrellas + luna (scroll lento).
## NEAR = siluetas de torres en el horizonte (scroll más rápido).
## Cada textura se devuelve DUPLICADA (2× de ancho) para loop sin costura.
const SKY_W := 192
const SKY_H := 48

static var _sky_far: Texture2D
func _sky_far_texture() -> Texture2D:
	if _sky_far != null:
		return _sky_far
	var img := Image.create_empty(SKY_W, SKY_H, false, Image.FORMAT_RGBA8)
	for y in SKY_H:
		var t := float(y) / float(SKY_H)
		var c := Color(0.04, 0.05, 0.14).lerp(Color(0.12, 0.13, 0.26), t)
		for x in SKY_W:
			img.set_pixel(x, y, c)
	var sr := RandomNumberGenerator.new()
	sr.seed = 1337
	for _i in 70:                                       # estrellas
		var sx := sr.randi_range(0, SKY_W - 1)
		var sy := sr.randi_range(0, int(SKY_H * 0.78))
		var b := sr.randf_range(0.5, 1.0)
		img.set_pixel(sx, sy, Color(b, b, minf(b * 1.1, 1.0), 1.0))
	var mcx := 132                                      # luna
	var mcy := 15
	var mr := 9
	for y in range(maxi(mcy - mr, 0), mini(mcy + mr + 1, SKY_H)):
		for x in range(maxi(mcx - mr, 0), mini(mcx + mr + 1, SKY_W)):
			var d := Vector2(x - mcx, y - mcy).length()
			if d <= mr:
				var g := clampf(1.0 - d / float(mr), 0.0, 1.0)
				img.set_pixel(x, y, Color(0.40, 0.48, 0.66).lerp(Color(0.9, 0.92, 1.0), g))
	_sky_far = ImageTexture.create_from_image(_doubled(img))
	return _sky_far

static var _sky_near: Texture2D
func _sky_near_texture() -> Texture2D:
	if _sky_near != null:
		return _sky_near
	var img := Image.create_empty(SKY_W, SKY_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tower := Color(0.06, 0.05, 0.12)
	var bases: Array[int] = [22, 58, 96, 138, 168]      # torres lejanas
	var i := 0
	for bx in bases:
		var tw := 9 + (i % 3) * 2
		var top := 22 + (i % 4) * 3
		for y in range(top, SKY_H):
			for x in range(bx, bx + tw):
				if x >= 0 and x < SKY_W:
					img.set_pixel(x, y, tower)
		var apex := bx + int(tw / 2.0)                  # techo triangular
		for dy in 6:
			var yy := top - 6 + dy
			for x in range(apex - dy, apex + dy + 1):
				if x >= 0 and x < SKY_W and yy >= 0:
					img.set_pixel(x, yy, tower)
		i += 1
	_sky_near = ImageTexture.create_from_image(_doubled(img))
	return _sky_near

## Devuelve la imagen duplicada horizontalmente (2×) → permite scrollear el
## recorte sin salir de bounds ni ver costura (la 2ª mitad repite la 1ª).
func _doubled(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w * 2, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 0))
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(w, 0))
	return out

## Marco de ventana generado EN CÓDIGO: borde + cruz de montantes (4 vidrios) +
## alféizar. Los vidrios quedan transparentes → se ve el cielo de atrás.
static var _win_tex: Texture2D
func _window_frame_texture() -> Texture2D:
	if _win_tex != null:
		return _win_tex
	var w := 24
	var h := 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.16, 0.13, 0.10)         # marco oscuro
	var fb := 3                                   # grosor del marco
	for y in h:
		for x in w:
			if x < fb or x >= w - fb or y < fb or y >= h - fb:
				img.set_pixel(x, y, frame)
	for y in h:                                   # montante vertical
		@warning_ignore("integer_division")
		for x in range(w / 2 - 1, w / 2 + 1):
			img.set_pixel(x, y, frame)
	for x in w:                                   # montante horizontal
		@warning_ignore("integer_division")
		for y in range(h / 2 - 1, h / 2 + 1):
			img.set_pixel(x, y, frame)
	var sill := Color(0.30, 0.26, 0.22)           # alféizar abajo
	for y in range(h - 3, h):
		for x in w:
			img.set_pixel(x, y, sill)
	_win_tex = ImageTexture.create_from_image(img)
	return _win_tex

## En cada celda-ventana: parche de cielo (detrás) + marco transparente (delante,
## deja ver el cielo por los vidrios) + una luz de luna fría que entra a la sala.
func _place_windows() -> void:
	var parent := get_parent()
	var holder := parent.get_node_or_null("Windows")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Windows"
		parent.add_child(holder)
	else:
		for c in holder.get_children():
			c.queue_free()
	if window_cells.is_empty():
		return
	var light_tex := load("res://assets/fx/light_pool.tres")
	for cell in window_cells:
		var pos := to_global(map_to_local(cell))
		# La celda quedó como hueco (saltada en _paint) → se ve el fondo detrás.
		# El marco va encima; sus vidrios transparentes dejan ver el paisaje.
		var win := Sprite2D.new()
		win.texture = _window_frame_texture()
		win.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		win.position = pos
		win.z_as_relative = false
		win.z_index = -7
		holder.add_child(win)
		var body := StaticBody2D.new()         # colisión: el hueco es solo visual, no se pasa
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(TILE, TILE)
		cs.shape = box
		body.add_child(cs)
		body.position = pos
		holder.add_child(body)
		var lt := PointLight2D.new()
		lt.texture = light_tex
		lt.color = Color(0.55, 0.72, 1.0)      # luz de luna fría
		lt.energy = 1.25
		lt.texture_scale = 0.55
		lt.position = pos + Vector2(0, 14)     # cae hacia adentro de la sala
		holder.add_child(lt)
	LightField.mark_dirty()

# ---------------------------------------------------------------------------
# Pintado
# ---------------------------------------------------------------------------
## 2.5D en UNA SOLA capa (sin sub-capas → sin seam entre capas). El contraste
## piso / cara-de-ladrillo / tope-oscuro / AO da la profundidad; los topes son
## lit pero muy oscuros (0.10) en vez de unshaded.
# ---------------------------------------------------------------------------
# RENDER ISO (fase 1 del merge): reusa _gen_grid; pinta piso en esta capa y los
# muros traseros (frente abierto) en una capa hija. map_to_local pasa a iso solo.
# ---------------------------------------------------------------------------
func _ensure_iso() -> void:
	tile_set = ISO_TILESET
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -10
	y_sort_enabled = false
	scale = Vector2(0.5, 0.5)   # provisional; se afina en fase 2 (escala/cámara)
	if _iso_walls == null or not is_instance_valid(_iso_walls):
		_iso_walls = TileMapLayer.new()
		_iso_walls.name = "IsoWalls"
		add_child(_iso_walls)
	_setup_iso_wall_layer(_iso_walls, 1)         # fachada delantera: ENCIMA del player (+ reveal)
	if _iso_walls_back == null or not is_instance_valid(_iso_walls_back):
		_iso_walls_back = TileMapLayer.new()
		_iso_walls_back.name = "IsoWallsBack"
		add_child(_iso_walls_back)
	_setup_iso_wall_layer(_iso_walls_back, -1)   # muros traseros: DEBAJO del player → el player los tapa
	_install_iso_occluders()
	_cache_wall_tile_data()
	_iso_wall_mat_solid = _make_wall_mat()   # caras de muro: unshaded foot-lit
	# NATIVE_WALLS: sin material custom → pipeline LIT nativo. El shader unshaded solo si NATIVE_WALLS=false.
	var wm: ShaderMaterial = null if NATIVE_WALLS else _iso_wall_mat_solid
	_iso_walls.material = wm
	_iso_walls_back.material = wm

## Precomputa textura y texture_origin de CADA fuente de muro del tileset → para clonar
## un tile como Sprite2D pixel-perfect (overlay de 3-bordes + sprite de reveal). El origin
## sale del .tres (lo afina el usuario en el editor), así sprite y tile calzan idéntico.
func _cache_wall_tile_data() -> void:
	_wall_tex = {}
	_wall_origin = {}
	for sid in WALL_SOURCES:
		var src := ISO_TILESET.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		_wall_tex[sid] = src.texture
		var td := src.get_tile_data(Vector2i(0, 0), 0)
		if td == null:
			continue
		_wall_origin[sid] = Vector2(td.texture_origin)

## Config común de una capa de muros iso. z ABSOLUTO: +1 = fachada delantera (tapa al player);
## −1 = muros traseros (debajo del player → el player los tapa). Cada capa y-sortea sus tiles.
func _setup_iso_wall_layer(layer: TileMapLayer, z: int) -> void:
	layer.tile_set = ISO_TILESET
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.y_sort_enabled = true
	layer.z_as_relative = false
	layer.z_index = z

## Material foot-lit de las caras de muro (normal plana → solo falloff por distancia +
## cara direccional). _update_iso_wall_mat le pasa las luces cada frame.
func _make_wall_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACE_SHADER
	var flat := Image.create(1, 1, false, Image.FORMAT_RGB8)
	flat.set_pixel(0, 0, Color(0.5, 0.5, 1.0))
	m.set_shader_parameter("normal_tex", ImageTexture.create_from_image(flat))
	m.set_shader_parameter("relief_floor", 1.0)
	m.set_shader_parameter("use_face_normal", true)   # cara plana direccional (mira a la cámara)
	return m

## Instala OccluderPolygon2D en CADA fuente de muro → los muros proyectan sombra sobre el
## piso. El occluder es la LÍNEA BASE donde el muro toca el piso (el/los borde/s de rombo que
## la pieza cierra), en coords de celda (rombo 256x128, igual que _build_iso_boundaries). Es
## independiente del texture_origin (que solo mueve el dibujo). Godot 4.6 no persiste el
## occluder per-tile en el .tres → se setea en runtime.
func _install_iso_occluders() -> void:
	var ts := ISO_TILESET
	if ts.get_occlusion_layers_count() == 0:
		ts.add_occlusion_layer()
	# light_mask 0 → ningún occluder de muro proyecta sombra (mata self-shadow + gigantes).
	ts.set_occlusion_layer_light_mask(0, 1 if WALL_SHADOWS else 0)
	# Esquinas del rombo de piso (centro de celda): Top, Right, Bottom, Left.
	var t := Vector2(0, -64)
	var r := Vector2(128, 0)
	var b := Vector2(0, 64)
	var l := Vector2(-128, 0)
	# Por fuente: polilínea del/los borde/s de rombo que la pieza ocupa.
	var edges := {
		SRC_WALL_NW: PackedVector2Array([l, t]),          # borde NW
		SRC_WALL_NE: PackedVector2Array([t, r]),          # borde NE
		SRC_WALL_SE: PackedVector2Array([r, b]),          # borde SE
		SRC_WALL_SW: PackedVector2Array([b, l]),          # borde SW
		SRC_CORNER_TOP: PackedVector2Array([l, t, r]),    # NW+NE
		SRC_CORNER_BOTTOM: PackedVector2Array([r, b, l]), # SE+SW
		SRC_CORNER_LEFT: PackedVector2Array([b, l, t]),   # SW+NW
		SRC_CORNER_RIGHT: PackedVector2Array([t, r, b]),  # NE+SE
	}
	for sid in edges:
		var src := ts.get_source(sid) as TileSetAtlasSource
		if src == null:
			continue
		var td := src.get_tile_data(Vector2i(0, 0), 0)
		if td == null:
			continue
		var occ := OccluderPolygon2D.new()
		occ.closed = false   # línea base (no área) → sombra desde el contacto piso/muro
		occ.cull_mode = OccluderPolygon2D.CULL_DISABLED
		occ.polygon = edges[sid]
		td.set_occluder_polygons_count(0, 1)
		td.set_occluder_polygon(0, 0, occ)

func _paint_iso() -> void:
	clear()
	if _iso_walls:
		_iso_walls.clear()
	if _iso_walls_back:
		_iso_walls_back.clear()
	# Reset: liberar overlays previos (clear() borra tiles, NO los Sprite2D hijos).
	for s in _corner_sprites:
		if is_instance_valid(s):
			s.queue_free()
	for h in _reveal_sprites.values():
		if is_instance_valid(h):
			h.queue_free()
	_corner_sprites = []
	_room_facade = {}
	_room_front = {}
	_front_src = {}
	_room_corners = {}
	_reveal_sprites = {}
	_reveal_tw = {}
	_active_room = -1
	_pending_room = -99
	_room_hold = 0
	_wall_cells = {}
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	# Piso.
	for y in gh:
		for x in gw:
			if grid[y][x] == 1:
				set_cell(Vector2i(x, y), ISO_FLOOR_SRC, Vector2i(0, 0))
	_paint_walls()
	update_internals()
	if _iso_walls:
		_iso_walls.update_internals()
	if _iso_walls_back:
		_iso_walls_back.update_internals()

## Pinta TODOS los muros como TILES del TileSet (set_cell) en la capa y-sorted. Una celda mapea
## a 1 o 2 piezas (esquinas = 2 bordes en una pieza; bordes sueltos = 1 cada uno). Como un
## TileMapLayer admite 1 tile por celda, la 1ª pieza va de tile y las EXTRA (celdas raras con 3
## bordes) van de Sprite2D overlay. Las fachadas delanteras (S/E) se registran por sala para el
## reveal de transparencia. Modelo: A (highwall)=NW/SE, B (wall_ne)=NE/SW + 4 esquinas dedicadas.
func _paint_walls() -> void:
	var sides_of := {}
	for seg in _wall_segments:
		var c: Vector2i = seg.interior_cell
		if not sides_of.has(c):
			sides_of[c] = {}
		sides_of[c][seg.side] = true
	for c in sides_of:
		var s: Dictionary = sides_of[c]
		var rid: int = _room_of.get(c, -1)
		var nw: bool = s.has(WallSegment.Side.NW)
		var ne: bool = s.has(WallSegment.Side.NE)
		var se: bool = s.has(WallSegment.Side.SE)
		var sw: bool = s.has(WallSegment.Side.SW)
		# Piezas a colocar en la celda: [{src, front}]. Esquinas primero (consumen 2 bordes).
		var pieces: Array = []
		if nw and ne:
			pieces.append({"src": SRC_CORNER_TOP, "front": false}); nw = false; ne = false
		if se and sw:
			pieces.append({"src": SRC_CORNER_BOTTOM, "front": true}); se = false; sw = false
		if nw and sw:
			pieces.append({"src": SRC_CORNER_LEFT, "front": false}); nw = false; sw = false
		if ne and se:
			pieces.append({"src": SRC_CORNER_RIGHT, "front": false}); ne = false; se = false
		# Bordes sueltos restantes. SE/SW = fachada delantera (revelable).
		if nw: pieces.append({"src": SRC_WALL_NW, "front": false})
		if ne: pieces.append({"src": SRC_WALL_NE, "front": false})
		if se: pieces.append({"src": SRC_WALL_SE, "front": true})
		if sw: pieces.append({"src": SRC_WALL_SW, "front": true})
		_place_wall_pieces(c, rid, pieces)

## Coloca las piezas de una celda: la 1ª como TILE (set_cell), las extra como Sprite2D overlay.
## Registra las fachadas delanteras por sala para el reveal (tile → swap; overlay → tween).
func _place_wall_pieces(c: Vector2i, rid: int, pieces: Array) -> void:
	if pieces.is_empty():
		return
	var prim: Dictionary = pieces[0]
	_wall_layer_for(prim.src).set_cell(c, prim.src, Vector2i(0, 0))
	_wall_cells[c] = prim.src
	if prim.front and rid >= 0:
		_front_src[c] = prim.src
		_add_front_entry(rid, {"kind": 0, "cell": c})
	for i in range(1, pieces.size()):
		var p: Dictionary = pieces[i]
		var h := _spawn_wall_sprite(c, p.src, true)
		if p.front and rid >= 0:
			_add_front_entry(rid, {"kind": 1, "holder": h})

func _add_front_entry(rid: int, entry: Dictionary) -> void:
	if not _room_front.has(rid):
		_room_front[rid] = []
	_room_front[rid].append(entry)

## Clona una fuente de muro como Sprite2D (mismo árbol y-sort que el tile → orden idéntico). El
## holder va en map_to_local(cell) (su .y = clave de sort, igual que el tile); el sprite se offsetea
## por -texture_origin → pixel-perfect. permanent=true lo agrega a _corner_sprites (overlay de
## 3-bordes); false = sprite efímero del reveal (vive en _reveal_sprites).
## Capa según la pieza: fachadas delanteras (FRONT_SOURCES) arriba del player; el resto (traseras) debajo.
func _wall_layer_for(src: int) -> TileMapLayer:
	return _iso_walls if src in FRONT_SOURCES else _iso_walls_back

func _spawn_wall_sprite(cell: Vector2i, source: int, permanent: bool) -> Node2D:
	var layer := _wall_layer_for(source)
	var holder := Node2D.new()
	holder.position = layer.map_to_local(cell)
	var spr := Sprite2D.new()
	spr.texture = _wall_tex.get(source)
	spr.centered = true
	spr.offset = -_wall_origin.get(source, Vector2.ZERO)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = null if NATIVE_WALLS else _iso_wall_mat_solid
	holder.add_child(spr)
	layer.add_child(holder)
	if permanent:
		_corner_sprites.append(holder)
	return holder

func _build_iso_nav() -> void:
	var cells := get_used_cells()
	if cells.is_empty():
		return
	var mn := cells[0]
	var mx := cells[0]
	for c in cells:
		mn = mn.min(c)
		mx = mx.max(c)
	_iso_astar.region = Rect2i(mn, mx - mn + Vector2i.ONE)
	_iso_astar.cell_size = Vector2.ONE
	_iso_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_iso_astar.update()
	for yy in range(_iso_astar.region.position.y, _iso_astar.region.end.y):
		for xx in range(_iso_astar.region.position.x, _iso_astar.region.end.x):
			_iso_astar.set_point_solid(Vector2i(xx, yy), true)
	for c in cells:
		_iso_astar.set_point_solid(c, false)
	if _iso_walls:
		for wc in _iso_walls.get_used_cells():
			if _iso_astar.is_in_boundsv(wc):
				_iso_astar.set_point_solid(wc, true)
	if _iso_walls_back:
		for wc in _iso_walls_back.get_used_cells():
			if _iso_astar.is_in_boundsv(wc):
				_iso_astar.set_point_solid(wc, true)
	Enemy.path_grid = self

## Contrato de pathfinding para los mobs (igual que iso_procgen.next_point).
func next_point(from_world: Vector2, to_world: Vector2) -> Vector2:
	var fc := local_to_map(to_local(from_world))
	var tc := local_to_map(to_local(to_world))
	if not _iso_astar.is_in_boundsv(fc) or not _iso_astar.is_in_boundsv(tc):
		return to_world
	if _iso_astar.is_point_solid(fc) or _iso_astar.is_point_solid(tc):
		return to_world
	var path := _iso_astar.get_id_path(fc, tc)
	if path.size() < 2:
		return to_world
	return to_global(map_to_local(path[1]))


## Barrera de colisión en el perímetro del piso: por cada celda VACÍA (grid==0)
## pegada a piso (cardinal), un CollisionShape que cubre la celda → el player no
## puede salirse al vacío. Un solo StaticBody2D (capa 1, como los muros).
func _build_iso_boundaries() -> void:
	if _iso_bounds != null and is_instance_valid(_iso_bounds):
		_iso_bounds.queue_free()
	_iso_bounds = StaticBody2D.new()
	_iso_bounds.collision_layer = 1
	_iso_bounds.collision_mask = 0
	add_child(_iso_bounds)
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	var cardinals := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in gh:
		for x in gw:
			if grid[y][x] != 0:
				continue
			var adj := false
			for d in cardinals:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < gw and ny >= 0 and ny < gh and grid[ny][nx] == 1:
					adj = true
					break
			if not adj:
				continue
			var cs := CollisionShape2D.new()
			# Rombo iso (256x128) en vez de un RECT AABB: el rect se metía en los diamantes
			# de piso vecinos (sus 4 esquinas triangulares) → "contactos extraños" y no poder
			# acercarse al borde. El rombo calza exacto con el borde visual del piso.
			var diamond := ConvexPolygonShape2D.new()
			diamond.points = PackedVector2Array([
				Vector2(0, -64), Vector2(128, 0), Vector2(0, 64), Vector2(-128, 0)
			])
			cs.shape = diamond
			cs.position = map_to_local(Vector2i(x, y))
			_iso_bounds.add_child(cs)


## Fase 1: genera los muros como SEGMENTOS (un muro por LADO de celda que da al vacío).
## A diferencia del if/elif viejo, una celda puede emitir varias caras (esquinas). Por ahora
## corre en PARALELO al pintado viejo (no cambia el render); las fases siguientes pintarán
## desde acá. Loguea cuántas esquinas detecta que el sistema viejo dejaba con una sola cara.
func _build_wall_segments() -> Array:
	var segs: Array = []
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	for y in gh:
		for x in gw:
			if grid[y][x] != 1:
				continue
			var cell := Vector2i(x, y)
			# 4 bordes de rombo: hay muro si el vecino al otro lado es vacío.
			for side in [WallSegment.Side.NW, WallSegment.Side.NE, WallSegment.Side.SE, WallSegment.Side.SW]:
				if _seg_is_floor(WallSegment.neighbor(cell, side), gw, gh):
					continue
				var facade: bool = side == WallSegment.Side.SE or side == WallSegment.Side.SW
				var seg = WallSegment.new(cell, side, 0, facade)
				seg.room_id = _room_of.get(cell, -1)
				segs.append(seg)
	print("[walls] segmentos=%d" % segs.size())
	return segs

func _seg_is_floor(c: Vector2i, gw: int, gh: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh and grid[c.y][c.x] == 1

## Cada celda de piso → índice de su sala (rect de procgen). Corredores (fuera de todo rect)
## quedan en -1. Usamos los rects y NO flood-fill, porque el flood-fill daría UNA sola región
## (todo el piso está conectado por pasillos) y el reveal por sala perdería sentido.
func _assign_rooms() -> Dictionary:
	var out := {}
	# Procgen iso: etiqueta por las celdas EXACTAS de cada paralelogramo (el bbox solaparía vecinos).
	if not _gen_room_cells.is_empty():
		for i in _gen_room_cells.size():
			for c in _gen_room_cells[i]:
				if c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[c.y].size() and grid[c.y][c.x] == 1:
					out[c] = i
		return out
	# Fallback cartesiano (mapas fijos / _gen_test_grid): salas = Rect2i.
	for i in rooms.size():
		var r: Rect2i = rooms[i]
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				if y >= 0 and y < grid.size() and x >= 0 and x < grid[y].size() and grid[y][x] == 1:
					out[Vector2i(x, y)] = i
	return out

## Mapa de prueba FIJO: 3 cuartos cerrados conectados por corredores (deterministas).
func _gen_test_grid() -> void:
	rooms.clear()
	_gen_room_cells = []   # test fijo usa Rect2i → _assign_rooms cae al fallback cartesiano
	grid = []
	var gw := 28
	var gh := 24
	for y in gh:
		var row: Array = []
		row.resize(gw)
		row.fill(0)
		grid.append(row)
	var ra := Rect2i(2, 2, 8, 8)
	var rb := Rect2i(17, 2, 9, 8)
	var rc := Rect2i(9, 13, 9, 8)
	for r in [ra, rb, rc]:
		_carve_room(r)
		rooms.append(r)
	# Corredores deterministas (L) — dejan vanos/puertas en las fachadas.
	var ca := ra.get_center()
	var cb := rb.get_center()
	var cc := rc.get_center()
	_carve_h(ca.x, cb.x, ca.y)
	_carve_v(ca.y, cc.y, ca.x)
	_carve_h(ca.x, cc.x, cc.y)
	spawn_cell = ca
	exit_cell = Vector2i(-1, -1)


func _paint() -> void:
	_clear_faces()
	clear()
	y_sort_enabled = false
	z_index = -10
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	for y in gh:
		for x in gw:
			if window_cells.has(Vector2i(x, y)):
				continue                       # hueco: deja ver el fondo por la ventana
			var atlas: Vector2i
			if grid[y][x] == 1:
				var wall_above: bool = y - 1 >= 0 and grid[y - 1][x] == 0
				var v := _variant(x, y, FLOOR_VARIANTS)
				atlas = Vector2i(v, ROW_FLOOR_AO if wall_above else ROW_FLOOR)
				# AO en las uniones laterales (oeste/este): overlay direccional.
				if x - 1 >= 0 and grid[y][x - 1] == 0:
					_spawn_ao_side(x, y, true)
				if x + 1 < gw and grid[y][x + 1] == 0:
					_spawn_ao_side(x, y, false)
			elif y + 1 < gh and grid[y + 1][x] == 1:
				atlas = Vector2i(_variant(x, y, WALL_VARIANTS), ROW_FACE)
				_spawn_face(x, y)   # cara foot-lit encima (el tile del tilemap aporta occluder+colisión)
			else:
				atlas = Vector2i(_variant(x, y, WALL_VARIANTS), ROW_TOP)
			set_cell(Vector2i(x, y), SRC_ID, atlas)

# ---------------------------------------------------------------------------
# Caras foot-lit
# ---------------------------------------------------------------------------
## La cara del muro se dibuja como Sprite2D UNSHADED encima de su tile (que queda
## oscuro por el occluder, pero tapado) y se tinta cada frame con LightField →
## la antorcha la ilumina aunque el occluder de la propia cara proyecte la sombra
## desde la esquina del muro. Pierde el relieve por normal-map (tinte plano).
func _spawn_face(x: int, y: int) -> void:
	var v := _variant(x, y, WALL_VARIANTS)
	var spr := Sprite2D.new()
	spr.texture = _face_tex[v]
	spr.material = _face_mats[v]   # shader unshaded: luz por píxel + relieve
	# Cara 16×24 (1.5 ladrillos, escala nativa) anclada en la base: los 8px de arriba
	# invaden el tile superior → altura real sin deformar. La física sigue en el footprint.
	spr.position = map_to_local(Vector2i(x, y)) - Vector2(0, 4)
	spr.z_as_relative = false
	spr.z_index = -9   # sobre el piso/tope del tilemap (z=-10), debajo de las entidades (z=0)
	add_child(spr)
	_face_sprites.append(spr)

func _clear_faces() -> void:
	for s in _face_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_face_sprites.clear()
	for s in _ao_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_ao_sprites.clear()

## Pasa las luces (empaquetadas por LightField) al shader de las caras cada frame.
func _process(_delta: float) -> void:
	if ISO and _iso_wall_mat_solid != null:
		_update_iso_wall_mat()
	_tune_torches_live()
	if _face_mats.is_empty():
		return
	var p := LightField.current_packed()
	var relief: float = LightCfg.get_v("wall_relief")   # 1 = la cara recibe luz como el piso
	var boost: float = LightCfg.get_v("wall_light")     # sube intensidad Y techo (cap) juntos
	for mat in _face_mats:
		LightField.apply_lights(mat, p)
		mat.set_shader_parameter("relief_floor", relief)
		mat.set_shader_parameter("light_boost", boost)
		mat.set_shader_parameter("cap", 1.4 * boost)

## Alimenta luz (foot-lit) al material de las caras de muro iso cada frame.
func _update_iso_wall_mat() -> void:
	var packed := LightField.current_packed()
	var boost: float = LightCfg.get_v("wall_light")
	# Las caras iso usan normal direccional → relief_floor pasa a ser la "luz mínima de
	# cara trasera" (wall_face_floor), no el wall_relief del camino 2.5D.
	var face_floor: float = LightCfg.get_v("wall_face_floor")
	var face_n := Vector3(0.0, 1.0, LightCfg.get_v("wall_face_z"))
	if _iso_wall_mat_solid != null:
		LightField.apply_lights(_iso_wall_mat_solid, packed)
		_iso_wall_mat_solid.set_shader_parameter("relief_floor", face_floor)
		_iso_wall_mat_solid.set_shader_parameter("face_normal", face_n)
		_iso_wall_mat_solid.set_shader_parameter("light_boost", boost)
		_iso_wall_mat_solid.set_shader_parameter("cap", 1.4 * boost)

	var pl = GameState.player
	if pl == null or not is_instance_valid(pl):
		return
	_update_room_reveal(pl)

## Reveal por habitación: al entrar a una sala (con histéresis), su fachada trasera baja a
## semitransparente como CONJUNTO; al salir, vuelve a sólida. Sin dither, sin per-tile flicker.
func _update_room_reveal(pl: Node2D) -> void:
	if _iso_walls == null:
		return
	var pc := local_to_map(to_local(pl.global_position))
	var rid: int = _room_of.get(pc, -1)
	if rid != _pending_room:
		_pending_room = rid
		_room_hold = 0
		return
	_room_hold += 1
	if _room_hold < ROOM_HYST or rid == _active_room:
		return
	_set_room_faded(_active_room, false)   # restaurar la sala que dejás
	_active_room = rid
	_set_room_faded(rid, true)             # revelar la sala en la que entrás

## Aplica/quita el fade a la fachada DELANTERA (S/E) de una sala, como CONJUNTO, con tween.
## Un tile NO se transparenta individual → al revelar, cada tile-fachada se SWAPEA a un Sprite2D
## (mismo y-sort/pixel) y se le baja el alpha; al salir, vuelve el alpha a 1 y se restaura el tile.
## Las fachadas que ya eran overlay (celdas de 3 bordes) solo tweenan su alpha.
func _set_room_faded(rid: int, faded: bool) -> void:
	if rid < 0:
		return
	var target: float = REVEAL_ALPHA if faded else 1.0
	var touched := false
	for e in _room_front.get(rid, []):
		if int(e.kind) == 1:                       # overlay ya-sprite: solo tween
			if is_instance_valid(e.holder):
				_tween_alpha(e.holder, target)
			continue
		var cell: Vector2i = e.cell                # tile-fachada: swap tile↔sprite
		if faded:
			if not _reveal_sprites.has(cell):
				_iso_walls.erase_cell(cell)
				_reveal_sprites[cell] = _spawn_wall_sprite(cell, _front_src[cell], false)
				touched = true
			_reveal_fade(cell, REVEAL_ALPHA, false)
		elif _reveal_sprites.has(cell):
			_reveal_fade(cell, 1.0, true)          # tween a opaco y, al terminar, restaurar tile
	if touched:
		_iso_walls.update_internals()

## Tween de alpha de un sprite de reveal. Cancela cualquier tween previo de ESA celda (swaps
## rápidos entrar/salir). restore=true: al terminar, libera el sprite y repone el tile.
func _reveal_fade(cell: Vector2i, to_a: float, restore: bool) -> void:
	if _reveal_tw.has(cell) and _reveal_tw[cell] != null and _reveal_tw[cell].is_valid():
		_reveal_tw[cell].kill()
	var h: Node2D = _reveal_sprites[cell]
	var tw := create_tween()
	tw.tween_property(h, "modulate:a", to_a, 0.18).set_trans(Tween.TRANS_SINE)
	if restore:
		var src: int = _front_src[cell]
		tw.tween_callback(func() -> void:
			if is_instance_valid(h):
				h.queue_free()
			_reveal_sprites.erase(cell)
			_reveal_tw.erase(cell)
			_iso_walls.set_cell(cell, src, Vector2i(0, 0))
			_iso_walls.update_internals())
	_reveal_tw[cell] = tw

func _tween_alpha(node: Node2D, to_a: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", to_a, 0.18).set_trans(Tween.TRANS_SINE)
