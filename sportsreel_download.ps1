<#
.SYNOPSIS
    Descarga videos de SportsReel y los corta en clips de 15 segundos.

.DESCRIPTION
    Auto-descubre la cámara, genera el vodBlock via la API, descarga con ffmpeg
    y corta en clips con timestamps en el nombre para buscar visualmente.
    Si ffmpeg no está instalado, lo descarga automáticamente.

.EXAMPLE
    # Sin argumentos: Olimpicus 1, Cancha 3, lunes anterior, 21 y 22 hs
    .\sportsreel_download.ps1

.EXAMPLE
    # Con nombre personalizado
    .\sportsreel_download.ps1 -Nombre "fulbo_martes"

.EXAMPLE
    # Fecha y horarios específicos
    .\sportsreel_download.ps1 -Nombre "fulbito" -Fecha "2026-07-06" -Horas "21,22"
#>

param(
    [string]$Nombre = "fulbito",
    [string]$Fecha = "",
    [string]$Horas = "21,22",
    [int]$CanchaId = 347,
    [int]$EstablecimientoId = 71
)

$ErrorActionPreference = "Stop"

# --- Colores y helpers ---
function Write-Header($text) { Write-Host "`n============================================" -ForegroundColor Cyan; Write-Host "  $text" -ForegroundColor Cyan; Write-Host "============================================" -ForegroundColor Cyan }
function Write-Step($text)   { Write-Host "  $text" -ForegroundColor Green }
function Write-Info($text)   { Write-Host "  $text" -ForegroundColor Gray }
function Write-Err($text)    { Write-Host "  ERROR: $text" -ForegroundColor Red }

# --- Calcular lunes anterior ---
function Get-LastMonday {
    $today = Get-Date
    $dow = [int]$today.DayOfWeek  # 0=domingo, 1=lunes, ...
    # Convertir a 1=lunes style
    $daysBack = (($dow - 1) + 7) % 7
    if ($daysBack -eq 0 -and $dow -ne 1) { $daysBack = 7 }
    return $today.AddDays(-$daysBack).ToString("yyyy-MM-dd")
}

if ([string]::IsNullOrEmpty($Fecha)) {
    $Fecha = Get-LastMonday
}

$FechaCompact = $Fecha -replace "-", ""

# --- Buscar o descargar ffmpeg ---
function Get-FfmpegPath {
    # 1. Verificar si está en PATH
    $inPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    # 2. Verificar en la carpeta local tools/
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = (Get-Location).Path }
    $localFfmpeg = Join-Path $scriptDir "tools\ffmpeg.exe"
    if (Test-Path $localFfmpeg) { return $localFfmpeg }

    # 3. Descargar ffmpeg portable
    Write-Host ""
    Write-Host "  ffmpeg no encontrado. Descargando version portable..." -ForegroundColor Yellow

    $toolsDir = Join-Path $scriptDir "tools"
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

    $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    $zipPath = Join-Path $toolsDir "ffmpeg.zip"
    $extractDir = Join-Path $toolsDir "ffmpeg_temp"

    Write-Info "Descargando ffmpeg (~90MB, esto puede tardar unos minutos)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'  # Acelerar descarga
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Err "No se pudo descargar ffmpeg: $_"
        Write-Host "  Descargalo manualmente de https://ffmpeg.org/download.html" -ForegroundColor Yellow
        Write-Host "  y pone ffmpeg.exe en la carpeta tools/" -ForegroundColor Yellow
        exit 1
    }

    Write-Info "Extrayendo..."
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # ffmpeg está en una subcarpeta con nombre variable
    $ffmpegExe = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
    $ffprobeExe = Get-ChildItem -Path $extractDir -Recurse -Filter "ffprobe.exe" | Select-Object -First 1

    if (-not $ffmpegExe) {
        Write-Err "No se encontro ffmpeg.exe en el zip descargado"
        exit 1
    }

    Copy-Item $ffmpegExe.FullName $localFfmpeg -Force
    if ($ffprobeExe) {
        Copy-Item $ffprobeExe.FullName (Join-Path $toolsDir "ffprobe.exe") -Force
    }

    # Limpiar
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Step "ffmpeg instalado en tools/"
    return $localFfmpeg
}

function Get-FfprobePath {
    $inPath = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = (Get-Location).Path }
    $localProbe = Join-Path $scriptDir "tools\ffprobe.exe"
    if (Test-Path $localProbe) { return $localProbe }

    return $null
}

$ffmpeg = Get-FfmpegPath
$ffprobe = Get-FfprobePath

# --- API helpers ---
$ApiBase = "https://servicios.sportsreel.com.ar"

