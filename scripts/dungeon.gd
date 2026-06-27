extends TileMapLayer
class_name Dungeon
## Generador procedural de mazmorras ISOMÉTRICAS (path VIVO: ISO=true).
## Arma: grid + grafo de salas (MST+loops) + roles → pinta como mundo iso (piso + muros
## delanteros/traseros en capas hijas, con WallSegment como fuente lógica) → nav (AStarGrid) →
## antorchas → reveal de fachada por sala → niebla de guerra (cell_seen/_visible_now).
## El path 2.5D/Tiled LEGACY (_paint, generate_from_tiled y cía.) fue removido (2026-06-27):
## ISO=true era la única ruta viva. `use_test_map` debe quedar en false en producción.

const TILE := 16
const MAP_W := 64
const MAP_H := 64
const ROOM_COUNT := 20
## Modo PUERTAS (banco de pruebas de la oscuridad): salas CERRADAS (sin corredores) conectadas por
## puertas que TELETRANSPORTAN al tocarlas → cada sala queda aislada. true = puertas; false = corredores
## zigzag clásicos. Las puertas siguen el grafo de salas (MST + loops) que arma _connect_rooms.
const USE_DOORS := true
const DEBUG_LOG := false   # logs de debug del procgen (ej. cantidad de segmentos de muro). Off en producción.

const FACE_SHADER := preload("res://shaders/wall_face.gdshader")

var grid: Array = []
var rooms: Array[Rect2i] = []
## Niebla de guerra — FUENTE DE VERDAD (el minimapa y el gating de entidades leen de acá).
## cell_seen[y][x]=true: la celda fue vista alguna vez (persistente). _visible_now: set de
## celdas en el radio del player AHORA (se limpia cada update). Estilo Diablo 2: "explorado" se
## recuerda (minimapa), pero la info viva solo se ve en el radio actual.
## La niebla/reveal en sí vive en DungeonFog (scripts/dungeon_fog.gd); cell_seen queda acá porque
## es la fuente de verdad que leen otros sistemas (minimapa, visibility_manager).
var cell_seen: Array = []
## Lista de adyacencia del grafo de salas (índices de `rooms`). La llena
## `_connect_rooms()` (MST + loops). Disponible para roles por BFS.
var _room_graph: Array = []
## Fase 2: room_id → rol ("entry"/"combat"/"treasure"/"boss"/"merchant"). Vacío en
## mapas fijos/test → main.gd cae al comportamiento por índice.
var room_roles: Dictionary = {}

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
# Variaciones de muro recto (random por celda). Arte tipo A = highwall (bordes NW/SE), B = wall_ne (NE/SW).
# Son drop-in 144×200 → reusan el texture_origin del borde base (Reinforced 146×200 ~ igual). Se registran
# como sources del TileSet EN RUNTIME (sin tocar el .tres ni el tool de origin para las 144×200).
const WALL_VAR_DIR := "res://assets/iso/walls/variations/"
const WALL_VAR_ARTS := {
	"A": ["NormalWallVariation1NW", "NormalWallVariation2NW", "NormalWallVariation3NW", "BrokenWallNW", "BigBrokenWallNW", "ReinforcedWallNW"],
	"B": ["NormalWallVariation1NE", "NormalWallVariation2NE", "NormalWallVariation3NE", "BrokenWallNE", "BigBrokenWallNE", "ReinforcedWallNE"],
}
# Borde recto → tipo de arte. Array (no dict con claves-const) por seguridad de parseo.
const WALL_VAR_BORDERS := [[SRC_WALL_NW, "A"], [SRC_WALL_SE, "A"], [SRC_WALL_NE, "B"], [SRC_WALL_SW, "B"]]
const WALL_VAR_FIRST_ID := 100
# Puerta (USE_DOORS): tile de puerta en la cara del muro que mira a la sala vecina. Mismo arte
# 144×200 que los muros (A=DoorNW→bordes NW/SE, B=DoorNE→NE/SW) → reusa origin+occluder del borde
# base, igual que las variaciones. Se estampa SOLO en la cara-puerta (get_door_specs); el resto, muro.
const DOOR_ARTS := {"A": "DoorNW", "B": "DoorNE"}
const DOOR_FIRST_ID := 200
var _door_src: Dictionary = {}     # borde base (SRC_WALL_*) → source id del tile de puerta
var _door_faces: Dictionary = {}   # celda de puerta → Side donde estampar la puerta
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
var _wall_variants: Dictionary = {} # base_src → Array[int] (pool de variantes, incluye el base)
var _variant_base: Dictionary = {}  # variant_src → base_src (para layer front/back y reveal)
var _wall_segments: Array = []   # Fase 1: lista de WallSegment (muro = lado de celda)
var _corner_sprites: Array = []  # Fase 2: piezas extra de celdas con 3 bordes (Sprite2D permanente)
# Fase 3: reveal por habitación (reemplaza el viejo cutout). Cada celda de piso pertenece
# a una sala (rect de procgen); al entrar, la fachada trasera de esa sala baja a semitransparente
# como CONJUNTO (sin dither, sin per-tile flicker). Estilo Baldur's Gate 3 / Divinity OS2.
# El estado del reveal (sprites/tweens/sala activa) y los consts (REVEAL_ALPHA/ROOM_HYST) viven en
# DungeonFog; _room_of/_room_front/_front_src quedan acá porque los producen/consumen otros sistemas.
var _room_of: Dictionary = {}        # cell → room_id (rect de sala; corredores = -1)
var _room_front: Dictionary = {}     # room_id → Array de entradas de fachada delantera (ver _paint_walls):
									 #   {kind=0, cell} = tile-muro (se swapea a sprite al revelar)
									 #   {kind=1, holder} = sprite overlay ya existente (solo tween de alpha)
