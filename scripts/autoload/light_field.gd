extends Node
## Foot-light (estilo Pixi lightAtFoot): las entidades se dibujan UNSHADED y se
## tintan con sample(pos) → la luz les llega "por los pies" y NO las afecta la
## sombra de los muros (el cuerpo no se oscurece contra una pared).

var _lights: Array = []          # PointLight2D (jugador + antorchas) — estáticas del piso
var _dynamic: Array = []         # luces de entidades (los _glow de los mobs) → su luz los ilumina a ellos
var _amb_node: CanvasModulate
var _amb_fallback := Color(0.34, 0.33, 0.42)
var _gathered := false

# Iluminación por píxel (mismo shader que las caras de muro). entity_material lo
# comparten todas las entidades foot-lit (enemigos/boss): la luz se calcula por
# fragmento desde estas luces, así obtienen gradiente por píxel en vez de un
# tinte plano por sprite. Sin relieve (normal plana) porque no tienen normal-map.
const LIT_SHADER := preload("res://shaders/wall_face.gdshader")
const MAX_LIGHTS := 64
# Más allá de esto (px, + el radio de la luz) una luz no alcanza a iluminar ningún píxel en
# pantalla (cámara clavada al jugador), pero igual ocuparía un slot de los MAX_LIGHTS. Las
# antorchas/fogatas de salas lejanas robaban los slots y dejaban afuera el aura propia de los
# mobs cercanos (cargados al final de la lista) → mobs negros en pisos con muchas luces. Las
# descartamos por proximidad al jugador. La luz del jugador está a distancia 0: nunca se descarta.
const LIGHT_CULL_DIST := 560.0
var entity_material: ShaderMaterial
var _packed: Dictionary = {}

# Buffers de empaquetado pre-alocados (FIX allocs): pack_lights() los rellena IN-PLACE
# cada frame en vez de crear PackedArrays nuevos → sin churn de GC. Dimensionados a
# MAX_LIGHTS una sola vez; el "count" real va aparte en el Dictionary devuelto.
var _pk_pos := PackedVector2Array()
var _pk_col := PackedVector3Array()
var _pk_energy := PackedFloat32Array()
var _pk_radius := PackedFloat32Array()
var _pk_height := PackedFloat32Array()
var _pk_ready := false

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
	entity_material.set_shader_parameter("light_falloff", LightCfg.get_v("light_falloff"))

## Empaqueta las luces de la escena para el shader (reusado por dungeon para las
## caras). Devuelve arrays de tamaño fijo MAX_LIGHTS + count real + ambiente.
func pack_lights() -> Dictionary:
	# Buffers a tamaño fijo MAX_LIGHTS, alocados una sola vez (rellenados in-place abajo).
	if not _pk_ready:
		_pk_pos.resize(MAX_LIGHTS); _pk_col.resize(MAX_LIGHTS)
		_pk_energy.resize(MAX_LIGHTS); _pk_radius.resize(MAX_LIGHTS); _pk_height.resize(MAX_LIGHTS)
		_pk_ready = true
	# Purga in-place los _glow de mobs muertos (iterar en reversa + remove_at, sin alocar
	# un Array nuevo por frame como hacía _dynamic.filter(lambda)).
	for i in range(_dynamic.size() - 1, -1, -1):
		if not is_instance_valid(_dynamic[i]):
			_dynamic.remove_at(i)
	var count := 0
	# is_instance_valid ANTES del cast: al volver al menú (ESC) GameState.player apunta a un nodo
	# ya liberado y `as Node2D` sobre un objeto freed crashea ("cast freed object").
	var pc: Node2D = null
	if is_instance_valid(GameState.player):
		pc = GameState.player as Node2D
	var cull := pc != null
	var ppos := pc.global_position if cull else Vector2.ZERO
	for L in get_lights() + _dynamic:
		if not is_instance_valid(L):
			continue                       # luz liberada en un regen → no castear un objeto freed (el cast en sí erroraba)
		var lp := L as PointLight2D
		if lp == null or not lp.enabled:
			continue
		var rad := lp.texture_scale * LightCfg.LIGHT_POOL_RADIUS
		if rad <= 0.0:
			continue
		# Cull por proximidad (ver LIGHT_CULL_DIST): libera slots para las auras de mobs cercanos.
		if cull and ppos.distance_to(lp.global_position) > LIGHT_CULL_DIST + rad:
			continue
		_pk_pos[count] = lp.global_position
		_pk_col[count] = Vector3(lp.color.r, lp.color.g, lp.color.b)
		_pk_energy[count] = lp.energy
		_pk_radius[count] = rad
		_pk_height[count] = lp.height
		count += 1
		if count >= MAX_LIGHTS:
			break
	var amb := LightCfg.ambient_color() * LightCfg.get_v("foot_ambient")
	return {"count": count, "pos": _pk_pos, "col": _pk_col, "energy": _pk_energy,
		"radius": _pk_radius, "height": _pk_height, "ambient": Vector3(amb.r, amb.g, amb.b)}

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
	_dynamic.clear()
	_gathered = false

## Registra la luz propia de una entidad (el _glow de un mob) → el campo la incluye, así su sprite
## (y los cercanos) se iluminan con ella, como el jugador con su Light. Se purga sola al liberarse.
func add_dynamic(l: Node) -> void:
	if l != null and not (l in _dynamic):
		_dynamic.append(l)

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
	if pl == null:
		# iso: player anidado (World/Player). Buscar recursivo.
		var _p := scene.find_child("Player", true, false)
		if _p:
			pl = _p.get_node_or_null("Light")
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
	for L in _lights + _dynamic:
		if not is_instance_valid(L):
			continue
		var lp := L as PointLight2D
		if not lp.enabled:
			continue
		var rad := lp.texture_scale * LightCfg.LIGHT_POOL_RADIUS   # extensión real del light_pool (256/2)
		if rad <= 0.0:
			continue
		var d := pos.distance_to(lp.global_position)
		if d >= rad:
			continue
		var at := pow(1.0 - d / rad, LightCfg.get_v("light_falloff")) * lp.energy
		r += lp.color.r * at
		g += lp.color.g * at
		b += lp.color.b * at
	# Cap de brillo PRESERVANDO el tono: si recortás canal por canal, cerca de una
	# antorcha R y G topan en el techo y el cálido vira a amarillo/verdoso. Escalando
	# el color entero se mantiene el matiz (anaranjado).
	var m := maxf(r, maxf(g, b))
	var lim := LightCfg.LIGHT_CAP   # cap de brillo (antes literal 1.4)
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
		var rad := lp.texture_scale * LightCfg.LIGHT_POOL_RADIUS
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
