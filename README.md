# Fulbito Downloader

Descarga videos de partidos de fútbol desde [SportsReel](https://sportsreel.com.ar) y los corta en clips de 15 segundos para revisar jugadas rápidamente en VLC.

## Requisitos

- **ffmpeg** — descarga y corte de video
- **curl** — llamadas a la API
- **jq** — parseo de JSON

En macOS:

```bash
brew install ffmpeg jq
```

## Instalación

```bash
git clone git@github.com:faustow/fulbitodownloader.git
cd fulbitodownloader
chmod +x sportsreel_download.sh
```

## Uso

### Sin argumentos (uso más común)

```bash
./sportsreel_download.sh
```

Descarga los videos de las **21:00** y **22:00 hs** del **lunes anterior** de **Olimpicus 1, Cancha 3**.

### Con nombre personalizado

```bash
./sportsreel_download.sh "fulbo_martes"
```

### Fecha específica

```bash
./sportsreel_download.sh "fulbito" 2026-07-06
```

### Horarios específicos

```bash
# Solo el de las 21hs
./sportsreel_download.sh "fulbito" 2026-07-06 "21"

# Las 20, 21 y 22hs
./sportsreel_download.sh "fulbito" 2026-07-06 "20,21,22"
```

### Otra cancha u otro complejo

```bash
./sportsreel_download.sh "fulbito" 2026-07-06 "21,22" CANCHA_ID ESTABLECIMIENTO_ID
```

Los IDs de cancha y establecimiento se pueden obtener de la URL de SportsReel. Por ejemplo:

```
https://sportsreel.com.ar/#/canchasEstablecimiento/71/cancha/347
                                                   ^^         ^^^
                                          establecimiento   cancha
```

## Parámetros

| # | Parámetro | Default | Descripción |
|---|-----------|---------|-------------|
| 1 | Nombre | `fulbito` | Nombre base para los archivos |
| 2 | Fecha | Lunes anterior | Fecha del partido (`YYYY-MM-DD`) |
| 3 | Horarios | `21,22` | Horas de inicio separadas por coma |
| 4 | Cancha ID | `347` | ID de la cancha en SportsReel (Cancha 3, Olimpicus) |
| 5 | Establecimiento ID | `71` | ID del complejo en SportsReel (Olimpicus 1) |

## Archivos generados

```
~/Movies/20260706_fulbito/
├── 20260706_fulbito_2100-2200.mp4          Video completo 21-22hs
├── 20260706_fulbito_2100-2200.m3u          Playlist VLC para los clips
├── 20260706_fulbito_2200-2300.mp4          Video completo 22-23hs
├── 20260706_fulbito_2200-2300.m3u
└── clips/
    ├── 20260706_fulbito_2100-2200_00m00s.mp4
    ├── 20260706_fulbito_2100-2200_00m15s.mp4
    ├── 20260706_fulbito_2100-2200_00m30s.mp4
    ├── ...
    ├── 20260706_fulbito_2100-2200_59m45s.mp4
    ├── 20260706_fulbito_2200-2300_00m00s.mp4
    ├── 20260706_fulbito_2200-2300_00m15s.mp4
    └── ...
```

### Naming

Los archivos siguen el formato `YYYYMMDD_nombre_HHmm-HHmm[_MMmSSs].mp4`:

- `20260706` — fecha del partido
- `fulbito` — nombre que le pusiste
- `2100-2200` — rango horario (21:00 a 22:00)
- `15m30s` — (solo clips) timestamp dentro del video

Esto permite ordenar y buscar visualmente por horario. Querés ver el minuto 15 del partido de las 21? Buscá `2100-2200_15m`.

## Ver en VLC

Abrí la playlist para navegar los clips de 15 segundos:

```bash
open ~/Movies/20260706_fulbito/20260706_fulbito_2100-2200.m3u
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
