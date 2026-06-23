extends CharacterBody2D
class_name Player
## Jugador — F8a-2: rig con cuerpo-sin-arma (walk_empty/idle_hold) + Weapon
## intercambiable. Para west/sw/nw espejamos el Rig (mirror), así reutilizamos
## las 5 dirs base de walk_empty. El proyectil sale de Tip (punta del staff).

const PROJECTILE := preload("res://scenes/projectile.tscn")
@export var camera_zoom := 4.0   # knob de zoom de cámara (3 = original, más = más cerca)
@export var rig_scale := 0.4     # escala visual del rig (0.4 = top-down; subir para iso)

# Mapeo de octantes (de velocity.angle, 0=east, sentido horario)
const OCTANTS := ["east", "south_east", "south", "south_west", "west", "north_west", "north", "north_east"]
# Solo tenemos animaciones para 5 dirs base. El resto va por mirror del Rig.
const FACING_MIRROR := {"west": "east", "north_west": "north_east", "south_west": "south_east"}
# HandOverlay (los dedos por delante de la vara, para el agarre).
const HAND_OVERLAY_DIRS := {"south": "south", "south_east": "south-east", "north_east": "north-east"}
# Solo en NORTE puro la vara va detrás del cuerpo (sube z del cuerpo). En
# NE/NW usamos el agarre: vara delante del cuerpo + dedos (overlay) delante
# de la vara → "dedo - vara - resto de mano".
const STAFF_BEHIND := {"north": true}

@export_group("Movimiento")
@export var base_speed := 78.0           # knob: velocidad base de desplazamiento
@export var walk_anim_speed := 0.7       # knob: cadencia base de la caminata
@export var walk_speed_ref := 95.0       # knob: velocidad donde walk_anim_speed queda calibrada
@export_group("")
@export var base_max_hp := 100
@export var base_attack_dmg := 12
@export var max_mana := 100.0

# Bonus por mejoras de nivel.
var bonus_hp := 0
var dmg_mul := 1.0
var spd_add := 0.0
var crit := 8.0
var atkspd_mul := 1.0
var defense := 0

# Equipo / inventario.
var equip := {}
var bag: Array = []

var hp := 100
var mana := 100.0
var coins := 0
var xp := 0
var level := 1
var xp_to_next := 8
var potions := 1

var no_cast_t := 0.0
var atk_cd_t := 0.0
var kb := Vector2.ZERO
var dash_t := 0.0
var dash_cd_t := 0.0
var dash_vel := Vector2.ZERO
static var _px_tex: Texture2D            # 1×1 blanco compartido (partícula del dash)
var ifr := 0.0

# Animación / facing
var facing_dir := "south"
var cur_anim := ""
var cur_staff_idx := -1

# Cache de texturas cargadas en runtime (los PNGs no están importados por Godot,
# los cargamos con Image.load_from_file).
var _staff_textures: Array[Texture2D] = []
var _hand_textures := {}

@onready var rig: Node2D = $Rig
@onready var body: AnimatedSprite2D = $Rig/Body
@onready var hand: Node2D = $Rig/Hand
@onready var weapon: Sprite2D = $Rig/Hand/Weapon
@onready var tip: Marker2D = $Rig/Hand/Weapon/Tip
@onready var hand_overlay: Sprite2D = $Rig/Hand/HandOverlay
@onready var staff_arm: Sprite2D = $Rig/StaffArm
@onready var cam: Camera2D = $Camera2D

var shake_t := 0.0
var shake_amt := 0.0
@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	GameState.player = self
	equip["arma"] = {"slot": "arma", "weapon_type": "varita", "dmg": 9, "rarity": "comun",
		"material": "madera", "mat_name": "Madera", "mods": {}, "def": 0, "name": "Vara del Aprendiz"}
	hp = max_hp()
	mana = max_mana
	_load_textures()
	_refresh_weapon()
	_play("idle", facing_dir)
	cam.zoom = Vector2(camera_zoom, camera_zoom)   # knob de zoom (subir = más cerca)
	_setup_light()
	CastShadow.attach(self, body)          # sombra proyectada PRO + contacto (auto-ancla a los pies)
	# Foot-light: el rig se dibuja UNSHADED y se tinta por LightField cada frame,
	# así la luz le llega "por los pies" y la sombra del muro no lo oscurece.
	var fm := CanvasItemMaterial.new()
	fm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	for s in [body, weapon, hand_overlay, staff_arm]:
		if s:
			s.material = fm

