class_name KidText
extends RefCounted
## Convierte la informacion tecnica del juego en comunicacion visual para ninos de 7 a 12 anos:
## palabras clave -> iconos, frases cortas por estado, analogias sencillas. Solo cambia la PRESENTACION:
## las mecanicas y los datos de NASA no se tocan (el detalle sigue disponible en «¿Sabías qué?»).

## Palabra clave (sin tildes finales) -> icono. El orden importa: gana la primera que aparezca.
const KEYWORDS := [
	["reserva", "🔋"], ["⚡", "⚡"], ["energ", "⚡"], ["producci", "🏭"], ["trabaj", "🏗️"], ["electric", "⚡"], ["bater", "🔋"], ["comida", "🍎"], ["aliment", "🍎"],
	["oxígeno", "💨"], ["aire", "💨"], ["agua", "💧"], ["material", "🧱"], ["blindaje", "🛡️"], ["protecci", "🛡️"],
	["radiaci", "☢️"], ["refugio", "🏠"], ["salud", "❤️"], ["frío", "🥶"], ["calor", "🔥"], ["calefacc", "🔥"],
	["investigaci", "🔬"], ["laboratorio", "🔬"], ["mejora", "🔬"], ["soporte vital", "🛠️"], ["fallo", "⚠️"],
	["datos", "📡"], ["control", "🔌"], ["obras", "🏗️"], ["planta", "🌱"], ["cultivo", "🌱"], ["horas", "⏱️"],
	["tiempo", "⏱️"], ["tormenta", "☀️"], ["panel", "☀️"], ["descanso", "😴"], ["fisura", "🔧"], ["sellad", "🔧"],
	["traje", "🧑‍🚀"], ["tripulaci", "🧑‍🚀"], ["luz", "💡"],
]

## Palabras clave de la ETIQUETA de una opcion -> ilustracion grande.
const ILLUSTRATIONS := [
	["led alta", "💡"], ["luz alta", "🌞"], ["oscuridad", "🌑"], ["led baja", "🌙"], ["apagar luces", "🌑"], ["ahorro", "🔋"],
	["máximo", "⚡"], ["reserva", "🔋"], ["blindaje", "🛡️"], ["ampliar", "🌱"], ["invernadero", "🌱"], ["cultivos", "🌱"],
	["refugio", "🏠"], ["panel", "☀️"], ["tripulación", "🩺"], ["calefacción", "🔥"], ["transmitir", "📡"], ["control", "🔌"],
	["hogar", "🏠"], ["trajes", "🧑‍🚀"], ["sellar", "🔧"], ["soldar", "🔧"], ["terminar", "🔧"], ["laboratorio", "🔬"],
	["soporte vital", "🛠️"], ["mantener", "🛠️"], ["esperar", "⏳"], ["seguir", "▶️"], ["dejarlo", "🔌"], ["guardar", "🔒"],
]

const MODULE_PHRASE := {
	"habitat": ["¡Hace frío en casa!", "El hogar necesita cuidado.", "¡Un hogar calentito y seguro!"],
	"dorms": ["¡Estamos muy cansados!", "Hay que descansar más.", "¡Todos duermen bien!"],
	"common": ["¡Nadie se siente bien aquí!", "Falta un poco de ánimo.", "¡Aquí comemos y nos reímos!"],
	"lab": ["El laboratorio necesita energía.", "Podemos investigar algo nuevo.", "¡Descubrimos cosas increíbles!"],
	"life_support": ["¡Falta aire limpio!", "El aire se está gastando.", "¡Respiramos aire fresco!"],
	"greenhouse": ["¡Las plantas sufren!", "Las plantas piden cuidados.", "¡Tus plantas están creciendo!"],
	"fertilization": ["¡Faltan nutrientes!", "A las plantas les falta comida.", "¡La tierra está bien alimentada!"],
	"infirmary": ["¡La tripulación necesita ayuda!", "Alguien no se siente bien.", "¡Todos están sanos!"],
	"command": ["¡Sin control no podemos trabajar!", "Hay que cuidar la energía.", "¡Todo bajo control, comandante!"],
	"main_energy": ["¡Casi no queda energía!", "La energía baja rápido.", "¡Tenemos energía de sobra!"],
	"backup_energy": ["¡La reserva casi se acaba!", "La reserva está bajando.", "¡Reserva lista para emergencias!"],
	"shelter": ["¡Aquí no estamos seguros!", "El refugio puede mejorar.", "¡Un refugio fuerte nos protege!"],
	"panels": ["¡Los paneles casi no dan energía!", "Los paneles trabajan poco.", "¡Los paneles beben luz del Sol!"],
	"processing": ["¡Faltan materiales!", "Quedan pocos materiales.", "¡Hay materiales para construir!"],
}

## Analogias sencillas que el robot usa para explicar la ciencia.
const ANALOGY := {
	"habitat": "Es como la casa de la tripulación: tiene que estar calentita.",
	"dorms": "Dormir recarga a los astronautas, igual que la batería de una tablet.",
	"common": "Es la cocina y el salón: comer juntos da energía y ánimo.",
	"lab": "Aquí se hacen experimentos para mejorar la base.",
	"life_support": "Son los pulmones de la base: limpian el aire y reciclan el agua.",
	"greenhouse": "Es la huerta de la base. Las plantas necesitan luz, como tú necesitas comer.",
	"fertilization": "Es la comida de las plantas: sin nutrientes no crecen.",
	"infirmary": "Aquí se cuida a la tripulación, como el médico de la escuela.",
	"command": "Es el cerebro de la base: sin él no se puede construir ni investigar.",
	"main_energy": "Es la batería grande. Todo lo que se enciende gasta de aquí.",
	"backup_energy": "Es la batería de emergencia: como la linterna del cajón.",
	"shelter": "Es nuestro paraguas contra la radiación del Sol.",
	"panels": "Convierten la luz del Sol en electricidad. De noche no funcionan.",
	"processing": "Transforma el polvo de la Luna en materiales para construir.",
}

