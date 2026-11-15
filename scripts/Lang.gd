extends Node
## Idioma del juego (English por defecto; Español disponible). El texto fuente del codigo esta en espanol y se traduce
## al mostrarse: Godot pasa por aqui TODO texto de etiquetas, botones y ayudas (traduccion automatica de la interfaz),
## asi tambien se traducen los mensajes con numeros («Dia 2 · Turno 4 de 9») sin tocar cada punto del codigo.
## El diccionario esta en res://data/lang_en.json (texto en espanol -> ingles).
##
## Uso:  Lang.t("texto")  (para texto dibujado con draw_string)   ·   Lang.set_language("es" | "en")
## Pruebas:  Lang.set_language("es", false)  ·  argumento de linea de comandos:  -- --lang=es

signal language_changed(code: String)

const DICT_PATH := "res://data/lang_en.json"
const SETTINGS_PATH := "user://settings.cfg"
const LANGUAGES := {"en": "English", "es": "Español"}

var language := "en"
var _tr: _EnglishTranslation


## Traduccion al ingles: Godot llama a _get_message() para cada texto de la interfaz.
class _EnglishTranslation extends Translation:
	var exact: Dictionary = {}                 # español -> ingles (sin marcadores)
	var lower_map: Dictionary = {}             # español en minusculas -> ingles
	var templates: Array = []                  # [{re, en, n}] para textos con %d %s %.1f
	var phrases: Array = []                    # claves ordenadas de la mas larga a la mas corta (reemplazo por trozos)
	var _cache: Dictionary = {}
	var _letter := RegEx.new()
	var _spec := RegEx.new()
	var _prefix := RegEx.new()

	func setup(dict: Dictionary) -> void:
		locale = "en"
		_letter.compile("[A-Za-zÁÉÍÓÚÜáéíóúüñÑ]")
		_prefix.compile("^[^A-Za-zÁÉÍÓÚÜáéíóúüñÑ¿¡]+")
		_spec.compile("%%|%[+\\-]?\\d*\\.?\\d*[dsf]")
		for k in dict:
			var es: String = k
			var en: String = dict[k]
			if _spec.search(es) != null and "%%" != es:
				var t := _template(es.strip_edges(), en.strip_edges())
				if not t.is_empty():
					templates.append(t)
			else:
				exact[es] = en
				lower_map[es.to_lower()] = en
				if es.strip_edges().length() >= 4:
					phrases.append(es)
		templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]))
		phrases.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())

	## Convierte «Dia %d · Turno %d de %d» en una expresion regular con un grupo por marcador.
	func _template(es: String, en: String) -> Dictionary:
		var pat := "^"
		var literal := 0
		var i := 0
		while i < es.length():
			var c := es[i]
			if c == "%":
				var m := _spec.search(es, i)
				if m != null and m.get_start() == i:
					var token := m.get_string()
					if token == "%%":
						pat += "%"
					elif token.ends_with("s"):
						pat += "(.*?)"
					else:
						pat += "(-?\\d+(?:\\.\\d+)?)"
					i += token.length()
					continue
			if c in "\\.^$|()[]{}*+?":
				pat += "\\" + c
			else:
				pat += c
			literal += 1
			i += 1
		var core_pat := pat.substr(1)
		pat += "$"
		if literal < 6:
			return {}
		var re := RegEx.new()
		if re.compile(pat) != OK:
			return {}
		# Version sin anclas: reconoce la plantilla DENTRO de un texto mas largo (fragmentos unidos). Si la plantilla
		# termina en un marcador abierto no se usa, porque se tragaria el resto del texto.
		var free: RegEx = null
		if literal >= 8 and not core_pat.ends_with(")"):
			free = RegEx.new()
			if free.compile(core_pat) != OK:
				free = null
		return {"re": re, "free": free, "en": en, "n": literal}

	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		var s := String(src_message)
		var r := translate_text(s)
		return StringName(r) if r != s else StringName()

	func translate_text(src: String) -> String:
		if src.length() < 2 or _letter.search(src) == null:
			return src
		if _cache.has(src):
			return _cache[src]
		var out := _tr(src, 0)
		if _cache.size() > 6000:
			_cache.clear()
		_cache[src] = out
		return out

	func _tr(src: String, depth: int, allow_phrases: bool = true) -> String:
		if depth > 4:
			return src
		if exact.has(src):
			return exact[src]
		var core := src.strip_edges()
		if core != src and core != "":
			var lead := src.substr(0, src.length() - src.lstrip(" \t\n").length())
			var trail := src.substr(src.rstrip(" \t\n").length())
			var rc := _tr(core, depth + 1, false)
			if rc != core:
				return lead + rc + trail
		for t in templates:   # primero sobre el texto completo (con su emoji delante, si lo lleva)
			var m: RegExMatch = (t["re"] as RegEx).search(core)
			if m != null:
				return _fill(str(t["en"]), m, depth)
		var pm := _prefix.search(core)
		if pm != null and pm.get_string().length() > 0 and pm.get_string().length() < core.length():
			var pre := pm.get_string()
			var rest := core.substr(pre.length())
			var rr := _tr(rest, depth + 1, false)
			if rr != rest:
				return pre + rr
		var lk := core.to_lower()
		if lower_map.has(lk):
			var en: String = lower_map[lk]
			return en.to_upper() if (core == core.to_upper() and core != core.to_lower()) else en
		for sep in ["\n", ", "]:
			if core.contains(sep):
				var parts := core.split(sep)
				var changed := 0
				var texty := 0
				for j in parts.size():
					if _letter.search(parts[j]) != null:
						texty += 1
					# cada linea puede llevar varias frases; los elementos de una lista con comas solo si se reconocen enteros
					var p := _tr(parts[j], depth + 1, sep == "\n")
					if p != parts[j]:
						parts[j] = p
						changed += 1
				if changed > 0 and (sep == "\n" or changed >= texty):
					return sep.join(parts)
		return _by_phrases(src, depth) if allow_phrases else src

	func _fill(en: String, m: RegExMatch, depth: int) -> String:
		var out := ""
		var g := 1
		var i := 0
		while i < en.length():
			# dos %s seguidos separados por un espacio («descripcion» + «detalle»): se traducen JUNTOS para reconocer frases enteras
			if en.substr(i, 5) == "%s %s" and en.substr(i + 5, 1) != "%" and g + 1 <= m.get_group_count():
				out += _tr(m.get_string(g) + " " + m.get_string(g + 1), depth + 1)
				g += 2
				i += 5
				continue
			if en[i] == "%":
				var sm := _spec.search(en, i)
				if sm != null and sm.get_start() == i:
					var token := sm.get_string()
					if token == "%%":
						out += "%"
					else:
						var val := m.get_string(g) if g <= m.get_group_count() else ""
						if token.ends_with("s"):
							# si la plantilla pone un punto justo despues del grupo, ese punto era de la ultima frase del grupo:
							# se traduce con el punto para reconocer la frase entera y luego se quita (la plantilla lo repone)
							var dot_next := i + token.length() < en.length() and en[i + token.length()] == "."
							var with_dot := _tr(val + ".", depth + 1) if dot_next else ""
							if dot_next and with_dot != val + ".":
								out += with_dot.trim_suffix(".")
							else:
								out += _tr(val, depth + 1)
						else:
							out += val
						g += 1
					i += token.length()
					continue
			out += en[i]
			i += 1
		return out

	## Ultimo recurso: sustituye las frases conocidas que aparezcan dentro del texto (textos concatenados o con numeros).
	func _by_phrases(src: String, depth: int = 0) -> String:
		var out := src
		var changed := false
		# 1) plantillas con numeros dentro del texto («archivo 2025→hoy: 3072 eventos»)
		for t in templates:
			var fr: RegEx = t["free"]
			if fr == null:
				continue
			var ms := fr.search_all(out)
			for k in range(ms.size() - 1, -1, -1):
				var mm: RegExMatch = ms[k]
				out = out.substr(0, mm.get_start()) + _fill(str(t["en"]), mm, depth) + out.substr(mm.get_end())
				changed = true
		# 2) frases fijas
		for phrase in phrases:
			var p: String = phrase
			var from := 0
			while true:
				var idx := out.find(p, from)
				if idx == -1:
					break
				var before := out.substr(idx - 1, 1) if idx > 0 else ""
				var after_i := idx + p.length()
				var after := out.substr(after_i, 1) if after_i < out.length() else ""
				var edge_l := _letter.search(p.substr(0, 1)) != null
				var edge_r := _letter.search(p.substr(p.length() - 1, 1)) != null
				if (edge_l and before != "" and _letter.search(before) != null) or (edge_r and after != "" and _letter.search(after) != null):
					from = idx + 1
					continue
				var rep: String = exact[p]
				out = out.substr(0, idx) + rep + out.substr(after_i)
				from = idx + rep.length()
				changed = true
		return out if changed else src


