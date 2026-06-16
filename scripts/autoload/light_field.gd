extends Node
## Foot-light (estilo Pixi lightAtFoot): las entidades se dibujan UNSHADED y se
## tintan con sample(pos) → la luz les llega "por los pies" y NO las afecta la
## sombra de los muros (el cuerpo no se oscurece contra una pared).

var _lights: Array = []          # PointLight2D (jugador + antorchas)
var _amb_node: CanvasModulate
var _amb_fallback := Color(0.34, 0.33, 0.42)
var _gathered := false

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
