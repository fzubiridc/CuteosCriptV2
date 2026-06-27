extends Node2D
class_name HealthBar
## Barra de vida fina (roja) sobre la cabeza de un mob. Se oculta a vida llena
## y al morir. Unshaded para que el rojo no lo apague la luz ambiente del nivel.
## Lee hp/max_hp del nodo padre (Enemy). El padre llama refresh() al recibir daño.

var width := 18.0
var _e = null   # nodo padre (Enemy); sin tipar para leer hp/max_hp por duck-typing

func _ready() -> void:
	_e = get_parent()
	z_index = 60
	z_as_relative = false   # z absoluto: por encima del mundo
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if _e == null or not is_instance_valid(_e):
		return
	var mx := maxf(1.0, float(_e.max_hp))
	var hp := float(_e.hp)
	if hp >= mx or hp <= 0.0:
		return   # vida llena o muerto → barra oculta
	var ratio := clampf(hp / mx, 0.0, 1.0)
	var w := width
	var h := 2.0
	var x := -w * 0.5
	draw_rect(Rect2(x - 1.0, -1.0, w + 2.0, h + 2.0), Color(0, 0, 0, 0.85))   # marco
	draw_rect(Rect2(x, 0.0, w, h), Color(0.12, 0.04, 0.05, 0.95))             # fondo vacío
	draw_rect(Rect2(x, 0.0, w * ratio, h), Color(0.75, 0.22, 0.17, 1.0))      # relleno rojo
