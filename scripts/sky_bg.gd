extends CanvasLayer
class_name ParallaxBg
## Capa de fondo (paisaje) DETRÁS de la torre. Se ve donde no hay tiles.
## - parallax: 0 = fija (skybox); >0 = se mueve con la cámara (profundidad).
## - zoom + yoff: ENCUADRE. Elige qué franja vertical de la imagen se ve.
##   yoff negativo = sube la imagen → las ventanas muestran partes más BAJAS
##   (horizonte / valle). zoom da margen para no dejar huecos al desplazar.

var _tex_path := ""
var _parallax := 0.0
var _parallax_y := 0.0
var _tint := Color.WHITE
var _zoom := 1.0
var _yoff := 0.0
var _spr: Sprite2D

func init(tex_path: String, canvas_layer: int, parallax: float, tint := Color.WHITE, zoom := 1.0, yoff := 0.0, parallax_y := 0.0) -> ParallaxBg:
	_tex_path = tex_path
	layer = canvas_layer
	_parallax = parallax
	_parallax_y = parallax_y
	_tint = tint
	_zoom = zoom
	_yoff = yoff
	return self

func _ready() -> void:
	var tex := load(_tex_path) as Texture2D
	_spr = Sprite2D.new()
	_spr.texture = tex
	_spr.modulate = _tint
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_spr)
	_frame()
	get_viewport().size_changed.connect(_frame)
	set_process(_parallax != 0.0 or _parallax_y != 0.0)

func _frame() -> void:
	if _spr == null or _spr.texture == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var ts := _spr.texture.get_size()
	# COVER: llena la pantalla por el lado que falte (sin huecos a los costados); el
	# sobrante se recorta. El fondo es cuadrado y la pantalla 16:9 → fit por ancho.
	var fit := maxf(vp.x / ts.x, vp.y / ts.y) * _zoom
	_spr.scale = Vector2.ONE * fit
	# Anclado ARRIBA: muestra cielo + luna/eclipse; el valle inferior (que igual tapa
	# la mazmorra) queda fuera. yoff < 0 baja el encuadre para ver más valle.
	_spr.position = Vector2(vp.x * 0.5, ts.y * fit * 0.5 + _yoff)

func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var c := cam.get_screen_center_position()
		offset = Vector2(-c.x * _parallax, -c.y * _parallax_y)
