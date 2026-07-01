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

## Z-ORDER DINÁMICO + CUTAWAY unificados (patrón de DungeonProps.update_occlusion), con FADE TEMPORAL para que
## no prenda/apague de golpe (menos "chunky"). Por-frame, para cada muro cercano:
##  · TRANSPARENCIA: si estás DETRÁS de su arista base (norte), su `cutaway_strength` LERPEA hacia 1 (hueco);
##    si no, hacia 0 (opaco). Se incluye a los muros CONTIGUOS (rango CUTAWAY_RX, más ancho que tu columna) →
##    la elipse cruza de tile a tile sin cortarse.
##  · Z: solo los muros de tu COLUMNA X (±halfwidth) flipean su z vs el player (z=0): detrás → +1 (te tapa),
##    delante → -1 (lo tapás). El flip a "arriba" recién cuando el muro ya está transparente (strength > Z_MASK)
##    → el salto de z queda enmascarado por la transparencia. Si el z de capa por defecto ya es correcto, no fuerza.
const Z_MASK := 0.5        # el flip de z a "arriba" recién con strength > esto (evita el pop del salto de z)
func update_cutaway(pl) -> void:
	var mat: ShaderMaterial = d._iso_wall_mat_solid
	if mat == null:
		return
	if pl == null or not is_instance_valid(pl) or not (pl is Node2D):
		mat.set_shader_parameter("cutaway_on", false)
		for h in d._cut_active:
			if is_instance_valid(h):
				_default_z(h)
				_set_strength(h, 0.0)
		d._cut_active.clear()
		return
	var n2 := pl as Node2D
	var feet := n2.get_node_or_null("Feet") as Node2D
	var f: Vector2 = feet.global_position if feet != null else n2.global_position
	var hw := _player_halfwidth(n2)
	# Knobs en vivo (panel L, LightCfg): tamaño/transparencia del óvalo + fade + rango contiguo.
	var fade: float = LightCfg.get_v("cutaway_fade")
	var rng: float = LightCfg.get_v("cutaway_range")
	mat.set_shader_parameter("cutaway_on", true)
	mat.set_shader_parameter("cutaway_min", LightCfg.get_v("cutaway_min"))
	mat.set_shader_parameter("cutaway_rx", LightCfg.get_v("cutaway_rx"))
	mat.set_shader_parameter("cutaway_ry", LightCfg.get_v("cutaway_ry"))
	mat.set_shader_parameter("cutaway_pos", f + Vector2(0, LightCfg.get_v("cutaway_up")))   # centro del óvalo
	var pc := d.local_to_map(d.to_local(f))
	# 1) Agrupar los muros cercanos por RUN (key). Todos los tiles de un muro comparten run → una decisión.
	var runs := {}   # key → {ra, rb, front, holders}
	for dy in range(-d.CUT_R, d.CUT_R + 1):
		for dx in range(-d.CUT_R, d.CUT_R + 1):
			var cell := pc + Vector2i(dx, dy)
			if not d._wall_depth_index.has(cell):
				continue
			for e in d._wall_depth_index[cell]:
				var k: String = e["key"]
				if not runs.has(k):
					runs[k] = {"ra": e["ra"], "rb": e["rb"], "front": bool(e["front"]), "holders": []}
				(runs[k]["holders"] as Array).append(e["holder"])
	# 2) UNA decisión por RUN (línea base del muro completo) → todos sus tiles flipean JUNTOS (sin escalera).
	var target := {}   # holder → 1.0 (estás detrás → tiende a transparente)
	var col := {}      # holder → {behind, front} (el muro está en tu columna X → flip de z)
	for k in runs:
		var r: Dictionary = runs[k]
		var ra: Vector2 = r["ra"]
		var rb: Vector2 = r["rb"]
		var xlo := minf(ra.x, rb.x)
		var xhi := maxf(ra.x, rb.x)
		var dxo := maxf(maxf(xlo - f.x, f.x - xhi), 0.0)   # distancia X del player al rango del muro
		if dxo > rng:
			continue
		var xq := clampf(f.x, xlo, xhi)
		var yb: float
		if absf(rb.x - ra.x) < 0.001:
			yb = maxf(ra.y, rb.y)
		else:
			yb = ra.y + (xq - ra.x) / (rb.x - ra.x) * (rb.y - ra.y)   # Y de la línea del muro en tu X
		var behind := f.y < yb        # pies al norte de la línea → el muro te tapa
		var in_col := dxo <= hw       # tu X cae dentro del muro → flipea su z
		for h in r["holders"]:
			if behind:
				target[h] = 1.0
			if in_col:
				col[h] = {"behind": behind, "front": bool(r["front"])}
	# 3) Lerp de strength + z, sobre la unión de (targets nuevos + activos previos).
	var keys := {}
	for h in target:
		keys[h] = true
	for h in d._cut_active:
		keys[h] = true
	var done: Array = []
	for h in keys:
		if not is_instance_valid(h):
			done.append(h)
			continue
		var cur: float = lerpf(float(d._cut_active.get(h, 0.0)), float(target.get(h, 0.0)), fade)
		if not target.has(h) and cur < 0.01:
			cur = 0.0
		_set_strength(h, cur)
		if col.has(h):
			var info: Dictionary = col[h]
			var z_over: bool = bool(info["behind"]) and cur > Z_MASK   # flip a "arriba" ya transparente
			_apply_z(h, z_over, bool(info["front"]))
		else:
			_default_z(h)
		if cur <= 0.0 and not col.has(h):
			done.append(h)
		else:
			d._cut_active[h] = cur
	for h in done:
		d._cut_active.erase(h)

## z del muro vs el player (0). z_over → +1 (te tapa); si no → -1 (lo tapás). Si coincide con el z de capa por
## defecto (fachada +1 / trasero -1), lo deja en relativo (no fuerza) → menos churn.
func _apply_z(holder: Node2D, z_over: bool, is_front: bool) -> void:
	if z_over == is_front:
		_default_z(holder)
	else:
		holder.z_as_relative = false
		holder.z_index = 1 if z_over else -1

func _default_z(holder: Node2D) -> void:
	holder.z_as_relative = true
	holder.z_index = 0

func _set_strength(holder: Node2D, s: float) -> void:
	if holder.get_child_count() == 0:
		return
	var ci := holder.get_child(0) as CanvasItem
	if ci != null:
		ci.set_instance_shader_parameter("cutaway_strength", s)

const HALFWIDTH_PAD := 7.0
## Medio-ancho (world) de la colisión del player (RectangleShape2D "Shape") + margen → la "columna" de comparación.
func _player_halfwidth(n2: Node2D) -> float:
	var sh := n2.get_node_or_null("Shape") as CollisionShape2D
	if sh != null and sh.shape is RectangleShape2D:
		return (sh.shape as RectangleShape2D).size.x * 0.5 * absf(n2.global_scale.x) + HALFWIDTH_PAD
	return 8.0 + HALFWIDTH_PAD
