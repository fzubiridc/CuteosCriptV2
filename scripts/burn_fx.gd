class_name BurnFx
extends Object
## Efecto visual de "quemándose": al recibir daño de FUEGO, salpica VARIAS llamitas
## chiquitas y random sobre el cuerpo del mob, animadas (9 frames en loop, ~12fps),
## auto-iluminadas (ADD+UNSHADED), que arden ~1s y se desvanecen. Las llamas son HIJAS
## del mob → lo siguen si se mueve, y se liberan solas. Aplicado EXTERNO (no toca enemy.gd):
## lo invocan projectile.gd (impacto del bolt de fuego) y aoe.gd (explosión, siempre fuego).

const VARIANTS := 2            # carpetas assets/fx/burn/1 y /2
const FRAMES := 9              # frame_000 … frame_008 por variante
const FPS := 12.0             # ciclo de la animación de la llama
const MIN_FLAMES := 3
const MAX_FLAMES := 5
const LIFE_MIN := 1.0         # duración base de la quemada (s)
const LIFE_MAX := 1.4
const FADE := 0.4             # tramo final de fade-out (incluido en la vida)
const META_KEY := "_burn_until"   # marcador en el mob: instante (ms) hasta el que sigue ardiendo

# SpriteFrames de cada variante, cacheados (no recargar las texturas por llama).
static var _frames: Array = []   # [SpriteFrames variante 1, variante 2]

## Prende al mob: si NO está ardiendo, le agrega 3-5 llamitas random; si YA está ardiendo
## (fuego repetido), solo refresca la duración del marcador → no apila llamas infinitas.
static func apply(mob: Node2D) -> void:
	if mob == null or not is_instance_valid(mob):
		return
	var now := Time.get_ticks_msec()
	var life := Rng.range_f(LIFE_MIN, LIFE_MAX)
	# Anti-saturación: si sigue ardiendo de un golpe anterior, solo extiende el marcador.
	if mob.has_meta(META_KEY) and int(mob.get_meta(META_KEY)) > now:
		mob.set_meta(META_KEY, now + int(life * 1000.0))
		return
	mob.set_meta(META_KEY, now + int(life * 1000.0))
	# Tamaño del cuerpo (los mobs exponen `var size: float`); fallback razonable si no.
	var body: float = float(mob.get("size")) if mob.get("size") != null else 8.0
	var n := Rng.range_i(MIN_FLAMES, MAX_FLAMES)
	for i in n:
		_spawn_flame(mob, body, life)

## Una llamita: variante/posición/escala/frame inicial random, ADD+UNSHADED, z alto,
## animada en loop, y tween de fade-out (modulate:a) → queue_free al terminar.
static func _spawn_flame(mob: Node2D, body: float, life: float) -> void:
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _get_frames(Rng.range_i(0, VARIANTS - 1))
	spr.animation = "burn"
	# Esparcidas sobre el cuerpo: offset random dentro de ~el tamaño del mob, centrado y un
	# poco hacia arriba (las llamas lamen el torso, no los pies).
	spr.position = Vector2(Rng.range_f(-body, body), Rng.range_f(-body * 1.2, body * 0.3))
	# Escala chica: los frames son 48px; el mob mide ~size*2 → una llama ≈ medio cuerpo.
	var sc := (body * Rng.range_f(0.7, 1.2)) / 48.0
	spr.scale = Vector2(sc, sc)
	spr.frame = Rng.range_i(0, FRAMES - 1)   # desfasa el arranque → no laten al unísono
	spr.material = FxMaterials.add_unshaded()   # fuego auto-iluminado (suma destello)
	spr.z_index = 50                            # por encima del mob (entidades en z 0)
	spr.play("burn")
	mob.add_child(spr)
	# Vida: arde sólida y se apaga en el último tramo (fade sobre el alpha). Se libera sola.
	var tw := spr.create_tween()
	tw.tween_interval(maxf(0.0, life - FADE))
	tw.tween_property(spr, "modulate:a", 0.0, FADE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(spr.queue_free)

## SpriteFrames de una variante (0/1) → assets/fx/burn/<n>/frame_NNN.png, loop a FPS.
## Cacheados en static (una sola copia por variante, compartida por todas las llamas).
static func _get_frames(variant: int) -> SpriteFrames:
	if _frames.is_empty():
		_frames.resize(VARIANTS)
	if _frames[variant] != null:
		return _frames[variant]
	var sf := SpriteFrames.new()
	sf.add_animation("burn")
	sf.set_animation_loop("burn", true)
	sf.set_animation_speed("burn", FPS)
	for i in FRAMES:
		var t := load("res://assets/fx/burn/%d/frame_%03d.png" % [variant + 1, i]) as Texture2D
		if t != null:
			sf.add_frame("burn", t)
	_frames[variant] = sf
	return sf