func _setup_light() -> void:
	var light := get_node_or_null("Light") as PointLight2D
	if light == null:
		return
	# Charco de luz compartido (elíptico, achatado en Y → vista 3/4).
	var pool := load("res://assets/fx/light_pool.tres") as Texture2D
	if pool != null:
		light.texture = pool
		return
	var s := 256
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	var maxd := s / 2.0
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / maxd
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a   # falloff suave (halo)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	light.texture = ImageTexture.create_from_image(img)

func _load_textures() -> void:
	for i in 9:
		var path := "res://assets/hero/staffs/staff%d.png" % (i + 1)
		_staff_textures.append(_load_runtime_tex(path))
	for godot_dir in HAND_OVERLAY_DIRS:
		var src_name: String = HAND_OVERLAY_DIRS[godot_dir]
		var path := "res://assets/hero/hands/%s.png" % src_name
		_hand_textures[godot_dir] = _load_runtime_tex(path)
	staff_arm.texture = _load_runtime_tex("res://assets/hero/staffarm.png")

func _load_runtime_tex(res_path: String) -> Texture2D:
	# La textura importada ya está en el .pck; load() la trae en cualquier export.
	return load(res_path) as Texture2D

# ---------------- Stats derivados ----------------
func _equip_sum(field: String) -> float:
	var t := 0.0
	for slot in equip:
		var it: Dictionary = equip[slot]
		if field == "def": t += float(it.get("def", 0))
		t += float((it.get("mods", {}) as Dictionary).get(field, 0))
	return t

func max_hp() -> int: return base_max_hp + bonus_hp + int(_equip_sum("hp"))
func move_speed() -> float: return base_speed + spd_add + _equip_sum("spd")
func crit_chance() -> float: return crit + _equip_sum("crit")
func atkspd() -> float: return atkspd_mul + _equip_sum("atkspd") / 100.0
func defense_total() -> int: return defense + int(_equip_sum("def"))

# ---------------- Persistencia (F10) ----------------
func to_save() -> Dictionary:
	return {
		"bonus_hp": bonus_hp, "dmg_mul": dmg_mul, "spd_add": spd_add,
		"crit": crit, "atkspd_mul": atkspd_mul, "defense": defense,
		"hp": hp, "mana": mana, "coins": coins, "xp": xp, "level": level,
		"xp_to_next": xp_to_next, "potions": potions,
		"equip": equip, "bag": bag,
	}

func load_save(d: Dictionary) -> void:
	bonus_hp = int(d.get("bonus_hp", 0))
	dmg_mul = float(d.get("dmg_mul", 1.0))
	spd_add = float(d.get("spd_add", 0.0))
	crit = float(d.get("crit", 8.0))
	atkspd_mul = float(d.get("atkspd_mul", 1.0))
	defense = int(d.get("defense", 0))
	coins = int(d.get("coins", 0))
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	xp_to_next = int(d.get("xp_to_next", 8))
	potions = int(d.get("potions", 1))
	equip = d.get("equip", equip)
	bag = d.get("bag", [])
	hp = mini(int(d.get("hp", max_hp())), max_hp())
	mana = float(d.get("mana", max_mana))
	_refresh_weapon()
	GameState.coins_changed.emit(coins)
	GameState.xp_changed.emit(xp, level)

func _weapon_type_data() -> Dictionary:
	var w = equip.get("arma", null)
	if w and Data.WEAPON_TYPES.has(w.get("weapon_type", "")):
		return Data.WEAPON_TYPES[w.weapon_type]
	return {"cd": 0.28, "mana_cost": 9, "proj_spd": 260}

func attack_damage() -> int:
	var w = equip.get("arma", null)
	var wdmg := int(w.dmg) if w else base_attack_dmg
	return int(round((wdmg + _equip_sum("dmg")) * dmg_mul))

func _staff_tier_index() -> int:
	var w = equip.get("arma", null)
	if w == null:
		return -1
	var mat_id: String = w.get("material", "madera")
	for i in Data.MATERIALS.size():
		if Data.MATERIALS[i].id == mat_id:
			return clampi(i, 0, _staff_textures.size() - 1)
	return 0

