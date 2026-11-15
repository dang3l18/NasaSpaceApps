# ZYRANTH — Junior Astronaut: Mission Trainer

**An educational 2D space-survival game for kids aged 7–12, built with real NASA open data.**
Made with Godot 4.7 (GDScript) for the **NASA Space Apps Challenge 2026**. English (default) and Spanish.

▶ **Play online:** https://nasas-8a24c.web.app  *(runs in the browser, nothing to install)*
Español: ver [README.es.md](README.es.md) · el juego tiene selector de idioma 🌐 en el menú.

## What is it?

You are the commander of a small base next to the Moon. **Four systems compete for the same budget of energy, materials and crew-hours:**
life support, protection (shielding), energy and food. Improving one part of the base always costs another. Every mission is an
**engineering dilemma**: something to protect and something to sacrifice. There is no single "best" answer, and the game
shows the consequences of each choice before you confirm it.

The goal is to teach, through play, that **space survival is about trade-offs**, and to connect those trade-offs to **real space weather and
Earth/Moon observation data from NASA and NOAA**.

## How to play (60 seconds)

1. Press **PLAY**, choose your age mode (Explorer 7–9 / Commander 10–12) and a mission.
2. Tap a building on the base: a window shows what it does, how it is doing (✓ ⚠ ✗) and what you can do with it.
3. Spend your **⚡ energy, 🧱 materials and ⏱ hours** on tasks, then press **End turn**.
4. When the robot asks, make a decision (cards show what you **gain ▲** and what it **costs ▼**).
5. Survive 9 turns. **Space alerts** (meteorites, solar flares, leaks…) can appear in real time: you have seconds to decide.

The robot assistant guides you with short tips and a **step-by-step tutorial for every mission** (repeatable with "❓ Repeat help").

## Missions (unlocked in a chain)

| Level | Mission | Dilemma |
|---|---|---|
| Easy | Lunar Shelter: The Awakening | Four systems, one budget (tutorial) |
| Easy | Storm on the Horizon | Crops or shield: sacrifice the plants' energy to protect the crew |
| Easy | Blackout at the Polar Cap | Which subsystem do we switch off? |
| Intermediate | The Lava Tube Harvest | Light or energy: alternate high light and darkness |
| Intermediate | Orbital Shadow Effect | Warmth or contact: heating vs. sending data to Earth |
| Intermediate | Thermal Shield Anomaly | Seal the crack or look after the air before the storm |
| Advanced | Mars base | *in preparation* |

Progress, achievements and stars are saved as JSON in the browser/computer. Each mission checks its own win and lose conditions.

## Real NASA data — and how we label it honestly

Every piece of information shows where it comes from. **We never invent data and never present a solar-event class as a real radiation dose.**

| Source | Label | What it does in the game |
|---|---|---|
| NASA DONKI (CCMC) — flares, CMEs, geomagnetic storms, SEP, WSA-Enlil, notifications | REAL / HISTORICAL DATA | The latest strong solar event sets the **alert level** of the solar-storm turn (a *simulation parameter*) |
| NASA GIBS — MODIS/VIIRS Earth imagery, Black Marble | REAL / HISTORICAL DATA | The real Earth in the sky and in "Learn more" |
| NASA LRO · Moon Trek — global WAC mosaic | HISTORICAL DATA | The real Moon behind the base |
| NASA Earthdata CMR — ISS lightning sensor (LIS) | HISTORICAL DATA | Context in the Space Data Center |
| NOAA SWPC — planetary Kp index, space-weather scales | REAL DATA | Cross-check of DONKI's geomagnetic activity |
| NASA ECLSS, Radiation Protection, Moon Base Systems, Veggie | NASA REFERENCE | Explain what each building does, with a link to the source |
| Game numbers (`SimConfig.gd`) | SIMULATION PARAMETER | Energy, materials, hours, exposure: game values, **not measurements** |

Without internet the game keeps working with the last saved copy; without a copy it uses a clearly labeled **EDUCATIONAL SIMULATION** scenario.
DONKI is queried through NASA's CCMC service, which needs **no API key**.

## Features

- 14 interactive modules, 4 interdependent systems, shared budgets of energy / materials / hours.
- Real-time **space alerts** with countdown, illustrated scenes and real consequences (energy, air, radiation, health, panels, score).
- **Child-friendly UX**: rounded font, big icons instead of numbers, 3-state meters (✓ ⚠ ✗ — never colour alone), illustrated decision cards, positive messages when you lose.
- Adaptive robot guide that reads your decisions and a per-mission progressive tutorial.
- **Space Data Center**: see the real datasets behind the game (charts, images, status, attribution).
- Runs on desktop and **in the browser (WebAssembly)**; works offline with a cache.
- Fully bilingual (English / Español) with a runtime language switch.

## Run locally

Open the folder with **Godot 4.7** and press *Play*. No key is needed. (Optional: your own NASA key in `NASA_API_KEY`,
`user://nasa_config.cfg` or `config/nasa_config.local.cfg` — git-ignored — is only used as a fallback for DONKI.)

Web build: export with the "Web" preset and serve the folder over HTTP (e.g. `python -m http.server`); opening `index.html` with a double click does not work in browsers.

## Tests

```
godot --headless --path . res://scenes/SimTests.tscn        # balance of the 4 systems
godot --headless --path . res://scenes/MissionTests.tscn    # missions, unlocking, achievements, JSON save
godot --headless --path . res://scenes/UIPlaythrough.tscn   # a whole mission played through the real UI
godot --headless --path . res://scenes/AlertTests.tscn      # space alerts
godot --headless --path . res://scenes/KidUITests.tscn      # child-friendly UI, tutorial series, results
godot --headless --path . res://scenes/UILayoutTests.tscn   # movable / hideable panels
godot --headless --path . res://scenes/LangTests.tscn       # English build contains no Spanish text (1,300+ strings)
godot --headless --path . res://scenes/ConnectionTests.tscn # network, cache and offline mode (real network)
```
(All tests except `LangTests` run in Spanish, the source language of the strings.)

## Architecture

`scripts/sim` (pure logic: `BaseState`, `SpaceEvents`, `AlertDirector`, `MissionDirector`, `GuideCoach`) · `scripts/data` (HTTP + cache + dataset registry) ·
`scripts/missions` (definitions, save, achievements) · `scripts/game` (main scene, alert overlay, tutorial) · `scripts/ui` (design system `UI`/`KidKit`/`KidText`/`KidArt`, menu) ·
`scripts/Lang.gd` (language: translates every label at display time from `data/lang_en.json`).

## Credits and attributions

Data: NASA / GSFC / CCMC (DONKI), NASA EOSDIS GIBS, NASA LRO · Moon Trek, NASA EOSDIS / GHRC DAAC, NOAA SWPC.
Fonts: Fredoka (SIL OFL 1.1), Twemoji · Mozilla COLR (CC-BY 4.0), DejaVu Sans (Bitstream Vera licence).
This project is not an official NASA product and is not endorsed by NASA.
