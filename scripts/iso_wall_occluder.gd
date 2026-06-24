extends TileMapLayer
## Muros iso — dos cosas:
##  1) OCCLUDER por código (deducido del polígono de COLISIÓN del tile) → el muro
##     proyecta sombra sobre el PISO. Godot 4.7 no persiste el occluder per-tile
##     en el .tres, por eso se setea en runtime.
##  2) ILUMINACIÓN per-píxel por DISTANCIA con wall_face.gdshader (unshaded) → el
##     muro no usa la luz 2D nativa (evita los artefactos de cara mal iluminada /
##     sombra del occluder sobre el sprite); se ilumina por cercanía a las luces.
##
## Nota: la iluminación DIRECCIONAL de cara (que la cara responda a de qué lado
## viene la luz) se intentó pero no conviene con muros altos iso — quedó descartada.

const WALL_SOURCE_ID := 1              # source "wall" en iso_dungeon_v8.tres
const WALL_ATLAS := Vector2i(0, 0)
const OCC_LAYER := 0
const FACE_SHADER := preload("res://shaders/wall_face.gdshader")

## Cutout: el muro abre una cúpula dithered donde el player queda detrás.
@export var cutout_enabled := true
@export var cutout_w := 45.0            # medio-ancho del hueco (world units)
@export var cutout_h := 85.0            # alto de la cúpula hacia abajo, cabeza→pies (world units)
@export var cutout_up_squash := 4.0     # cuánto se cierra por encima de la cabeza (más alto = no sube a muros de atrás)
@export var cutout_angle_deg := 22.0    # rota el hueco para alinear el squash a la cara del muro iso (±)
@export var cutout_soft := 0.4          # ancho del anillo dithered (fracción 0..1)
@export var cutout_px := 2.0            # tamaño de celda del dither (más alto = más gordo)
@export var cutout_offset_y := 62.0     # subir el ancla del pie a la CABEZA

var _mat: ShaderMaterial
var _player: Node2D

func _ready() -> void:
	_install_occluder()
	_setup_face_material()
	_player = get_node_or_null("../Player") as Node2D

func _setup_face_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = FACE_SHADER
	# Normal plana → el shader hace solo falloff por distancia (sin relieve).
	var flat := Image.create(1, 1, false, Image.FORMAT_RGB8)
	flat.set_pixel(0, 0, Color(0.5, 0.5, 1.0))
	_mat.set_shader_parameter("normal_tex", ImageTexture.create_from_image(flat))
	material = _mat

func _process(_dt: float) -> void:
	if _mat == null:
		return
	LightField.apply_lights(_mat, LightField.current_packed())
	var boost: float = LightCfg.get_v("wall_light")
	_mat.set_shader_parameter("relief_floor", LightCfg.get_v("wall_relief"))
	_mat.set_shader_parameter("light_boost", boost)
	_mat.set_shader_parameter("cap", 1.4 * boost)

	# Cutout dithered siguiendo al player.
	var on := cutout_enabled and is_instance_valid(_player)
	_mat.set_shader_parameter("cutout_on", on)
	if on:
		_mat.set_shader_parameter("cutout_pos", _player.global_position - Vector2(0, cutout_offset_y))
		_mat.set_shader_parameter("cutout_w", cutout_w)
		_mat.set_shader_parameter("cutout_h", cutout_h)
		_mat.set_shader_parameter("cutout_up_squash", cutout_up_squash)
		_mat.set_shader_parameter("cutout_rot", deg_to_rad(cutout_angle_deg))
		_mat.set_shader_parameter("cutout_soft", cutout_soft)
		_mat.set_shader_parameter("cutout_px", cutout_px)

func _install_occluder() -> void:
	var ts := tile_set
	if ts == null:
		push_error("[iso_wall] capa Walls sin TileSet.")
		return
	if ts.get_occlusion_layers_count() == 0:
		ts.add_occlusion_layer()
	ts.set_occlusion_layer_light_mask(OCC_LAYER, 1)

	var src := ts.get_source(WALL_SOURCE_ID) as TileSetAtlasSource
	if src == null:
		push_error("[iso_wall] source %d no es TileSetAtlasSource." % WALL_SOURCE_ID)
		return
	var td := src.get_tile_data(WALL_ATLAS, 0)
	if td == null:
		push_error("[iso_wall] sin TileData para el muro.")
		return

	# Occluder = polígono de colisión del tile (huella física del muro).
	var pts := PackedVector2Array([
		Vector2(-128, 0), Vector2(0, -64), Vector2(10, -52), Vector2(-118, 12)
	])
	if td.get_collision_polygons_count(0) > 0:
		var cpts := td.get_collision_polygon_points(0, 0)
		if not cpts.is_empty():
			pts = cpts

	var occ := OccluderPolygon2D.new()
	occ.closed = true
	occ.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occ.polygon = pts
	td.set_occluder_polygons_count(OCC_LAYER, 1)
	td.set_occluder_polygon(OCC_LAYER, 0, occ)
	update_internals()