var _front_src: Dictionary = {}      # cell → source de la pared delantera (para restaurar el tile)

# Celdas de marcadores (spawn/salida + listas de entidades). spawn_cell/exit_cell las exponen
# get_spawn_point()/get_exit_cell() (las leen main.gd y minimap.gd); window_cells se resetea por piso.
var spawn_cell: Vector2i = Vector2i(-1, -1)
var exit_cell: Vector2i = Vector2i(-1, -1)
var enemy_cells: Array[Vector2i] = []
var chest_cells: Array[Vector2i] = []
var torch_cells: Array[Vector2i] = []
var window_cells: Array[Vector2i] = []

## Emitida al terminar de generar un piso (la usa el minimapa para resetear niebla).
signal regenerated

func generate() -> void:
	spawn_cell = Vector2i(-1, -1)
	exit_cell = Vector2i(-1, -1)
	window_cells.clear()
	if ISO:
		_ensure_iso()
		_ensure_gen()                             # procgen vive en DungeonGen (incluye los carve_* del test grid)
		if use_test_map:
			_gen_test_grid()
		else:
			_gen.gen_grid()
		_room_of = _assign_rooms()                # cada celda de piso → su sala (rect)
		_gen.assign_roles()                       # Fase 2: roles por BFS + spawn/exit por rol
		_wall_segments = _build_wall_segments()   # Fase 2: segmentos = fuente de verdad del pintado
		_paint_iso()
		_build_iso_nav()
		_build_iso_boundaries()   # colisión en el perímetro → no caminar al vacío
		_ensure_decor()
		_decor.place_torches()     # antorchas de sala → luz + sombras proyectadas
		_decor.place_campfires()   # fogatas cada tanto en el centro de algunas salas (no en la de spawn)
		_ensure_fog()
		_fog.init_visibility()   # niebla (cell_seen) lista para este piso
		regenerated.emit()
		return

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
# Generación de la grilla
# ---------------------------------------------------------------------------
## Procgen extraído a scripts/dungeon_gen.gd (DungeonGen). Se crea lazy (_ensure_gen) porque
## hay entradas que NO pasan por generate() (closed_room_test llama carve_iso_room directo).
var _gen: DungeonGen

