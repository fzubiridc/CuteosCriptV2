extends CharacterBody2D
class_name Player
## Jugador — F8a-2: rig con cuerpo-sin-arma (walk_empty/idle_hold) + Weapon
## intercambiable. Para west/sw/nw espejamos el Rig (mirror), así reutilizamos
## las 5 dirs base de walk_empty. El proyectil sale de Tip (punta del staff).

const PROJECTILE := preload("res://scenes/projectile.tscn")
const AOE := preload("res://scripts/aoe.gd")
@export var camera_zoom := 4.0   # knob de zoom de cámara (3 = original, más = más cerca)
@export var rig_scale := 0.36    # escala visual del rig (achicado un toque; 0.4 era el anterior)

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
var aoe_cd_t := 0.0
var dash_vel := Vector2.ZERO

# --- Barra de habilidades (slots clásicos 1-4, ver AbilityDefs) ---
var skill_slots: Array = AbilityDefs.DEFAULT_SLOTS.duplicate()   # ids de habilidad por slot ("" = vacío)
var skill_cd := [0.0, 0.0, 0.0, 0.0]                             # cooldown restante por slot
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
	# Cámara fija al jugador: el mago queda clavado en el centro y el mapa se desliza.
	# Sin límites ni suavizado → centrado pixel-perfect (no se despega del centro).
	cam.position_smoothing_enabled = false
	cam.ignore_rotation = true
	cam.make_current()
	_setup_light()
	_apply_feet_anchor()                   # ancla unificada (luz+sombra+proyección) + knob feet_y
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
	_apply_light_tex(light)
	# Regenerar el charco en vivo al mover el knob de suavidad (tecla L).
	if not LightCfg.changed.is_connected(_on_light_cfg_changed):
		LightCfg.changed.connect(_on_light_cfg_changed)

func _on_light_cfg_changed() -> void:
	var light := get_node_or_null("Light") as PointLight2D
	if light:
		_apply_light_tex(light)
	_apply_feet_anchor()

## Ancla de los pies = marcador Feet en (0, FEET_BASE_Y + knob feet_y). Mueve el marcador (la
## sombra de contacto y la proyección al muro lo leen cada frame → lo siguen) y resincroniza la
## luz a ese punto. Un solo knob (feet_y, tecla L) baja/sube los tres juntos.
const FEET_BASE_Y := 4.0
func _apply_feet_anchor() -> void:
	var feet := get_node_or_null("Feet") as Node2D
	if feet == null:
		return
	feet.position = Vector2(0, FEET_BASE_Y + LightCfg.get_v("feet_y"))
	var light := get_node_or_null("Light") as Node2D
	if light:
		light.position = feet.position

