class_name CastShadow
extends Node2D
## Sombras proyectadas PRO (billboard) — equivalente Godot del `drawCastCone` de
## la versión Pixi. Por CADA luz cercana proyecta la SILUETA REAL del sprite
## (frame actual) sobre el piso, en dirección opuesta a esa luz → varias sombras
## en abanico (una por antorcha). Suma una sombra de contacto en los pies.
##
## Ancla = borde INFERIOR del frame del sprite fuente (calculado en runtime), así
## la sombra sale de los pies sin números mágicos. Knob `cast_lift` para nudge fino.
##
## Física de luz puntual (plan aprobado):
##   L = d · H / (zL − H)   → sombra CORTA pegada a la luz, LARGA lejos.
##   opacidad = cast_alpha · prox^cast_falloff → se apaga en el borde (sin pop).

const MAX_SHADOWS := 4    # tope de luces que proyectan a la vez (perf)

var _src: Node2D          # AnimatedSprite2D o Sprite2D fuente (la silueta)
var _foot_y := 6.0        # fallback si no hay nodo "Feet" en la entidad
var _pool: Array[Sprite2D] = []
var _contact: Sprite2D
var _cast_projected := true   # false → solo sombra circular de contacto (sin siluetas)

# Cache de la fila de los pies (último píxel opaco) por textura → no rescanear.
static var _feet_cache: Dictionary = {}
const SHADER := preload("res://shaders/cast_shadow.gdshader")

static func attach(entity: Node2D, src: Node2D, foot_y: float = 6.0, cast_projected: bool = true) -> CastShadow:
	var cs := CastShadow.new()
	cs._src = src
	cs._foot_y = foot_y
	cs._cast_projected = cast_projected
	cs.z_index = -4                 # sobre el piso (-10), debajo de entidades (0)
	cs.show_behind_parent = true
	entity.add_child(cs)
	return cs

static var _blob_tex: Texture2D

## Blob radial suave generado por código (gradiente difuso, sin silueta).
static func _get_blob() -> Texture2D:
	if _blob_tex != null:
		return _blob_tex
	var s := 64
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	var maxd := s * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / maxd
			# Núcleo sólido (oscuro) hasta ~55% del radio, borde suave después →
			# sombra de contacto bien marcada debajo, no un puntito difuso.
			var a := clampf((1.0 - d) / 0.45, 0.0, 1.0)
			a = pow(a, 0.7)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex

func _ready() -> void:
	_contact = Sprite2D.new()
	_contact.texture = _get_blob()
	_contact.centered = true            # centrado en los pies (no sale de ellos)
	_contact.light_mask = 0
	_contact.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # blob suave, no pixelado
	_contact.material = _unshaded()
	add_child(_contact)

func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

func _make_sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.light_mask = 0
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	s.material = mat
	add_child(s)
	_pool.append(s)
	return s

## Fila (px de textura) del último píxel opaco = los pies dentro del frame.
## Cacheado por textura. Si falla, asume 80% del alto.
func _feet_py(tex: Texture2D, h: float) -> float:
	var key := tex.get_rid().get_id()
	if _feet_cache.has(key):
		return _feet_cache[key]
	var fp := h * 0.8
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var iw := img.get_width()
		var ih := img.get_height()
		for y in range(ih - 1, -1, -1):
			var any := false
			for x in iw:
				if img.get_pixel(x, y).a > 0.15:
					any = true
					break
			if any:
				fp = float(y + 1)        # justo debajo del último píxel opaco
				break
	_feet_cache[key] = fp
	return fp

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
	if _contact:
		_contact.visible = false
	for s in _pool:
		s.visible = false

