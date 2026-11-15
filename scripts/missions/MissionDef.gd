class_name MissionDef
extends Resource
## Definicion de una mision de ZYRANTH. Cada mision es un dilema de ingenieria: algo que
## proteger y algo que sacrificar. Todos los numeros son PARAMETROS DE SIMULACION, no datos reales.
##
## Niveles (tier): 1 = Facil, 2 = Intermedio, 3 = Avanzado. Dentro de cada nivel la mision tiene
## su propia dificultad (1 Facil, 2 Media, 3 Dificil) y se desbloquea al superar la anterior.

const TIER_NAMES: PackedStringArray = ["", "Fácil", "Intermedia", "Avanzada"]
const TIER_COLORS: Array[Color] = [Color.WHITE, Color("2ecc71"), Color("4fa3ff"), Color("b07cff")]
const DIFFICULTY_NAMES: PackedStringArray = ["", "Fácil", "Media", "Difícil"]
const DIFFICULTY_COLORS: Array[Color] = [Color.WHITE, Color("2ecc71"), Color("f1b434"), Color("ff7a4d")]

@export var id: String = ""
@export var title: String = ""
@export var place: String = ""
@export var icon: String = ""
@export_range(1, 3) var tier: int = 1
@export_range(1, 3) var difficulty: int = 1   # dificultad dentro de su nivel
@export var requires: String = ""          # id de la mision que hay que superar antes
@export var ready: bool = true             # false = "proximamente"
@export var scene: String = "res://scenes/LunarBase.tscn"   # escena que se carga al empezar
@export var summary: String = ""

# --- Dilema o compensacion (se muestra antes de empezar)
@export var dilemma_title: String = ""
@export var dilemma_text: String = ""
@export var protect: String = ""           # lo que hay que salvar
@export var sacrifice: String = ""         # lo que habra que ceder
@export var objectives: PackedStringArray = PackedStringArray()
@export var victory_text: String = ""

# --- Escenario
@export var script_id: String = "awakening"   # guion de eventos en MissionDirector
@export var turns: int = 9
@export var night_from_turn: int = 4
@export var alert_turn: int = 6               # 0 = sin alerta solar
@export var alert_tier_min: int = 0           # >0 fija un nivel minimo de alerta (parametro de simulacion)
@export var solar_factor: float = 1.0         # multiplica la generacion de los paneles
@export var start: Dictionary = {}            # valores iniciales que cambian (main, backup, materials, shield...)
@export var win_extra: Dictionary = {}        # condiciones extra de victoria (max_exposure, min_health, min_data...)

# --- Modificadores de dificultad
@export var consumption_factor: float = 1.0   # >1 = la tripulacion y el hogar consumen mas por turno
@export var event_aggression: float = 0.0     # 0 = sin sucesos de riesgo; >0 = fallos mas probables si descuidas un sistema
@export var rules: Dictionary = {}            # reglas propias: light_cycle, plant_o2, ls_output, heat_comms, breach


func tier_label() -> String:
	return TIER_NAMES[clampi(tier, 1, 3)]


func tier_color() -> Color:
	return TIER_COLORS[clampi(tier, 1, 3)]


func difficulty_label() -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 1, 3)]


func difficulty_color() -> Color:
	return DIFFICULTY_COLORS[clampi(difficulty, 1, 3)]


func stars() -> String:
	return "★".repeat(clampi(difficulty, 1, 3)) + "☆".repeat(3 - clampi(difficulty, 1, 3))


## Resumen corto de los modificadores para mostrar antes de empezar.
func modifiers_text() -> String:
	var parts: PackedStringArray = []
	if consumption_factor > 1.001:
		parts.append("consumo +%d%%" % int(round((consumption_factor - 1.0) * 100.0)))
	if event_aggression > 0.0:
		parts.append("fallos más agresivos (%d%%)" % int(round(event_aggression * 100.0)))
	if solar_factor < 0.999:
		parts.append("paneles al %d%%" % int(round(solar_factor * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "sin modificadores"