## player_soft = 2.0 (default) → usa el charco HORNEADO (look actual intacto). Si lo movés, genera
## el charco por código desde la curva (1-d)^player_soft → manejás el difuminado del charco del piso.
func _apply_light_tex(light: PointLight2D) -> void:
	var p := LightCfg.get_v("player_soft")
	if absf(p - 2.0) < 0.01:
		var pool := load("res://assets/fx/light_pool.tres") as Texture2D
		if pool != null:
			light.texture = pool
			return
	# Charco elíptico (achatado en Y → vista 3/4) con caída GAUSSIANA: el perímetro se DIFUMINA en
	# vez de cortar en un círculo nítido (lo que pidió Felipe). La pow(1-d,p) anterior, aun en su
	# máximo (p=4), dejaba un borde demasiado definido. La gaussiana tiene una cola larga y suave;
	# le restamos el valor del borde para que llegue a 0 sin dejar un anillo en el límite de la
	# textura. player_soft controla el ancho (sigma): más alto = más difuso/extendido.
	# RGBAH (half float) en vez de RGBA8: con 8 bits el degradé gaussiano quantiza en escalones y,
	# como el light_pool se samplea NEAREST y escalado, esos escalones se ven como ANILLOS
	# concéntricos. En punto flotante cada texel difiere apenas → degradé continuo, sin aros.
	var s := 320
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBAH)
	var c := Vector2(s / 2.0, s / 2.0)
	var maxd := s / 2.0
	var sigma := clampf(0.12 * p, 0.12, 0.9)          # p=4 → 0.48 (bien difuso); p=8 → 0.9
	var two_sig2 := 2.0 * sigma * sigma
	var edge := exp(-1.0 / two_sig2)                  # valor en el borde → restado para llegar a 0 sin anillo
	var inv := 1.0 / maxf(1.0 - edge, 0.0001)
	for y in s:
		for x in s:
			var off := Vector2(x, y) - c
			off.y *= 2.0   # achatado Y (mismo look 3/4 que el charco horneado)
			var d := off.length() / maxd
			var g := exp(-(d * d) / two_sig2)
			var a := clampf((g - edge) * inv, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	light.texture = ImageTexture.create_from_image(img)

func _load_textures() -> void:
	# Carga dinámica: staff1.png, staff2.png, … hasta que falte una (soporta varas
	# nuevas insertadas desde el rigtool sin tocar código). Requiere que Godot ya
	# las haya importado (al parar el play o reenfocar el editor).
	var si := 1
	while ResourceLoader.exists("res://assets/hero/staffs/staff%d.png" % si):
		_staff_textures.append(_load_runtime_tex("res://assets/hero/staffs/staff%d.png" % si))
		si += 1
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
		"equip": equip, "bag": bag, "skill_slots": skill_slots,
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
	var saved_slots: Variant = d.get("skill_slots", null)
	if saved_slots is Array and saved_slots.size() == skill_slots.size():
		skill_slots = (saved_slots as Array).duplicate()
	hp = mini(int(d.get("hp", max_hp())), max_hp())
	mana = float(d.get("mana", max_mana))
	_refresh_weapon()
	GameState.coins_changed.emit(coins)
	GameState.xp_changed.emit(xp, level)
	GameState.skills_changed.emit()

func _weapon_type_data() -> Dictionary:
	var w = equip.get("arma", null)
	if w and Data.WEAPON_TYPES.has(w.get("weapon_type", "")):
		return Data.WEAPON_TYPES[w.weapon_type]
	return {"cd": 0.28, "mana_cost": 9, "proj_spd": 260}

func attack_damage() -> int:
	var w = equip.get("arma", null)
	var wdmg := int(w.dmg) if w else base_attack_dmg
	return int(round((wdmg + _equip_sum("dmg")) * dmg_mul))

## DEBUG (panel tecla J): -1 = normal (según material); >=0 fuerza esa vara para previsualizarla.
var debug_staff_idx: int = -1

func _staff_tier_index() -> int:
	if debug_staff_idx >= 0 and not _staff_textures.is_empty():
		return clampi(debug_staff_idx, 0, _staff_textures.size() - 1)
	var w = equip.get("arma", null)
	if w == null:
		return -1
	var mat_id: String = w.get("material", "madera")
	for i in Data.MATERIALS.size():
		if Data.MATERIALS[i].id == mat_id:
			return clampi(i, 0, _staff_textures.size() - 1)
	return 0

## DEBUG: fuerza la vara i (o -1 = normal) y refresca al toque (invalida el cache).
func debug_set_staff(i: int) -> void:
	debug_staff_idx = i
	cur_staff_idx = -1
	_refresh_weapon()

func debug_staff_count() -> int:
	return _staff_textures.size()

## Rig de la vara idx: Data.STAFF_RIG si existe, o un default razonable (grip centro-abajo,
## gema arriba) para varas nuevas todavía sin riggear → una vara recién insertada ya funciona.
func _staff_rig(idx: int) -> Dictionary:
	if idx >= 0 and idx < Data.STAFF_RIG.size():
		return Data.STAFF_RIG[idx]
	var tex: Texture2D = _staff_textures[idx] if idx >= 0 and idx < _staff_textures.size() else null
	var w: int = tex.get_width() if tex != null else 24
	var h: int = tex.get_height() if tex != null else 24
	return {"grip": {"x": int(w * 0.5), "y": int(h * 0.72)}, "focus": {"x": int(w * 0.5), "y": int(h * 0.12)}, "rot_deg": 0, "spx": w}

func _refresh_weapon() -> void:
	var idx := _staff_tier_index()
	if idx < 0 or _staff_textures.is_empty() or _staff_textures[idx] == null:
		weapon.visible = false
		cur_staff_idx = -1
		_staff_anim_frames.clear()
		return
	if idx == cur_staff_idx:
		return
	cur_staff_idx = idx
	var cfg: Dictionary = _staff_rig(idx)
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
	_load_staff_anim(idx)
	_load_staff_bolt(idx)

## Animación propia de la vara: si existe assets/hero/staffs/staffN_anim/frame_000.png…,
## los carga y _tick_staff_anim cicla weapon.texture sobre ellos. Mismas dims que la estática
## (así el grip/escala del rig siguen valiendo). Sin carpeta _anim → vara estática.
var _staff_anim_frames: Array = []
var _staff_anim_t := 0.0
var _staff_anim_playing := false          # la anim de la vara solo corre MIENTRAS atacás
var _staff_static_tex: Texture2D = null   # textura estática a la que se vuelve al terminar
var _staff_anim_fps := 18.0               # fps de la vara activa (Data.STAFF_ANIM_FPS, default 18)
# Bolt propio de la vara (staffN_bolt/travel|impact): si la vara tiene estas carpetas, el
# proyectil usa estos frames (fuego, etc.) en vez del orbe azul. Vacío → orbe azul.
var _bolt_travel_frames: Array = []
var _bolt_impact_frames: Array = []
var _bolt_scale_mul := 1.0                 # escala del bolt de la vara activa (Data.STAFF_BOLT_SCALE, default 1.0 = tamaño auto)
var _spell_profile: ElementProfile = null  # FX de la vara (tool "Hechizos"); null si la vara no esta configurada

func _load_staff_anim(idx: int) -> void:
	_staff_anim_frames.clear()
	_staff_anim_t = 0.0
	_staff_anim_playing = false
	_staff_static_tex = _staff_textures[idx] if idx >= 0 and idx < _staff_textures.size() else null
	_staff_anim_fps = float(Data.STAFF_ANIM_FPS.get(idx, 18.0))
	var i := 0
	while ResourceLoader.exists("res://assets/hero/staffs/staff%d_anim/frame_%03d.png" % [idx + 1, i]):
		_staff_anim_frames.append(_load_runtime_tex("res://assets/hero/staffs/staff%d_anim/frame_%03d.png" % [idx + 1, i]))
		i += 1

## Carga el bolt propio de la vara (assets/hero/staffs/staffN_bolt/travel|impact/frame_000.png…).
## Si la carpeta existe, el proyectil usa estos frames; si no, queda el orbe azul. N = idx + 1.
func _load_staff_bolt(idx: int) -> void:
	_bolt_travel_frames.clear()
	_bolt_impact_frames.clear()
	_bolt_scale_mul = float(Data.STAFF_BOLT_SCALE.get(idx, 1.0))   # 1.0 = tamaño auto (default)
	if idx < 0:
		return
	var i := 0
	while ResourceLoader.exists("res://assets/hero/staffs/staff%d_bolt/travel/frame_%03d.png" % [idx + 1, i]):
		_bolt_travel_frames.append(_load_runtime_tex("res://assets/hero/staffs/staff%d_bolt/travel/frame_%03d.png" % [idx + 1, i]))
		i += 1
	i = 0
	while ResourceLoader.exists("res://assets/hero/staffs/staff%d_bolt/impact/frame_%03d.png" % [idx + 1, i]):
		_bolt_impact_frames.append(_load_runtime_tex("res://assets/hero/staffs/staff%d_bolt/impact/frame_%03d.png" % [idx + 1, i]))
		i += 1
	SpellLibrary.reload()   # relee spells.json: editar la tool + reiniciar la corrida ya se ve (sin recompilar)
	_spell_profile = SpellLibrary.get_profile(idx)   # FX de la vara (estela/particulas); null si no esta en la tool
	if _spell_profile != null and _spell_profile.bolt_scale > 0.0:
		_bolt_scale_mul = _spell_profile.bolt_scale   # escala del bolt: la tab "Hechizos" (sViaje) manda sobre el auto

func _tick_staff_anim(delta: float) -> void:
	if _staff_anim_frames.is_empty() or not weapon.visible or not _staff_anim_playing:
		return
	_staff_anim_t += delta
	var total := float(_staff_anim_frames.size()) / _staff_anim_fps
	if _staff_anim_t >= total:   # terminó el ciclo → vuelve a la vara estática
		_staff_anim_playing = false
		if _staff_static_tex != null:
			weapon.texture = _staff_static_tex
		return
	weapon.texture = _staff_anim_frames[int(_staff_anim_t * _staff_anim_fps) % _staff_anim_frames.size()]

# ---------------- Loop ----------------
func _physics_process(delta: float) -> void:
	rig.modulate = LightField.sample(global_position + Vector2(0, 8.0))
	_tick_timers(delta)
	if dash_t > 0.0:
		velocity = dash_vel
	else:
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Espacio isométrico 2:1 (tile 256×128) — comprimir el eje Y a la mitad
		# (128/256) para que las diagonales sigan las aristas de los rombos, y
		# normalizar para que la velocidad sea pareja en todas las direcciones.
		var iso := Vector2(dir.x, dir.y * 0.5)
		velocity = iso.normalized() * move_speed() + kb
	if dash_t > 0.0:                          # estela fantasma del pixi: 1 partícula/frame
		_spawn_dash_particle()
	kb = kb.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()
	_regen_mana(delta)
	_update_anim()
	_tick_staff_anim(delta)
	if Input.is_action_just_pressed("dash"): _try_dash()
	if Input.is_action_pressed("attack"): _try_attack()
	if Input.is_action_just_pressed("potion"): _use_potion()
	# Barra de habilidades (slots 1-4). El Meteoro/AoE migró acá (slot 1); E quedó solo para
	# interactuar (cofres/mercader, que escuchan E ellos mismos).
	for i in 4:
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			_cast_slot(i)
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
	aoe_cd_t = maxf(0.0, aoe_cd_t - delta)
	dash_t = maxf(0.0, dash_t - delta)
	dash_cd_t = maxf(0.0, dash_cd_t - delta)
	ifr = maxf(0.0, ifr - delta)
	no_cast_t += delta
	for i in skill_cd.size():
		if skill_cd[i] > 0.0:
			skill_cd[i] = maxf(0.0, skill_cd[i] - delta)

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
	s.material = FxMaterials.mix_unshaded()        # color exacto, sin tinte de luz (material compartido)
	s.modulate = Color(0.60, 0.72, 0.85, 0.66)    # #9ab8d8, alpha = min(1, t*3) inicial
	s.global_position = global_position + Vector2(randf_range(-2.5, 2.5), 4.0 + randf_range(-3.5, 3.5))
	get_parent().add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.22) # vida 0.22s, fade lineal
	tw.tween_callback(s.queue_free)

