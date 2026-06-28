extends Node2D
## Escena principal. Loop de pisos (F10): genera la mazmorra, ubica al jugador,
## siembra enemigos/jefe por zona, y maneja descenso → próximo piso → victoria.
## Persistencia: carga/continúa la run desde user:// y la guarda en cada piso.

const ENEMY := preload("res://scenes/enemy.tscn")
const BOSS := preload("res://scenes/boss.tscn")
const MINIMAP := preload("res://scripts/minimap.gd")
# Preload con const → instanciado tipado (DOOR.new()/VISIBILITY_MANAGER.new()); evita el
# parse-error fantasma de la línea 58 que daba el load(...).new() dinámico.
const DOOR := preload("res://scripts/door.gd")
const VISIBILITY_MANAGER := preload("res://scripts/visibility_manager.gd")

# Eclipse: usa las imágenes versión eclipse (fondo/montañas/árboles). false = noche.
const ECLIPSE := true
const NIGHT_DRAGON_TINT := Color(0.30, 0.40, 0.62)    # dragón: silueta azul (noche)
const ECLIPSE_DRAGON_TINT := Color(0.55, 0.20, 0.20)  # dragón: silueta rojiza (eclipse)

# Encuadre del fondo: yoff negativo SUBE la imagen → las ventanas muestran el
# horizonte/valle (en vez del cielo de arriba). zoom da margen para no dejar huecos.
# Fondo: alto completo de la imagen, fijo (costados recortados). zoom=1 → alto exacto.
const BG_ZOOM := 1.0
const BG_YOFF := 0.0
const BG_PARALLAX_Y := 0.0

@onready var dungeon: Dungeon = $Dungeon
@onready var player: CharacterBody2D = $Player

var _exit: Area2D
var _exit_open := false

func _ready() -> void:
	# Pantalla de carga: el procgen del piso (dungeon.generate + spawns) corre SÍNCRONO y bloquea
	# el frame → sin esto se ve un hueco "vacío". Mostramos el loader, esperamos UN frame para que
	# se dibuje, y recién ahí hacemos el trabajo pesado (que congela el frame, ya con el loader visible).
	var loading := _show_loading_overlay()
	await get_tree().process_frame
	GameState.boss_died.connect(_on_boss_died)
	var sky_img := "res://assets/bg/eclipse_vista.png" if ECLIPSE else "res://assets/bg/night_vista.png"
	var sky := ParallaxBg.new().init(sky_img, -100, 0.0, Color.WHITE, BG_ZOOM, BG_YOFF, BG_PARALLAX_Y)
	add_child(sky)
	var dragon := SkyDragon.new()
	dragon.tint = ECLIPSE_DRAGON_TINT if ECLIPSE else NIGHT_DRAGON_TINT
	sky.add_child(dragon)                                                 # dragón cerca de la luna
	# Montañas/árboles: REMOVIDAS — el nuevo fondo (night/eclipse_vista) ya trae el valle pintado.
	if SaveSystem.has_run():
		var save := SaveSystem.load_run()
		var r: Dictionary = save.get("run", {})
		if not r.is_empty():
			GameState.run = r
		_build_floor()   # reproduce el piso guardado vía (run_seed, depth)
		if save.has("player"):
			player.load_save(save["player"])
	else:
		GameState.reset_run()
		_build_floor()
	GameState.set_mode(GameState.Mode.PLAY)
	SaveSystem.save_run(GameState.run, player)   # checkpoint al entrar
	var mm := MINIMAP.new()                      # minimapa + mapa (M), con niebla
	add_child(mm)
	mm.setup(dungeon, player)
	var vm := VISIBILITY_MANAGER.new()   # tipado vía preload; gatea objetos del mundo (cofres/decor/mercader) por celda vista; los mobs se auto-gatean en enemy.gd
	add_child(vm)
	vm.setup(dungeon)
	_hide_loading_overlay(loading)   # piso listo → desvanece el loader

var _autosave_t := 0.0

## Overlay de carga a pantalla completa (loading.png sobre fondo oscuro), por encima de todo.
func _show_loading_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 200
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var tex := load("res://assets/ui/loading.png") as Texture2D
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.add_child(tr)
	add_child(layer)
	return layer

