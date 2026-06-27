extends CharacterBody2D
class_name Enemy
## Enemigo data-driven. IAs: chaser/erratic/shooter. Aggro híbrido.
## F8b: sprite real (AnimatedSprite2D) para los mobs sheet; fallback a
## Polygon2D de color para los tipos sin sprite aún.

const TILE := 16.0
const PROJECTILE := preload("res://scenes/projectile.tscn")
# type de Data.ENEMIES -> set de sprites en res://assets/mobs/<set>_frames.tres
const SPRITE_SETS := {"slime": "slime", "lich": "lich", "fantasma": "ghost", "zombi": "zombie", "orco": "orc", "rata": "rata", "murcielago": "murcielago", "arana": "arana", "golem_chico": "golem", "espectro": "espectro", "cultista": "cultista", "caballero": "caballero", "arana_v2": "arana_v2"}

var type_key := "rata"
var ai := "chaser"
var max_hp := 30
var damage := 8
var speed := 60.0
var size := 8.0
var _shadow_attached := false
var atk_range := 0.0
var fire_cd := 1.5
var proj_spd := 150.0
var elite := false
var base_color := Color(0.85, 0.3, 0.35)
var use_sprite := false
var face := "south"

var home_pos := Vector2.ZERO
var home_rect := Rect2()

var hp := 30
var kb := Vector2.ZERO   # empuje (knockback) que decae cada frame
var _shadow: CastShadow   # sombra de contacto (para apagar su _process al dormir)
var _sleeping := false    # mob lejano "dormido" (gating de performance)
const WAKE_RANGE := 650.0 # distancia al jugador para activarse (más allá: duerme). Iso zoom-out: cubre la pantalla.
var aggro := false
var hit_cd := 0.0
var flash_t := 0.0
var fire_t := 0.0
var wander_t := 0.0
var wander_target := Vector2.ZERO
var wobble := 0.0

# --- IA melee ARPG (mini-FSM por timers) ---
enum St { CHASE, WINDUP, RECOVER }
var st: int = St.CHASE
var st_t := 0.0                 # timer del estado actual
var windup := 0.25             # telegraph (frenado) antes de pegar (s)
var recover := 0.35            # vulnerable (frenado) después de pegar (s)
var atk_enter := 0.0           # rango para ENTRAR a windup
var atk_exit := 0.0            # rango para SALIR de combate (atk_enter < atk_exit → histéresis)
var slot_dist := 26.0          # radio del anillo de cerco alrededor del player (no apilarse)
var _slot_ang := 0.0           # ángulo fijo de mi slot
const MELEE_PAD := 6.0
var _glow: PointLight2D = null  # aura propia (hija): ilumina el piso Y al propio mob (foot-light)
# Self-light: el sprite del mob se dibuja con entity_material (luz por píxel, mismo shader
# que los muros). Sin una luz propia con ALTURA, el aura del piso casi no lo aclara y el mob
# se ve negro de lejos (a diferencia del player, cuya Light tiene height ~24 → se autoilumina
# siempre). Estos pisos garantizan que el aura ilumine bien al sprite aunque los knobs del
# piso (mob_glow_*) estén bajos; no bajan lo que el usuario suba, solo ponen un mínimo.
const GLOW_HEIGHT := 22.0      # altura de la luz propia (≈ player_height) → ilumina el cuerpo, no solo el piso
const GLOW_MIN_ENERGY := 1.3   # energía efectiva mínima del aura para autoiluminar el sprite
const GLOW_MIN_RADIUS := 0.62  # texture_scale mínimo → alcanza toda la altura del sprite
# Cache de knobs del aura (antes se leían por frame en _physics_process). Se refrescan
# SOLO cuando LightCfg emite "changed" (ver _apply_light_cfg), igual que torch.gd.
var _k_glow_energy := 0.9
var _k_glow_radius := 0.5
var _k_reveal_dist := 220.0   # cache de mob_reveal_dist (antes se leía por frame en _physics_process)

# Director de combate: limita cuántos mobs golpean a la vez (static, compartido por todos).
static var _atk_active: Dictionary = {}   # instance_id → true
const MAX_ATTACKERS := 3

## Proveedor de rutas por grilla (AStarGrid2D del nivel iso). Si está seteado
## (lo pone iso_procgen), los mobs rutean por la grilla esquivando muros. En el
## juego 2D queda null → usan el NavigationAgent2D de siempre.
static var path_grid = null

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var visual: Polygon2D = $Visual
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hpbar = $HealthBar   # HealthBar (sin tipar: evita depender del registro de class_name)

