class_name ModuleDefs
extends RefCounted
## Las 14 instalaciones de la base lunar: posicion en el mapa, funcion y tareas que ofrecen.
## Posiciones (Rect2) en coordenadas locales del mapa (700 x 540), segun el boceto.

const ORDER := ["habitat", "dorms", "common", "lab", "life_support", "greenhouse", "fertilization",
		"infirmary", "command", "main_energy", "backup_energy", "shelter", "panels", "processing"]

const DEFS := {
	"habitat": {"name": "Hábitat central", "icon": "🏠", "rect": Rect2(160, 298, 70, 34), "tasks": [],
		"func": "Conecta todos los módulos con corredores presurizados.",
		"needs": "Energía para mantener la presión del aire.",
		"conseq": "Si falta energía, la tripulación descansa peor.",
		"ref": {"label": "Referencia NASA: LRO", "url": "https://science.nasa.gov/mission/lro/",
			"text": "NASA indica que LRO cartografió la Luna y midió su temperatura, composición y entorno de radiación. Sirve de contexto: no decimos que haya agua accesible aquí."}},
	"dorms": {"name": "Dormitorios", "icon": "🛏", "rect": Rect2(285, 175, 40, 100), "tasks": [],
		"func": "La tripulación duerme y recupera fuerzas.",
		"needs": "Energía del hogar (luz y temperatura).",
		"conseq": "Descansar mejor da más horas de trabajo."},
	"common": {"name": "Área común", "icon": "🍽", "rect": Rect2(340, 270, 110, 90), "tasks": [],
		"func": "Comer, convivir y reunirse. Aquí empieza cada corredor.",
		"needs": "Energía del hogar.",
		"conseq": "Una tripulación contenta trabaja mejor."},
	"lab": {"name": "Laboratorio", "icon": "🔬", "rect": Rect2(480, 215, 100, 45), "tasks": ["research"],
		"func": "Investiga mejoras para la base.",
		"needs": "50 de energía y 4 horas por turno de trabajo.",
		"conseq": "Investigar mejora la base, pero quita tiempo al mantenimiento."},
	"life_support": {"name": "Soporte vital y oxígeno", "icon": "💨", "rect": Rect2(190, 190, 80, 90), "tasks": ["maintain_ls", "recharge_suits"],
		"func": "Produce oxígeno, quita el CO₂ y recicla el agua.",
		"needs": "70 de energía cada turno, mantenimiento y repuestos.",
		"conseq": "Si se desgasta o se queda sin energía, el aire se vuelve peligroso.",
		"ref": {"label": "Referencia NASA: ECLSS", "url": "https://www.nasa.gov/reference/environmental-control-and-life-support-systems-eclss/",
			"text": "NASA divide el soporte vital en tres partes: recuperación de agua, revitalización del aire y generación de oxígeno."}},
	"greenhouse": {"name": "Invernadero", "icon": "🌱", "rect": Rect2(350, 140, 80, 100), "tasks": ["tend", "expand_bed"],
		"func": "Cultiva comida. Las plantas también ayudan con el aire y el agua.",
		"needs": "Luz LED (energía), agua, nutrientes y cuidados.",
		"conseq": "Más luz = más comida, pero gasta energía. No reemplaza al soporte vital.",
		"ref": {"label": "Referencia NASA: Veggie", "url": "https://science.nasa.gov/mission/veggie/",
			"text": "NASA cultiva lechugas con luces LED como comida fresca complementaria. En el juego, el aire y el agua que aportan las plantas son parámetros de simulación."}},
	"fertilization": {"name": "Fertilización", "icon": "🧪", "rect": Rect2(440, 150, 48, 50), "tasks": ["fertilize"],
		"func": "Prepara nutrientes para las plantas.",
		"needs": "10 de energía, 4 materiales y 2 horas.",
		"conseq": "Sin nutrientes las plantas se debilitan y dan menos comida."},
	"infirmary": {"name": "Enfermería", "icon": "🩺", "rect": Rect2(90, 265, 60, 100), "tasks": ["treat"],
		"func": "Cuida la salud y ayuda a recuperarse de la radiación.",
		"needs": "10 de energía y 2 horas.",
		"conseq": "Una tripulación sana tiene más horas de trabajo."},
	"command": {"name": "Centro de comandos", "icon": "📡", "rect": Rect2(350, 400, 100, 70), "tasks": [],
		"func": "Desde aquí controlas el ahorro de energía y lees las alertas.",
		"needs": "Energía de control.",
		"conseq": "El ahorro conserva baterías, pero reduce la producción."},
	"main_energy": {"name": "Energía principal", "icon": "⚡", "rect": Rect2(490, 345, 90, 60), "tasks": [],
		"func": "Batería principal: guarda lo que generan los paneles.",
		"needs": "Paneles al sol. De noche solo gasta.",
		"conseq": "Reparte la energía con prioridades: vida, refugio, control, hogar, luces, resto.",
		"ref": {"label": "Referencia NASA: Moon Base Systems", "url": "https://www.nasa.gov/moonbase-systems/",
			"text": "NASA estudia sistemas de energía de superficie para sostener bases durante las largas noches lunares."}},
	"backup_energy": {"name": "Energía de respaldo", "icon": "🔋", "rect": Rect2(490, 285, 90, 45), "tasks": [],
		"func": "Baterías de emergencia. Se usan cuando la principal se acaba.",
		"needs": "Se cargan con el sobrante de la batería principal.",
		"conseq": "Gastar la reserva ahora deja menos para la tormenta solar."},
	"shelter": {"name": "Refugio contra radiación", "icon": "🛡", "rect": Rect2(215, 445, 110, 60), "tasks": ["seal_breach", "build_shield", "build_shelter"],
		"func": "Protege a la tripulación. Se cubre con regolito lunar.",
		"needs": "Materiales, horas y 40 de energía durante una alerta solar.",
		"conseq": "Más protección usa materiales que no irán a otras obras.",
		"ref": {"label": "Referencia NASA: Radiation Protection", "url": "https://www.nasa.gov/radiation-protection/",
			"text": "NASA investiga materiales de protección, como compuestos de polímero y regolito lunar."}},
	"panels": {"name": "Paneles solares", "icon": "☀", "rect": Rect2(600, 300, 90, 110), "tasks": ["expand_panel"],
		"func": "Convierten la luz del Sol en electricidad.",
		"needs": "Luz solar: solo de día.",
		"conseq": "De noche generan 0. Más paneles = más carga de día."},
	"processing": {"name": "Procesamiento de materiales", "icon": "⛏", "rect": Rect2(480, 440, 110, 60), "tasks": ["process"],
		"func": "El robot recoge regolito y lo convierte en materiales.",
		"needs": "40 de energía y 4 horas.",
		"conseq": "Da materiales para blindaje y ampliaciones; gasta energía y tiempo."},
}

