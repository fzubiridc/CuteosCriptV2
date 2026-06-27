extends RefCounted
class_name DungeonDecor
## DECORACIÓN de la mazmorra ISOMÉTRICA (antorchas + fogatas), extraída de dungeon.gd
## (movimiento mecánico, misma lógica). Coloca antorchas de pared (luz + sombras proyectadas)
## y fogatas en el centro de algunas salas. Toda referencia a estado/consts/exports/métodos del
## nodo Dungeon va prefijada con `d.`; los autoloads/builtins (LightCfg, LightField, Vector2i…) no.

var d: Dungeon

func _init(dungeon: Dungeon) -> void:
	d = dungeon

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
## en vivo. La usa el sandbox (closed_room_test) y, a futuro, place_torches del procgen.
func spawn_wall_torch(interior_cell: Vector2i, side: int) -> Node:
	var parent := d.get_parent()
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
	var anchor := d.to_global(d.map_to_local(cell) + _edge_midpoint(side))
	var flame := Vector2(LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"))
	var light_off: Vector2 = d.WallSegment.INWARD_NORMAL[side] * LightCfg.get_v("torch_light_inset")
	t.set("light_offset", light_off)
	t.set("position", anchor + light_off)
	if t.has_method("set_mount"):
		t.call("set_mount", flame, light_off)

## Punto medio del borde de muro, en coords de celda iso (rombo 256×128 centrado).
func _edge_midpoint(side: int) -> Vector2:
	match side:
		d.WallSegment.Side.NW: return Vector2(-64, -32)
		d.WallSegment.Side.NE: return Vector2(64, -32)
		d.WallSegment.Side.SE: return Vector2(64, 32)
		d.WallSegment.Side.SW: return Vector2(-64, 32)
	return Vector2.ZERO

## Reposiciona las antorchas ancladas si cambiaste los @export (Remote inspector durante Play).
func tune_torches_live() -> void:
	if _torches.is_empty():
		return
	var c := [LightCfg.get_v("torch_flame_x"), LightCfg.get_v("torch_flame_y"), LightCfg.get_v("torch_light_inset")]
	if c == _torch_cfg_cache:
		return
	_torch_cfg_cache = c
	for e in _torches:
		if is_instance_valid(e.node):
			_position_torch(e.node, e.cell, e.side)

func place_torches() -> void:
	var gw: int = d.grid[0].size() if not d.grid.is_empty() else d.MAP_W
	var gh := d.grid.size()
	var parent := d.get_parent()
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
	for room_i in d.rooms.size():
		var r := d.rooms[room_i]
		if idx >= MAX_TORCHES:
			break
		var wall_row := r.position.y - 1
		if wall_row < 0:
			continue
		for x in [r.position.x + 2, r.position.x + r.size.x - 3]:
			if idx >= MAX_TORCHES:
				break
			if x < 0 or x >= gw or d.grid[wall_row][x] != 0:
				continue
			var t := PointLight2D.new()
			t.set_script(torch_script)
			t.seed_off = idx * 1.7
			var light_inset := ISO_TORCH_LIGHT_INSET if d.ISO else Vector2.ZERO
			t.light_offset = light_inset
			# La LUZ va un poco DENTRO de la sala (fuera del occluder del muro) para
			# que ilumine el piso; si la dejábamos en la cara, el muro bloqueaba su
			# propia luz. El SPRITE de la antorcha se sube en torch.gd para quedar
			# sobre la cara del muro.
			t.position = d.to_global(d.map_to_local(Vector2i(x, wall_row))) + Vector2(0, 11) + light_inset
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
				if d.grid[wall_y][wall_x] != 0 or d.grid[wall_y][inner_x] != 1:
					continue
				var side_torch := PointLight2D.new()
				side_torch.set_script(side_torch_script)
				side_torch.wall_side = side
				side_torch.seed_off = idx * 1.7
				var inward := Vector2(11, 6) if side == &"left" else Vector2(-11, 6)
				var side_light_inset := Vector2.ZERO
				if d.ISO:
					side_light_inset = Vector2(
						ISO_SIDE_TORCH_LIGHT_INSET if side == &"left" else -ISO_SIDE_TORCH_LIGHT_INSET,
						-6
					)
				side_torch.light_offset = side_light_inset
				side_torch.position = d.to_global(d.map_to_local(Vector2i(wall_x, wall_y))) + inward + side_light_inset
				holder.add_child(side_torch)
				idx += 1
				break
	LightField.mark_dirty()   # refrescar la lista de luces para el foot-light

# ---------------------------------------------------------------------------
# Fogatas
# ---------------------------------------------------------------------------
const CAMPFIRE_SCENE := preload("res://scenes/campfire.tscn")   # fogata de leña (sprite anim + luz + sfx); se instancia en place_campfires

## Coloca fogatas (campfire.tscn) en el CENTRO de algunas salas, "cada tanto" (~1 de cada 3) para no
## saturar. La fogata se autoubica en el piso (Node2D) → solo seteo position y seed_off (desfasa la
## llama/sfx). Holder propio "Campfires" bajo el padre, que se LIMPIA al regenerar el piso (igual que
## "Torches"). Salta la sala de spawn (no aparecer sobre el player) y centra en celda CAMINABLE
## (room_center_cell devuelve piso real, no muro/puerta).
func place_campfires() -> void:
	d._ensure_gen()
	var parent := d.get_parent()
	var holder := parent.get_node_or_null("Campfires")
	if holder == null:
		holder = Node2D.new()
		holder.name = "Campfires"
		parent.add_child(holder)
	else:
		for c in holder.get_children():
			c.queue_free()
	# Sala de spawn por celda (robusto en procgen y mapas fijos): la que contiene spawn_cell.
	var spawn_room: int = d._room_of.get(d.spawn_cell, -1)
	var placed := 0
	for room_i in d.rooms.size():
		if room_i == spawn_room:
			continue
		if room_i % 3 != 0:   # densidad moderada: ~1 de cada 3 salas
			continue
		var cell := d._gen.room_center_cell(room_i)   # celda de piso real, centrada en la sala
		var fire := CAMPFIRE_SCENE.instantiate()
		fire.seed_off = placed * 1.7   # desfasa parpadeo/sfx entre fogatas (set antes de add_child)
		fire.position = d.to_global(d.map_to_local(cell))   # a ras de piso, posición iso
		holder.add_child(fire)
		placed += 1
	LightField.mark_dirty()   # las fogatas aportan luz → refrescar el foot-light