func _refresh_weapon() -> void:
	var idx := _staff_tier_index()
	if idx < 0 or _staff_textures.is_empty() or _staff_textures[idx] == null:
		weapon.visible = false
		cur_staff_idx = -1
		return
	if idx == cur_staff_idx:
		return
	cur_staff_idx = idx
	var cfg: Dictionary = Data.STAFF_RIG[idx]
	var grip: Dictionary = cfg.grip
	var focus: Dictionary = cfg.focus
	weapon.texture = _staff_textures[idx]
	# centered=false + offset=-grip → el origen local del Sprite2D queda
	# en el píxel "grip" de la imagen (alineado con la mano).
	weapon.offset = Vector2(-float(grip.x), -float(grip.y))
	weapon.rotation = deg_to_rad(float(cfg.rot_deg))
	# Escala spx/ancho_nativo: normaliza el tamaño (staff5-8 son 128px).
	var tw := _staff_textures[idx].get_width()
	var s := float(cfg.get("spx", tw)) / float(tw) if tw > 0 else 1.0
	weapon.scale = Vector2(s, s)
	weapon.visible = true
	# Tip es hijo del Weapon: su posición es relativa al grip (que es el origen local).
	tip.position = Vector2(float(focus.x) - float(grip.x), float(focus.y) - float(grip.y))

# ---------------- Loop ----------------
func _physics_process(delta: float) -> void:
	rig.modulate = LightField.sample(global_position + Vector2(0, 8.0))
	_tick_timers(delta)
	if dash_t > 0.0:
		velocity = dash_vel
	else:
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = dir * move_speed() + kb
	if dash_t > 0.0:                          # estela fantasma del pixi: 1 partícula/frame
		_spawn_dash_particle()
	kb = kb.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()
	_regen_mana(delta)
	_update_anim()
	if Input.is_action_just_pressed("dash"): _try_dash()
	if Input.is_action_pressed("attack"): _try_attack()
	if Input.is_action_just_pressed("potion"): _use_potion()
	if shake_t > 0.0:
		shake_t -= delta
		cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_amt * (shake_t / 0.25)
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO

func shake(amt := 4.0) -> void:
	shake_amt = amt
	shake_t = 0.25

func _tick_timers(delta: float) -> void:
	atk_cd_t = maxf(0.0, atk_cd_t - delta)
	dash_t = maxf(0.0, dash_t - delta)
	dash_cd_t = maxf(0.0, dash_cd_t - delta)
	ifr = maxf(0.0, ifr - delta)
	no_cast_t += delta

func _regen_mana(delta: float) -> void:
	if no_cast_t > 0.6 and mana < max_mana:
		mana = minf(max_mana, mana + max_mana * 0.28 * delta)

# ---------------- Facing / animación ----------------
# Coordinación pasos↔desplazamiento: la cadencia de la caminata escala con la
# velocidad real (knobs walk_anim_speed / walk_speed_ref, arriba), así un aumento
# de velocidad acelera los pasos en proporción y los pies no "patinan".

func _update_anim() -> void:
	var moving := velocity.length() > 5.0
	Audio.footsteps(moving)
	if Input.is_action_pressed("attack"):
		# Atacando: el cuerpo gira hacia donde apunta el mouse (como el pixi), así los
		# tiros no salen "por la espalda" y queda mirando hacia donde disparó.
		var aim := _aim_dir(global_position)
		if aim != Vector2.ZERO:
			facing_dir = OCTANTS[int(round(aim.angle() / (PI / 4.0)) + 8) % 8]
		_play("walk" if moving else "idle", facing_dir)
	elif moving:
		facing_dir = OCTANTS[int(round(velocity.angle() / (PI / 4.0)) + 8) % 8]
		_play("walk", facing_dir)
	else:
		_play("idle", facing_dir)