## Textura 1×1 blanca compartida (se escala a 2×2 y se tinta por modulate).
static func _get_px_tex() -> Texture2D:
	if _px_tex != null:
		return _px_tex
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_px_tex = ImageTexture.create_from_image(img)
	return _px_tex

const MANA_COST_MUL := 0.6   # menos consumo de maná por tiro
const MIN_BOLT_RANGE := 80.0   # piso de distancia de aterrizaje del bolt (que el arco se note)

func _try_attack() -> void:
	var w := _weapon_type_data()
	var cost := float(w.get("mana_cost", 9)) * MANA_COST_MUL
	if atk_cd_t > 0.0 or mana < cost: return
	atk_cd_t = float(w.get("cd", 0.28)) / atkspd()
	if not _staff_anim_frames.is_empty():   # dispara el destello/animación de la vara
		_staff_anim_playing = true
		_staff_anim_t = 0.0
	mana -= cost
	no_cast_t = 0.0
	# Modelo 2.5D (pixi): el orbe COLISIONA en el plano de los pies y se DIBUJA elevado.
	# ARQUEA hacia el punto del piso bajo el cursor: nace en la punta (alto) y baja hasta
	# tocar el piso en el objetivo, donde su luz/sombra (que va en el piso) converge con el
	# orbe. La colisión sigue en el plano de los pies (no choca muros que la punta "pisa");
	# como el orbe ya viene bajando, el impacto a un mob se ve a su altura, no flotando.
	var target := get_global_mouse_position()
	var tipg := tip.global_position if weapon.visible else global_position
	var aim := (target - global_position).normalized()
	# Origen de la colisión: pies bajo la punta (adelantado un toque en la mira).
	var spawn := Vector2(tipg.x, global_position.y + 5.0 + aim.y * 6.0)
	# Vuelo hacia el punto del piso clickeado; piso de distancia para que el arco se note.
	var to_target := target - spawn
	var dir := to_target.normalized() if to_target.length() > 0.001 else aim
	var land := maxf(to_target.length(), MIN_BOLT_RANGE)
	var is_crit := Rng.unit() * 100.0 < crit_chance()
	var dmg := attack_damage()
	if is_crit: dmg *= 2
	var p := PROJECTILE.instantiate()
	get_parent().add_child(p)
	# Altura visual inicial = gap real pies→punta (SIN tope: el viejo clamp 12+rig_scale*32
	# se quedaba corto con rig_scale=0.8). El arco la baja de z0 (punta) a 0 (objetivo).
	var z0 := maxf(2.0, spawn.y - tipg.y)
	p.z_height = z0
	if Dungeon.ISO:
		p.scale = Vector2(1.6, 1.6)   # orbe más grande para el zoom-out iso
	p.setup(spawn, dir, dmg, true, float(w.get("proj_spd", 260)))
	p.set_arc(z0, land)               # baja de z0 (punta) a 0 (objetivo del piso)
	p.is_crit = is_crit               # número de daño dorado si crittea
	if not _bolt_travel_frames.is_empty():   # vara con bolt propio (fuego, etc.) → reemplaza el orbe azul
		p.set_bolt_frames(_bolt_travel_frames, _bolt_impact_frames, _bolt_scale_mul)   # escala por vara (rigtool)
	if _spell_profile != null:   # FX nuevo de la vara (estela/particulas), SIN pisar el bolt
		p.set_element(_spell_profile)
	Audio.play("cast", -8.0)   # salida del orbe (sfx 'cast' del pixi)