function Invoke-SportsReelApi($url, $method = "GET", $body = $null) {
    $params = @{
        Uri = $url
        Method = $method
        ContentType = "application/json"
        UseBasicParsing = $true
    }
    if ($body) {
        $params.Body = ($body | ConvertTo-Json -Compress)
    }
    try {
        $response = Invoke-RestMethod @params
        return $response
    } catch {
        Write-Err "API falló: $url - $_"
        return $null
    }
}

# --- Inicio ---
Write-Header "SportsReel Downloader"
Write-Info "Fecha:            $Fecha"
Write-Info "Horarios:         $Horas hs"
Write-Info "Cancha ID:        $CanchaId"
Write-Info "Establecimiento:  $EstablecimientoId"
Write-Info "Nombre:           $Nombre"
Write-Info "ffmpeg:           $ffmpeg"

# --- Obtener cámara ---
Write-Host ""
Write-Step "Consultando camara para cancha $CanchaId ..."
$camaraData = Invoke-SportsReelApi "$ApiBase/camara/getByCanchaId/$CanchaId"
if (-not $camaraData -or -not $camaraData.camaras -or $camaraData.camaras.Count -eq 0) {
    Write-Err "No se encontro camara para cancha $CanchaId"
    exit 1
}
$camaraNombre = $camaraData.camaras[0].Nombre
Write-Info "Camara: $camaraNombre"

# --- Obtener VMS ---
Write-Step "Consultando establecimiento $EstablecimientoId ..."
$estabData = Invoke-SportsReelApi "$ApiBase/establecimiento/getById/$EstablecimientoId"
if (-not $estabData -or -not $estabData.establecimiento.Vms) {
    Write-Err "No se encontro VMS para establecimiento $EstablecimientoId"
    exit 1
}
$vmsUrl = $estabData.establecimiento.Vms.url
$vmsPort = $estabData.establecimiento.Vms.port
Write-Info "VMS: ${vmsUrl}:${vmsPort}"

$proxyBase = "https://${vmsUrl}:${vmsPort}"

