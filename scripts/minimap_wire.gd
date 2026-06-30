extends Node2D
class_name MinimapWire
## Wireframe iso de aristas de pared (estilo AUTOMAP de Diablo II). Recibe las aristas en coords
## world-local del Dungeon + una proyección (center → origin, zoom) y las dibuja como líneas. Se usa
## en el radar (con material de recorte circular) y en el mapa completo (overlay translúcido).
## El recorte circular del radar lo hace el material (shaders/minimap_circle.gdshader), que opera
## sobre la posición LOCAL del vértice → funciona directo sobre lo que dibuja _draw().

var pts: PackedVector2Array = PackedVector2Array()   # pares (a, b) consecutivos, world-local del dungeon
var center := Vector2.ZERO      # punto world que cae sobre `origin`
var origin := Vector2.ZERO      # punto local del nodo donde se ancla `center` (centro del recuadro)
var zoom := 0.042               # world → px local
var color := Color(0.85, 0.78, 0.58, 0.92)
var width := 1.0
var cull := 0.0                 # si > 0: descarta segmentos cuyo punto medio diste más que esto de `origin`
# Markers (world-local; x = INF → oculto)
var player_w := Vector2(INF, INF)
var exit_w := Vector2(INF, INF)

func _to_local(w: Vector2) -> Vector2:
	return (w - center) * zoom + origin

func _draw() -> void:
	var n := pts.size()
	if n >= 2:
		var line := PackedVector2Array()
		var i := 0
		while i + 1 < n:
			var a := _to_local(pts[i])
			var b := _to_local(pts[i + 1])
			i += 2
			if cull > 0.0 and (((a + b) * 0.5) - origin).length() > cull:
				continue
			line.append(a)
			line.append(b)
		if line.size() >= 2:
			draw_multiline(line, color, width, true)
	if exit_w.x != INF:
		_draw_diamond(_to_local(exit_w), 4.5, Color(0.78, 0.55, 1.0, 0.95))
	if player_w.x != INF:
		_draw_diamond(_to_local(player_w), 5.0, Color(0.45, 0.9, 1.0, 1.0))

func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)
	]), col)
