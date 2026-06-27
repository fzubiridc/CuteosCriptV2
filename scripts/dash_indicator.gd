extends Control
## Indicador de cooldown del dash. Muestra el icono (bota del pixi) y, mientras
## recarga, una cortina oscura que cubre desde arriba la fracción restante
## (barrido vertical, igual que el pixi). Listo → icono pleno con destello azul.

var _icon: Texture2D

func _ready() -> void:
	_icon = _load_icon("res://assets/ui/hud/dash_boot.png")
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED   # el HUD no lo apaga la luz del nivel
	material = m

## load() normal; fallback a PNG crudo si Godot aún no importó el asset.
func _load_icon(path: String) -> Texture2D:
	var t := load(path) as Texture2D
	if t != null:
		return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null else null

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	var pl = GameState.player
	if pl == null or not is_instance_valid(pl):
		return
	var cd: float = maxf(0.001, float(Data.BALANCE.dash_cd))
	var t: float = pl.dash_cd_t
	var ratio: float = clampf(t / cd, 0.0, 1.0)   # 1 = recién usado, 0 = listo
	var rect := Rect2(Vector2.ZERO, size)

	# Icono base.
	if _icon != null:
		draw_texture_rect(_icon, rect, false, Color(1, 1, 1, 1))

	if t > 0.0:
		# Cortina oscura cubriendo la fracción restante desde arriba; se retira hacia
		# arriba a medida que recarga (revela el icono de abajo hacia arriba).
		var h := size.y * ratio
		draw_rect(Rect2(0.0, 0.0, size.x, h), Color(0.04, 0.03, 0.06, 0.62))
		draw_line(Vector2(0.0, h), Vector2(size.x, h), Color(0.45, 0.8, 1.0, 0.85), 1.0)
	else:
		# Listo: aro/destello azul sutil alrededor del icono.
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_arc(c, r, 0.0, TAU, 48, Color(0.45, 0.8, 1.0, 0.9), 2.0, true)