# --- Ataque de área (E) -----------------------------------------------------
const AOE_COST := 35.0    # maná
const AOE_CD := 0.5       # cooldown s
const AOE_DMG_MUL := 2.0  # pega más fuerte que el bolt normal (es habilidad con cooldown)
						  # (tamaño/achatado del AoE salen de assets/fx/aoe_config.json)

## ¿Hay algún objeto interactuable (cofre/mercader) disponible en rango? Si sí, E hace
## interact (lo maneja el objeto) y NO casteamos el AoE. Reusa el grupo "interactable".
func _interactable_near() -> bool:
	for n in get_tree().get_nodes_in_group("interactable"):
		if is_instance_valid(n) and n.has_method("interactable_now") and n.interactable_now():
			return true
	return false

## Planta el AoE bajo el cursor (targeted). Cuesta maná + cooldown, como los otros ataques.
func _try_aoe() -> void:
	if aoe_cd_t > 0.0 or mana < AOE_COST: return
	aoe_cd_t = AOE_CD
	mana -= AOE_COST
	no_cast_t = 0.0
	var a := AOE.new()
	get_parent().add_child(a)
	a.setup(get_global_mouse_position(), int(attack_damage() * AOE_DMG_MUL), 1.0)

# --- Barra de habilidades --------------------------------------------------------
## Dispara la habilidad del slot i (0-3) si está lista (cooldown) y hay maná. El cooldown y
## el coste salen de AbilityDefs; el EFECTO de cada id vive en _cast_ability (un solo lugar).
func _cast_slot(i: int) -> void:
	if i < 0 or i >= skill_slots.size():
		return
	var id: String = skill_slots[i]
	if id == "" or not AbilityDefs.has(id):
		return
	if skill_cd[i] > 0.0:
		return
	var d := AbilityDefs.get_def(id)
	var cost := float(d.get("mana", 0.0))
	if mana < cost:
		return
	if not _cast_ability(id):   # la habilidad puede abortar (heal a vida llena, sin dirección…)
		return
	mana -= cost
	skill_cd[i] = float(d.get("cooldown", 0.0))
	no_cast_t = 0.0