## Desvanece y libera el overlay de carga.
func _hide_loading_overlay(layer: CanvasLayer) -> void:
	if not is_instance_valid(layer):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	for c in layer.get_children():
		if c is CanvasItem:
			tw.tween_property(c, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(layer.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	# ESC durante la partida → vuelve al menú (con SALIR). Guarda la run primero.
	if event.is_action_pressed("ui_cancel") and GameState.mode == GameState.Mode.PLAY:
		SaveSystem.save_run(GameState.run, player)
		get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")

func _process(delta: float) -> void:
	if GameState.mode == GameState.Mode.PLAY:
		GameState.run["time"] = float(GameState.run.get("time", 0.0)) + delta
		_autosave_t += delta
		if _autosave_t >= 8.0:
			_autosave_t = 0.0
			SaveSystem.save_run(GameState.run, player)

# ---------------------------------------------------------------------------
# Construcción de un piso
# ---------------------------------------------------------------------------
## Seed determinista por (run_seed, depth): recargar el piso lo REPRODUCE (mismo
## layout), avanzar de piso cambia el mapa, y `force_new=true` (botón debug) fuerza
## una run nueva → mapa nuevo. Una sola fuente de verdad, sin el viejo -1/seed ambiguo.
func _build_floor(force_new := false) -> void:
	for n in get_children():
		if n is Enemy or n is Boss or n is Pickup or n is Projectile or n is Chest or n is Merchant or n.is_in_group("decor") or n.is_in_group("door"):
			n.queue_free()
	var run_seed := int(GameState.run.get("run_seed", 0))
	if run_seed == 0:
		run_seed = int(GameState.run.get("seed", 0))   # compat: saves viejos sin run_seed
	if force_new or run_seed == 0:
		run_seed = Rng.range_i(1, 0x7FFFFFFF)
	GameState.run["run_seed"] = run_seed
	var depth := int(GameState.run.get("depth", 1))
	# Mezclador explícito y estable entre versiones de Godot (hash([...]) podía variar).
	var floor_seed: int = (run_seed * 2654435761 + depth) & 0x7FFFFFFF
	Rng.set_seed(floor_seed)
	GameState.run["seed"] = floor_seed   # se mantiene por compatibilidad/minimapa

	dungeon.generate()
	player.global_position = dungeon.get_spawn_point()
	player.reset_physics_interpolation()

	# clampi anti-crash: un save corrupto/futuro con zone_idx fuera de rango crasheaba el indexado.
	var zone: Dictionary = Data.ZONES[clampi(int(GameState.run.get("zone_idx", 0)), 0, Data.ZONES.size() - 1)]
	var is_boss_floor: bool = int(GameState.run.get("floor_in_zone", 0)) >= int(zone.floors) - 1
	_spawn_enemies(zone)
	_spawn_chests()
	_spawn_decor()
	_spawn_doors()
	_make_exit()
	if is_boss_floor:
		_close_exit()
		_spawn_boss(String(zone.boss))
	else:
		_open_exit()
		_spawn_merchant_floor()

func next_floor() -> void:
	if not _exit_open:
		return
	var r := GameState.run
	r["depth"] = int(r.get("depth", 1)) + 1
	r["floor_in_zone"] = int(r.get("floor_in_zone", 0)) + 1
	var zone: Dictionary = Data.ZONES[int(r.get("zone_idx", 0))]
	if r["floor_in_zone"] >= int(zone.floors):
		r["floor_in_zone"] = 0
		r["zone_idx"] = int(r.get("zone_idx", 0)) + 1
	if int(r["zone_idx"]) >= Data.ZONES.size():
		_win()
		return
	GameState.floor_changed.emit(int(r["depth"]))
	_build_floor()
	SaveSystem.save_run(GameState.run, player)

func _win() -> void:
	GameState.set_mode(GameState.Mode.WIN)
	SaveSystem.record(GameState.run, player, true)
	SaveSystem.clear_run()

# ---------------------------------------------------------------------------
# Salida (portal al próximo piso)
# ---------------------------------------------------------------------------
func _make_exit() -> void:
	if _exit and is_instance_valid(_exit):
		_exit.queue_free()
	_exit = Area2D.new()
	_exit.collision_layer = 0
	_exit.collision_mask = 2   # detecta al jugador (capa 2)
	var shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 9.0
	shape.shape = circ
	_exit.add_child(shape)
	# Visual: portal violeta aditivo + luz emisiva.
	var spr := Sprite2D.new()
	spr.texture = load("res://assets/fx/light_radial.tres")
	spr.modulate = Color(0.7, 0.45, 1.0, 0.9)
	spr.scale = Vector2(0.12, 0.12)
	spr.z_index = 30
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	spr.material = m
	_exit.add_child(spr)
	var lt := PointLight2D.new()
	lt.texture = load("res://assets/fx/light_pool.tres")
	lt.color = Color(0.6, 0.4, 1.0)
	lt.energy = 1.6
	lt.texture_scale = 0.5
	_exit.add_child(lt)
	var exit_cell: Vector2i = dungeon.get_exit_cell()
	if exit_cell.x >= 0:
		_exit.global_position = dungeon.to_global(dungeon.map_to_local(exit_cell))
	else:
		var last: Rect2i = dungeon.rooms[dungeon.rooms.size() - 1]
		_exit.global_position = dungeon.to_global(dungeon.map_to_local(last.get_center()))
	_exit.body_entered.connect(func(b: Node) -> void:
		if b is Player:
			next_floor.call_deferred())   # fuera del flush de física
	add_child(_exit)

func _open_exit() -> void:
	_exit_open = true
	if _exit and is_instance_valid(_exit):
		_exit.visible = true
		_exit.set_deferred("monitoring", true)

func _close_exit() -> void:
	_exit_open = false
	if _exit and is_instance_valid(_exit):
		_exit.visible = false
		_exit.set_deferred("monitoring", false)

func _on_boss_died() -> void:
	_open_exit()
	_spawn_merchant()

func _spawn_merchant() -> void:
	if _exit == null or not is_instance_valid(_exit):
		return
	var m := Merchant.new()
	add_child(m)
	_gate(m, false)
	m.global_position = _exit.global_position + Vector2(-34, 16)
	m.reset_physics_interpolation()
	GameState.floater(m.global_position + Vector2(0, -22), "Un mercader apareció...", Color("c7b8e8"))

# --- Roles de sala (Fase 2): si dungeon asignó roles los usamos; si no (mapas fijos), "" → fallback por índice ---
func _room_role(i: int) -> String:
	return String(dungeon.room_roles.get(i, ""))

## Índice de la primera sala con el rol dado, o -1 si no hay roles asignados.
func _room_role_index(role: String) -> int:
	for i in dungeon.room_roles:
		if String(dungeon.room_roles[i]) == role:
			return int(i)
	return -1

## Marca una entidad para el gating de visibilidad (ocultar info estilo D2). Arranca OCULTA.
## threat=true → amenaza viva (parpadea con tu radio de visión); false → objeto del mundo (sticky al verla).
func _gate(node: Node2D, threat: bool) -> void:
	node.add_to_group("vis_gated")
	if threat:
		node.add_to_group("vis_threat")
	node.visible = false

# --- Cofres ---
func _spawn_chests() -> void:
	if dungeon.rooms.is_empty():
		return
	for ri in dungeon.rooms.size():
		var role := _room_role(ri)
		var place := false
		var gold := false
		if role == "treasure":
			place = true; gold = true                 # cofre bueno garantizado
		elif role == "combat":
			place = Rng.chance(0.3)                    # 30% en salas de combate
		elif role == "":
			place = true; gold = Rng.chance(0.22)      # sin roles (mapas fijos): uno por sala
		# entry / boss / merchant → sin cofre
		if not place:
			continue
		var room: Rect2i = dungeon.rooms[ri]
		var ch := Chest.new()
		ch.gold = gold
		add_child(ch)
		_gate(ch, false)   # objeto del mundo: oculto hasta ver su celda, después sticky
		ch.global_position = dungeon.to_global(dungeon.map_to_local(_rand_room_cell(room)))
		ch.reset_physics_interpolation()

# --- Puertas (modo salas aisladas Dungeon.USE_DOORS): teleport entre salas conectadas por el grafo ---
func _spawn_doors() -> void:
	if not dungeon.USE_DOORS:
		return
	for spec in dungeon.get_door_specs():
		var d := DOOR.new()   # tipado vía preload (Door)
		add_child(d)
		d.global_position = dungeon.to_global(dungeon.map_to_local(spec.from))
		d.target_pos = dungeon.to_global(dungeon.map_to_local(spec.to))

# --- Mercader en pisos normales (además del post-jefe), en la sala más lejana ---
func _spawn_merchant_floor() -> void:
	var rooms := dungeon.rooms
	if rooms.size() < 3:
		return
	var best := _room_role_index("merchant")   # Fase 2: sala con rol mercader
	if best < 0:
		# Fallback (mapas fijos): sala (ni spawn ni salida) lo más lejos posible de AMBOS.
		var spawn_c := dungeon.to_global(dungeon.map_to_local(rooms[0].get_center()))
		var exit_c: Vector2 = _exit.global_position if (_exit and is_instance_valid(_exit)) else spawn_c
		var best_score := -1.0
		for ri in range(1, rooms.size() - 1):
			var c := dungeon.to_global(dungeon.map_to_local(rooms[ri].get_center()))
			var score: float = minf(c.distance_to(spawn_c), c.distance_to(exit_c))
			if score > best_score:
				best_score = score
				best = ri
		if best < 0:
			return
	var pos := dungeon.to_global(dungeon.map_to_local(_rand_room_cell(rooms[best])))
	var m := Merchant.new()
	add_child(m)
	_gate(m, false)   # objeto del mundo: oculto hasta explorar su sala
	m.global_position = pos
	m.reset_physics_interpolation()
	# Despejar mobs cerca del mercader → zona segura para comprar.
	for n in get_children():
		if n is Enemy and n.global_position.distance_to(pos) < 70.0:
			n.queue_free()

# --- Decoración de salas (props del pixi, solo visual / sin colisión) ---
const DECOR_SHEETS := {"furniture": "magic_furniture", "supplies": "dobj_supplies", "other": "dobj_other"}
const DECOR := {
	"bookshelf":     {"sheet": "furniture", "r": [1, 69, 46, 52], "scale": 0.55},
	"bookshelf_pot": {"sheet": "furniture", "r": [1, 133, 46, 52], "scale": 0.55},
	"cabinet":       {"sheet": "furniture", "r": [1, 5, 46, 52], "scale": 0.55},
	"desk":          {"sheet": "furniture", "r": [53, 40, 39, 24], "scale": 0.6},
	"table":         {"sheet": "furniture", "r": [53, 10, 39, 22], "scale": 0.6},
	"barrel":        {"sheet": "supplies", "r": [22, 332, 19, 29], "scale": 0.8},
	"sack":          {"sheet": "supplies", "r": [112, 335, 28, 28], "scale": 0.55},
	"statue":        {"sheet": "other", "r": [7, 5, 34, 43], "scale": 0.55},
	"crystal":       {"sheet": "other", "r": [70, 59, 21, 27], "scale": 0.6},
	"banner_blue":   {"sheet": "other", "r": [196, 64, 23, 30], "scale": 0.6},
	"banner_red":    {"sheet": "other", "r": [164, 64, 23, 30], "scale": 0.6},
}
const FURNITURE := ["bookshelf", "bookshelf_pot", "cabinet", "desk", "table"]
const SCATTER := ["barrel", "sack", "statue", "crystal"]
const BANNERS := ["banner_blue", "banner_red"]
static var _decor_tex := {}

func _spawn_decor() -> void:
	for ri in range(dungeon.rooms.size()):
		var role := _room_role(ri)
		if role == "entry" or (role == "" and ri == 0):
			continue   # sin decoración en la entrada
		var room: Rect2i = dungeon.rooms[ri]
		if room.size.x < 4 or room.size.y < 4:
			continue
		if Rng.chance(0.6):   # mueble contra la pared norte
			var fx := Rng.range_i(room.position.x + 1, room.position.x + room.size.x - 2)
			_place_decor(FURNITURE[Rng.range_i(0, FURNITURE.size() - 1)], Vector2i(fx, room.position.y + 1))
		if Rng.chance(0.35):  # estandarte en la pared norte
			var bx := Rng.range_i(room.position.x + 1, room.position.x + room.size.x - 2)
			_place_decor(BANNERS[Rng.range_i(0, BANNERS.size() - 1)], Vector2i(bx, room.position.y))
		for j in Rng.range_i(0, 2):   # props sueltos
			_place_decor(SCATTER[Rng.range_i(0, SCATTER.size() - 1)], _rand_room_cell(room))

func _place_decor(type: String, cell: Vector2i) -> void:
	var def: Dictionary = DECOR[type]
	var sheet := _decor_sheet(def.sheet)
	if sheet == null:
		return
	var spr := Sprite2D.new()
	spr.add_to_group("decor")
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(def.r[0], def.r[1], def.r[2], def.r[3])
	spr.texture = at
	var sc: float = def.scale
	spr.scale = Vector2(sc, sc)
	spr.offset = Vector2(0, 8.0 / sc - float(def.r[3]) * 0.5)   # base anclada al piso
	spr.z_index = -1   # debajo de entidades, sobre el piso
	spr.global_position = dungeon.to_global(dungeon.map_to_local(cell))
	add_child(spr)
	_gate(spr, false)   # decor: oculto hasta ver su celda, después sticky

func _decor_sheet(key: String) -> Texture2D:
	if _decor_tex.has(key):
		return _decor_tex[key]
	var path := "res://assets/decor/%s.png" % DECOR_SHEETS[key]
	var tex := load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_decor_tex[key] = tex
	return tex

# ---------------------------------------------------------------------------
# Spawns
# ---------------------------------------------------------------------------
func _spawn_boss(key: String) -> void:
	var ri := _room_role_index("boss")   # Fase 2: sala del jefe (la más profunda)
	if ri < 0:
		ri = dungeon.rooms.size() - 1
	var room: Rect2i = dungeon.rooms[ri]
	var b := BOSS.instantiate()
	add_child(b)
	b.setup_boss(key)
	b.global_position = dungeon.to_global(dungeon.map_to_local(_rand_room_cell(room)))
	b.reset_physics_interpolation()

func _spawn_enemies(zone: Dictionary) -> void:
	var pool: Array = zone.enemies
	var dens := float(zone.get("density", 1.0))
	var elite_p := float(Data.BALANCE.elite_chance)
	# Fase 3: escalado por profundidad.
	var depth := int(GameState.run.get("depth", 1))
	var depth_mul := 1.0 + 0.12 * (depth - 1)    # +12% densidad por piso
	var elite_d := elite_p + 0.02 * (depth - 1)  # más élites en profundidad
	var stat_mul := 1.0 + 0.10 * (depth - 1)     # +10% HP/daño por piso
	for i in range(dungeon.rooms.size()):
		var role := _room_role(i)
		if role == "entry" or role == "merchant" or role == "boss":
			continue   # sin mobs en entrada / mercader / sala de jefe
		if role == "" and i == 0:
			continue   # sin roles (mapas fijos): mantener el viejo "salta sala 0"
		var room: Rect2i = dungeon.rooms[i]
		# Varios mobs por sala, escalado por área (salas grandes → más) y por profundidad.
		var n := clampi(int(round(room.size.x * room.size.y / 14.0 * dens * depth_mul)), 4, 14)
		# home_rect en el MISMO espacio que home_pos (iso). Antes usaba room*TILE (espacio
		# flat 16px, leftover del 2D) → el box quedaba pegado al origen y los mobs NO-aggro
		# vagaban hacia él = drift al oeste, peor cuanto más lejos del origen.
		var _rp := room.position
		var _rs := room.size
		var _cs := [dungeon.map_to_local(_rp), dungeon.map_to_local(_rp + Vector2i(_rs.x, 0)),
			dungeon.map_to_local(_rp + Vector2i(0, _rs.y)), dungeon.map_to_local(_rp + _rs)]
		var _mn: Vector2 = _cs[0]
		var _mx: Vector2 = _cs[0]
		for _c in _cs:
			_mn = _mn.min(_c); _mx = _mx.max(_c)
		var home_rect := Rect2(dungeon.to_global(_mn), dungeon.to_global(_mx) - dungeon.to_global(_mn))
		for j in n:
			var e := ENEMY.instantiate()
			add_child(e)
			e.setup_type(Rng.pick(pool), Rng.chance(elite_d))
			if stat_mul > 1.0:
				e.max_hp = int(round(e.max_hp * stat_mul))
				e.hp = e.max_hp
				e.damage = int(round(e.damage * stat_mul))
			var pos := dungeon.to_global(dungeon.map_to_local(_rand_room_cell(room)))
			e.global_position = pos
			e.home_pos = pos
			e.home_rect = home_rect
			e.reset_physics_interpolation()

## Celda al azar dentro de la sala (con 1 tile de margen para no pegarse al muro).
func _rand_room_cell(room: Rect2i) -> Vector2i:
	# Muestrea el bbox y EXIGE piso real (con salas iso el bbox incluye vacío/muros → no
	# spawnear mobs dentro de paredes). Fallback al centro tras varios intentos.
	for _t in 24:
		var x := Rng.range_i(room.position.x, room.position.x + room.size.x - 1)
		var y := Rng.range_i(room.position.y, room.position.y + room.size.y - 1)
		if y >= 0 and y < dungeon.grid.size() and x >= 0 and x < dungeon.grid[y].size() and dungeon.grid[y][x] == 1:
			return Vector2i(x, y)
	return room.get_center()
