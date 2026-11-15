class_name Progress
extends RefCounted
## Logros y progreso guardados en local (user://progress.cfg). Sin red, sin datos personales.

const PATH := "user://progress.cfg"

const ACHIEVEMENTS := [
	{"id": "first_win", "name": "Primera misión superada", "desc": "Completa los 9 turnos del Refugio Lunar."},
	{"id": "shield_saver", "name": "Escudo de regolito", "desc": "Supera la tormenta solar con el blindaje reforzado."},
	{"id": "expert", "name": "Astronauta experto", "desc": "Gana una misión en Modo Intermedio."},
	{"id": "storm_survivor", "name": "Sobreviviente de tormentas", "desc": "Gana ante una alerta solar de nivel 3."},
	{"id": "data_scientist", "name": "Científico de datos", "desc": "Abre el Space Data Center."},
]


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)
	return c


static func unlock(id: String) -> void:
	var c := _cfg()
	if not c.get_value("achievements", id, false):
		c.set_value("achievements", id, true)
		c.save(PATH)


static func is_unlocked(id: String) -> bool:
	return bool(_cfg().get_value("achievements", id, false))


static func record_game(won: bool, mode: String, reinforced: bool, severity: int) -> void:
	var c := _cfg()
	c.set_value("stats", "played", int(c.get_value("stats", "played", 0)) + 1)
	if won:
		c.set_value("stats", "won", int(c.get_value("stats", "won", 0)) + 1)
	c.save(PATH)
	if won:
		unlock("first_win")
		if reinforced:
			unlock("shield_saver")
		if mode == "intermedio":
			unlock("expert")
		if severity >= 3:
			unlock("storm_survivor")


static func stats() -> Dictionary:
	var c := _cfg()
	return {"played": int(c.get_value("stats", "played", 0)), "won": int(c.get_value("stats", "won", 0))}