func _ready() -> void:
	var parsed: Variant = _read_json(DICT_PATH)
	if parsed is Dictionary:
		_tr = _EnglishTranslation.new()
		_tr.setup(parsed)
		TranslationServer.add_translation(_tr)
	else:
		push_warning("Lang: no se pudo leer %s" % DICT_PATH)
	var code := _saved_language()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			code = a.substr(7)
	set_language(code, false)


## Lee un JSON del proyecto. En un juego exportado los .json son recursos importados: FileAccess no los ve, load() si.
static func _read_json(path: String) -> Variant:
	if FileAccess.file_exists(path):
		return JSON.parse_string(FileAccess.get_file_as_string(path))
	var res: Resource = load(path)
	if res is JSON:
		return (res as JSON).data
	return null


func _saved_language() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return str(cfg.get_value("game", "language", "en"))
	return "en"


## Cambia el idioma. `save` = recordarlo para la proxima vez.
func set_language(code: String, save: bool = true) -> void:
	if not LANGUAGES.has(code):
		code = "en"
	language = code
	TranslationServer.set_locale(code)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("game", "language", code)
		cfg.save(SETTINGS_PATH)
	language_changed.emit(code)


## Traduce un texto a mano (para lo que se dibuja con draw_string y no es una etiqueta).
func t(text: String) -> String:
	return tr(text)


func is_english() -> bool:
	return language == "en"
