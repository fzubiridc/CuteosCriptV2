extends Node
## Materiales de FX compartidos (cacheados) para no crear un CanvasItemMaterial nuevo por
## instancia/frame. Los FX 2.5D (orbe, estela, explosión, llamas del AoE, estela del dash)
## se dibujan auto-iluminados: o bien ADD+UNSHADED (suman luz: orbe glow, fuego, destellos),
## o bien solo UNSHADED (arte con glow propio que no debe recibir la luz del mundo).
## Como estos materiales no tienen estado por-instancia, una sola copia compartida alcanza.

static var _add: CanvasItemMaterial
static var _mix: CanvasItemMaterial

## ADD + UNSHADED: suma destello (glow aditivo) sin recibir la luz de la escena. Para orbes
## glow, fuego del AoE y discos/flashes de impacto. Lazy-init cacheado (se crea al 1er uso).
func add_unshaded() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _add

## Solo UNSHADED (blend normal): arte con glow propio que no debe oscurecerse con la luz del
## mundo (animación `power`/`powerboom` del orbe del mago, estela del dash). Lazy-init cacheado.
func mix_unshaded() -> CanvasItemMaterial:
	if _mix == null:
		_mix = CanvasItemMaterial.new()
		_mix.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _mix