func _process(_dt: float) -> void:
	if _src == null or not is_instance_valid(_src):
		_hide_all()
		return
	var tex := _frame_tex()
	if tex == null:
		_hide_all()
		return
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var gs: Vector2 = _src.global_scale
	var bscale: float = absf(gs.y)
	if bscale <= 0.001:
		bscale = 0.4
	var mir: float = -1.0 if gs.x < 0.0 else 1.0

	# Ancla en MUNDO = nodo "Feet" de la entidad si existe (lo posicionás en el
	# editor justo en los pies); si no, fallback a origen + _foot_y. `cast_lift` nudge.
	var parent := get_parent() as Node2D
	var lift: float = LightCfg.get_v("cast_lift")
	var feet_node := parent.get_node_or_null("Feet") as Node2D
	var foot_global: Vector2
	if feet_node != null:
		foot_global = feet_node.global_position
	else:
		# Pies REALES del sprite (centrado): centro + (fila_pies − medio_alto) × escala.
		# Evita que la sombra quede por debajo y la entidad parezca flotar.
		var fpy0: float = _feet_py(tex, h)
		foot_global = _src.global_position + Vector2(0, (fpy0 - h * 0.5) * bscale)
	foot_global.y -= lift
	var foot_local: Vector2 = to_local(foot_global)

	# Contacto: blob radial suave, elíptico, CENTRADO en los pies. Fijo (no depende
	# de antorchas) y simple. Blob de 64px → /64.
	var cw: float = w * bscale / 64.0 * LightCfg.get_v("contact_size")
	_contact.visible = true
	_contact.position = foot_local
	_contact.scale = Vector2(cw, cw * LightCfg.get_v("contact_flat"))
	_contact.modulate = Color(0.0, 0.0, 0.0, LightCfg.get_v("contact_alpha"))

	# Sin proyectadas (p.ej. mobs): solo la circular de contacto.
	if not _cast_projected:
		for s in _pool:
			s.visible = false
		return

	# Una silueta proyectada por luz cercana.
	var lights := LightField.shadow_lights(foot_global, MAX_SHADOWS, parent)
	while _pool.size() < lights.size():
		_make_sprite()
	var feet_py: float = _feet_py(tex, h)              # fila de los pies (auto-detect, cacheado)
	var feet_v: float = feet_py / h                    # mismo punto en UV (para el shader)
	var body_h: float = feet_py * bscale               # alto VISIBLE (pies→cabeza) en mundo
	var zL: float = LightCfg.get_v("cast_light_ht")
	var maxlen: float = LightCfg.get_v("cast_max_len")
	var calpha: float = LightCfg.get_v("cast_alpha")
	var cfall: float = LightCfg.get_v("cast_falloff")
	var cwidth: float = LightCfg.get_v("cast_width")
	var cblur: float = LightCfg.get_v("cast_blur")
	var cblur_grow: float = LightCfg.get_v("cast_blur_grow")
	var ctip: float = LightCfg.get_v("cast_tip_fade")
	var cbase: float = LightCfg.get_v("cast_base_fade")

	for i in _pool.size():
		var s := _pool[i]
		if i >= lights.size():
			s.visible = false
			continue
		var info: Dictionary = lights[i]
		s.visible = true
		s.texture = tex
		# Anclar en los PIES del frame (no el borde inferior, que es padding).
		s.offset = Vector2(-w * 0.5, -feet_py)
		s.position = foot_local
		var away: Vector2 = info.dir                 # luz → entidad → sombra
		var llen: float = clampf(info.d * body_h / maxf(zL - body_h, 4.0), body_h * 0.35, maxlen)
		s.rotation = atan2(away.x, -away.y)          # −Y local → away
		s.scale = Vector2(cwidth * bscale * mir, llen / feet_py)   # cuerpo (feet_py) → llen
		var a: float = clampf(calpha * pow(info.prox, cfall), 0.0, 0.96)
		var mat := s.material as ShaderMaterial      # difusión + pérdida hacia la punta
		mat.set_shader_parameter("feet_v", feet_v)
		mat.set_shader_parameter("strength", a)
		mat.set_shader_parameter("blur", cblur)
		mat.set_shader_parameter("blur_grow", cblur_grow)
		mat.set_shader_parameter("tip_fade", ctip)
		mat.set_shader_parameter("base_fade", cbase)
