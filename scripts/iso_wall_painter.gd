extends RefCounted
class_name IsoWallPainter
## PINTOR DE MUROS ISO — extraído de dungeon.gd (que se volvió god-object otra vez, ~1660 líneas). Opera
## sobre el nodo Dungeon vía `d.*` (estado/consts/métodos), igual que DungeonGen/DungeonDecor/DungeonFog.
## Se crea lazy (`_ensure_wall_painter` en dungeon.gd). El ESTADO de muros (texturas, spans, materiales,
## _front_walls…) sigue viviendo en dungeon.gd (lo leen varios sistemas por `d.`); acá vive la LÓGICA.
##
## Extracción por TAJADAS verificadas en vivo. Tajada 1: CUTAWAY por-muro.

var d: Dungeon

func _init(dungeon: Dungeon) -> void:
	d = dungeon

## CUTAWAY HÍBRIDO (CPU decide + shader dibuja): la CPU determina POR-MURO cuáles fachadas te tapan de verdad
## (test de silueta `_wall_covers`, exacto — sin heurístico de profundidad que fallaba en los sub-cuartos) y
## les prende el flag `cutaway_active`. El shader (`wall_face.gdshader`) hace el HUECO elíptico por-píxel
## centrado en el player SOLO en esos muros → suave (sin chunk, sin costura entre tiles) Y preciso (nada de
## transparencias raras en muros que no te tapan). El "parche" a vecinos hace que la elipse cruce el borde de
## tile a tile sin cortarse.
func update_cutaway(pl) -> void:
	var mat: ShaderMaterial = d._iso_wall_mat_solid
	if mat == null:
		return
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		mat.set_shader_parameter("cutaway_on", false)
		for h in d._cut_active:
			_set_active(h, false)
		d._cut_active.clear()
		return
	var n2 := pl as Node2D
	var feet := n2.get_node_or_null("Feet") as Node2D
	var pp: Vector2 = feet.global_position if feet != null else n2.global_position
	var body := pp + Vector2(0, d.CUT_BODY_UP)   # centro del hueco un toque arriba de los pies
	mat.set_shader_parameter("cutaway_on", true)
	mat.set_shader_parameter("cutaway_pos", body)
	# CPU: qué FACHADAS tapan al player (test de silueta por-muro). Solo mira las cercanas.
	var pc := d.local_to_map(d.to_local(pp))
	var covering := {}
	var cover_cells := {}
	for dy in range(-d.CUT_R, d.CUT_R + 1):
		for dx in range(-d.CUT_R, d.CUT_R + 1):
			var cell := pc + Vector2i(dx, dy)
			if not d._front_walls.has(cell):
				continue
			for h in d._front_walls[cell]:
				if is_instance_valid(h) and _wall_covers(h, body):
					covering[h] = true
					cover_cells[cell] = true
	# Parche a las fachadas PEGADAS (vecinos de las que tapan) → la elipse cruza de tile a tile sin cortarse.
	for cell in cover_cells:
		for nb in d.CUT_NEIGHBORS:
			var nc: Vector2i = cell + nb
			if not d._front_walls.has(nc):
				continue
			for h2 in d._front_walls[nc]:
				if is_instance_valid(h2):
					covering[h2] = true
	# Prender las que tapan; apagar las que dejaron de tapar (o se liberaron).
	for h in covering:
		_set_active(h, true)
		d._cut_active[h] = true
	var done: Array = []
	for h in d._cut_active:
		if not is_instance_valid(h):
			done.append(h)
		elif not covering.has(h):
			_set_active(h, false)
			done.append(h)
	for h in done:
		d._cut_active.erase(h)

## Prende/apaga el flag cutaway_active del sprite (hijo 0 del holder) para el shader.
func _set_active(holder: Node2D, on: bool) -> void:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var ci := holder.get_child(0) as CanvasItem
	if ci != null:
		ci.set_instance_shader_parameter("cutaway_active", on)

## ¿Esta fachada tapa al player? Su base al SUR/cerca del cuerpo (muro adelante) y su silueta (ancho CUT_HW,
## alto CUT_H) cubre el cuerpo. Es el test exacto por-muro (más preciso que el gate de profundidad del shader).
func _wall_covers(holder: Node2D, body: Vector2) -> bool:
	var base := holder.global_position
	if base.y < body.y - 6.0:   # base al norte del cuerpo → muro detrás del player → no lo tapa
		return false
	return absf(body.x - base.x) < d.CUT_HW and body.y > base.y - d.CUT_H and body.y < base.y + d.CUT_FOOT
