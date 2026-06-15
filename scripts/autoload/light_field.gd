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
	var r := amb.r
	var g := amb.g
	var b := amb.b
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
	return Color(minf(r, 1.5), minf(g, 1.5), minf(b, 1.5))

## Luz dominante en `pos` para la sombra proyectada (billboard). Devuelve:
##   dir   = versor desde la luz hacia `pos` (hacia donde cae la sombra)
##   d     = distancia px a esa luz
##   prox  = 1 - d/radio (1 pegado a la luz, 0 en el borde)
## Ignora luces cuyo centro coincide con `pos` (p.ej. la luz propia del jugador).
func shadow_vector(pos: Vector2) -> Dictionary:
	if not _gathered or _lights.is_empty():
		_gather()
	var best := 0.0
	var res := {"dir": Vector2.ZERO, "d": 0.0, "prox": 0.0}
	for L in _lights:
		if not is_instance_valid(L):
			continue
		var lp := L as PointLight2D
		if not lp.enabled:
			continue
		var rad := lp.texture_scale * 128.0
		if rad <= 0.0:
			continue
		var off := pos - lp.global_position
		var d := off.length()
		if d >= rad or d < 2.0:        # < 2px → es la luz propia de la entidad
			continue
		var prox := 1.0 - d / rad
		var at := pow(prox, 2.0) * lp.energy
		if at > best:
			best = at
			res = {"dir": off / d, "d": d, "prox": prox}
	return res
