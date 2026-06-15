class_name CastShadow
extends Sprite2D
## Sombra proyectada PRO (billboard) — equivalente Godot del `drawCastCone` de la
## versión Pixi. Proyecta la SILUETA REAL del sprite (frame actual) sobre el piso,
## en dirección opuesta a la luz dominante.
##
## Física de luz puntual (igual que el plan aprobado):
##   L = d · H / (zL − H)   → sombra CORTA pegada a la luz, LARGA lejos.
##   opacidad = cast_alpha · prox^cast_falloff → se apaga en el borde del radio (sin pop).
## Unshaded + light_mask 0 → ninguna luz la aclara. Knobs en LightCfg (panel tecla L).

var _src: Node2D          # AnimatedSprite2D o Sprite2D fuente (la silueta a proyectar)
var _foot_y := 0.0        # offset vertical desde el origen de la entidad hasta los pies

## Engancha una sombra proyectada a `entity`, usando `src` como silueta.
static func attach(entity: Node2D, src: Node2D, foot_y: float) -> CastShadow:
	var cs := CastShadow.new()
	cs._src = src
	cs._foot_y = foot_y
	cs.z_index = -4                 # sobre el piso (-10), debajo de entidades (0)
	cs.show_behind_parent = true
	cs.light_mask = 0
	cs.centered = false
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	cs.material = mat
	cs.modulate = Color(0, 0, 0, 0)
	entity.add_child(cs)
	return cs

func _frame_tex() -> Texture2D:
	if _src is AnimatedSprite2D:
		var a := _src as AnimatedSprite2D
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation):
			return null
		return a.sprite_frames.get_frame_texture(a.animation, a.frame)
	elif _src is Sprite2D:
		return (_src as Sprite2D).texture
	return null

func _process(_dt: float) -> void:
	var parent := get_parent() as Node2D
	if parent == null or _src == null or not is_instance_valid(_src):
		visible = false
		return
	var tex := _frame_tex()
	if tex == null:
		visible = false
		return
	var foot := parent.global_position + Vector2(0, _foot_y)
	var info := LightField.shadow_vector(foot)
	var dir: Vector2 = info.dir
	if dir == Vector2.ZERO:
		visible = false      # sin luz dominante → no hay sombra proyectada
		return
	visible = true
	texture = tex
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var gs: Vector2 = _src.global_scale
	var bscale: float = absf(gs.y)
	if bscale <= 0.001:
		bscale = 0.4
	var mir: float = -1.0 if gs.x < 0.0 else 1.0
	var away: Vector2 = -dir
	# Largo proyectado L = d·H/(zL−H).
	var ph: float = h * bscale
	var zL: float = LightCfg.get_v("cast_light_ht")
	var llen: float = info.d * ph / maxf(zL - ph, 4.0)
	llen = clampf(llen, ph * 0.35, LightCfg.get_v("cast_max_len"))
	# Anclar en los pies (bottom-center → origen), "parado" hacia −Y, y rotar −Y→away.
	offset = Vector2(-w * 0.5, -h)
	position = Vector2(0, _foot_y)
	rotation = atan2(away.x, -away.y)
	var wfac: float = LightCfg.get_v("cast_width") * bscale * mir
	scale = Vector2(wfac, llen / h)
	var a: float = LightCfg.get_v("cast_alpha") * pow(info.prox, LightCfg.get_v("cast_falloff"))
	modulate = Color(0.0, 0.0, 0.0, clampf(a, 0.0, 0.85))
