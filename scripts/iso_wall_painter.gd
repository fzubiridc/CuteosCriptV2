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

## CUTAWAY POR-MURO: cada frame, transparenta las FACHADAS que tapan al player (sala o corredor) y vuelve
## opacas las que dejaron de taparlo. Reemplaza el reveal por-sala. Solo mira fachadas cerca del player.
func update_cutaway(pl) -> void:
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		return
	var n2 := pl as Node2D
	var feet := n2.get_node_or_null("Feet") as Node2D
	var pp: Vector2 = feet.global_position if feet != null else n2.global_position
	var body := pp + Vector2(0, d.CUT_BODY_UP)
	var pc := d.local_to_map(d.to_local(pp))
	var covering := {}
	var cover_cells := {}
	for dy in range(-d.CUT_R, d.CUT_R + 1):
		for dx in range(-d.CUT_R, d.CUT_R + 1):
			var cell := pc + Vector2i(dx, dy)
			if not d._front_walls.has(cell):
				continue
			for h in d._front_walls[cell]:
				if is_instance_valid(h) and _wall_covers(h, pp, body):
					covering[h] = true
					d._cut_active[h] = true
					cover_cells[cell] = true
	# Expandir a las fachadas PEGADAS (vecinos de las celdas que tapan) → patch suave, no un tile suelto.
	for cell in cover_cells:
		for nb in d.CUT_NEIGHBORS:
			var nc: Vector2i = cell + nb
			if not d._front_walls.has(nc):
				continue
			for h2 in d._front_walls[nc]:
				if is_instance_valid(h2):
					covering[h2] = true
					d._cut_active[h2] = true
	var done: Array = []
	for h in d._cut_active:
		if not is_instance_valid(h):
			done.append(h)
			continue
		var target: float = d.CUT_ALPHA if covering.has(h) else 1.0
		# Histéresis asimétrica: ENCENDER rápido (0.4) / APAGAR lento (0.05) → en el frame de cruce
		# entre dos muros del borde, el siguiente muro ya está prendido antes de que el anterior apague.
		var rate: float = 0.40 if covering.has(h) else 0.05
		h.modulate.a = lerpf(h.modulate.a, target, rate)
		if not covering.has(h) and h.modulate.a > 0.985:
			h.modulate.a = 1.0
			done.append(h)
	for h in done:
		d._cut_active.erase(h)

## ¿Esta fachada tapa al player? Su base tiene que estar al SUR/cerca (muro adelante) y su silueta
## (ancho CUT_HW, alto CUT_H hacia arriba) cubrir el cuerpo del player.
func _wall_covers(holder: Node2D, _pp: Vector2, body: Vector2) -> bool:
	var base := holder.global_position
	if base.y < body.y - 6.0:   # base al norte del CUERPO → muro detrás del player → no lo tapa.
		return false
	return absf(body.x - base.x) < d.CUT_HW and body.y > base.y - d.CUT_H and body.y < base.y + d.CUT_FOOT
