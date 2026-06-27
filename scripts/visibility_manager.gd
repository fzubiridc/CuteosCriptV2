extends Node
class_name VisibilityManager   # class_name para preload/tipado estático desde main.gd
## Gating de visibilidad — "ocultar info" estilo Diablo 2. Cada EVERY_N frames recorre las
## entidades del grupo "vis_gated" y setea su `visible` según la grilla de niebla del Dungeon.
##   - "vis_threat" (enemigos/jefe = amenazas vivas) → visible SOLO si su celda está en tu radio
##     AHORA (parpadea con tu visión). Te pueden acechar/pegar desde la sombra: SIGUEN simulando.
##   - resto (cofres/mercader/decor = objetos del mundo) → sticky: visible una vez que su celda
##     fue vista (cell_seen no se revierte) → no desaparecen al alejarte (no molesta).
## Solo se gatea el RENDER acá; la SIMULACIÓN (física/IA) no se toca — eso es el sleep del enemy, aparte.

const EVERY_N := 4   # recalcular cada 4 frames (~15 Hz): invisible al ojo, divide el costo por 4

var _dungeon = null   # sin tipar → acceso dinámico a cell_seen / is_cell_visible / is_cell_seen
var _t := 0

func setup(dungeon) -> void:
	_dungeon = dungeon
	_t = EVERY_N   # correr en el primer frame para no mostrar entidades no-vistas ni un instante

func _process(_dt: float) -> void:
	if _dungeon == null or not is_instance_valid(_dungeon):
		return
	_t += 1
	if _t < EVERY_N:
		return
	_t = 0
	if _dungeon.cell_seen.is_empty():
		return
	for e in get_tree().get_nodes_in_group("vis_gated"):
		var n := e as Node2D
		if n == null or not is_instance_valid(n):
			continue
		if n.is_in_group("vis_threat"):
			n.visible = _dungeon.is_cell_visible(n.global_position)   # amenaza: parpadea con tu radio
		else:
			n.visible = _dungeon.is_cell_seen(n.global_position)      # objeto: sticky (cell_seen no revierte)