func _ensure_gen() -> void:
	if _gen == null:
		_gen = DungeonGen.new(self)

## API pública preservada: closed_room_test.gd talla una sala sin pasar por generate() → _ensure_gen acá.
func carve_iso_room(origin: Vector2i, width: int, depth: int) -> Array:
	_ensure_gen()
	return _gen.carve_iso_room(origin, width, depth)

## API pública preservada: main.gd lee las puertas (get_door_specs) para teletransportar al tocarlas.
func get_door_specs() -> Array:
	_ensure_gen()
	return _gen.get_door_specs()

# ---------------------------------------------------------------------------
# Antorchas + fogatas → DungeonDecor (scripts/dungeon_decor.gd). Lazy, igual que _gen.
# ---------------------------------------------------------------------------
var _decor: DungeonDecor

func _ensure_decor() -> void:
	if _decor == null:
		_decor = DungeonDecor.new(self)

## API pública preservada: closed_room_test.gd crea una antorcha de pared sin pasar por generate().
func spawn_wall_torch(interior_cell: Vector2i, side: int) -> Node:
	_ensure_decor()
	return _decor.spawn_wall_torch(interior_cell, side)

# ---------------------------------------------------------------------------
# Niebla de guerra + reveal por habitación → DungeonFog (scripts/dungeon_fog.gd). Lazy, igual que _gen.
# cell_seen (fuente de verdad) y _room_of/_room_front/_front_src siguen viviendo en este nodo: la niebla
# las USA como d.*, pero las producen/leen otros sistemas (procgen, minimapa, visibility_manager).
# ---------------------------------------------------------------------------
var _fog: DungeonFog

func _ensure_fog() -> void:
	if _fog == null:
		_fog = DungeonFog.new(self)

## API pública preservada (la usan enemy.gd, minimap.gd, visibility_manager.gd): wrappers a DungeonFog.
func is_cell_visible(world_pos: Vector2) -> bool:
	_ensure_fog()
	return _fog.is_cell_visible(world_pos)

func is_cell_seen(world_pos: Vector2) -> bool:
	_ensure_fog()
	return _fog.is_cell_seen(world_pos)

func is_seen_cell(c: Vector2i) -> bool:
	_ensure_fog()
	return _fog.is_seen_cell(c)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	_ensure_fog()
	return _fog.world_to_cell(world_pos)

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
	_ensure_wall_variants()   # variantes de muro recto como sources en runtime (reusan origins base)
	_ensure_door_sources()    # tiles de puerta (1 por cara) como sources, mismo patrón que las variantes
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

