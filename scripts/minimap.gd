extends CanvasLayer
class_name Minimap
## Minimapa (esquina sup. derecha, siempre visible) + mapa completo (tecla M),
## ambos con niebla de guerra: se revela la grilla del Dungeon a medida que el
## jugador camina. Dibuja desde Dungeon.grid (1=piso/0=muro) sobre una Image que
## se actualiza solo cuando se descubren celdas nuevas. Markers: jugador y salida.

const MAP_W := Dungeon.MAP_W
const MAP_H := Dungeon.MAP_H
const REVEAL_RADIUS := 6        # tiles revelados alrededor del jugador
const MINI_SCALE := 2           # px por tile en el minimapa (64*2 = 128)
const FULL_SCALE := 8           # px por tile en el mapa grande (64*8 = 512)

const C_UNSEEN := Color(0, 0, 0, 0)
const C_FLOOR := Color(0.60, 0.56, 0.66, 1.0)
const C_WALL := Color(0.16, 0.15, 0.20, 1.0)
const C_PLAYER := Color(0.45, 0.9, 1.0, 1.0)
const C_EXIT := Color(0.75, 0.45, 1.0, 1.0)

var _dungeon: Dungeon
var _player: Node2D
var _explored: Array = []
var _img: Image
var _tex: ImageTexture
var _dirty := true
var _exit_cell := Vector2i(-1, -1)

var _mini_tex: TextureRect
var _mini_player: ColorRect
var _mini_exit: ColorRect
var _full_root: Control
var _full_tex: TextureRect
var _full_player: ColorRect
var _full_exit: ColorRect

func setup(dungeon: Dungeon, player: Node2D) -> void:
	_dungeon = dungeon
	_player = player
	if not _dungeon.regenerated.is_connected(_on_regenerated):
		_dungeon.regenerated.connect(_on_regenerated)
	_reset()   # construir desde el piso ya generado

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_img = Image.create_empty(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	_img.fill(C_UNSEEN)
	_tex = ImageTexture.create_from_image(_img)
	_build_ui()

func _build_ui() -> void:
	var mw := MAP_W * MINI_SCALE
	var mh := MAP_H * MINI_SCALE
	# --- Minimapa (esquina sup. derecha) ---
	var box := Control.new()
	box.anchor_left = 1.0; box.anchor_right = 1.0
	box.offset_left = -mw - 12; box.offset_right = -12
	box.offset_top = 12; box.offset_bottom = 12 + mh
	add_child(box)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = -3; bg.offset_top = -3; bg.offset_right = 3; bg.offset_bottom = 3
	box.add_child(bg)
	_mini_tex = _make_map_rect(box)
	_mini_exit = _make_dot(_mini_tex, C_EXIT, MINI_SCALE + 1)
	_mini_player = _make_dot(_mini_tex, C_PLAYER, MINI_SCALE + 2)

	# --- Mapa completo (tecla M) ---
	_full_root = Control.new()
	_full_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.visible = false
	add_child(_full_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.add_child(dim)
	var fw := MAP_W * FULL_SCALE
	var fh := MAP_H * FULL_SCALE
	var fbox := Control.new()
	fbox.anchor_left = 0.5; fbox.anchor_right = 0.5; fbox.anchor_top = 0.5; fbox.anchor_bottom = 0.5
	fbox.offset_left = -fw / 2.0; fbox.offset_right = fw / 2.0
	fbox.offset_top = -fh / 2.0; fbox.offset_bottom = fh / 2.0
	_full_root.add_child(fbox)
	_full_tex = _make_map_rect(fbox)
	_full_exit = _make_dot(_full_tex, C_EXIT, FULL_SCALE)
	_full_player = _make_dot(_full_tex, C_PLAYER, FULL_SCALE + 2)
	var title := Label.new()
	title.text = "MAPA  ·  [M] cerrar"
	title.add_theme_color_override("font_color", Color("ffd84f"))
	title.add_theme_font_size_override("font_size", 18)
	title.anchor_left = 0.5; title.anchor_right = 0.5
	title.offset_left = -fw / 2.0; title.offset_right = fw / 2.0
	title.offset_top = -fh / 2.0 - 30; title.offset_bottom = -fh / 2.0 - 6
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fbox.add_child(title)

func _make_map_rect(parent: Control) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixeles nítidos
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr

func _make_dot(parent: Control, color: Color, sz: float) -> ColorRect:
	var d := ColorRect.new()
	d.color = color
	d.size = Vector2(sz, sz)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(d)
	return d

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_full_root.visible = not _full_root.visible

func _on_regenerated() -> void:
	_reset()

func _reset() -> void:
	_explored = []
	for y in MAP_H:
		var row: Array = []
		row.resize(MAP_W)
		row.fill(false)
		_explored.append(row)
	if _img != null:
		_img.fill(C_UNSEEN)
		_dirty = true
	_exit_cell = Vector2i(-1, -1)
	if _dungeon != null and not _dungeon.rooms.is_empty():
		_exit_cell = _dungeon.rooms[_dungeon.rooms.size() - 1].get_center()

func _process(_dt: float) -> void:
	if _dungeon == null or not is_instance_valid(_dungeon) or _player == null or not is_instance_valid(_player):
		return
	if _explored.is_empty() or _dungeon.grid.is_empty():
		return
	var cell := _dungeon.local_to_map(_dungeon.to_local(_player.global_position))
	_reveal(cell)
	if _dirty:
		_tex.update(_img)
		_dirty = false
	_place_markers(cell)

func _reveal(c: Vector2i) -> void:
	var r2 := REVEAL_RADIUS * REVEAL_RADIUS
	for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy > r2:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H:
				continue
			if _explored[y][x]:
				continue
			_explored[y][x] = true
			var is_floor: bool = int(_dungeon.grid[y][x]) == 1
			_img.set_pixel(x, y, C_FLOOR if is_floor else C_WALL)
			_dirty = true

func _place_markers(cell: Vector2i) -> void:
	_set_dot(_mini_player, cell, MINI_SCALE)
	_set_dot(_full_player, cell, FULL_SCALE)
	var exit_seen: bool = _exit_cell.x >= 0 and _explored[_exit_cell.y][_exit_cell.x]
	_mini_exit.visible = exit_seen
	_full_exit.visible = exit_seen
	if exit_seen:
		_set_dot(_mini_exit, _exit_cell, MINI_SCALE)
		_set_dot(_full_exit, _exit_cell, FULL_SCALE)

func _set_dot(dot: ColorRect, cell: Vector2i, scale: int) -> void:
	dot.position = Vector2(cell.x * scale, cell.y * scale) + Vector2(scale, scale) * 0.5 - dot.size * 0.5
