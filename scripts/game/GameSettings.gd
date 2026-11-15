class_name GameSettings
extends RefCounted
## Modo de juego elegido en el menu. Estatico: sobrevive al cambio de escena.
##   principiante (7-9 anos):   +4 horas de trabajo por turno y alertas solares mas suaves.
##   intermedio  (10-12 anos):  reglas normales.

static var mode: String = "intermedio"
static var start_screen: String = "title"   # pantalla del menu al volver de una partida


static func actions_per_turn() -> int:
	return 3 if mode == "principiante" else 2


static func consumption_factor() -> float:
	return 0.75 if mode == "principiante" else 1.0


static func mode_label() -> String:
	return "Modo 7–9 años" if mode == "principiante" else "Modo 10–12 años"