func _ready() -> void:
	add_to_group("enemies")   # grupo consumido por otros sistemas (spawner/targeting)
	wander_target = home_pos
	agent.path_desired_distance = 4.0
	agent.target_desired_distance = 6.0
	# Cache inicial de knobs del aura + suscripción a cambios en vivo (panel tecla L).
	_apply_light_cfg()
	LightCfg.changed.connect(_apply_light_cfg)

## Refresca el cache de knobs del aura. Se llama en _ready y luego SOLO cuando
## LightCfg emite "changed" → _physics_process deja de hacer get_v() por frame.
func _apply_light_cfg() -> void:
	# El aura sirve para DOS cosas: pintar el charco del piso (lo gobierna el knob) y autoiluminar
	# al propio mob. Para lo segundo aplicamos un piso (maxf) → el sprite se ve bien aunque el knob
	# del piso esté bajo, sin pisar lo que el usuario suba.
	_k_glow_energy = maxf(LightCfg.get_v("mob_glow_energy"), GLOW_MIN_ENERGY)
	_k_glow_radius = maxf(LightCfg.get_v("mob_glow_radius"), GLOW_MIN_RADIUS)
	_k_reveal_dist = LightCfg.get_v("mob_reveal_dist")   # cacheado: lo usa el auto-revelado por frame
	if _glow != null:
		_glow.energy = _k_glow_energy
		_glow.texture_scale = _k_glow_radius
		_glow.height = GLOW_HEIGHT

func setup_type(key: String, is_elite := false) -> void:
	type_key = key
	var d: Dictionary = Data.ENEMIES.get(key, {})
	ai = String(d.get("ai", "chaser"))
	max_hp = int(d.get("hp", 30))
	damage = int(d.get("dmg", 8))
	speed = float(d.get("spd", 60)) * float(Data.BALANCE.speed_mul)
	size = float(d.get("size", 8))
	atk_range = float(d.get("range", 0.0))
	fire_cd = float(d.get("fire_cd", 1.5))
	proj_spd = float(d.get("proj_spd", 150.0))
	elite = is_elite
	if elite:
		max_hp = int(max_hp * 1.5)
		damage = int(damage * 1.3)
		size *= 1.3
	hp = max_hp
	# IA: slot de cerco (anillo determinista por instancia) + stats de combate por tipo.
	_slot_ang = float(get_instance_id() % 360) * (TAU / 360.0)
	windup = float(d.get("windup", _ai_default_windup()))
	recover = float(d.get("recover", _ai_default_recover()))
	slot_dist = float(d.get("slot_dist", size + 14.0))
	var reach := size + 10.0 + MELEE_PAD
	atk_enter = float(d.get("atk_enter", reach + 4.0))
	atk_exit = float(d.get("atk_exit", reach + 22.0))   # atk_enter < atk_exit → histéresis (no vibra)
	visible = false   # se auto-revela en _physics_process por distancia (no lo gatea el manager)
	_apply_visual()

func _apply_visual() -> void:
	base_color = _ai_color()
	if sprite.material == null:   # luz POR PÍXEL (mismo shader unshaded que las caras de muro)
		sprite.material = LightField.entity_material
		visual.material = LightField.entity_material
	var sprite_set: String = SPRITE_SETS.get(type_key, "")
	if sprite_set != "":
		var sf
		if sprite_set.begins_with("arana_"):
			sf = _get_spider_frames(sprite_set)   # construido por código desde el sheet
		else:
			sf = load("res://assets/mobs/%s_frames.tres" % sprite_set)
		if sf != null:
			sprite.sprite_frames = sf
			var fh := 64.0
			var t0 = sf.get_frame_texture("idle_south", 0)
			if t0 != null:
				fh = float(t0.get_height())
			var s := (size * 2.6) / fh
			sprite.scale = Vector2(s, s)
			sprite.modulate = _idle_tint()
			sprite.visible = true
			visual.visible = false
			use_sprite = true
			sprite.play("idle_south")
	if not use_sprite:
		visual.visible = true
		visual.color = base_color
		visual.polygon = PackedVector2Array([
			Vector2(-size, -size), Vector2(size, -size),
			Vector2(size, size), Vector2(-size, size)])
	var sh := CircleShape2D.new()
	sh.radius = size
	$Shape.shape = sh

	# Barra de vida fina sobre la cabeza (ancho ∝ tamaño; arriba del sprite/polígono).
	if hpbar:
		hpbar.width = size * 2.2
		hpbar.position = Vector2(0, -(size * 1.3 + 8.0))

	# Sombra: proyectada PRO (silueta) si hay sprite; de contacto si es polígono.
	if not _shadow_attached:
		_shadow_attached = true
		if use_sprite:
			_shadow = CastShadow.attach(self, sprite, size, false)   # mobs: solo sombra circular (sin proyectada)
		else:
			FootShadow.attach(self, size * 0.9, size * 2.2)

	# Aura propia (luz suave hija): ilumina el piso alrededor → presencia visible en la oscuridad.
	if _glow == null:
		_glow = PointLight2D.new()
		_glow.texture = load("res://assets/fx/light_radial.tres")
		_glow.color = Color(1, 0.86, 0.62); _glow.scale = LightCfg.floor_scale(); LightField.add_dynamic(_glow)   # = luz del jugador (player.tscn) + achatado elíptico (vista 3/4), como las otras luces de piso
		add_child(_glow)
	_glow.energy = _k_glow_energy            # cacheados (refrescados vía LightCfg.changed)
	_glow.texture_scale = _k_glow_radius
	_glow.height = GLOW_HEIGHT               # altura → el shader por píxel ilumina el cuerpo del mob, no solo el piso

