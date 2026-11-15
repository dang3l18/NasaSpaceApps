# Publica la version web de ZYRANTH en GitHub Pages (rama gh-pages del repositorio "origin").
#
# Requisitos: haber exportado el proyecto con el preset "Web" a build/web (Godot: Proyecto > Exportar > Web),
# y tener permiso de escritura en el repositorio (el mismo que usas con git push).
#
# Uso (desde la carpeta del proyecto):   powershell -ExecutionPolicy Bypass -File tools/publish_web.ps1
#
# Despues, UNA SOLA VEZ, en GitHub: Settings > Pages > Source = "Deploy from a branch" > Branch = gh-pages / (root) > Save.
# La pagina queda en https://<usuario>.github.io/<repositorio>/  (tarda 1-2 minutos la primera vez).

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$web = Join-Path $project "build/web"
if (-not (Test-Path (Join-Path $web "index.html"))) { throw "No encuentro build/web/index.html: exporta primero el preset Web." }

$remote = (git -C $project remote get-url origin).Trim()
$tmp = Join-Path $env:TEMP "zyranth_pages"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory $tmp | Out-Null
Get-ChildItem $web | Where-Object { $_.Extension -ne ".import" } | Copy-Item -Destination $tmp
New-Item -ItemType File (Join-Path $tmp ".nojekyll") | Out-Null     # GitHub Pages no debe procesar los archivos
Set-Content (Join-Path $tmp "README.md") "ZYRANTH web build (generated). Source code: branch main." -Encoding UTF8

Push-Location $tmp
try {
    git init -b gh-pages | Out-Null
    git config user.name "Zyranth build"
    git config user.email "noreply@users.noreply.github.com"
    git add -A
    git commit -m "Deploy ZYRANTH web build" | Out-Null
    git remote add origin $remote
    git push --force origin gh-pages     # la rama gh-pages solo contiene la compilacion (un unico commit)
    Write-Host "Publicado en la rama gh-pages de $remote"
} finally {
    Pop-Location
}