## Registra (una vez por sesión) las VARIACIONES de muro recto como sources del TileSet,
## reusando el texture_origin + occluder del borde base. Idempotente: si los sources ya
## existen (otra corrida en la misma sesión), sólo reconstruye los mapeos (que _cache_wall_tile_data
## borra). Llena _wall_variants (pool por borde) y _variant_base (variante → base).
func _ensure_wall_variants() -> void:
	_wall_variants = {}
	_variant_base = {}
	var next_id := WALL_VAR_FIRST_ID
	var tex_cache := {}
	for pair in WALL_VAR_BORDERS:
		var base_src: int = pair[0]
		var pool: Array = [base_src]                      # el muro base es una "variante" más
		var origin: Vector2 = _wall_origin.get(base_src, Vector2.ZERO)
		var edge := _wall_edge_for(base_src)
		for art in WALL_VAR_ARTS[pair[1]]:
			var vid := next_id
			next_id += 1
			if not ISO_TILESET.has_source(vid):
				var path: String = WALL_VAR_DIR + art + ".png"
				var tex = tex_cache.get(path)
				if tex == null:
					tex = _load_wall_tex(path)
					tex_cache[path] = tex
				if tex == null:
					continue                              # falta el PNG → salta este vid (consistente)
				var src := TileSetAtlasSource.new()
				src.texture = tex
				src.texture_region_size = Vector2i(tex.get_size())
				src.create_tile(Vector2i(0, 0))
				ISO_TILESET.add_source(src, vid)   # add_source ANTES: el tile hereda la occlusion layer del TileSet
				var td := src.get_tile_data(Vector2i(0, 0), 0)
				td.texture_origin = Vector2i(origin)
				if edge.size() > 0 and ISO_TILESET.get_occlusion_layers_count() > 0:
					var occ := OccluderPolygon2D.new()
					occ.closed = false
					occ.cull_mode = OccluderPolygon2D.CULL_DISABLED
					occ.polygon = edge
					td.set_occluder_polygons_count(0, 1)
					td.set_occluder_polygon(0, 0, occ)
			var s2 := ISO_TILESET.get_source(vid) as TileSetAtlasSource
			if s2 == null:
				continue
			_wall_tex[vid] = s2.texture
			var td2 := s2.get_tile_data(Vector2i(0, 0), 0)
			if td2 != null:
				_wall_origin[vid] = Vector2(td2.texture_origin)
			_variant_base[vid] = base_src
			pool.append(vid)
		_wall_variants[base_src] = pool

## Registra los sources de PUERTA (uno por cara recta), con textura DoorNW/DoorNE según el tipo
## (A=NW/SE, B=NE/SW), reusando texture_origin + occluder del borde base — mismo patrón que las
## variaciones. _door_src mapea borde base → source de puerta; hereda front/back vía _variant_base.
func _ensure_door_sources() -> void:
	_door_src = {}
	var next_id := DOOR_FIRST_ID
	var tex_cache := {}
	for pair in WALL_VAR_BORDERS:
		var base_src: int = pair[0]
		var art: String = DOOR_ARTS[pair[1]]
		var vid := next_id
		next_id += 1
		var origin: Vector2 = _wall_origin.get(base_src, Vector2.ZERO)
		var edge := _wall_edge_for(base_src)
		if not ISO_TILESET.has_source(vid):
			var path: String = WALL_VAR_DIR + art + ".png"
			var tex = tex_cache.get(path)
			if tex == null:
				tex = _load_wall_tex(path)
				tex_cache[path] = tex
			if tex == null:
				continue
			var src := TileSetAtlasSource.new()
			src.texture = tex
			src.texture_region_size = Vector2i(tex.get_size())
			src.create_tile(Vector2i(0, 0))
			ISO_TILESET.add_source(src, vid)
			var td := src.get_tile_data(Vector2i(0, 0), 0)
			td.texture_origin = Vector2i(origin)
			if edge.size() > 0 and ISO_TILESET.get_occlusion_layers_count() > 0:
				var occ := OccluderPolygon2D.new()
				occ.closed = false
				occ.cull_mode = OccluderPolygon2D.CULL_DISABLED
				occ.polygon = edge
				td.set_occluder_polygons_count(0, 1)
				td.set_occluder_polygon(0, 0, occ)
		var s2 := ISO_TILESET.get_source(vid) as TileSetAtlasSource
		if s2 == null:
			continue
		_wall_tex[vid] = s2.texture
		var td2 := s2.get_tile_data(Vector2i(0, 0), 0)
		if td2 != null:
			_wall_origin[vid] = Vector2(td2.texture_origin)
		_variant_base[vid] = base_src
		_door_src[base_src] = vid

## SRC_WALL_* del borde recto correspondiente a un Side.
func _base_for_side(side: int) -> int:
	match side:
		WallSegment.Side.NE: return SRC_WALL_NE
		WallSegment.Side.SE: return SRC_WALL_SE
		WallSegment.Side.SW: return SRC_WALL_SW
	return SRC_WALL_NW

