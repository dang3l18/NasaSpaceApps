# ZYRANTH — Junior Astronaut: Mission Trainer

Videojuego educativo 2D hecho en **Godot 4.7** (GDScript) para niños de 7 a 12 años, con misiones espaciales basadas en datos abiertos de NASA.

## Misiones

Cada misión es un **dilema de ingeniería**: algo que proteger y algo que sacrificar. Se desbloquean en cadena:
hay que superar una para abrir la siguiente.

| # | Misión | Dificultad | Dilema | Estado |
|---|---|---|---|---|
| 1 | 🌙 **Refugio Lunar: El Despertar** | ★ Fácil | Cuatro sistemas, un solo presupuesto (tutorial) | Jugable |
| 2 | ☀️ **Tormenta en el Horizonte** | ★★ Media | Cultivos o escudo: sacrificar energía de las plantas para proteger a la tripulación | Se desbloquea al superar la 1 |
| 3 | 🔦 **Apagón en el Casquete** | ★★★ Difícil | ¿Qué subsistema apagamos? (hogar, control o luces de cultivo) | Se desbloquea al superar la 2 |
| 4 | 🔴 Base en Marte | Avanzada | — | En preparación |

### Nivel Intermedio (independiente del nivel Fácil; en cadena dentro del nivel)

| # | Misión | Dificultad | Dilema y mecánica propia | Modificadores |
|---|---|---|---|---|
| 1 | 🌋 **La Cosecha de los Tubos de Lava** | ★ Fácil | Luz o energía: alterna luz alta y oscuridad; tras la oscuridad la luz alta da un impulso, dos turnos seguidos estresan a las plantas | consumo +5%, fallos 25% |
| 2 | 🌑 **Efecto de Sombra Orbital** | ★★ Media | Calor o contacto: noche prolongada; calefacción y transmisión de datos compiten por la batería (hay que enviar 4 paquetes) | consumo +5%, fallos 35% |
| 3 | 🛡 **Anomalía en el Escudo Térmico** | ★★★ Difícil | Sellar la fisura o cuidar el aire: la soldadura desvía energía del soporte vital y gasta oxígeno de los trajes de EVA antes de la tormenta (DONKI, nivel 3 de escenario educativo) | consumo +10%, fallos 45% |

Los **fallos** son sucesos de riesgo que solo pueden ocurrir si descuidas un sistema (soporte vital desgastado, poca
reserva de energía, plantas enfermas o tripulación agotada); cuanto más agresiva la misión, más probables.
Cada misión comprueba su propia condición de victoria y se marca como «Superada» en el guardado JSON.

Las misiones viven en `scripts/missions/MissionManager.gd` (una `MissionDef` por misión) y su guion de eventos en
`scripts/sim/MissionDirector.gd`. El progreso y los logros se guardan en JSON (`user://zyranth_save.json`).

**Logros** (`AchievementManager`): Ingeniero de Campo, Escudo Humano, Agricultor Espacial, Maestro del Trade-off,
Primera misión superada y Científico de datos.

## Operación: Refugio Lunar (simulación común)

Gestionas una **base lunar**
durante 3 días (9 turnos) y aprendes que sobrevivir en la Luna exige **equilibrar cuatro sistemas** que compiten por
los mismos recursos.

## Los cuatro sistemas (interdependientes)

| Sistema | Qué hace | Qué consume |
|---|---|---|
| 💨 Soporte vital | Oxígeno, CO₂ y agua | Energía, mantenimiento, repuestos |
| 🛡 Protección | Blindaje con regolito y refugio contra radiación | Materiales, horas, energía en alertas |
| ⚡ Energía | Paneles (solo de día), baterías y respaldo | — (de noche solo gasta) |
| 🌱 Alimentos | Invernadero; también aporta algo de aire y agua | Energía (LED), agua, nutrientes, cuidados |

Comparten tres presupuestos por turno: **⚡ energía, 🧱 materiales y ⏱ horas de la tripulación**. Cada decisión tiene un
coste inmediato y consecuencias en turnos posteriores. Ninguna estrategia "maximizar una sola cosa" gana.
Las 14 instalaciones de la base (hábitat, dormitorios, área común, laboratorio, soporte vital, invernadero,
fertilización, enfermería, comandos, energía principal y de respaldo, refugio, paneles y procesamiento de materiales)
son interactivas.

## Datos de NASA y cómo influyen en la misión

| Fuente | Tipo de dato | Efecto en el juego |
|---|---|---|
| NASA DONKI | **Real / histórico** | Su evento solar elige el *nivel de alerta* (1–3) del turno 6. Es un parámetro de simulación, **no una dosis real** |
| NASA LRO · Moon Trek (WMTS) | **Histórico** (mosaico) | Imagen real de la Luna en la presentación de la misión |
| NASA GIBS | **Real** | La Tierra visible en el cielo lunar |
| NASA Earthdata CMR, NOAA SWPC | Histórico / real | Contexto y contraste en el Space Data Center |
| NASA ECLSS, Radiation Protection, Moon Base Systems, Veggie, LRO/PDS | **Referencia NASA** | Explican las mecánicas de cada módulo, con enlace a la fuente |
| Parámetros del juego (`SimConfig.gd`) | **Parámetro de simulación** | Cifras de energía, materiales, horas y exposición: valores de juego, no mediciones |

El juego nunca afirma que la base sea una instalación real de NASA ni que haya agua accesible en el sitio. Sin
conexión y sin caché, la alerta solar pasa a un escenario rotulado como **SIMULACIÓN EDUCATIVA**.

## Ejecutar

1. Abre la carpeta en Godot 4.7 y pulsa *Play*.
2. Para DONKI necesitas una clave gratuita de <https://api.nasa.gov>. **No la subas al repositorio**:
   variable de entorno `NASA_API_KEY`, o `user://nasa_config.cfg`, o `config/nasa_config.local.cfg`
   (ignorado por git; plantilla en `config/nasa_config.example.cfg`).

## Pruebas

```
godot --headless --path . res://scenes/SimTests.tscn        # equilibrio de los 4 sistemas (sin red)
godot --headless --path . res://scenes/MissionTests.tscn    # misiones, desbloqueo, logros y guardado JSON (sin red)
godot --headless --path . res://scenes/UIPlaythrough.tscn   # misión completa por la interfaz (sin red)
godot --headless --path . res://scenes/UILayoutTests.tscn   # interfaz movible y ocultable (sin red)
godot --headless --path . res://scenes/ConnectionTests.tscn # conexión, caché y modo sin conexión (red real)
```

## Atribuciones

Datos: NASA / GSFC / CCMC (DONKI), NASA EOSDIS GIBS, NASA LRO · Moon Trek, NASA EOSDIS / GHRC DAAC, NOAA SWPC.
Este proyecto no es un producto oficial de NASA ni está respaldado por NASA.
