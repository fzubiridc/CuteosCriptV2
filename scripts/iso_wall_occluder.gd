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

var _mat: ShaderMaterial
# Knobs cacheados (FIX: antes se leían de LightCfg.get_v() cada frame). Se refrescan
# solo cuando el panel cambia un valor, vía LightCfg.changed (patrón de torch.gd).
var _k_relief: float = 1.0
var _k_boost: float = 2.0
var _k_cap: float = LightCfg.LIGHT_CAP

func _ready() -> void:
	_install_occluder()
	_setup_face_material()
	_apply_cfg()
	LightCfg.changed.connect(_apply_cfg)

## Cachea los knobs de muro (refrescado por LightCfg.changed, no por frame).
func _apply_cfg() -> void:
	_k_boost = LightCfg.get_v("wall_light")
	_k_relief = LightCfg.get_v("wall_relief")
	_k_cap = LightCfg.LIGHT_CAP * _k_boost   # cap = LIGHT_CAP * boost (cap de luz, antes literal 1.4)

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
	# Las luces sí cambian por frame (dinámicas); los knobs salen del cache (_apply_cfg).
	LightField.apply_lights(_mat, LightField.current_packed())
	_mat.set_shader_parameter("relief_floor", _k_relief)
	_mat.set_shader_parameter("light_boost", _k_boost)
	_mat.set_shader_parameter("cap", _k_cap)

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