## Precomputa, por cada puerta (get_door_specs), la CELDA y CARA donde estampar el tile de puerta:
## la cara con muro de `from` cuyo vecino apunta a la sala destino (`to`). _door_faces[celda]=Side.
func _compute_door_faces() -> void:
	_door_faces = {}
	if not USE_DOORS:
		return
	var sides_by_cell := {}
	for seg in _wall_segments:
		if not sides_by_cell.has(seg.interior_cell):
			sides_by_cell[seg.interior_cell] = []
		(sides_by_cell[seg.interior_cell] as Array).append(seg.side)
	for spec in get_door_specs():
		var from_cell: Vector2i = spec.from
		var to_cell: Vector2i = spec.to
		var best_side := -1
		var best_d := INF
		for side in sides_by_cell.get(from_cell, []):
			var nb := WallSegment.neighbor(from_cell, side)
			var d: float = (Vector2(nb) - Vector2(to_cell)).length_squared()
			if d < best_d:
				best_d = d
				best_side = side
		if best_side >= 0:
			_door_faces[from_cell] = best_side

## Polilínea base del rombo (occluder) del borde recto: misma que _install_iso_occluders.
func _wall_edge_for(src: int) -> PackedVector2Array:
	var t := Vector2(0, -64)
	var r := Vector2(128, 0)
	var b := Vector2(0, 64)
	var l := Vector2(-128, 0)
	match src:
		SRC_WALL_NW: return PackedVector2Array([l, t])
		SRC_WALL_NE: return PackedVector2Array([t, r])
		SRC_WALL_SE: return PackedVector2Array([r, b])
		SRC_WALL_SW: return PackedVector2Array([b, l])
	return PackedVector2Array()

## Carga una textura de muro (load normal; fallback a PNG crudo si Godot no la importó aún).
func _load_wall_tex(path: String) -> Texture2D:
	var t := load(path) as Texture2D
	if t != null:
		return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null else null

