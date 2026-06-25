extends CanvasLayer
class_name Minimap
## Minimapa (esquina sup. derecha, siempre visible) + mapa completo (tecla M),
## ambos con niebla de guerra: se revela la grilla del Dungeon a medida que el
## jugador camina. Dibuja desde Dungeon.grid (1=piso/0=muro) sobre una Image que
## se actualiza solo cuando se descubren celdas nuevas. Markers: jugador y salida.
##
## El tamaño se toma del grid REAL del piso (no de un 64×64 fijo): los pisos
## procedurales son 64×64, pero un mapa fijo de Tiled puede ser de cualquier
## tamaño. La escala de dibujo se adapta para que entre en pantalla.

const REVEAL_RADIUS := 6        # tiles revelados alrededor del jugador

const C_UNSEEN := Color(0, 0, 0, 0)
const C_FLOOR := Color(0.60, 0.56, 0.66, 1.0)
const C_WALL := Color(0.16, 0.15, 0.20, 1.0)
const C_PLAYER := Color(0.45, 0.9, 1.0, 1.0)
const C_EXIT := Color(0.75, 0.45, 1.0, 1.0)

var _mw := Dungeon.MAP_W         # ancho del grid actual (tiles)
var _mh := Dungeon.MAP_H         # alto del grid actual (tiles)
var _mini_scale := 2             # px por tile en el minimapa
var _full_scale := 8             # px por tile en el mapa grande

var _dungeon: Dungeon
var _player: Node2D
var _explored: Array = []
var _img: Image
var _tex: ImageTexture
var _dirty := true
var _exit_cell := Vector2i(-1, -1)

var _mini_box: Control
var _mini_tex: TextureRect
var _mini_player: ColorRect
var _mini_exit: ColorRect
var _full_root: Control
var _fbox: Control
var _full_tex: TextureRect
var _full_player: ColorRect
var _full_exit: ColorRect
var _title: Label

func setup(dungeon: Dungeon, player: Node2D) -> void:
	_dungeon = dungeon
	_player = player
	if not _dungeon.regenerated.is_connected(_on_regenerated):
		_dungeon.regenerated.connect(_on_regenerated)
	_resync_size()   # ajustar al tamaño del piso ya generado
	_reset()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_compute_scales()
	_img = Image.create_empty(_mw, _mh, false, Image.FORMAT_RGBA8)
	_img.fill(C_UNSEEN)
	_tex = ImageTexture.create_from_image(_img)
	_build_ui()
	_apply_layout()

## Escala de dibujo adaptada al tamaño del grid para que el mini quepa en la
## esquina y el mapa grande entre en pantalla.
func _compute_scales() -> void:
	_mini_scale = clampi(int(140.0 / maxi(_mw, _mh)), 1, 3)
	var vp := Vector2(1152, 648)
	if is_inside_tree():
		var r := get_viewport().get_visible_rect().size
		if r.x > 0 and r.y > 0:
			vp = r
	_full_scale = clampi(int(min(vp.x * 0.82 / _mw, vp.y * 0.82 / _mh)), 2, 10)

## Relee el tamaño del grid del dungeon; si cambió, recrea la Image y reajusta UI.
func _resync_size() -> void:
	var w := _mw
	var h := _mh
	if _dungeon != null and not _dungeon.grid.is_empty():
		h = _dungeon.grid.size()
		w = _dungeon.grid[0].size()
	if w == _mw and h == _mh and _img != null:
		return
	_mw = w
	_mh = h
	_compute_scales()
	_img = Image.create_empty(_mw, _mh, false, Image.FORMAT_RGBA8)
	_img.fill(C_UNSEEN)
	_tex.set_image(_img)
	_apply_layout()

