extends Sprite2D
class_name WindowSky
## Cielo de una ventana: muestra un recorte de una panorámica grande y lo
## desplaza horizontalmente según la cámara → parallax (al moverse el jugador,
## el paisaje "se mueve" dentro de la ventana, como mirar afuera).
## Pensado para una imagen NO tileable y mucho más grande que la ventana: se
## fitea el alto del recorte a la ventana y se panea dentro de los límites.

var view := Vector2(24, 32)
var _parallax := 0.10
var _base := 0.0          # offset horizontal base (px de la imagen) → variedad por ventana
var _rw := 0.0            # ancho del recorte (px de la imagen)
var _rh := 0.0            # alto del recorte
var _ry := 0.0            # y del recorte
var _max_ox := 0.0

## crop_top / crop_frac: qué franja VERTICAL de la imagen se muestra (0..1).
## Default: el 70% de arriba (cielo + luna + montañas), saltea el bosque de abajo.
func setup(tex: Texture2D, parallax: float, phase: float, crop_top := 0.0, crop_frac := 0.70) -> void:
	texture = tex
	_parallax = parallax
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # foto, no pixel-art
	region_enabled = true
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	_rh = th * crop_frac
	_ry = th * crop_top
	_rw = view.x * (_rh / view.y)            # mismo aspecto que la ventana
	_max_ox = maxf(tw - _rw, 0.0)
	_base = fposmod(phase, maxf(_max_ox, 1.0))
	var s := view.y / _rh                     # escala uniforme: fitear alto a la ventana
	scale = Vector2(s, s)
	_update()

func _process(_dt: float) -> void:
	_update()

func _update() -> void:
	if texture == null:
		return
	var cam := get_viewport().get_camera_2d()
	var cx := cam.get_screen_center_position().x if cam != null else 0.0
	var ox := clampf(_base + cx * _parallax, 0.0, _max_ox)
	region_rect = Rect2(ox, _ry, _rw, _rh)