# --- Directorio de salida ---
$outputDir = Join-Path ([Environment]::GetFolderPath("MyVideos")) "${FechaCompact}_${Nombre}"
if ([string]::IsNullOrEmpty([Environment]::GetFolderPath("MyVideos"))) {
    $outputDir = Join-Path $env:USERPROFILE "Videos\${FechaCompact}_${Nombre}"
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$clipsDir = Join-Path $outputDir "clips"
New-Item -ItemType Directory -Path $clipsDir -Force | Out-Null

Write-Info "Destino: $outputDir"

# --- Timezone: Argentina = UTC-3 ---
$argentinaOffset = [TimeSpan]::FromHours(-3)

# --- Descargar cada horario ---
$horaArray = $Horas -split "," | ForEach-Object { $_.Trim() }
$total = $horaArray.Count
$count = 0

foreach ($hora in $horaArray) {
    $count++
    $horaInt = [int]$hora
    $horaEnd = $horaInt + 1
    $horaTag = "{0:D2}00-{1:D2}00" -f $horaInt, $horaEnd
    $fileBase = "${FechaCompact}_${Nombre}_${horaTag}"

    Write-Host ""
    Write-Host "  [$count/$total] Descargando video de las ${hora}:00 hs" -ForegroundColor White -BackgroundColor DarkBlue

    # Calcular epoch (fecha + hora en Argentina -> UTC)
    $localDateTime = [DateTime]::ParseExact("$Fecha ${hora}:00:00", "yyyy-MM-dd H:mm:ss", $null)
    $utcDateTime = $localDateTime - $argentinaOffset
    $epoch = [int][double]::Parse(($utcDateTime - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds.ToString())

    $epochAfter = $epoch - 1
    $epochBefore = $epoch + 3600

    Write-Info "Epoch: $epochAfter -> $epochBefore"

    # --- Crear vodBlock ---
    Write-Step "Creando vodBlock..."
    $vodBody = @{
        before = $epochBefore
        after = $epochAfter
        cameras = $camaraNombre
        establecimientoId = $EstablecimientoId
        canchaId = $CanchaId
        create = $true
    }
    $vodResponse = Invoke-SportsReelApi "$proxyBase/api/recordings" "POST" $vodBody

    if (-not $vodResponse -or [string]::IsNullOrEmpty($vodResponse.vodBlock)) {
        Write-Err "No se pudo crear vodBlock para las ${hora}hs"
        continue
    }

    $vodUuid = $vodResponse.vodBlock
    $recCount = 0
    if ($vodResponse.recordings) { $recCount = $vodResponse.recordings.Count }

    Write-Info "vodBlock: $vodUuid"
    Write-Info "Recordings: $recCount fragmentos"

    if ($recCount -eq 0) {
        Write-Host "  AVISO: No hay grabaciones para este horario. Saltando." -ForegroundColor Yellow
        continue
    }

    # --- Descargar con ffmpeg ---
    $m3u8Url = "$proxyBase/vod/$camaraNombre/vodBlock/$vodUuid/index.m3u8"
    $outputFile = Join-Path $outputDir "$fileBase.mp4"

    Write-Info "Stream: $m3u8Url"
    Write-Info "Destino: $outputFile"
    Write-Host ""

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $ffmpeg -y -i $m3u8Url -c copy -bsf:a aac_adtstoasc $outputFile 2>&1 | Select-String -Pattern "time=|error"
    $ErrorActionPreference = $prevEAP

    if (-not (Test-Path $outputFile)) {
        Write-Err "La descarga fallo para las ${hora}hs"
        continue
    }

    $fileSize = "{0:N1} MB" -f ((Get-Item $outputFile).Length / 1MB)
    $duration = ""
    if ($ffprobe) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $duration = & $ffprobe -v quiet -show_entries format=duration -of csv=p=0 $outputFile 2>$null
        $ErrorActionPreference = $prevEAP
        if ($duration) {
            $durationSec = [math]::Floor([double]$duration)
            $durationMin = [math]::Floor($durationSec / 60)
            Write-Step "Descargado: ${durationSec}s (~${durationMin} min), $fileSize"
        } else {
            Write-Step "Descargado: $fileSize"
        }
    } else {
        Write-Step "Descargado: $fileSize"
    }

    # --- Cortar en clips de 15 segundos ---
    Write-Host ""
    Write-Step "Cortando en clips de 15 segundos..."

    $clipPattern = Join-Path $clipsDir "${fileBase}_clip_%03d.mp4"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $ffmpeg -y -i $outputFile -c copy -map 0 -segment_time 15 -f segment -reset_timestamps 1 $clipPattern 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP

    # Renombrar clips con timestamp legible
    $clipFiles = Get-ChildItem -Path $clipsDir -Filter "${fileBase}_clip_*.mp4" | Sort-Object Name
    foreach ($clip in $clipFiles) {
        if ($clip.Name -match "clip_(\d+)\.mp4$") {
            $num = [int]$Matches[1]
            $startSec = $num * 15
            $mins = [math]::Floor($startSec / 60)
            $secs = $startSec % 60
            $tsTag = "{0:D2}m{1:D2}s" -f $mins, $secs
            $newName = "${fileBase}_${tsTag}.mp4"
            Rename-Item $clip.FullName $newName
        }
    }

    $clipCount = (Get-ChildItem -Path $clipsDir -Filter "${fileBase}_*.mp4").Count
    Write-Info "$clipCount clips generados en clips/"

    # --- Generar playlist M3U ---
    $playlist = Join-Path $outputDir "$fileBase.m3u"
    $m3uContent = "#EXTM3U`r`n"
    $sortedClips = Get-ChildItem -Path $clipsDir -Filter "${fileBase}_*.mp4" | Sort-Object Name
    foreach ($clip in $sortedClips) {
        if ($clip.Name -match "(\d+m\d+s)\.mp4$") {
            $tsLabel = $Matches[1]
            $m3uContent += "#EXTINF:15,$($clip.Name) ($tsLabel)`r`n"
            $m3uContent += "$($clip.FullName)`r`n"
        }
    }
    [System.IO.File]::WriteAllText($playlist, $m3uContent)
    Write-Info "Playlist: $playlist"
}

# --- Resumen ---
Write-Header "Listo!"
Write-Info "Directorio: $outputDir"
Write-Host ""
Write-Host "  Videos completos:" -ForegroundColor White
Get-ChildItem -Path $outputDir -Filter "*.mp4" -File | ForEach-Object {
    $size = "{0:N1} MB" -f ($_.Length / 1MB)
    Write-Host "    $($_.Name) ($size)"
}
Write-Host ""
$totalClips = (Get-ChildItem -Path $clipsDir -Filter "*.mp4" -ErrorAction SilentlyContinue).Count
Write-Host "  Clips: $totalClips clips de 15s en clips/" -ForegroundColor White
Write-Host ""
Write-Host "  Abrir en VLC:" -ForegroundColor White
Get-ChildItem -Path $outputDir -Filter "*.m3u" | ForEach-Object {
    Write-Host "    start `"$($_.FullName)`""
}
Write-Host ""
Write-Host "  En VLC: Ctrl+N = siguiente, Ctrl+P = anterior" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
