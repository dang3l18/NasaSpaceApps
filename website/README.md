# ZYRANTH · project website

Una sola página HTML (sin dependencias externas, fuentes e imágenes incluidas), bilingüe English / Español.
Es independiente del juego: el botón «Play now» abre el juego en su propia dirección.

## Qué editar

Todo lo configurable está en `index.html`, en el bloque `SITE` (busca «CONFIGURACION»):

| Campo | Para qué |
|---|---|
| `gameUrl` | Dirección del juego (ya apunta a https://nasas-8a24c.web.app) |
| `presentation.slidesEmbed` | Google Slides: *Archivo → Compartir → Publicar en la Web → Insertar* → copia la dirección `https://docs.google.com/presentation/d/…/embed?…` |
| `presentation.videoUrl` | Enlace de YouTube o Vimeo (opcional) |
| `presentation.pdf` | Copia tu PDF como `assets/presentation.pdf` y escribe `"assets/presentation.pdf"`: se muestra en la página y se ofrece para descargar |
| `team` | `[{ name: "Nombre", role: "Rol" }]`; si está vacío, la sección Equipo no aparece |

Mientras no pongas nada, la sección «Presentation» muestra «available here soon».

## Probar en local

```
cd website
python -m http.server 8090
```
y abre http://localhost:8090 (abrir `index.html` con doble clic funciona, pero el PDF solo se detecta por HTTP).

## Publicar en Firebase (otro proyecto distinto del juego)

```
cd website
firebase login
firebase use --add          # elige el proyecto nuevo de la web
firebase deploy --only hosting
```
Los textos están en el objeto `T` (en/es) del mismo archivo.
