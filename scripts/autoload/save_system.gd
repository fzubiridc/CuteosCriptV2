extends Node
## Persistencia (F10): guarda la run en curso en user:// (para cerrar y continuar)
## y los récords (meta-progresión). Schema carcel_run_v1.

const RUN_PATH := "user://carcel_run_v1.json"
const REC_PATH := "user://carcel_records_v1.json"
## Versión de schema: si el archivo no la trae o no coincide, se trata como ausente.
const SCHEMA_VERSION := 1

func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func save_run(run: Dictionary, player: Node) -> void:
	if player == null:
		return
	# Estampa la versión de schema para validarla al cargar.
	_write(RUN_PATH, {"v": SCHEMA_VERSION, "run": run, "player": player.to_save()})

func load_run() -> Dictionary:
	return _read(RUN_PATH)

func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))

## Registra el resultado de una run terminada (muerte o victoria) en los récords.
func record(run: Dictionary, player: Node, won: bool) -> void:
	var r := get_records()
	r["v"] = SCHEMA_VERSION  # estampa versión de schema en los récords
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
## Escritura atómica: vuelca a un .tmp, lo cierra y recién ahí reemplaza el
## archivo final con rename. Así un crash a mitad de escritura no deja el JSON
## destino truncado (a lo sumo queda un .tmp incompleto que se ignora).
func _write(path: String, data: Dictionary) -> void:
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: no se pudo abrir para escribir %s" % tmp_path)
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()  # cierra antes de renombrar para garantizar el volcado a disco
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	var abs_dst := ProjectSettings.globalize_path(path)
	# rename_absolute no sobrescribe en Windows: borro el destino previo primero.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_dst)
	var err := DirAccess.rename_absolute(abs_tmp, abs_dst)
	if err != OK:
		push_warning("SaveSystem: fallo al renombrar %s -> %s (err %d)" % [tmp_path, path, err])

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary):
		# JSON corrupto/truncado: lo preservo en .corrupt para diagnóstico y devuelvo vacío.
		push_warning("SaveSystem: JSON inválido en %s; se preserva como .corrupt" % path)
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(path + ".corrupt"))
		return {}
	var dict: Dictionary = d
	# Validación de schema: si falta "v" o no coincide, trato el save como ausente
	# (no cargo a ciegas un formato viejo/desconocido).
	if int(dict.get("v", -1)) != SCHEMA_VERSION:
		push_warning("SaveSystem: versión de schema ausente/incompatible en %s; se ignora" % path)
		return {}
	return dict