func _idle_tint() -> Color:
	return Color(1.0, 0.92, 0.6) if elite else Color.WHITE

# --- Arañas: SpriteFrames por código desde un sheet RPGM 3 col × 4 fila.
# Filas: 0=south, 1=west, 2=east, 3=north. walk = 3 frames en loop; idle = frame medio. ---
static var _spider_cache := {}
static var _spider_sheets := {}
const SPIDER_ROWS := {"south": 0, "west": 1, "east": 2, "north": 3}

static func _get_spider_frames(setname: String) -> SpriteFrames:
	if _spider_cache.has(setname):
		return _spider_cache[setname]
	var sheet := _spider_sheet(setname)
	var sf := SpriteFrames.new()
	if sheet != null:
		@warning_ignore("integer_division")
		var fw := sheet.get_width() / 3
		@warning_ignore("integer_division")
		var fh := sheet.get_height() / 4
		for kind in ["idle", "walk"]:
			for dir in SPIDER_ROWS:
				var row: int = SPIDER_ROWS[dir]
				var an := "%s_%s" % [kind, dir]
				sf.add_animation(an)
				sf.set_animation_speed(an, 8.0)
				sf.set_animation_loop(an, true)
				if kind == "walk":
					for col in [0, 1, 2]:
						sf.add_frame(an, _spider_atlas(sheet, fw, fh, col, row))
				else:
					sf.add_frame(an, _spider_atlas(sheet, fw, fh, 1, row))   # idle = frame del medio
	_spider_cache[setname] = sf
	return sf