const MISSION_TAG := {
	"lunar_awakening": "¡Aprende a cuidar tu base!", "storm_horizon": "¡Llega una tormenta solar!",
	"lunar_blackout": "Casi sin luz del Sol", "lava_harvest": "Plantas dentro de una cueva",
	"orbital_shadow": "Una noche larguísima", "thermal_anomaly": "¡Hay una grieta en el escudo!",
	"mars_outpost": "¡Muy pronto!",
}


## «Hoy aprendimos»: 2-3 ideas cortas por mision para la pantalla final.
const LEARN := {
	"default": ["Mejorar una parte de la base puede dañar otra.", "Energía, materiales y horas se reparten con cuidado."],
	"lunar_awakening": ["Mejorar una parte de la base puede dañar otra.", "Energía, materiales y horas se reparten con cuidado.", "Las plantas ayudan, pero no lo hacen todo."],
	"storm_horizon": ["Un buen escudo nos protege de la radiación del Sol.", "Guardar energía hoy ayuda mañana.", "Cada decisión tiene un precio."],
	"lunar_blackout": ["Sin Sol mandan las baterías.", "Apagar algo ahorra energía, pero cuesta.", "La reserva es para emergencias."],
	"lava_harvest": ["Las plantas dan aire y comida.", "Luz alta gasta energía; la oscuridad las descansa.", "Alternar luz y descanso las hace crecer."],
	"orbital_shadow": ["En la sombra no trabajan los paneles solares.", "El calor y los datos compiten por la batería.", "Elegir qué es lo más importante es ser comandante."],
	"thermal_anomaly": ["Una grieta en el escudo deja pasar radiación.", "Reparar gasta energía y oxígeno.", "Prepararse a tiempo salva al equipo."],
}

## Si la mision no sale bien: que mejorar la proxima vez, segun el motivo del final (reason_id).
const IMPROVE := {
	"ls": ["💨", "cuida el aire y el soporte vital."], "radiation": ["🛡️", "mejora el escudo y el refugio antes de la tormenta."],
	"energy": ["⚡", "guarda energía para lo más importante."], "food": ["🍎", "cuida las plantas para tener comida."],
	"final": ["⚖️", "reparte mejor la energía, los materiales y las horas."],
}


## Primera frase de un texto, recortada a `max_len` caracteres (sin cortar palabras).
static func short(text: String, max_len: int = 70) -> String:
	var t := Lang.t(text).strip_edges()   # se traduce ANTES de recortar: la primera frase en ingles no esta en el diccionario
	var cut := t.length()
	for sep in ["? ", ". ", "! ", "?", "."]:
		var i := t.find(sep)
		if i != -1 and i + 1 < cut:
			cut = i + 1
	t = t.substr(0, cut)
	if t.length() > max_len:
		t = t.substr(0, max_len)
		var sp := t.rfind(" ")
		if sp > 20:
			t = t.substr(0, sp)
		t += "…"
	return t


## Icono de la primera palabra clave que aparece en el texto ("" si no hay).
static func icon_of(text: String) -> String:
	var low := text.to_lower()
	var best := ""
	var best_pos := 100000
	for k in KEYWORDS:
		var p := low.find(str(k[0]))
		if p != -1 and p < best_pos:
			best_pos = p
			best = str(k[1])
	return best


## Todos los iconos distintos que aparecen en un texto, en el orden en que aparecen.
static func icons_in(text: String) -> Array:
	var low := text.to_lower()
	var found: Array = []
	for k in KEYWORDS:
		var p := low.find(str(k[0]))
		if p != -1:
			found.append([p, str(k[1])])
	found.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array = []
	for f in found:
		if not (f[1] in out):
			out.append(f[1])
	return out


## «CULTIVOS O ENERGÍA» -> «Cultivos o energía» (frase normal: no gritamos en los titulos largos).
static func sentence(t: String) -> String:
	var s := t.strip_edges().to_lower()
	if s == "":
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


## Lista de {icon, num} (sin repetir iconos) a partir de frases como «Gasta 70 de energía».
static func chips(lines: Array) -> Array:
	var out: Array = []
	var seen: Array = []
	var re := RegEx.new()
	re.compile("[−\\-+]?\\d+")
	for l in lines:
		var s := str(l)
		var ic := icon_of(s)
		if ic == "" or ic in seen:
			continue
		seen.append(ic)
		var m := re.search(s)
		out.append({"icon": ic, "num": m.get_string() if m != null else ""})
	return out


## Ilustracion grande para una opcion segun su etiqueta (o el icono de la tarjeta si no hay coincidencia).
static func illustration(label: String, fallback: String) -> String:
	var low := label.to_lower()
	for it in ILLUSTRATIONS:
		if low.contains(str(it[0])):
			return str(it[1])
	return fallback


static func module_phrase(id: String, level: int) -> String:
	var arr: Array = MODULE_PHRASE.get(id, [])
	if arr.is_empty():
		return ""
	return str(arr[clampi(level, 0, 2)])


## Estado en 3 niveles con color Y simbolo (el color no es la unica pista).
static func state(level: int) -> Dictionary:
	level = clampi(level, 0, 2)
	return {"icon": ["✗", "⚠", "✓"][level], "word": ["¡Peligro!", "Cuidado", "¡Bien!"][level], "col": UI.light_color(level)}
