extends Node
## Generador procedural iso (v1).
## Genera salas rectangulares y pinta:
##   - PISO en la capa Floor (source 0)
##   - MUROS TRASEROS en la capa Walls — frente abierto: solo las dos aristas de
##     atrás (borde top = SE source 1, borde left = SW source 2).
## Reusa el TileSet iso_pixel.tres (256x128, 2:1). Ambas capas deben compartir
## la misma transform global (ya alineadas en (-118,54), scale 0.5).
##
## Al final centra una cámara overview y guarda un screenshot en
## user://procgen_shot.png para revisión.

@export var floor_path: NodePath = ^"../Floor"
@export var walls_path: NodePath = ^"../World/Walls"
@export var player_path: NodePath = ^"../World/Player"

@export var room_count := 5
@export var room_min := Vector2i(4, 4)
@export var room_max := Vector2i(8, 7)
@export var area := Vector2i(30, 30)
@export var seed_value := 0            # 0 = aleatorio
@export var auto_screenshot := false   # solo para sacar la foto overview; en juego normal va OFF
@export var paint_walls := true        # false = solo piso (mientras se resuelve import de muros)

const FLOOR_SRC := 0
const WALL_SE_SRC := 1     # borde superior (top)
const WALL_SW_SRC := 2     # borde izquierdo (left)
const TILE0 := Vector2i(0, 0)

var _floor: TileMapLayer
var _walls: TileMapLayer
var _rooms: Array[Rect2i] = []

func _ready() -> void:
	_floor = get_node_or_null(floor_path) as TileMapLayer
	_walls = get_node_or_null(walls_path) as TileMapLayer
	if _floor == null or _walls == null:
		push_error("[procgen] no encontré Floor/Walls (%s / %s)" % [floor_path, walls_path])
		return
	if seed_value != 0:
		seed(seed_value)
	generate()
	_place_player()
	if auto_screenshot:
		_shoot()

func generate() -> void:
	_floor.clear()
	_walls.clear()
	_rooms.clear()
	var tries := 0
	while _rooms.size() < room_count and tries < 300:
		tries += 1
		var w := randi_range(room_min.x, room_max.x)
		var h := randi_range(room_min.y, room_max.y)
		var px := randi_range(1, max(1, area.x - w - 1))
		var py := randi_range(1, max(1, area.y - h - 1))
		var r := Rect2i(px, py, w, h)
		var ok := true
		for o in _rooms:
			if r.grow(1).intersects(o):
				ok = false
				break
		if not ok:
			continue
		_rooms.append(r)
		_carve_room(r)
	# corredores conectando salas consecutivas (solo piso)
	for i in range(1, _rooms.size()):
		_corridor(_rooms[i - 1].get_center(), _rooms[i].get_center())
	_floor.update_internals()
	_walls.update_internals()
	print("[procgen] %d salas, %d celdas de piso" % [_rooms.size(), _floor.get_used_cells().size()])

func _carve_room(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_floor.set_cell(Vector2i(x, y), FLOOR_SRC, TILE0)
	# Muros traseros (frente abierto): borde top y borde left.
	if not paint_walls or _walls.tile_set == null or _walls.tile_set.get_source_count() < 3:
		return
	var top := r.position.y
	var left := r.position.x
	for x in range(r.position.x, r.end.x):
		_walls.set_cell(Vector2i(x, top), WALL_SE_SRC, TILE0)
	for y in range(r.position.y, r.end.y):
		_walls.set_cell(Vector2i(left, y), WALL_SW_SRC, TILE0)

func _corridor(a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var y := a.y
	while x != b.x:
		_floor.set_cell(Vector2i(x, y), FLOOR_SRC, TILE0)
		x += signi(b.x - x)
	while y != b.y:
		_floor.set_cell(Vector2i(x, y), FLOOR_SRC, TILE0)
		y += signi(b.y - y)

func _place_player() -> void:
	if _rooms.is_empty():
		return
	var p := get_node_or_null(player_path) as Node2D
	if p == null:
		return
	var c := _rooms[0].get_center()
	p.global_position = _floor.to_global(_floor.map_to_local(c))

var _brighten := false

func _process(_d: float) -> void:
	# Forzar ambient claro cada frame (el LightField lo pisa); mi nodo corre último.
	if _brighten:
		var amb := get_node_or_null(^"../Ambient") as CanvasModulate
		if amb:
			amb.color = Color(1, 1, 1)
		# El muro usa wall_face.gdshader (unshaded, foot-lit) → para la foto le subo
		# el ambient del shader así se ve el arte (en gameplay lo ilumina la antorcha).
		if _walls and _walls.material is ShaderMaterial:
			_walls.material.set_shader_parameter("ambient", Vector3(0.95, 0.95, 0.95))

func _shoot() -> void:
	_brighten = true
	# Forzar resolución alta para la foto (la ventana puede abrir chica).
	var win := get_window()
	if win:
		win.size = Vector2i(1920, 1080)
	# Cámara overview que encuadra todo el nivel.
	var used := _floor.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var corners := [
		used.position,
		used.position + Vector2i(used.size.x, 0),
		used.position + Vector2i(0, used.size.y),
		used.position + used.size,
	]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for cc in corners:
		var wpt := _floor.to_global(_floor.map_to_local(cc))
		mn = mn.min(wpt)
		mx = mx.max(wpt)
	var lvl_size := (mx - mn).max(Vector2(1, 1))
	var center := (mn + mx) * 0.5
	var vp := get_viewport().get_visible_rect().size
	var z: float = min(vp.x / lvl_size.x, vp.y / lvl_size.y) * 0.8
	var cam := Camera2D.new()
	add_child(cam)
	cam.zoom = Vector2(z, z)
	cam.global_position = center
	cam.make_current()
	await get_tree().create_timer(0.7).timeout
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://procgen_shot.png")
	print("[procgen] screenshot -> user://procgen_shot.png (err=%d, zoom=%.3f)" % [err, z])
	# Restaurar el juego normal: devolver la cámara al player y apagar el brillo.
	_brighten = false
	var pcam := get_node_or_null(^"../World/Player/Camera2D") as Camera2D
	if pcam:
		pcam.make_current()
	cam.queue_free()
