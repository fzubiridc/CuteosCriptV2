class_name AoE
extends Node2D
## Ataque de área (tecla E cuando no hay nada para interactuar). Planta un glifo en el
## piso, ~1s de BUILDUP (el círculo rúnico aparece con fade-in lineal; las llamas arden
## sólidas) y después EXPLOTA: daño a los enemigos dentro del óvalo + glow + shake + sfx.
## Tamaño (radius), achatado (flat) y posición de las llamas salen de assets/fx/aoe_config.json
## (editable con la AoE Glyph Tool, auto-guardado). Auto-contenido: se libera solo.

const GLYPH := preload("res://assets/fx/aoe_fire_glyph.png")
const FLAME := preload("res://assets/fx/aoe_fire_core.png")   # fallback estático de la llama
const FLAME_FPS := 12.0                                       # fps de la llama animada
static var _flame_frames: Array = []                          # frames del gif (compartidos)

var _ra := 120.0         # semieje X del óvalo (radio "ancho"), px de mundo — del config
var _rb := 60.0          # semieje Y — derivado del achatado del glifo
var _flat := 0.82        # achatado del círculo rúnico (1 = nativo) — del config
var _dmg := 40
var _buildup := 1.0
var _kb := 170.0         # empuje desde el centro al explotar

var _t := 0.0
var _exploded := false
var _base_scale := 1.0
var _glyph: Sprite2D
var _flames: Array = []
var _light: PointLight2D

## Llamar DESPUÉS de add_child. El tamaño/achatado/llamas salen del config (leído en _ready);
## acá solo van el punto del piso, el daño y la duración del buildup.
func setup(center: Vector2, dmg: int, buildup := 1.0) -> void:
	global_position = center
	_dmg = dmg
	_buildup = maxf(0.1, buildup)

func _ready() -> void:
	var cfg := _load_config()
	_ra = maxf(8.0, float(cfg.get("radius", 120.0)))
	_flat = clampf(float(cfg.get("flat", 0.82)), 0.1, 1.0)
	var flames_cfg: Array = cfg["flames"] if (cfg.has("flames") and cfg["flames"] is Array) else []
	if flames_cfg.is_empty():
		flames_cfg = [{"x": 0.5, "y": 0.5, "s": 0.7}]
	_base_scale = (2.0 * _ra) / float(GLYPH.get_width())   # el ancho del glifo cubre el diámetro
	var glyph_w := 2.0 * _ra
	var glyph_h := float(GLYPH.get_height()) * _base_scale * _flat
	_rb = glyph_h * 0.5   # área de daño = óvalo del glifo achatado (coincide con lo que se ve)
	# --- círculo rúnico (achatado, perspectiva de piso) ---
	_glyph = Sprite2D.new()
	_glyph.texture = GLYPH
	_glyph.z_index = -4   # sobre el piso (-10) y la sombra (-5), debajo de entidades (0): se pisa
	_glyph.material = FxMaterials.add_unshaded()
	_glyph.scale = Vector2(_base_scale, _base_scale * _flat)
	_glyph.modulate.a = 0.0   # arranca transparente (fade-in lineal en _process)
	add_child(_glyph)
	# --- llamas dentro del glifo (animadas y SÓLIDAS), posiciones normalizadas (0-1) ---
	var frames := _get_flame_frames()
	var fw := float(frames[0].get_width())
	for fdef in flames_cfg:
		var spr := Sprite2D.new()
		spr.texture = frames[0]
		spr.z_index = -3
		spr.material = FxMaterials.add_unshaded()
		spr.position = Vector2((float(fdef.get("x", 0.5)) - 0.5) * glyph_w,
							   (float(fdef.get("y", 0.5)) - 0.5) * glyph_h)
		var sc := (float(fdef.get("s", 0.7)) * glyph_w) / fw
		spr.scale = Vector2(sc, sc)
		spr.modulate.a = 1.0
		add_child(spr)
		_flames.append(spr)
	# --- charco de luz elíptico (acompaña el achatado) ---
	_light = PointLight2D.new()
	_light.texture = load("res://assets/fx/light_radial.tres")
	_light.color = Color(1.0, 0.5, 0.16)
	_light.energy = 0.0
	_light.texture_scale = _ra / 70.0
	_light.scale = Vector2(1.0, _flat * 0.6)
	add_child(_light)
	Audio.play("aoe_impact", -2.0)   # único sfx del AoE: suena al lanzarlo (cubre el buildup)

