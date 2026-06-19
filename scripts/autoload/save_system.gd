extends Node
## Persistencia (F10): guarda la run en curso en user:// (para cerrar y continuar)
## y los récords (meta-progresión). Schema carcel_run_v1.

const RUN_PATH := "user://carcel_run_v1.json"
const REC_PATH := "user://carcel_records_v1.json"

func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func save_run(run: Dictionary, player: Node) -> void:
	if player == null:
		return
	_write(RUN_PATH, {"v": 1, "run": run, "player": player.to_save()})

func load_run() -> Dictionary:
	return _read(RUN_PATH)

func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))

## Registra el resultado de una run terminada (muerte o victoria) en los récords.
func record(run: Dictionary, player: Node, won: bool) -> void:
	var r := get_records()
	r["runs"] = int(r.get("runs", 0)) + 1
	r["kills"] = int(r.get("kills", 0)) + int(run.get("kills", 0))
	if won:
		r["wins"] = int(r.get("wins", 0)) + 1
	r["best_depth"] = maxi(int(r.get("best_depth", 0)), int(run.get("depth", 1)))
	r["best_kills"] = maxi(int(r.get("best_kills", 0)), int(run.get("kills", 0)))
	if player != null:
		r["best_coins"] = maxi(int(r.get("best_coins", 0)), int(player.coins))
	if won:
		var t := float(run.get("time", 0.0))
		var prev := float(r.get("best_time", 0.0))
		r["best_time"] = t if prev <= 0.0 else minf(prev, t)
	_write(REC_PATH, r)

func get_records() -> Dictionary:
	return _read(REC_PATH)

# ---------------------------------------------------------------------------
func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