func _play(anim_kind: String, dir: String) -> void:
	if anim_kind == "walk":
		# Cadencia ∝ velocidad real → coordinación pasos/desplazamiento. Clamp para
		# evitar pies absurdamente rápidos con mucho stacking de velocidad.
		var ratio := clampf(move_speed() / walk_speed_ref, 0.5, 2.0)
		anim_player.speed_scale = walk_anim_speed * ratio
	else:
		anim_player.speed_scale = 1.0
	# Mirror para w/sw/nw — usamos la animación E/SE/NE con Rig.scale.x negativa.
	var actual_dir: String = FACING_MIRROR.get(dir, dir)
	var mirror: bool = actual_dir != dir
	rig.scale = Vector2(-rig_scale if mirror else rig_scale, rig_scale)
	# Las animaciones del AnimationPlayer se llaman "walk_<dir>" / "idle_<dir>"
	# y por dentro setean el Body al sprite_frames correcto (idle_hold/walk_empty).
	var anim_name := "%s_%s" % [anim_kind, actual_dir]
	if cur_anim == anim_name:
		_refresh_facing_visuals(dir)
		return
	cur_anim = anim_name
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
	_refresh_facing_visuals(dir)

func _refresh_facing_visuals(dir: String) -> void:
	# HandOverlay: visible si la dir tiene overlay propio.
	var overlay_key := dir
	if FACING_MIRROR.has(dir):
		overlay_key = FACING_MIRROR[dir]
	if _hand_textures.has(overlay_key) and _hand_textures[overlay_key] != null:
		hand_overlay.texture = _hand_textures[overlay_key]
		hand_overlay.visible = true
		hand_overlay.centered = true
	else:
		hand_overlay.visible = false
	# Z-order: la vara SIEMPRE está sobre el piso (z=1). Cuando el mago mira
	# para atrás (N/NE/NW) subimos el z del CUERPO para que la tape donde se
	# cruzan (la punta que sobresale igual se ve). No bajamos la vara, porque
	# z negativo la mandaría detrás del TileMapLayer del piso (z=0).
	weapon.z_index = 1
	hand_overlay.z_index = 2
	# Brazo estático en walk de costado: vara(1) < brazo(2) < cuerpo(3 vía anim).
	var side_walk: bool = cur_anim.begins_with("walk") and FACING_MIRROR.get(dir, dir) == "east"
	staff_arm.visible = side_walk
	if side_walk:
		hand_overlay.visible = false
	# El z del CUERPO lo controla el AnimationPlayer por animación y por frame
	# (track Rig/Body:z_index): 0 = vara adelante, 5 = el cuerpo la tapa. Así
	# en walk_east/west el torso esconde el brazo de la vara en los frames en
	# que el brazo va hacia atrás del ciclo de caminata.

# ---------------- Combate ----------------
func _try_dash() -> void:
	if dash_cd_t > 0.0 or dash_t > 0.0: return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = _aim_dir(global_position)
	dash_vel = dir * float(Data.BALANCE.dash_speed)
	dash_t = float(Data.BALANCE.dash_time)
	dash_cd_t = float(Data.BALANCE.dash_cd)
	ifr = maxf(ifr, dash_t + 0.05)
	Audio.play("dash")

## Partícula del dash IDÉNTICA al pixi ("estela fantasma"): cuadradito 2×2 px,
## color #9ab8d8, quieto, alpha ~0.66 que se desvanece en 0.22s. Una por frame.
func _spawn_dash_particle() -> void:
	var s := Sprite2D.new()
	s.texture = _get_px_tex()
	s.scale = Vector2(2, 2)                       # 2×2 px (pixiRect 2×2)
	s.z_index = -3
	s.material = _unshaded_mat()                  # color exacto, sin tinte de luz
	s.modulate = Color(0.60, 0.72, 0.85, 0.66)    # #9ab8d8, alpha = min(1, t*3) inicial
	s.global_position = global_position + Vector2(randf_range(-2.5, 2.5), 4.0 + randf_range(-3.5, 3.5))
	get_parent().add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.22) # vida 0.22s, fade lineal
	tw.tween_callback(s.queue_free)

func _unshaded_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

## Textura 1×1 blanca compartida (se escala a 2×2 y se tinta por modulate).
static func _get_px_tex() -> Texture2D:
	if _px_tex != null:
		return _px_tex
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_px_tex = ImageTexture.create_from_image(img)
	return _px_tex

const MANA_COST_MUL := 0.6   # menos consumo de maná por tiro

