extends Node
## Foot-light (estilo Pixi lightAtFoot): las entidades se dibujan UNSHADED y se
## tintan con sample(pos) → la luz les llega "por los pies" y NO las afecta la
## sombra de los muros (el cuerpo no se oscurece contra una pared).

var _lights: Array = []          # PointLight2D (jugador + antorchas)
var _amb_node: CanvasModulate
var _amb_fallback := Color(0.34, 0.33, 0.42)
var _gathered := false

# Iluminación por píxel (mismo shader que las caras de muro). entity_material lo
# comparten todas las entidades foot-lit (enemigos/boss): la luz se calcula por
# fragmento desde estas luces, así obtienen gradiente por píxel en vez de un
# tinte plano por sprite. Sin relieve (normal plana) porque no tienen normal-map.
const LIT_SHADER := preload("res://shaders/wall_face.gdshader")
const MAX_LIGHTS := 64
var entity_material: ShaderMaterial
var _packed: Dictionary = {}

func _ready() -> void:
	entity_material = ShaderMaterial.new()
	entity_material.shader = LIT_SHADER
	var flat := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	flat.set_pixel(0, 0, Color(0.5, 0.5, 1.0))   # normal (0,0,1)
	entity_material.set_shader_parameter("normal_tex", ImageTexture.create_from_image(flat))
	entity_material.set_shader_parameter("relief_floor", 1.0)   # solo falloff, sin relieve

func _process(_delta: float) -> void:
	_packed = pack_lights()
	apply_lights(entity_material, _packed)

## Empaqueta las luces de la escena para el shader (reusado por dungeon para las
## caras). Devuelve arrays de tamaño fijo MAX_LIGHTS + count real + ambiente.
func pack_lights() -> Dictionary:
	var pos := PackedVector2Array()
	var col := PackedVector3Array()
	var energy := PackedFloat32Array()
	var radius := PackedFloat32Array()
	var height := PackedFloat32Array()
	for L in get_lights():
		var lp := L as PointLight2D
		if lp == null or not is_instance_valid(lp) or not lp.enabled:
			continue
		var rad := lp.texture_scale * 128.0
		if rad <= 0.0:
			continue
		pos.append(lp.global_position)
		col.append(Vector3(lp.color.r, lp.color.g, lp.color.b))
		energy.append(lp.energy)
		radius.append(rad)
		height.append(lp.height)
		if pos.size() >= MAX_LIGHTS:
			break
	var count := pos.size()
	pos.resize(MAX_LIGHTS); col.resize(MAX_LIGHTS)
	energy.resize(MAX_LIGHTS); radius.resize(MAX_LIGHTS); height.resize(MAX_LIGHTS)
	var amb := LightCfg.ambient_color() * LightCfg.get_v("foot_ambient")
	return {"count": count, "pos": pos, "col": col, "energy": energy,
		"radius": radius, "height": height, "ambient": Vector3(amb.r, amb.g, amb.b)}

## Resultado de pack_lights de este frame (lo cachea _process). dungeon lo reusa
## para no empaquetar dos veces.
func current_packed() -> Dictionary:
	if _packed.is_empty():
		_packed = pack_lights()
	return _packed

func apply_lights(mat: ShaderMaterial, p: Dictionary) -> void:
	if mat == null or p.is_empty():
		return
	mat.set_shader_parameter("light_count", p["count"])
	mat.set_shader_parameter("light_pos", p["pos"])
	mat.set_shader_parameter("light_color", p["col"])
	mat.set_shader_parameter("light_energy", p["energy"])
	mat.set_shader_parameter("light_radius", p["radius"])
	mat.set_shader_parameter("light_height", p["height"])
	mat.set_shader_parameter("ambient", p["ambient"])

## Llamar cuando cambian las luces de la escena (al generar la mazmorra).
func mark_dirty() -> void:
	_lights.clear()
	_gathered = false

## Lista de PointLight2D activas (jugador + antorchas). La usa el shader de las
## caras de muro para iluminarlas por píxel con las mismas luces.
func get_lights() -> Array:
	if not _gathered or _lights.is_empty():
		_gather()
	return _lights

func _gather() -> void:
	_lights.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	_amb_node = scene.get_node_or_null("Ambient") as CanvasModulate
	var pl := scene.get_node_or_null("Player/Light")
	if pl:
		_lights.append(pl)
	var torches := scene.get_node_or_null("Torches")
	if torches:
		for c in torches.get_children():
			if c is PointLight2D:
				_lights.append(c)
	_gathered = true

## Color de luz acumulado en `pos` = ambiente + aporte de cada luz (falloff²).
func sample(pos: Vector2) -> Color:
	if not _gathered or _lights.is_empty():
		_gather()
	var amb := _amb_node.color if (_amb_node and is_instance_valid(_amb_node)) else _amb_fallback
	# Piso de ambiente SOLO para entidades foot-lit (no afecta piso/muros): más bajo
	# → los mobs fuera del alcance de toda luz se oscurecen de verdad.
	var fa := LightCfg.get_v("foot_ambient")
	var r := amb.r * fa
	var g := amb.g * fa
	var b := amb.b * fa
	for L in _lights:
		if not is_instance_valid(L):
			continue
		var lp := L as PointLight2D
		if not lp.enabled:
			continue
		var rad := lp.texture_scale * 128.0   # extensión real del light_pool (256/2)
		if rad <= 0.0:
			continue
		var d := pos.distance_to(lp.global_position)
		if d >= rad:
			continue
		var at := pow(1.0 - d / rad, 2.0) * lp.energy
		r += lp.color.r * at
		g += lp.color.g * at
		b += lp.color.b * at
	# Cap de brillo PRESERVANDO el tono: si recortás canal por canal, cerca de una
	# antorcha R y G topan en el techo y el cálido vira a amarillo/verdoso. Escalando
	# el color entero se mantiene el matiz (anaranjado).
	var m := maxf(r, maxf(g, b))
	var lim := 1.4
	if m > lim:
		var sc := lim / m
		r *= sc
		g *= sc
		b *= sc
	return Color(r, g, b)

## TODAS las luces que iluminan `pos`, para sombras proyectadas (una por luz).
## Cada item: {dir, d, prox, w} — dir = versor luz→pos (hacia donde cae la sombra),
## d = distancia px, prox = 1-d/radio, w = intensidad (para ordenar/recortar).
## Ordenadas por intensidad desc y recortadas a `max_n`. Ignora la luz propia
## de la entidad (centro a <2px de `pos`).
func shadow_lights(pos: Vector2, max_n: int = 4, exclude_owner: Node = null) -> Array:
	if not _gathered or _lights.is_empty():
		_gather()
	var out: Array = []
	for L in _lights:
		if not is_instance_valid(L):
			continue
		var lp := L as PointLight2D
		if not lp.enabled:
			continue
		# Saltar la luz propia de la entidad (su luz cuelga del mismo nodo).
		if exclude_owner != null and exclude_owner.is_ancestor_of(lp):
			continue
		var rad := lp.texture_scale * 128.0
		if rad <= 0.0:
			continue
		var off := pos - lp.global_position
		var d := off.length()
		if d >= rad:
			continue
		var prox := 1.0 - d / rad
		out.append({"dir": off / d, "d": d, "prox": prox, "w": pow(prox, 2.0) * lp.energy})
	out.sort_custom(func(a, b): return a.w > b.w)
	if out.size() > max_n:
		out = out.slice(0, max_n)
	return out