## Elige al azar (RNG seedeado → reproducible por piso) un source del pool de variantes del borde.
func _pick_wall_variant(base_src: int) -> int:
	var pool: Array = _wall_variants.get(base_src, [base_src])
	return int(pool[Rng.range_i(0, pool.size() - 1)])

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
	# Matar primero los tweens de reveal activos: si no, su callback (restore) corre sobre
	# sprites ya liberados acá abajo / sobre _iso_walls en pleno regen → crash en regen rápida.
	_ensure_fog()
	for tw in _fog._reveal_tw.values():
		if tw != null and tw.is_valid():
			tw.kill()
	for h in _fog._reveal_sprites.values():
		if is_instance_valid(h):
			h.queue_free()
	_corner_sprites = []
	_room_front = {}
	_front_src = {}
	_fog._reveal_sprites = {}
	_fog._reveal_tw = {}
	_fog._active_room = -1
	_fog._pending_room = -99
	_fog._room_hold = 0
	_wall_cells = {}
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	# Piso.
	for y in gh:
		for x in gw:
			if grid[y][x] == 1:
				set_cell(Vector2i(x, y), ISO_FLOOR_SRC, Vector2i(0, 0))
	_compute_door_faces()   # qué celda/cara lleva tile de puerta (usa _wall_segments + get_door_specs)
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
		# La cara-puerta se estampa como tile de puerta (abajo) y se EXCLUYE de esquinas/bordes normales.
		var door_side: int = _door_faces.get(c, -1)
		var nw: bool = s.has(WallSegment.Side.NW) and door_side != WallSegment.Side.NW
		var ne: bool = s.has(WallSegment.Side.NE) and door_side != WallSegment.Side.NE
		var se: bool = s.has(WallSegment.Side.SE) and door_side != WallSegment.Side.SE
		var sw: bool = s.has(WallSegment.Side.SW) and door_side != WallSegment.Side.SW
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
		# Bordes sueltos restantes, con VARIACIÓN random por celda. SE/SW = fachada delantera (revelable).
		if nw: pieces.append({"src": _pick_wall_variant(SRC_WALL_NW), "front": false})
		if ne: pieces.append({"src": _pick_wall_variant(SRC_WALL_NE), "front": false})
		if se: pieces.append({"src": _pick_wall_variant(SRC_WALL_SE), "front": true})
		if sw: pieces.append({"src": _pick_wall_variant(SRC_WALL_SW), "front": true})
		# Tile de puerta en su cara (si ese borde existe y hay source). front si es fachada S/E.
		if door_side >= 0 and s.has(door_side):
			var dbase := _base_for_side(door_side)
			if _door_src.has(dbase):
				pieces.append({"src": _door_src[dbase], "front": dbase in FRONT_SOURCES})
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
	var base: int = _variant_base.get(src, src)   # las variantes heredan front/back de su borde base
	return _iso_walls if base in FRONT_SOURCES else _iso_walls_back

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
	# Fix nav (2026-06-26): NO re-marcar sólidas las celdas de _iso_walls/_iso_walls_back. Los muros
	# se pintan en la celda de PISO (interior_cell) → marcarlas sólidas bloqueaba el perímetro
	# CAMINABLE de cada sala (los mobs evitaban bordes/esquinas). Las celdas no-piso ya quedan sólidas
	# del barrido inicial; el borde real lo bloquea _build_iso_boundaries (colisión), no el nav.
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
	if DEBUG_LOG: print("[walls] segmentos=%d" % segs.size())
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
		_gen.carve_room(r)
		rooms.append(r)
	# Corredores deterministas (L) — dejan vanos/puertas en las fachadas.
	var ca := ra.get_center()
	var cb := rb.get_center()
	var cc := rc.get_center()
	_gen.carve_h(ca.x, cb.x, ca.y)
	_gen.carve_v(ca.y, cc.y, ca.x)
	_gen.carve_h(ca.x, cc.x, cc.y)
	spawn_cell = ca
	exit_cell = Vector2i(-1, -1)


## Pasa las luces (empaquetadas por LightField) al shader de las caras cada frame.
func _process(_delta: float) -> void:
	# FIX: una sola llamada a current_packed() por frame (antes había 2: acá y dentro de
	# _update_iso_wall_mat). Tipo explícito (no := sobre retorno de autoload) para no romper inferencia.
	var packed: Dictionary = LightField.current_packed()
	if ISO and _iso_wall_mat_solid != null:
		_update_iso_wall_mat(packed)
	# FIX: niebla/reveal DESACOPLADOS del material de muro. Antes colgaban dentro de
	# _update_iso_wall_mat → si el material fuera null, se congelaban sin error. Ahora corren
	# directo acá con su propio guard de player, independientes de que exista el material de muro.
	if ISO and _fog:
		# pl SIN tipo explícito a propósito: GameState.player es `Node` (no Node2D); tiparlo Node2D
		# acá sería un downcast estático que no compila. update_room_reveal(pl: Node2D) lo valida en runtime.
		var pl = GameState.player
		if pl != null and is_instance_valid(pl):
			_fog.update_visibility(local_to_map(to_local(pl.global_position)))   # niebla por celda (fuente de verdad)
			_fog.update_room_reveal(pl)
	if _decor: _decor.tune_torches_live()

## Alimenta luz (foot-lit) al material de las caras de muro iso cada frame.
## FIX: recibe `packed` de _process (no llama current_packed() de nuevo) y ya NO toca niebla/reveal.
func _update_iso_wall_mat(packed: Dictionary) -> void:
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
		_iso_wall_mat_solid.set_shader_parameter("cap", LightCfg.LIGHT_CAP * boost)   # cap de luz (antes literal 1.4)
		_iso_wall_mat_solid.set_shader_parameter("light_falloff", LightCfg.get_v("light_falloff"))