func _process(delta: float) -> void:
	_t += delta
	# Animar las llamas (cicla los frames del gif) — también durante el fade post-impacto.
	var frames := _get_flame_frames()
	if frames.size() > 1:
		var fi := int(_t * FLAME_FPS) % frames.size()
		for fl in _flames:
			fl.texture = frames[fi]
	if _exploded:
		return
	var p := clampf(_t / _buildup, 0.0, 1.0)
	_glyph.modulate.a = p              # fade-in LINEAL (solo el círculo rúnico)
	_light.energy = 1.4 * p            # glow tenue creciente (lineal)
	if _t >= _buildup:
		_explode()

func _explode() -> void:
	_exploded = true
	# --- daño: enemigos vivos dentro del ÓVALO (test de elipse sobre sus pies) ---
	# Enemy → grupo "enemies" (lo agrega enemy.gd; incluye también a los minions del jefe).
	# El Boss NO está en ese grupo (es hijo directo de la escena), así que lo buscamos aparte.
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: Vector2 = e.global_position - global_position
		if (d.x * d.x) / (_ra * _ra) + (d.y * d.y) / (_rb * _rb) <= 1.0:
			var push: Vector2 = d.normalized() * _kb if d.length() > 0.01 else Vector2.ZERO
			e.take_damage(_dmg, push, false, Color(1.0, 0.42, 0.1))   # número naranja (fuego)
			BurnFx.apply(e)   # el AoE es fuego → prende a cada mob alcanzado
	# Jefe: no está en "enemies"; lo ubicamos entre los hijos de la escena (igual que main.gd).
	for e in get_tree().current_scene.get_children():
		if not (e is Boss):
			continue
		var d: Vector2 = e.global_position - global_position
		if (d.x * d.x) / (_ra * _ra) + (d.y * d.y) / (_rb * _rb) <= 1.0:
			e.take_damage(_dmg, Vector2.ZERO, false, Color(1.0, 0.42, 0.1))   # naranja (fuego)
			BurnFx.apply(e)       # también lo prende
	# --- glow del impacto: destello cálido + flash de luz + shake ---
	_glyph.modulate = Color(1.0, 0.95, 0.85, 1.0)
	for fl in _flames:
		fl.modulate = Color(1.0, 0.97, 0.90, 1.0)
	_light.energy = 7.0
	if GameState.player and GameState.player.has_method("shake"):
		GameState.player.shake(6.0)
	# --- fade-out y autodestrucción ---
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_glyph, "modulate", Color(1, 1, 1, 0), 0.45)
	for fl in _flames:
		tw.tween_property(fl, "modulate", Color(1, 1, 1, 0), 0.45)
	tw.tween_property(_light, "energy", 0.0, 0.50)
	tw.chain().tween_callback(queue_free)

## Config del AoE (assets/fx/aoe_config.json, editable con la AoE Glyph Tool):
## {radius, flat, flames:[{x,y,s}]}. {} si no existe → defaults razonables.
func _load_config() -> Dictionary:
	var path := "res://assets/fx/aoe_config.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if typeof(data) == TYPE_DICTIONARY else {}

## Frames de la llama animada (assets/fx/aoe_fire_core_anim/frame_NNN.png). Si todavía no
## están importados, cae al PNG estático (FLAME) como único frame. Compartidos (static).
static func _get_flame_frames() -> Array:
	if not _flame_frames.is_empty():
		return _flame_frames
	var i := 0
	while ResourceLoader.exists("res://assets/fx/aoe_fire_core_anim/frame_%03d.png" % i):
		_flame_frames.append(load("res://assets/fx/aoe_fire_core_anim/frame_%03d.png" % i))
		i += 1
	if _flame_frames.is_empty():
		_flame_frames = [FLAME]
	return _flame_frames
