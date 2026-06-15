extends TileMapLayer
class_name Dungeon
## Generador procedural de mazmorras (reimaginado de dungeon.js).
## Construye su propio TileSet con tiles placeholder y se pinta a sí mismo.
## La colisión de muros sale del propio TileSet (física nativa de Godot).

const TILE := 16
const MAP_W := 64
const MAP_H := 64
const ROOM_COUNT := 14
const ROOM_MIN := 6
const ROOM_MAX := 11

const SRC_ID := 0
const FLOOR_ATLAS := Vector2i(0, 0)
const WALL_ATLAS := Vector2i(1, 0)

var grid: Array = []            # grid[y][x] -> 0 muro, 1 piso
var rooms: Array[Rect2i] = []   # salas generadas (orden de creación)

func generate() -> void:
	_ensure_tileset()
	_gen_grid()
	_paint()

## Centro de la primera sala, en coordenadas globales (punto de aparición).
func get_spawn_point() -> Vector2:
	if rooms.is_empty():
		return Vector2.ZERO
	return to_global(map_to_local(rooms[0].get_center()))

# ---------------------------------------------------------------------------
# TileSet placeholder construido en código (2 tiles: piso y muro)
# ---------------------------------------------------------------------------
func _ensure_tileset() -> void:
	if tile_set != null:
		return
	# Tiles reales (32px → bajados a 16, como el original que dibujaba a 0.5).
	var floor_img := _load_tile("res://assets/tiles/floor_torre.png")
	var wall_img := _load_tile("res://assets/tiles/wall_torre.png")
	var img := Image.create_empty(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	img.blit_rect(floor_img, Rect2i(0, 0, TILE, TILE), Vector2i(0, 0))
	img.blit_rect(wall_img, Rect2i(0, 0, TILE, TILE), Vector2i(TILE, 0))
	var tex := ImageTexture.create_from_image(img)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.add_navigation_layer()
	ts.add_occlusion_layer()

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	src.create_tile(FLOOR_ATLAS)
	src.create_tile(WALL_ATLAS)
	ts.add_source(src, SRC_ID)

	# Colisión sólo en el tile de muro (cuadrado completo).
	var td := src.get_tile_data(WALL_ATLAS, 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	]))
	# Oclusión del muro: proyecta sombras 2D desde las luces (Light2D).
	var occ := OccluderPolygon2D.new()
	occ.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	])
	td.set_occluder(0, occ)

	# Navegación en el tile de piso (para el NavigationAgent2D de los enemigos).
	var fd := src.get_tile_data(FLOOR_ATLAS, 0)
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	fd.set_navigation_polygon(0, nav)

	tile_set = ts

func _load_tile(path: String) -> Image:
	var im := Image.new()
	im.load(ProjectSettings.globalize_path(path))
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != TILE:
		im.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return im

# ---------------------------------------------------------------------------
# Generación de la grilla: salas rectangulares + pasillos en L de 2 de ancho
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
		for attempt in 20:
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
# Pintar la grilla en el TileMapLayer
# ---------------------------------------------------------------------------
func _paint() -> void:
	clear()
	for y in MAP_H:
		for x in MAP_W:
			var atlas := FLOOR_ATLAS if grid[y][x] == 1 else WALL_ATLAS
			set_cell(Vector2i(x, y), SRC_ID, atlas)
