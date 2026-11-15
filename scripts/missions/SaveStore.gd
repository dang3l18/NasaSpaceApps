class_name SaveStore
extends RefCounted
## Persistencia local en JSON (FileAccess). Una sola partida guardada con version.
## Escritura atomica: se escribe a un archivo temporal y luego se renombra, para no dejar
## un guardado a medias si el juego se cierra. Un archivo danado se ignora (no rompe el juego).

const VERSION := 1

static var path: String = "user://zyranth_save.json"
static var enabled: bool = true   # las pruebas lo desactivan o apuntan a otro archivo


static func default_data() -> Dictionary:
	return {"version": VERSION, "missions": {}, "achievements": {}, "stats": {"played": 0, "won": 0}}


static func load_data() -> Dictionary:
	var data := default_data()
	if not FileAccess.file_exists(path):
		return data
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return data
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null   # sin ruido en consola si esta danado
	if parsed is Dictionary:
		for k in data:
			if (parsed as Dictionary).has(k) and typeof(parsed[k]) == typeof(data[k]):
				data[k] = parsed[k]
	return data


static func save_data(data: Dictionary) -> bool:
	if not enabled:
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveStore: no se pudo escribir %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


static func delete_file() -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null and FileAccess.file_exists(path):
		dir.remove(path.get_file())