## Segmentos de corredor presurizado entre modulos (coordenadas locales).
const CORRIDORS := [
	[Vector2(150, 315), Vector2(160, 315)], [Vector2(230, 315), Vector2(340, 315)],
	[Vector2(230, 280), Vector2(230, 298)], [Vector2(305, 275), Vector2(305, 315)],
	[Vector2(390, 240), Vector2(390, 270)], [Vector2(450, 300), Vector2(490, 300)],
	[Vector2(450, 375), Vector2(490, 375)], [Vector2(400, 360), Vector2(400, 400)],
	[Vector2(450, 238), Vector2(480, 238)], [Vector2(420, 200), Vector2(440, 200)],
	[Vector2(325, 475), Vector2(350, 475)], [Vector2(450, 455), Vector2(480, 455)],
	[Vector2(580, 375), Vector2(600, 375)], [Vector2(225, 332), Vector2(225, 350)],
]


static func center(id: String) -> Vector2:
	var r: Rect2 = DEFS[id]["rect"]
	return r.position + r.size * 0.5


static func module_at(p: Vector2) -> String:
	for id in ORDER:
		var r: Rect2 = DEFS[id]["rect"]
		if r.grow(4).has_point(p):
			return id
	# Zonas decorativas que seleccionan su modulo: ventilacion (soporte vital) y panel izquierdo (paneles)
	if Rect2(190, 350, 70, 70).has_point(p):
		return "life_support"
	if Rect2(10, 250, 70, 130).has_point(p):
		return "panels"
	return ""