static func _spider_atlas(sheet: Texture2D, fw: int, fh: int, col: int, row: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(col * fw, row * fh, fw, fh)
	return at

## Sheet del color (cacheado). Fallback a carga cruda si el editor no lo importó aún.
static func _spider_sheet(setname: String) -> Texture2D:
	if _spider_sheets.has(setname):
		return _spider_sheets[setname]
	var path := "res://assets/mobs/spiders/%s.png" % setname
	var tex := load(path) as Texture2D
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_spider_sheets[setname] = tex
	return tex

func _ai_color() -> Color:
	var c := Color(0.85, 0.3, 0.35)
	match ai:
		"erratic": c = Color(0.7, 0.4, 0.9)
		"shooter": c = Color(0.95, 0.6, 0.2)
	if elite:
		c = c.lerp(Color(1.0, 0.95, 0.5), 0.4)
	return c

func _physics_process(delta: float) -> void:
	hit_cd = maxf(0.0, hit_cd - delta)
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		if flash_t == 0.0:
			if st == St.WINDUP:
				_set_telegraph(true)   # un flash de daño no debe borrar el telegraph
			elif use_sprite:
				sprite.modulate = _idle_tint()
			else:
				visual.color = base_color

	var player := GameState.player
	if player == null:
		return
	var ppos: Vector2 = player.global_position
	var to_player := global_position.distance_to(ppos)

	# Gating: los mobs lejanos "duermen" (sin pathfinding/anim/sombra) → ahorro grande
	# con muchos mobs. Se despiertan al acercarse el jugador.
	if to_player > WAKE_RANGE:
		if not _sleeping:
			_sleeping = true
			_reset_combat()
			visible = false   # al dormir (lejos) ocultar render + aura; cubre el alejamiento brusco por teleport de puerta
			if _shadow != null:
				_shadow.set_process(false)
			if use_sprite and sprite:
				sprite.stop()
		velocity = Vector2.ZERO
		return
	elif _sleeping:
		_sleeping = false
		if _shadow != null:
			_shadow.set_process(true)
		if use_sprite and sprite:
			sprite.play()

	# Auto-revelado: el mob (y su aura hija) se ven dentro de mob_reveal_dist y solo en zona ya vista
	# (un poco más allá de tu luz → los acechás como un brillo tenue acercándose en la oscuridad).
	var seen: bool = path_grid == null or not is_instance_valid(path_grid) or path_grid.is_cell_seen(global_position)
	visible = seen and to_player <= _k_reveal_dist   # cacheado (refrescado vía LightCfg.changed)
	if _glow != null:
		_glow.energy = _k_glow_energy        # cacheados (refrescados vía LightCfg.changed)
		_glow.texture_scale = _k_glow_radius

	_update_aggro(ppos, to_player)

	var target_pos := home_pos
	var move_speed := speed * float(Data.BALANCE.wander_speed)
	if aggro:
		move_speed = speed
		if ai == "shooter":
			target_pos = _shooter_target(ppos, to_player)
			_shooter_fire(delta, ppos, to_player)
		else:
			target_pos = _melee_think(delta, ppos, to_player, player)
	else:
		target_pos = _wander_point(delta)

	var next: Vector2
	if is_instance_valid(path_grid):
		next = path_grid.next_point(global_position, target_pos)   # A* por grilla (esquiva muros)
	else:
		agent.target_position = target_pos
		next = agent.get_next_path_position()
	var dir := next - global_position
	# Fallback: si no hay ruta útil (next ≈ posición actual), ir DIRECTO al objetivo.
	if dir.length() <= 1.0 and global_position.distance_to(target_pos) > 6.0:
		dir = target_pos - global_position
	if global_position.distance_to(target_pos) > 6.0 and dir.length() > 1.0:
		velocity = dir.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

	if aggro and ai == "erratic" and velocity.length() > 1.0:
		wobble += delta * 9.0
		var perp := Vector2(-velocity.y, velocity.x).normalized()
		velocity += perp * sin(wobble) * move_speed * 0.6

	velocity += kb
	move_and_slide()
	kb = kb.move_toward(Vector2.ZERO, 900.0 * delta)

	if use_sprite:
		_update_sprite_anim()

func _update_sprite_anim() -> void:
	var moving := velocity.length() > 5.0
	if moving:
		if absf(velocity.x) > absf(velocity.y):
			face = "east" if velocity.x > 0.0 else "west"
		else:
			face = "south" if velocity.y > 0.0 else "north"
	var anim := ("walk_" if moving else "idle_") + face
	if sprite.animation != anim:
		sprite.play(anim)

func _update_aggro(ppos: Vector2, to_player: float) -> void:
	if aggro:
		if home_pos.distance_to(ppos) > float(Data.BALANCE.leash_tiles) * TILE and not home_rect.has_point(ppos):
			aggro = false
			_reset_combat()   # soltar el cupo del director al perder aggro
	elif home_rect.has_point(ppos) or to_player < float(Data.BALANCE.aggro_radius) * TILE * 0.55:
		aggro = true
		if type_key == "golem_chico":
			Audio.play_at("growl", self, -2.0)   # gruñido POSICIONAL: más fuerte cuanto más cerca

func _wander_point(delta: float) -> Vector2:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = Rng.range_f(1.5, 3.0)
		if home_rect.has_area():
			wander_target = Vector2(
				Rng.range_f(home_rect.position.x, home_rect.end.x),
				Rng.range_f(home_rect.position.y, home_rect.end.y))
		else:
			wander_target = home_pos
	return wander_target

func _shooter_target(ppos: Vector2, to_player: float) -> Vector2:
	var ideal := atk_range * 0.65
	if to_player < ideal * 0.85:
		return global_position + (global_position - ppos).normalized() * 60.0
	elif to_player > ideal * 1.15:
		return ppos
	return global_position

func _shooter_fire(delta: float, ppos: Vector2, to_player: float) -> void:
	fire_t = maxf(0.0, fire_t - delta)
	if to_player <= atk_range and fire_t <= 0.0:
		fire_t = fire_cd
		var p := PROJECTILE.instantiate()
		get_parent().add_child(p)
		p.setup(global_position, (ppos - global_position).normalized(), damage, false, proj_spd)

# --- Director de combate (static): tope de atacantes simultáneos ---
static func _try_claim(id: int) -> bool:
	if _atk_active.has(id):
		return true
	for k in _atk_active.keys():        # poda ids de mobs ya liberados (regen/muerte sin release)
		if not is_instance_id_valid(k):
			_atk_active.erase(k)
	if _atk_active.size() >= MAX_ATTACKERS:
		return false
	_atk_active[id] = true
	return true

static func _release(id: int) -> void:
	_atk_active.erase(id)

func _reset_combat() -> void:
	if st != St.CHASE:
		_set_telegraph(false)
	st = St.CHASE
	st_t = 0.0
	_release(get_instance_id())

func _ai_default_windup() -> float:
	if ai == "erratic": return 0.18     # picaflor: telegraph corto, pica y se va
	if speed <= 24.0: return 0.45        # bruto lento (golem/zombi): telegraph largo y legible
	return 0.28

func _ai_default_recover() -> float:
	if ai == "erratic": return 0.22
	if speed <= 24.0: return 0.55
	return 0.35

func _set_telegraph(on: bool) -> void:
	if use_sprite:
		sprite.modulate = Color(1.0, 0.45, 0.4) if on else _idle_tint()
	else:
		visual.color = Color(1.0, 0.45, 0.4) if on else base_color

## FSM melee: orbita su slot (CHASE), pide cupo al director y se frena para telegraphear (WINDUP),
## pega al final del windup y queda vulnerable (RECOVER). Devuelve a dónde moverse.
func _melee_think(delta: float, ppos: Vector2, to_player: float, player) -> Vector2:
	st_t = maxf(0.0, st_t - delta)
	var slot := ppos + Vector2.RIGHT.rotated(_slot_ang) * slot_dist
	var reach := size + 10.0 + MELEE_PAD
	if st == St.WINDUP:
		if st_t <= 0.0:
			if to_player <= reach and hit_cd <= 0.0:
				hit_cd = 0.5
				player.take_damage(damage, global_position)
			st = St.RECOVER
			st_t = recover
			_set_telegraph(false)
		return global_position          # quieto durante el telegraph
	if st == St.RECOVER:
		if st_t <= 0.0 or to_player > atk_exit:
			_release(get_instance_id())
			st = St.CHASE
		return global_position          # quieto / vulnerable
	# CHASE: orbita su slot; al entrar en rango pide cupo al director y telegrafea.
	if to_player <= atk_enter and _try_claim(get_instance_id()):
		st = St.WINDUP
		st_t = windup
		_set_telegraph(true)
		return global_position
	return slot                         # persigue su SLOT, no el centro → no se apilan

func take_damage(amount: int, knockback := Vector2.ZERO, is_crit := false, dmg_color := Color(1, 0.9, 0.5)) -> void:
	hp -= amount
	kb += knockback
	aggro = true
	flash_t = 0.08
	if hpbar:
		hpbar.refresh()
	if use_sprite:
		sprite.modulate = Color(2.2, 2.2, 2.2)
	else:
		visual.color = Color(1, 1, 1)
	# Anti-spoiler: el número de daño solo aparece si la celda está en tu radio (no delata mobs en la sombra).
	if path_grid == null or not is_instance_valid(path_grid) or path_grid.is_cell_visible(global_position):
		GameState.floater(global_position, str(amount), dmg_color, is_crit)
	if hp <= 0:
		_die()

func _die() -> void:
	_reset_combat()   # soltar el cupo del director (el aura es hija → se libera sola con el mob)
	Audio.play("enemy_death", -8.0)
	GameState.run["kills"] = int(GameState.run.get("kills", 0)) + 1
	@warning_ignore("integer_division")
	GameState.drop_loot(global_position, maxi(2, max_hp / 4))
	GameState.enemy_killed.emit(self)
	# Si el sprite tiene animación de muerte (arañas: bolita), la reproduce y recién
	# ahí se libera. Mientras, se congela y deja de colisionar.
	if use_sprite and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("death"):
		set_physics_process(false)
		($Shape as CollisionShape2D).set_deferred("disabled", true)
		sprite.play("death")
		await sprite.animation_finished
	queue_free()
