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
const REVEAL_ALPHA := 0.2    # opacidad de la fachada DELANTERA revelada (transparente; uniforme y sin luz vía CanvasGroup + material reveal)
const ROOM_HYST := 6         # frames que el player debe estar en la sala antes de revelar (anti-flicker)
# La fachada revelada de la sala activa se composita en UN CanvasGroup atómico y la transparencia
# se aplica al GRUPO (self_modulate) → los bordes que se solapan se aplanan ANTES del alpha, así no
# se duplican (no quedan costuras oscuras) y la fachada se ve uniforme. Mismo truco que el rig del player.
var _reveal_group: CanvasGroup = null
var _reveal_group_tw: Tween = null
var _reveal_sprites: Dictionary = {} # cell → holder (tile-fachada swapeado a sprite, vive en el grupo)
var _reveal_overlays: Array = []     # holders de overlay reparentados al grupo (a devolver al salir)
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

## Revela/oculta la fachada DELANTERA (S/E) de una sala. Al revelar, TODAS sus fachadas se meten en
## un CanvasGroup y se le baja el alpha al GRUPO (no a cada tile) → uniforme, sin costuras de borde.
func _set_room_faded(rid: int, faded: bool) -> void:
	if rid < 0:
		return
	if faded:
		_reveal_room(rid)
	else:
		_unreveal_room()

func _reveal_room(rid: int) -> void:
	_clear_reveal_group()   # limpia/restaura cualquier grupo anterior al instante (entrar/salir rápido)
	var group := CanvasGroup.new()
	group.name = "RevealGroup"
	d._iso_walls.add_child(group)   # cuelga del layer de fachada (z+1, sobre el player); en (0,0)
	_reveal_group = group
	for e in d._room_front.get(rid, []):
		if int(e.kind) == 1:                       # overlay ya-sprite → reparentar al grupo
			var h = e.holder
			if is_instance_valid(h):
				h.get_parent().remove_child(h)
				group.add_child(h)
				h.modulate.a = 1.0
				if h.get_child_count() > 0:        # material sin óvalo mientras está revelado
					(h.get_child(0) as CanvasItem).material = d._iso_wall_mat_reveal
				_reveal_overlays.append(h)
		else:                                       # tile-fachada → swap a sprite DENTRO del grupo (sin óvalo)
			var cell: Vector2i = e.cell
			d._iso_walls.erase_cell(cell)
			_reveal_sprites[cell] = d._spawn_wall_sprite(cell, d._front_src[cell], false, group, true)
	d._iso_walls.update_internals()
	group.self_modulate.a = 1.0
	_reveal_group_tw = d.create_tween()
	_reveal_group_tw.tween_property(group, "self_modulate:a", REVEAL_ALPHA, 0.18).set_trans(Tween.TRANS_SINE)

func _unreveal_room() -> void:
	if _reveal_group == null or not is_instance_valid(_reveal_group):
		return
	if _reveal_group_tw != null and _reveal_group_tw.is_valid():
		_reveal_group_tw.kill()
	_reveal_group_tw = d.create_tween()
	_reveal_group_tw.tween_property(_reveal_group, "self_modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	_reveal_group_tw.tween_callback(_clear_reveal_group)

## Devuelve los overlays a _iso_walls, restaura los tiles swapeados y libera el grupo. Sincrónico.
func _clear_reveal_group() -> void:
	if _reveal_group_tw != null and _reveal_group_tw.is_valid():
		_reveal_group_tw.kill()
	_reveal_group_tw = null
	if _reveal_group == null or not is_instance_valid(_reveal_group):
		_reveal_group = null
		_reveal_sprites = {}
		_reveal_overlays = []
		return
	for h in _reveal_overlays:                  # overlays vuelven a su capa, opacos, con el óvalo de nuevo
		if is_instance_valid(h):
			h.get_parent().remove_child(h)
			d._iso_walls.add_child(h)
			h.modulate.a = 1.0
			if h.get_child_count() > 0:
				(h.get_child(0) as CanvasItem).material = d._iso_wall_mat_solid
	_reveal_overlays = []
	for cell in _reveal_sprites:                # tiles swapeados → repintar el tile
		d._iso_walls.set_cell(cell, d._front_src[cell], Vector2i(0, 0))
	_reveal_sprites = {}
	_reveal_group.queue_free()
	_reveal_group = null
	d._iso_walls.update_internals()
