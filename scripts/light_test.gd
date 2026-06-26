extends Node2D
## Mapa de testing AISLADO para la iluminación direccional de caras de muro.
## - 3 muros (mismo shader wall_face que el juego, con normal de cara que mira a la cámara).
## - UNA sola luz que seguís con el MOUSE (sin las 28 antorchas que confunden la escena real).
## - Logging en pantalla: facing/relief del muro central + si la cara está LIT/DARK.
## - SPACE: prende/apaga la direccionalidad (face_floor 0.2 <-> 1.0) para comparar al toque.
## - UP/DOWN: ajusta face_z en vivo.
##
## Cómo leerlo: movés el mouse ARRIBA de un muro (la luz queda "detrás") → la cara se
## apaga. Lo movés ABAJO (luz "delante", del lado de la cámara) → se ilumina. Con la
## direccionalidad OFF la cara se ilumina venga la luz de donde venga (el bug).

const FACE_SHADER := preload("res://shaders/wall_face.gdshader")
const WALL_TEX := preload("res://assets/iso/walls/wall1/highwall.png")
const FLOOR_TEX := preload("res://assets/iso/sbs/floor_pixel.png")

var _walls: Array[Sprite2D] = []
var _mat: ShaderMaterial
var _light_pos := Vector2(640, 500)
var _directional := true
var _face_z := 0.6
var _t := 0.0
var _auto := true   # la luz oscila sola atrás<->adelante; mové el mouse para tomar control
var _label: Label
var _light_dot: Sprite2D

func _ready() -> void:
	# Fondo oscuro para ver el contraste.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.size = Vector2(1280, 720)
	bg.z_index = -100
	add_child(bg)

	# Material de muro: igual config que el juego (cara plana direccional).
	_mat = ShaderMaterial.new()
	_mat.shader = FACE_SHADER
	var flat := Image.create(1, 1, false, Image.FORMAT_RGB8)
	flat.set_pixel(0, 0, Color(0.5, 0.5, 1.0))
	_mat.set_shader_parameter("normal_tex", ImageTexture.create_from_image(flat))
	_mat.set_shader_parameter("use_face_normal", true)

	# Una fila de 3 muros, separados, todos con cara mirando a la cámara (+Y).
	for i in 3:
		var w := Sprite2D.new()
		w.texture = WALL_TEX
		w.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		w.material = _mat
		w.position = Vector2(360 + i * 280, 320)
		add_child(w)
		_walls.append(w)

	# Marcador de la luz (punto magenta que sigue al mouse).
	_light_dot = Sprite2D.new()
	var dot := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	dot.fill(Color(1.0, 0.2, 1.0))
	_light_dot.texture = ImageTexture.create_from_image(dot)
	_light_dot.z_index = 100
	add_child(_light_dot)

	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	add_child(_label)

func _process(dt: float) -> void:
	# La luz oscila vertical: arranca DETRÁS de los muros (arriba) y baja al frente.
	_t += dt
	if _auto:
		_light_pos = Vector2(640, 320 - sin(_t * 0.9) * 280.0)
	var mouse := get_global_mouse_position()
	if mouse.distance_to(_light_pos) > 4.0 and Input.get_last_mouse_velocity().length() > 1.0:
		_auto = false
	if not _auto:
		_light_pos = mouse
	_light_dot.position = _light_pos

	var face_floor := 0.2 if _directional else 1.0
	# Alimentar el shader con UNA sola luz (sin LightField, control total).
	_mat.set_shader_parameter("light_count", 1)
	_mat.set_shader_parameter("light_pos", [_light_pos])
	_mat.set_shader_parameter("light_color", [Vector3(1.0, 1.0, 1.0)])
	_mat.set_shader_parameter("light_energy", [3.0])
	_mat.set_shader_parameter("light_radius", [900.0])
	_mat.set_shader_parameter("light_height", [10.0])
	_mat.set_shader_parameter("ambient", Vector3(0.06, 0.06, 0.09))
	_mat.set_shader_parameter("cap", 3.0)
	_mat.set_shader_parameter("light_boost", 1.0)
	_mat.set_shader_parameter("relief_floor", face_floor)
	_mat.set_shader_parameter("face_normal", Vector3(0.0, 1.0, _face_z))

	# Logging: facing/relief del muro central (mismo cálculo que el shader).
	var wc: Vector2 = _walls[1].position
	var fn := Vector2(0.0, 1.0)
	var delta := _light_pos - wc
	var facing := 0.0
	if delta.length() > 0.001:
		facing = fn.dot(delta.normalized())
	var ndl: float = clampf(facing, 0.0, 1.0)
	var relief: float = lerpf(face_floor, 1.0, ndl)
	var side := "DELANTE (cámara)" if facing > 0.0 else "DETRAS"
	var verdict := "LIT" if relief > 0.5 else ("DARK" if relief < 0.3 else "MEDIO")
	_label.text = "DIRECCIONALIDAD: %s   (SPACE para alternar)\nface_z: %.2f   (UP/DOWN)\n\nLuz del lado: %s\nfacing = %+.2f   relief = %.2f   ->  cara %s\n\nMové el mouse ARRIBA del muro (detrás) = oscuro,\nABAJO (delante/cámara) = iluminado." % [
		"ON" if _directional else "OFF (bug: ilumina venga de donde venga)",
		_face_z, side, facing, relief, verdict]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_directional = not _directional
		elif event.keycode == KEY_UP:
			_face_z = minf(_face_z + 0.1, 2.0)
		elif event.keycode == KEY_DOWN:
			_face_z = maxf(_face_z - 0.1, 0.0)
