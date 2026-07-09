# Fulbito Downloader

Descarga videos de partidos de fútbol desde [SportsReel](https://sportsreel.com.ar) y los corta en clips de 15 segundos para revisar jugadas rápidamente en VLC.

## Requisitos

### macOS / Linux

- **ffmpeg** — descarga y corte de video
- **curl** — llamadas a la API
- **jq** — parseo de JSON

```bash
# macOS
brew install ffmpeg jq

# Ubuntu/Debian
sudo apt install ffmpeg jq curl
```

### Windows

- **No necesitás instalar nada.** El `.bat` auto-descarga ffmpeg la primera vez (~90MB).

## Instalación

### macOS / Linux

```bash
git clone git@github.com:faustow/fulbitodownloader.git
cd fulbitodownloader
chmod +x sportsreel_download.sh
```

### Windows

[Descargá el ZIP](https://github.com/faustow/fulbitodownloader/archive/refs/heads/main.zip), extraé y hacé doble click en `descargar_fulbito.bat`.

O desde PowerShell:

```powershell
git clone https://github.com/faustow/fulbitodownloader.git
cd fulbitodownloader
```

## Uso

### Caso más común (sin argumentos)

Descarga los videos de las **21:00** y **22:00 hs** del **lunes anterior** de **Olimpicus 1, Cancha 3**.

```bash
# macOS / Linux
./sportsreel_download.sh

# Windows (doble click en descargar_fulbito.bat, o desde terminal)
.\descargar_fulbito.bat
```

### Con opciones

| | macOS / Linux | Windows (PowerShell) |
|---|---|---|
| Nombre personalizado | `./sportsreel_download.sh "fulbo_martes"` | `.\sportsreel_download.ps1 -Nombre "fulbo_martes"` |
| Fecha específica | `./sportsreel_download.sh "fulbito" 2026-07-06` | `.\sportsreel_download.ps1 -Fecha "2026-07-06"` |
| Solo las 21hs | `./sportsreel_download.sh "fulbito" 2026-07-06 "21"` | `.\sportsreel_download.ps1 -Horas "21"` |
| Las 20, 21 y 22hs | `./sportsreel_download.sh "fulbito" "" "20,21,22"` | `.\sportsreel_download.ps1 -Horas "20,21,22"` |
| Otra cancha | `./sportsreel_download.sh "" "" "" 347 71` | `.\sportsreel_download.ps1 -CanchaId 347 -EstablecimientoId 71` |

También podés pasar parámetros por el .bat:

```
descargar_fulbito.bat -Nombre "fulbo_martes" -Fecha "2026-07-06"
```

### ¿Dónde saco los IDs de cancha?

De la URL de SportsReel:

```
https://sportsreel.com.ar/#/canchasEstablecimiento/71/cancha/347
                                                   ^^         ^^^
                                          establecimiento   cancha
```

## Parámetros

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| Nombre | `fulbito` | Nombre base para los archivos |
| Fecha | Lunes anterior | Fecha del partido (`YYYY-MM-DD`) |
| Horarios | `21,22` | Horas de inicio separadas por coma |
| Cancha ID | `347` | ID de la cancha en SportsReel (Cancha 3, Olimpicus) |
| Establecimiento ID | `71` | ID del complejo en SportsReel (Olimpicus 1) |

## Archivos generados

```
~/Movies/20260706_fulbito/                        (macOS)
C:\Users\xxx\Videos\20260706_fulbito\             (Windows)
├── 20260706_fulbito_2100-2200.mp4          Video completo 21-22hs
├── 20260706_fulbito_2100-2200.m3u          Playlist VLC
├── 20260706_fulbito_2200-2300.mp4          Video completo 22-23hs
├── 20260706_fulbito_2200-2300.m3u
└── clips/
    ├── 20260706_fulbito_2100-2200_00m00s.mp4
    ├── 20260706_fulbito_2100-2200_00m15s.mp4
    ├── 20260706_fulbito_2100-2200_00m30s.mp4
    ├── ...
    ├── 20260706_fulbito_2200-2300_00m00s.mp4
    └── ...
```

### Naming

Los archivos siguen el formato `YYYYMMDD_nombre_HHmm-HHmm[_MMmSSs].mp4`:

- `20260706` — fecha del partido
- `fulbito` — nombre que le pusiste
- `2100-2200` — rango horario (21:00 a 22:00)
- `15m30s` — (solo clips) timestamp dentro del video

Querés ver el minuto 15 del partido de las 21? Buscá `2100-2200_15m`.

## Ver en VLC

Abrí la playlist para navegar los clips de 15 segundos:

```bash
# macOS
open ~/Movies/20260706_fulbito/20260706_fulbito_2100-2200.m3u

# Windows
start C:\Users\xxx\Videos\20260706_fulbito\20260706_fulbito_2100-2200.m3u
```

- **Ctrl+N** → siguiente clip
- **Ctrl+P** → clip anterior

## Cómo funciona

El script interactúa con la API de SportsReel en 4 pasos:

1. **Descubre la cámara** de la cancha (`/camara/getByCanchaId/{id}`)
2. **Obtiene el servidor de video** (VMS) del establecimiento (`/establecimiento/getById/{id}`)
3. **Crea un vodBlock** enviando fecha/hora al proxy (`POST /api/recordings` con `create: true`), que devuelve un UUID para el video
4. **Descarga el stream HLS** con ffmpeg (`/vod/{camara}/vodBlock/{uuid}/index.m3u8`)

No necesitás copiar URLs de la web — el script calcula los timestamps y obtiene el video automáticamente.

## Licencia

MIT
