class_name SimConfig
extends RefCounted
## PARAMETROS DE SIMULACION de Operacion: Refugio Lunar.
## Son valores de juego, ajustables, pensados para ensenar equilibrio entre sistemas.
## NO son cifras reales de NASA ni mediciones.

const TURNS := 9
const TURNS_PER_DAY := 3
const NIGHT_FROM_TURN := 4          # turnos 1-3 dia lunar; 4-9 noche (2 dias, segun el boceto)

# Presupuestos por turno
const CREW_HOURS := 24              # horas de trabajo de la tripulacion por turno
const START_MATERIALS := 100.0

# Energia (unidades de simulacion)
const PANEL_OUTPUT := 75.0          # por panel y por turno de dia
const PANELS_START := 4
const PANELS_MAX := 6
const MAIN_CAP := 600.0
const BACKUP_CAP := 400.0
const MAIN_START := 420.0
const LOAD_LS := 70.0               # soporte vital (esencial)
const LOAD_SHELTER := 40.0          # refugio activo durante una alerta
const LOAD_CONTROL := 30.0
const LOAD_HABITAT := 30.0
const LOAD_LED := [0.0, 35.0, 70.0]
const LIGHT := [0.2, 0.6, 1.0]      # factor de luz de cada nivel LED

# Soporte vital
const O2_USE := 9.0
const O2_LS := 11.0
const O2_PLANTS := 5.0
const CO2_GEN := 8.0
const CO2_LS := 9.0
const CO2_PLANTS := 3.0
const WATER_USE := 5.0
const WATER_LS := 6.0
const WATER_PLANTS_RETURN := 1.5
const WATER_PLANTS_USE := 1.2
const LS_DECAY := 7.0
const LS_MAINTAIN := 25.0

# Alimentos
const FOOD_USE := 12.0
const FOOD_PER_BED := 4.0
const START_FOOD := 60.0
const FOOD_WIN_MIN := 12.0

# Radiacion (nivel de alerta -> exposicion simulada de la tripulacion, 0-100)
const ALERT_TURN := 6
const ALERT_EXPOSURE := {1: 45.0, 2: 85.0, 3: 120.0}
const AMBIENT_EXPOSURE := 3.0
const EXPOSURE_FAIL := 100.0
const EXPOSURE_WIN_MAX := 80.0
const SHIELD_START := 40.0
const SHELTER_START := 25.0
const SHIELD_DECAY := 2.0
const SHIELD_BUILD := 14.0
const SHELTER_BUILD := 20.0

# Modo principiante (7-9 anos): mas horas de trabajo y alertas algo menos severas
const EASY_HOURS_BONUS := 4
const EASY_ALERT_FACTOR := 0.8
