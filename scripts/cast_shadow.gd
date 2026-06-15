class_name CastShadow
extends Node2D
## Sombras proyectadas PRO (billboard) — equivalente Godot del `drawCastCone` de
## la versión Pixi. Por CADA luz cercana proyecta la SILUETA REAL del sprite
## (frame actual) sobre el piso, en dirección opuesta a esa luz → varias sombras
## en abanico (una por antorcha), como en el original.
##
## Física de luz puntual (plan aprobado):
##   L = d · H / (zL − H)   → sombra CORTA pegada a la luz, LARGA lejos.
##   opacidad = cast_alpha · prox^cast_falloff → se apaga en el borde (sin pop).
## Cada silueta: Unshaded + light_mask 0 (ninguna luz la aclara). Knobs en
## LightCfg (panel tecla L, grupo "Sombras").

const MAX_SHADOWS := 4    # tope de antorchas que proyectan a la vez (perf)

var _src: Node2D          # AnimatedSprite2D o Sprite2D fuente (la silueta)
var _foot_y := 0.0        # offset hasta los pies (local a la entidad)
var _pool: Array[Sprite2D] = []

static func attach(entity: Node2D, src: Node2D, foot_y: float) -> CastShadow:
	var cs := CastShadow.new()
	cs._src = src
	cs._foot_y = foot_y
	cs.z_index = -4                 # sobre el piso (-10), debajo de entidades (0)
	cs.show_behind_parent = true
	entity.add_child(cs)
	return cs

func _make_sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.light_mask = 0
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	s.material = mat
	add_child(s)
	_pool.append(s)
	return s

func _frame_tex() -> Texture2D:
	if _src is AnimatedSprite2D:
		var a := _src as AnimatedSprite2D
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation):
			return null
		return a.sprite_frames.get_frame_texture(a.animation, a.frame)
	elif _src is Sprite2D:
		return (_src as Sprite2D).texture
	return null

func _hide_all() -> void:
	for s in _pool:
		s.visible = false

func _process(_dt: float) -> void:
	var parent := get_parent() as Node2D
	if parent == null or _src == null or not is_instance_valid(_src):
		_hide_all()
		return
	var tex := _frame_tex()
	if tex == null:
		_hide_all()
		return
	var foot := parent.global_position + Vector2(0, _foot_y)
	var lights := LightField.shadow_lights(foot, MAX_SHADOWS)
	while _pool.size() < lights.size():
		_make_sprite()

	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var gs: Vector2 = _src.global_scale
	var bscale: float = absf(gs.y)
	if bscale <= 0.001:
		bscale = 0.4
	var mir: float = -1.0 if gs.x < 0.0 else 1.0
	var ph: float = h * bscale
	var zL: float = LightCfg.get_v("cast_light_ht")
	var maxlen: float = LightCfg.get_v("cast_max_len")
	var calpha: float = LightCfg.get_v("cast_alpha")
	var cfall: float = LightCfg.get_v("cast_falloff")
	var cwidth: float = LightCfg.get_v("cast_width")

	for i in _pool.size():
		var s := _pool[i]
		if i >= lights.size():
			s.visible = false
			continue
		var info: Dictionary = lights[i]
		s.visible = true
		s.texture = tex
		s.offset = Vector2(-w * 0.5, -h)            # bottom-center → origen (pies)
		s.position = Vector2(0, _foot_y)
		var away: Vector2 = -info.dir
		var llen: float = clampf(info.d * ph / maxf(zL - ph, 4.0), ph * 0.35, maxlen)
		s.rotation = atan2(away.x, -away.y)         # −Y local → away
		s.scale = Vector2(cwidth * bscale * mir, llen / h)
		var a: float = calpha * pow(info.prox, cfall)
		s.modulate = Color(0.0, 0.0, 0.0, clampf(a, 0.0, 0.85))
