# Junior Astronaut: Mission Trainer — Operación: Última Órbita

Juego educativo hecho en **Godot 4.7** (GDScript). Gestionas una estación espacial en órbita durante 7 días y
tomas decisiones ante una tormenta solar basada en datos abiertos de NASA.

## Datos externos usados (consultas HTTP reales, con caché y modo sin conexión)

| Fuente | Uso en el juego |
|---|---|
| NASA DONKI (CME, FLR, GST, SEP) | Evento solar de la misión y archivo 2025–2026 |
| NASA GIBS / Worldview (WMS) | La Tierra real que se ve desde la estación |
| NASA Earthdata CMR | Metadatos del sensor de rayos ISS LIS (contexto educativo) |
| NOAA SWPC (agencia aliada) | Índice Kp para contrastar DONKI |

Cada dato se etiqueta como **DATO REAL**, **DATO HISTÓRICO** o **SIMULACIÓN EDUCATIVA** y se puede revisar en la
pantalla *Space Data Center*. Sin conexión y sin caché, el juego usa un escenario rotulado como simulación.

## Ejecutar

1. Abre la carpeta en Godot 4.7 y pulsa *Play*.
2. Para DONKI necesitas una clave gratuita de <https://api.nasa.gov>. **No la subas al repositorio**. Opciones:
   - variable de entorno `NASA_API_KEY`, o
   - `user://nasa_config.cfg`, o
   - `config/nasa_config.local.cfg` (ignorado por git; plantilla en `config/nasa_config.example.cfg`).

## Pruebas

```
godot --headless --path . res://scenes/ConnectionTests.tscn   # conexión, caché, offline (usa la red real)
godot --headless --path . res://scenes/GameSim.tscn           # simulación de partidas
```

## Atribuciones

Datos: NASA / GSFC / CCMC (DONKI), NASA EOSDIS GIBS, NASA EOSDIS / GHRC DAAC, NOAA SWPC.
Este proyecto no es un producto oficial de NASA ni está respaldado por NASA.