## Efecto de cada habilidad. Devuelve true si se ejecutó (consume maná + dispara cooldown).
func _cast_ability(id: String) -> bool:
	match id:
		"meteor":
			var a := AOE.new()
			get_parent().add_child(a)
			a.setup(get_global_mouse_position(), int(attack_damage() * AOE_DMG_MUL), 1.0)
			return true
		"nova":
			# Orbes arcanos en abanico completo (achatados al plano iso). Vuelan rectos.
			var n := 14
			for k in n:
				var ang := TAU * float(k) / float(n)
				var dir := Vector2(cos(ang), sin(ang) * 0.5)
				if dir.length() < 0.001:
					continue
				var p := PROJECTILE.instantiate()
				get_parent().add_child(p)
				if Dungeon.ISO:
					p.scale = Vector2(1.4, 1.4)
				p.setup(global_position + Vector2(0, 4.0), dir.normalized(), attack_damage(), true, 230.0)
			Audio.play("cast", -4.0)
			return true
		"heal":
			if hp >= max_hp():
				return false
			var amt := int(max_hp() * 0.35)
			heal(amt)
			GameState.floater(global_position, "+%d" % amt, Color(0.6, 1.0, 0.7))
			Audio.play("heal")
			return true
		"blink":
			var dir := _aim_dir(global_position)
			if dir == Vector2.ZERO:
				return false
			# Reusa la mecánica del dash (move_and_slide → no atraviesa muros), más rápido/largo.
			dash_vel = Vector2(dir.x, dir.y * 0.5).normalized() * (float(Data.BALANCE.dash_speed) * 1.45)
			dash_t = 0.16
			ifr = maxf(ifr, dash_t + 0.06)
			Audio.play("dash")
			return true
		"frost":
			# Estallido glacial: daño + empuje en un radio alrededor del jugador, con anillo visual.
			var r := 160.0
			var dmg := int(attack_damage() * 1.6)
			for nn in get_parent().get_children():
				if (nn is Enemy or nn is Boss) and is_instance_valid(nn):
					var off: Vector2 = (nn as Node2D).global_position - global_position
					if off.length() < r:
						nn.take_damage(dmg, off.normalized() * 130.0, false, Color(0.6, 0.92, 1.0))
			_spawn_frost_ring(r)
			Audio.play("boom", -6.0)
			return true
		"dash":
			_try_dash()
			return false   # el dash maneja su propio cooldown/feel; el slot no lo duplica
	return false

## Anillo de escarcha que se expande y se desvanece (visual del Estallido Glacial).
func _spawn_frost_ring(radius: float) -> void:
	var ring := Sprite2D.new()
	ring.texture = load("res://assets/fx/light_radial.tres")
	ring.material = FxMaterials.add_unshaded()
	ring.modulate = Color(0.6, 0.92, 1.0, 0.85)
	ring.z_index = 5
	ring.global_position = global_position + Vector2(0, 4.0)
	ring.scale = LightCfg.floor_scale() * 0.2
	get_parent().add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", LightCfg.floor_scale() * (radius / 80.0), 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.34).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)

## Asigna una habilidad a un slot (panel de habilidades). id="" limpia el slot.
func assign_skill(slot: int, id: String) -> void:
	if slot < 0 or slot >= skill_slots.size():
		return
	skill_slots[slot] = id
	GameState.skills_changed.emit()

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
