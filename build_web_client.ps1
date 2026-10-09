# Rebuild complet: clientul web (pentru iPhone/browser) + APK-ul Android
# care il serveste. De rulat din radacina proiectului: .\build_web_client.ps1
#
# Pasul 0 conteaza: `assets/web_client.zip` e declarat ca asset Flutter
# pentru orice target, deci si `flutter build web` l-ar bundla (nefolosit,
# dar prezent) daca acolo se afla deja arhiva "reala" dintr-o rulare
# anterioara -- fiecare rulare ar imbraca tot mai mult continut peste
# continutul anterior. Resetam mereu la un placeholder minuscul *inainte*
# de `flutter build web`, si abia *dupa* aceea scriem arhiva reala, care
# ajunge doar in APK-ul Android (unicul loc care chiar o foloseste).
$ErrorActionPreference = "Stop"

# `flutter` scrie si mesaje informative pe stderr (ex: "Wasm dry run
# succeeded"); cu "Stop", PowerShell 5.1 le-ar trata drept erori fatale
# cand iesirea e redirectionata. Succesul se verifica explicit pe
# $LASTEXITCODE, deci pe durata comenzilor flutter folosim "Continue".
function Invoke-Flutter {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { flutter @args } finally { $ErrorActionPreference = $previous }
}
$zipPath = Join-Path $PSScriptRoot "assets\web_client.zip"
$placeholderDir = Join-Path $PSScriptRoot "assets\_placeholder"

Write-Host "0/3 - resetez assets\web_client.zip la un placeholder minim..." -ForegroundColor Cyan
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Force -Path $placeholderDir | Out-Null
Set-Content -Path (Join-Path $placeholderDir "placeholder.txt") -Value "generat de build_web_client.ps1" -Encoding utf8
Compress-Archive -Path (Join-Path $placeholderDir "*") -DestinationPath $zipPath -Force
Remove-Item $placeholderDir -Recurse -Force

Write-Host "1/3 - compilez clientul web (flutter build web)..." -ForegroundColor Cyan
# --no-web-resources-cdn: CanvasKit se incarca din build\web\canvaskit,
# servit de telefonul-server -- invitatii pe hotspot fara internet nu pot
# ajunge la CDN-ul Google, iar pagina ar ramane alba.
Invoke-Flutter build web --release --no-web-resources-cdn
if ($LASTEXITCODE -ne 0) { throw "flutter build web a esuat" }

Write-Host "2/3 - arhivez build\web in assets\web_client.zip..." -ForegroundColor Cyan
Remove-Item $zipPath -Force
Push-Location (Join-Path $PSScriptRoot "build\web")
Compress-Archive -Path * -DestinationPath $zipPath -Force
Pop-Location

Write-Host "3/3 - compilez APK-ul Android (flutter build apk)..." -ForegroundColor Cyan
Invoke-Flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "flutter build apk a esuat" }

Write-Host "Gata. APK: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
