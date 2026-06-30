extends Node
## CATÁLOGO de props iso. Lee tools/rig/props.json (editado en props_tool.html) y expone los
## assets con su meta: textura, escala, anclaje (centro/borde de muro), offset, polígono(s) de
## colisión (cell-local, mismo espacio que el occluder del muro), weight y enabled.
##
## Fallback: si props.json no existe todavía, auto-descubre TODOS los PNG bajo assets/iso/props/
## con meta por defecto (enabled, escala por ancho, anclaje centro) → el scatter del generador
## funciona out-of-the-box y después curás en la tool. reload() re-lee tras editar.

const PROPS_PATH := "res://tools/rig/props.json"
const PROPS_DIR := "res://assets/iso/props"

## Punto de anclaje (cell-local) donde apoya la BASE del asset. Mismos midpoints que
## DungeonDecor._edge_midpoint (rombo 256×128 centrado en 0,0).
const ANCHOR := {
	"center": Vector2(0, 0),
	"wall_nw": Vector2(-64, -32),
	"wall_ne": Vector2(64, -32),
	"wall_se": Vector2(64, 32),
	"wall_sw": Vector2(-64, 32),
}

var props: Array = []          # Array[Dictionary]: {path, tex, scale, anchor, offset, collision, weight, enabled, z}
var _loaded := false

func _ready() -> void:
	reload()

## Re-lee el catálogo desde props.json (o auto-scan si no existe). Llamable tras editar en la tool.
func reload() -> void:
	props = []
	var cat := _read_catalog()
	if cat.is_empty():
		cat = _scan_defaults()
	for path in cat:
		var m: Dictionary = cat[path] if cat[path] is Dictionary else {}
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		if tex == null:
			continue   # no importado todavía → lo salteamos (no rompe el scatter)
		var w := tex.get_width()
		var scale_v: float = float(m.get("scale", 0.0))
		if scale_v <= 0.0:
			scale_v = (384.0 / float(w)) if w > 0 else 1.5   # default prominente (~1.5× tile; se ajusta en la tool)
		var off: Array = m.get("offset", [0, 0])
		var offset_v := Vector2(float(off[0]) if off.size() > 0 else 0.0, float(off[1]) if off.size() > 1 else 0.0)
		props.append({
			"path": path,
			"tex": tex,
			"scale": scale_v,
			"anchor": String(m.get("anchor", "center")),
			"offset": offset_v,
			"collision": _parse_collision(m.get("collision", [])),
			"occlusion": _parse_collision(m.get("occlusion", [])),   # huella para el z-order (si vacía → usa collision)
			"weight": float(m.get("weight", 1.0)),
			"enabled": bool(m.get("enabled", true)),
			"z": int(m.get("z", 0)),
			"ysort": float(m.get("ysort", 0.0)),   # offset del pivote de y-sort (cell-local; neg = te tapa más tarde)
		})
	_loaded = true

## Props habilitados (los que el generador puede esparcir).
func enabled_props() -> Array:
	if not _loaded:
		reload()
	return props.filter(func(p): return p.enabled)

## Elige un prop al azar ponderado por su weight (usa el RNG global seedable).
func pick_weighted(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for p in pool:
		total += maxf(0.0, p.weight)
	if total <= 0.0:
		return pool[Rng.range_i(0, pool.size() - 1)]
	var r := Rng.range_f(0.0, total)
	for p in pool:
		r -= maxf(0.0, p.weight)
		if r <= 0.0:
			return p
	return pool[pool.size() - 1]

func anchor_offset(name: String) -> Vector2:
	return ANCHOR.get(name, Vector2.ZERO)

# ---------------------------------------------------------------------------
# Lectura / parseo
# ---------------------------------------------------------------------------
func _read_catalog() -> Dictionary:
	var g := ProjectSettings.globalize_path(PROPS_PATH)
	if not FileAccess.file_exists(g):
		return {}
	var f := FileAccess.open(g, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}

## Polígonos de colisión: SINGLE [[x,y],...] o MULTI [[[x,y],...],...] → Array[PackedVector2Array].
func _parse_collision(raw: Variant) -> Array:
	var out: Array = []   # Array[PackedVector2Array]
	if not (raw is Array) or (raw as Array).is_empty():
		return out
	var arr := raw as Array
	var first = arr[0]
	var is_multi: bool = first is Array and (first as Array).size() > 0 and (first as Array)[0] is Array
	if is_multi:
		for poly_raw in arr:
			if poly_raw is Array:
				var p := _pts(poly_raw)
				if p.size() >= 3:
					out.append(p)
	else:
		var p := _pts(arr)
		if p.size() >= 3:
			out.append(p)
	return out

func _pts(raw: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in raw:
		if p is Array and (p as Array).size() >= 2:
			pts.append(Vector2(float(p[0]), float(p[1])))
	return pts

## Auto-descubre PNGs bajo PROPS_DIR (recursivo) con meta por defecto. Solo si props.json falta.
func _scan_defaults() -> Dictionary:
	var cat := {}
	_scan_dir(PROPS_DIR, cat)
	return cat

func _scan_dir(dir_path: String, cat: Dictionary) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_path + "/" + name
			if da.current_is_dir():
				_scan_dir(full, cat)
			elif name.to_lower().ends_with(".png"):
				cat[full] = {}   # meta vacía → defaults en reload()
		name = da.get_next()
	da.list_dir_end()