func _try_attack() -> void:
	var w := _weapon_type_data()
	var cost := float(w.get("mana_cost", 9)) * MANA_COST_MUL
	if atk_cd_t > 0.0 or mana < cost: return
	atk_cd_t = float(w.get("cd", 0.28)) / atkspd()
	mana -= cost
	no_cast_t = 0.0
	# Modelo 2.5D (pixi): el orbe COLISIONA en el plano de los pies (adelantado en la
	# mira) y se DIBUJA elevado hacia la punta de la vara (z). Así no choca contra un
	# muro que la punta "pisa" visualmente, y su luz cae en el piso.
	var aim := (get_global_mouse_position() - global_position).normalized()
	var tipg := tip.global_position if weapon.visible else global_position
	var spawn := Vector2(tipg.x, global_position.y + 5.0 + aim.y * 6.0)
	var dmg := attack_damage()
	if Rng.unit() * 100.0 < crit_chance(): dmg *= 2
	var p := PROJECTILE.instantiate()
	get_parent().add_child(p)
	p.z_height = clampf(spawn.y - tipg.y, 2.0, 12.0)   # altura visual del orbe (acotada)
	p.setup(spawn, aim, dmg, true, float(w.get("proj_spd", 260)))
	Audio.play("cast", -8.0)   # salida del orbe (sfx 'cast' del pixi)

## Dirección de apuntado: hacia el mouse.
func _aim_dir(from: Vector2) -> Vector2:
	return (get_global_mouse_position() - from).normalized()

func take_damage(amount: int, from_pos: Vector2) -> void:
	if ifr > 0.0: return
	var dealt := maxi(1, int(round(amount * 100.0 / (100.0 + defense_total() * 9.0))))
	hp -= dealt
	ifr = float(Data.BALANCE.player_ifr)
	kb = (global_position - from_pos).normalized() * 150.0
	GameState.floater(global_position, str(dealt), Color(1.0, 0.4, 0.4))
	GameState.player_damaged.emit(dealt)
	Audio.play("hurt")
	shake(5.0)
	if hp <= 0: _die()

func heal(amount: int) -> void: hp = mini(max_hp(), hp + amount)

func add_coins(n: int) -> void:
	coins += n
	GameState.coins_changed.emit(coins)

func gain_xp(amount: int) -> void:
	xp += amount
	var leveled := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = 8 + (level - 1) * 6
		leveled = true
	GameState.xp_changed.emit(xp, level)
	if leveled: _open_upgrade()

func _open_upgrade() -> void:
	var pool := (Data.UPGRADES as Array).duplicate()
	pool.shuffle()
	get_tree().paused = true
	GameState.level_up.emit(pool.slice(0, 3))

func apply_upgrade(id: String) -> void:
	match id:
		"vigor": bonus_hp += 20; hp += 20
		"fuerza": dmg_mul += 0.12
		"celeridad": spd_add += 8.0
		"precision": crit += 6.0
		"frenesi": atkspd_mul += 0.10
		"piel": defense += 3

func pick_up_item(item: Dictionary) -> void:
	var slot: String = item.slot
	var cur = equip.get(slot, null)
	if cur == null:
		equip[slot] = item
		GameState.floater(global_position, "+ " + item.name, Color(0.6, 1, 0.7))
	elif Items.item_score(item) > Items.item_score(cur):
		bag.append(cur)
		equip[slot] = item
		GameState.floater(global_position, "↑ " + item.name, Color(0.5, 0.9, 1))
	else:
		bag.append(item)
		GameState.floater(global_position, "→ bolsa", Color(0.8, 0.8, 0.8))
	hp = mini(hp, max_hp())
	if slot == "arma":
		_refresh_weapon()

func equip_from_bag(index: int) -> void:
	if index < 0 or index >= bag.size(): return
	var item: Dictionary = bag[index]
	bag.remove_at(index)
	var slot: String = item.slot
	var cur = equip.get(slot, null)
	equip[slot] = item
	if cur != null: bag.append(cur)
	hp = mini(hp, max_hp())
	if slot == "arma":
		_refresh_weapon()

func _use_potion() -> void:
	if potions > 0 and hp < max_hp():
		potions -= 1
		heal(int(Data.BALANCE.heart_heal) + 8)

func _die() -> void:
	hp = 0
	Audio.footsteps(false)
	GameState.set_mode(GameState.Mode.DEAD)
	GameState.player_died.emit()
	set_physics_process(false)
	GameState.floater(global_position, "MUERTO", Color(1, 0.2, 0.2))
