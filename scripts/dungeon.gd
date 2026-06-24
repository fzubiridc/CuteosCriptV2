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

## ISO: renderiza el mismo grid como mundo isométrico (piso + muros traseros en
## capa hija) con el tileset iso_pixel, en vez del 2.5D top-down. La generación
## (_gen_grid) y la interfaz (rooms, map_to_local, *_cells) no cambian.
const ISO := true
const ISO_TILESET := preload("res://assets/iso/iso_pixel.tres")
const ISO_FLOOR_SRC := 0
const ISO_WALL_SE_SRC := 1
const ISO_WALL_SW_SRC := 2
var _iso_walls: TileMapLayer
var _iso_astar := AStarGrid2D.new()

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
		_gen_grid()
		_paint_iso()
		_build_iso_nav()
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
	grid = []
	for y in MAP_H:
		var row: Array = []
		row.resize(MAP_W)
		row.fill(0)
		grid.append(row)

	var prev_center := Vector2i.ZERO
	for i in ROOM_COUNT:
		for attempt in 30:
			var w := Rng.range_i(ROOM_MIN, ROOM_MAX)
			var h := Rng.range_i(ROOM_MIN, ROOM_MAX - 1)
			var x := Rng.range_i(1, MAP_W - w - 1)
			var y := Rng.range_i(1, MAP_H - h - 1)
			var rect := Rect2i(x, y, w, h)
			var ok := true
			for r in rooms:
				if rect.grow(1).intersects(r):
					ok = false
					break
			if ok:
				_carve_room(rect)
				var center := rect.get_center()
				if not rooms.is_empty():
					_connect(prev_center, center)
				rooms.append(rect)
				prev_center = center
				break
	_remove_thin_walls()

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
			# La LUZ va un poco DENTRO de la sala (fuera del occluder del muro) para
			# que ilumine el piso; si la dejábamos en la cara, el muro bloqueaba su
			# propia luz. El SPRITE de la antorcha se sube en torch.gd para quedar
			# sobre la cara del muro.
			t.position = to_global(map_to_local(Vector2i(x, wall_row))) + Vector2(0, 11)
			holder.add_child(t)
			idx += 1

		# Una antorcha lateral en habitaciones alternas. El lado cambia por sala
		# para que ambas variantes aparezcan sin saturar el mapa de luces. Si el
		# lado elegido coincide con un pasillo abierto, prueba el muro opuesto.
		if room_i % 2 == 0 and idx < MAX_TORCHES:
			var preferred: StringName = &"left" if int(room_i / 2) % 2 == 0 else &"right"
			var alternate: StringName = &"right" if preferred == &"left" else &"left"
			var side_choices: Array[StringName] = [preferred, alternate]
			for side in side_choices:
				var wall_x: int = r.position.x - 1 if side == &"left" else r.position.x + r.size.x
				var inner_x: int = wall_x + 1 if side == &"left" else wall_x - 1
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
				side_torch.position = to_global(map_to_local(Vector2i(wall_x, wall_y))) + inward
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
		for x in range(w / 2 - 1, w / 2 + 1):
			img.set_pixel(x, y, frame)
	for x in w:                                   # montante horizontal
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
	_iso_walls.tile_set = ISO_TILESET
	_iso_walls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_iso_walls.y_sort_enabled = true
	_iso_walls.z_index = 1   # relativo a la capa (-10) → -9: sobre piso, bajo entidades

func _paint_iso() -> void:
	clear()
	if _iso_walls:
		_iso_walls.clear()
	var gh := grid.size()
	var gw: int = grid[0].size() if gh > 0 else 0
	for y in gh:
		for x in gw:
			if grid[y][x] != 1:
				continue
			set_cell(Vector2i(x, y), ISO_FLOOR_SRC, Vector2i(0, 0))
			# Muros traseros (frente abierto): vecino "de atrás" no-piso.
			if y - 1 < 0 or grid[y - 1][x] != 1:
				_iso_walls.set_cell(Vector2i(x, y), ISO_WALL_SE_SRC, Vector2i(0, 0))
			elif x - 1 < 0 or grid[y][x - 1] != 1:
				_iso_walls.set_cell(Vector2i(x, y), ISO_WALL_SW_SRC, Vector2i(0, 0))
	update_internals()
	if _iso_walls:
		_iso_walls.update_internals()

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
