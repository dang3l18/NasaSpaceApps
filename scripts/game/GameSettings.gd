class_name GameSettings
extends RefCounted
## Modo de juego elegido en el menu. Estatico: sobrevive al cambio de escena.
##   principiante (7-9 anos):   3 acciones por turno y consumo de recursos 25% menor.
##   intermedio  (10-12 anos):  2 acciones por turno y consumo normal.

static var mode: String = "intermedio"


static func actions_per_turn() -> int:
	return 3 if mode == "principiante" else 2


static func consumption_factor() -> float:
	return 0.75 if mode == "principiante" else 1.0


static func mode_label() -> String:
	return "Modo Principiante" if mode == "principiante" else "Modo Intermedio"
