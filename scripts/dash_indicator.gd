extends Control
## Indicador de cooldown del dash. Arco radial que se llena mientras recarga;
## círculo con glow azul cuando está listo. Lee el cooldown del player.

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	var pl = GameState.player
	if pl == null or not is_instance_valid(pl):
		return
	var cd: float = maxf(0.001, float(Data.BALANCE.dash_cd))
	var t: float = pl.dash_cd_t
	var ratio: float = 1.0 - clampf(t / cd, 0.0, 1.0)   # 0 recién usado → 1 listo
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	# Fondo + aro.
	draw_circle(c, r, Color(0, 0, 0, 0.55))
	draw_arc(c, r, 0.0, TAU, 40, Color(0.4, 0.35, 0.5, 0.8), 2.0, true)
	if t <= 0.0:
		# Listo: disco con glow azul.
		draw_circle(c, r - 3.0, Color(0.45, 0.8, 1.0, 0.85))
	else:
		# Recargando: arco de progreso desde arriba, en sentido horario.
		var start := -PI / 2.0
		draw_arc(c, r - 3.0, start, start + TAU * ratio, 40, Color(0.45, 0.8, 1.0, 0.9), 4.0, true)
