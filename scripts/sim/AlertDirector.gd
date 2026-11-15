class_name AlertDirector
extends RefCounted
## Decide CUANDO aparece una alerta espacial y CUAL, sin saturar al jugador. Logica pura (sin nodos).
##
## - Tiempo de juego real: solo avanza mientras el jugador esta planificando (no durante tarjetas ni informes).
## - Intervalos variables entre alertas + espera minima (COOLDOWN) + maximo de alertas por mision.
## - Dificultad: sale de la mision (nivel y dificultad): mas alertas, mas seguidas y con menos tiempo para reaccionar.
## - Progresion: al avanzar los turnos pesan mas los eventos peligrosos (tier 3).
## - Modo 7-9 anos: intervalos y tiempos un 40% mas largos y una alerta menos.
## - Nunca en el turno de la tormenta solar de la mision ni en el ultimo turno.

const COOLDOWN := 30.0          # segundos minimos entre dos alertas
const FIRST_MIN := 25.0         # la primera alerta no llega antes de esto
const EASY_SLOWDOWN := 1.4

var rng := RandomNumberGenerator.new()
var level := 1                  # 1 (facil) .. 9 (avanzada dificil)
var max_count := 3
var count := 0
var elapsed := 0.0              # segundos de juego (solo planificando)
var next_at := 0.0
var last_at := -999.0
var last_id := ""
var _easy := false


func _init(s: BaseState, seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_easy = s.easy
	level = difficulty_level(s)
	max_count = 2 + (1 if level >= 4 else 0) + (1 if level >= 7 else 0)
	if _easy:
		max_count = maxi(1, max_count - 1)
	next_at = maxf(FIRST_MIN, _gap() * 0.7)


## 1..9 segun nivel (tier) y dificultad de la mision.
static func difficulty_level(s: BaseState) -> int:
	if s.mission == null:
		return 1
	return clampi((s.mission.tier - 1) * 3 + s.mission.difficulty, 1, 9)


## Segundos hasta la siguiente alerta (aleatorio): mas corto cuanto mas dificil.
func _gap() -> float:
	var lo := clampf(70.0 - float(level) * 4.0, 38.0, 70.0)
	var g := rng.randf_range(lo, lo + 40.0)
	return g * (EASY_SLOWDOWN if _easy else 1.0)


## Probabilidad de que, llegado el momento, la alerta salga (sube con la dificultad).
func chance() -> float:
	return clampf(0.55 + 0.05 * float(level), 0.0, 1.0)


## Avanza el reloj `delta` segundos. Devuelve la alerta a mostrar (con `seconds` ajustados) o {} si todavia no toca.
func tick(delta: float, s: BaseState) -> Dictionary:
	if s.finished or count >= max_count:
		return {}
	elapsed += delta
	if elapsed < next_at or elapsed - last_at < COOLDOWN:
		return {}
	if s.turn >= s.turns or (s.alert_turn > 0 and s.turn == s.alert_turn):
		next_at = elapsed + 5.0          # no es buen momento: reintenta pronto
		return {}
	if rng.randf() > chance():
		next_at = elapsed + 8.0
		return {}
	var ev := pick(s)
	if ev.is_empty():
		next_at = elapsed + 8.0
		return {}
	last_at = elapsed
	next_at = elapsed + maxf(COOLDOWN, _gap())
	count += 1
	last_id = str(ev["id"])
	return ev


## Elige un evento segun la mision, el turno y la dificultad; devuelve una copia lista para jugar.
func pick(s: BaseState) -> Dictionary:
	var p := clampf(float(s.turn - 1) / maxf(1.0, float(s.turns - 1)), 0.0, 1.0)
	var weights := {1: 1.0 - 0.75 * p, 2: 0.7 + 0.3 * float(level) / 9.0, 3: 0.05 + 0.95 * p * (0.5 + float(level) / 18.0)}
	var pool: Array = []
	var total := 0.0
	for e in SpaceEvents.catalog():
		var only: Array = e.get("only", [])
		if not only.is_empty() and (s.mission == null or not (s.mission.id in only)):
			continue
		if str(e["id"]) == last_id:
			continue
		var w: float = float(weights[int(e["tier"])])
		pool.append([e, w])
		total += w
	if pool.is_empty():
		return {}
	var r := rng.randf() * total
	var chosen: Dictionary = pool[pool.size() - 1][0]
	for it in pool:
		r -= float(it[1])
		if r <= 0.0:
			chosen = it[0]
			break
	return instance(chosen, level, _easy)


## Copia del evento con el tiempo de reaccion ajustado a la dificultad (mas dificil = menos tiempo; modo 7-9 = mas).
static func instance(ev: Dictionary, lvl: int, easy: bool) -> Dictionary:
	var e: Dictionary = ev.duplicate(true)
	var secs := float(e["seconds"]) * (1.0 - 0.04 * float(lvl - 1)) * (EASY_SLOWDOWN if easy else 1.0)
	e["seconds"] = maxf(20.0, secs)
	return e