func _build_ui() -> void:
	# --- Minimapa (esquina sup. derecha) ---
	_mini_box = Control.new()
	_mini_box.anchor_left = 1.0
	_mini_box.anchor_right = 1.0
	add_child(_mini_box)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = -3; bg.offset_top = -3; bg.offset_right = 3; bg.offset_bottom = 3
	_mini_box.add_child(bg)
	_mini_tex = _make_map_rect(_mini_box)
	_mini_exit = _make_dot(_mini_tex, C_EXIT, 3)
	_mini_player = _make_dot(_mini_tex, C_PLAYER, 4)
	# Recorte circular + anillo ornamental dorado (todo en el shader, sin asset).
	var circ := ShaderMaterial.new()
	circ.shader = preload("res://shaders/minimap_circle.gdshader")
	bg.material = circ
	_mini_tex.material = circ

	# --- Mapa completo (tecla M) ---
	_full_root = Control.new()
	_full_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.visible = false
	add_child(_full_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.add_child(dim)
	_fbox = Control.new()
	_fbox.anchor_left = 0.5; _fbox.anchor_right = 0.5; _fbox.anchor_top = 0.5; _fbox.anchor_bottom = 0.5
	_full_root.add_child(_fbox)
	_full_tex = _make_map_rect(_fbox)
	_full_exit = _make_dot(_full_tex, C_EXIT, 8)
	_full_player = _make_dot(_full_tex, C_PLAYER, 10)
	_title = Label.new()
	_title.text = "MAPA  ·  [M] cerrar"
	_title.add_theme_color_override("font_color", Color("ffd84f"))
	_title.add_theme_font_size_override("font_size", 18)
	_title.anchor_left = 0.5; _title.anchor_right = 0.5
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fbox.add_child(_title)

## Posiciona/dimensiona las cajas según el tamaño del grid y la escala actual.
func _apply_layout() -> void:
	var mw_px := _mw * _mini_scale
	var mh_px := _mh * _mini_scale
	_mini_box.offset_left = -mw_px - 12
	_mini_box.offset_right = -12
	_mini_box.offset_top = 12
	_mini_box.offset_bottom = 12 + mh_px
	_mini_exit.size = Vector2.ONE * (_mini_scale + 1)
	_mini_player.size = Vector2.ONE * (_mini_scale + 2)

	var fw := _mw * _full_scale
	var fh := _mh * _full_scale
	_fbox.offset_left = -fw / 2.0; _fbox.offset_right = fw / 2.0
	_fbox.offset_top = -fh / 2.0; _fbox.offset_bottom = fh / 2.0
	_full_exit.size = Vector2.ONE * _full_scale
	_full_player.size = Vector2.ONE * (_full_scale + 2)
	_title.offset_left = -fw / 2.0; _title.offset_right = fw / 2.0
	_title.offset_top = -fh / 2.0 - 30; _title.offset_bottom = -fh / 2.0 - 6

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
	_resync_size()
	_reset()

func _reset() -> void:
	_explored = []
	for y in _mh:
		var row: Array = []
		row.resize(_mw)
		row.fill(false)
		_explored.append(row)
	if _img != null:
		_img.fill(C_UNSEEN)
		_dirty = true
	# Salida: marcador del mapa fijo si lo hay; si no, la última sala (procedural).
	_exit_cell = Vector2i(-1, -1)
	if _dungeon != null:
		_exit_cell = _dungeon.get_exit_cell()
		if _exit_cell.x < 0 and not _dungeon.rooms.is_empty():
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
			if x < 0 or y < 0 or x >= _mw or y >= _mh:
				continue
			if _explored[y][x]:
				continue
			_explored[y][x] = true
			var is_floor: bool = int(_dungeon.grid[y][x]) == 1
			_img.set_pixel(x, y, C_FLOOR if is_floor else C_WALL)
			_dirty = true

func _place_markers(cell: Vector2i) -> void:
	_set_dot(_mini_player, cell, _mini_scale)
	_set_dot(_full_player, cell, _full_scale)
	var exit_seen: bool = _exit_cell.x >= 0 and _in_bounds(_exit_cell) and _explored[_exit_cell.y][_exit_cell.x]
	_mini_exit.visible = exit_seen
	_full_exit.visible = exit_seen
	if exit_seen:
		_set_dot(_mini_exit, _exit_cell, _mini_scale)
		_set_dot(_full_exit, _exit_cell, _full_scale)

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _mw and c.y < _mh

func _set_dot(dot: ColorRect, cell: Vector2i, scale: int) -> void:
	dot.position = Vector2(cell.x * scale, cell.y * scale) + Vector2(scale, scale) * 0.5 - dot.size * 0.5
