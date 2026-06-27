extends RefCounted
class_name DungeonFog
## NIEBLA DE GUERRA + REVEAL por habitación de la mazmorra ISOMÉTRICA, extraído de dungeon.gd
## (movimiento mecánico, misma lógica). Mantiene la niebla por celda (cell_seen vive en Dungeon,
## es la FUENTE DE VERDAD que leen minimapa/entidades) y el reveal de la fachada delantera por sala.
## Toda referencia a estado/consts/exports/métodos del nodo Dungeon va prefijada con `d.`; los
## autoloads/builtins (GameState, Vector2i, Color, Tween…) no. El estado PROPIO de niebla/reveal
## (cell_seen NO; sí _visible_now/_reveal_*/_active_room…) y los consts movidos van en `self`.

var d: Dungeon

const VIS_RADIUS := 6   # tiles vistos alrededor del player (coincide con el minimapa)
var _visible_now: Dictionary = {}
## Última celda del player con la que se recalculó la visibilidad. Si el player no cambió de
## celda, update_visibility saltea el barrido del disco (~169 celdas/frame). Sentinela INT_MIN
## → la primera llamada siempre computa; init_visibility lo resetea por piso (regen).
var _last_vis_cell: Vector2i = Vector2i(-2147483648, -2147483648)

## Fase 3: reveal por habitación (reemplaza el viejo cutout). Cada celda de piso pertenece
## a una sala (rect de procgen); al entrar, la fachada trasera de esa sala baja a semitransparente
## como CONJUNTO (sin dither, sin per-tile flicker). Estilo Baldur's Gate 3 / Divinity OS2.
const REVEAL_ALPHA := 0.22   # opacidad de la fachada DELANTERA revelada (15-30%), conserva textura/volumen
const ROOM_HYST := 6         # frames que el player debe estar en la sala antes de revelar (anti-flicker)
var _reveal_sprites: Dictionary = {} # cell → Node2D (tile-muro swapeado a sprite mientras está revelado)
var _reveal_tw: Dictionary = {}      # cell → Tween activo del fade (para cancelarlo en swaps rápidos)
var _active_room: int = -1
var _pending_room: int = -99
var _room_hold: int = 0

func _init(dungeon: Dungeon) -> void:
	d = dungeon

# ---------------------------------------------------------------------------
# Niebla de guerra / visibilidad por celda (fuente de verdad; ver vars arriba)
# ---------------------------------------------------------------------------
## Dimensiona cell_seen al grid actual (todo no-visto) y limpia el set visible. Por piso.
func init_visibility() -> void:
	d.cell_seen = []
	var gh := d.grid.size()
	var gw: int = d.grid[0].size() if gh > 0 else 0
	for y in gh:
		var row: Array = []
		row.resize(gw)
		row.fill(false)
		d.cell_seen.append(row)
	_visible_now = {}
	_last_vis_cell = Vector2i(-2147483648, -2147483648)   # invalida el gate por piso → recomputa aunque respawnee en la misma celda

## Marca el disco de radio VIS_RADIUS alrededor de la celda del player: visible AHORA + seen sticky.
func update_visibility(pc: Vector2i) -> void:
	# Gate por celda: si el player no cambió de celda, _visible_now/cell_seen ya están al día
	# del frame anterior → no rebarrer ~169 celdas. Solo recalcula al cruzar de celda.
	if pc == _last_vis_cell:
		return
	_last_vis_cell = pc
	_visible_now.clear()   # reusar el dict cada frame (evita alocar uno nuevo + churn de GC)
	var gh := d.cell_seen.size()
	if gh == 0:
		return
	var r2 := VIS_RADIUS * VIS_RADIUS
	for dy in range(-VIS_RADIUS, VIS_RADIUS + 1):
		for dx in range(-VIS_RADIUS, VIS_RADIUS + 1):
			if dx * dx + dy * dy > r2:
				continue
			var x := pc.x + dx
			var y := pc.y + dy
			if y < 0 or y >= gh or x < 0 or x >= d.cell_seen[y].size():
				continue
			_visible_now[Vector2i(x, y)] = true
			d.cell_seen[y][x] = true

## Celda (grilla) de una posición de mundo. OJO: usa el to_local del Dungeon (scale 0.5).
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return d.local_to_map(d.to_local(world_pos))

## ¿La celda fue vista alguna vez? (sticky). Acepta celda directa.
func is_seen_cell(c: Vector2i) -> bool:
	return c.y >= 0 and c.y < d.cell_seen.size() and c.x >= 0 and c.x < d.cell_seen[c.y].size() and d.cell_seen[c.y][c.x]

func is_cell_seen(world_pos: Vector2) -> bool:
	return is_seen_cell(world_to_cell(world_pos))

## ¿La celda está en el radio del player AHORA?
func is_cell_visible(world_pos: Vector2) -> bool:
	return _visible_now.has(world_to_cell(world_pos))

## Reveal por habitación: al entrar a una sala (con histéresis), su fachada trasera baja a
## semitransparente como CONJUNTO; al salir, vuelve a sólida. Sin dither, sin per-tile flicker.
func update_room_reveal(pl: Node2D) -> void:
	if d._iso_walls == null:
		return
	var pc := d.local_to_map(d.to_local(pl.global_position))
	var rid: int = d._room_of.get(pc, -1)
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
	for e in d._room_front.get(rid, []):
		if int(e.kind) == 1:                       # overlay ya-sprite: solo tween
			if is_instance_valid(e.holder):
				_tween_alpha(e.holder, target)
			continue
		var cell: Vector2i = e.cell                # tile-fachada: swap tile↔sprite
		if faded:
			if not _reveal_sprites.has(cell):
				d._iso_walls.erase_cell(cell)
				_reveal_sprites[cell] = d._spawn_wall_sprite(cell, d._front_src[cell], false)
				touched = true
			_reveal_fade(cell, REVEAL_ALPHA, false)
		elif _reveal_sprites.has(cell):
			_reveal_fade(cell, 1.0, true)          # tween a opaco y, al terminar, restaurar tile
	if touched:
		d._iso_walls.update_internals()

## Tween de alpha de un sprite de reveal. Cancela cualquier tween previo de ESA celda (swaps
## rápidos entrar/salir). restore=true: al terminar, libera el sprite y repone el tile.
func _reveal_fade(cell: Vector2i, to_a: float, restore: bool) -> void:
	if _reveal_tw.has(cell) and _reveal_tw[cell] != null and _reveal_tw[cell].is_valid():
		_reveal_tw[cell].kill()
	var h: Node2D = _reveal_sprites[cell]
	var tw := d.create_tween()
	tw.tween_property(h, "modulate:a", to_a, 0.18).set_trans(Tween.TRANS_SINE)
	if restore:
		var src: int = d._front_src[cell]
		tw.tween_callback(func() -> void:
			if is_instance_valid(h):
				h.queue_free()
			_reveal_sprites.erase(cell)
			_reveal_tw.erase(cell)
			d._iso_walls.set_cell(cell, src, Vector2i(0, 0))
			d._iso_walls.update_internals())
	_reveal_tw[cell] = tw

func _tween_alpha(node: Node2D, to_a: float) -> void:
	var tw := d.create_tween()
	tw.tween_property(node, "modulate:a", to_a, 0.18).set_trans(Tween.TRANS_SINE)
