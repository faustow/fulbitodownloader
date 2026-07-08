#!/usr/bin/env bash
#
# sportsreel_download.sh
# Descarga videos de SportsReel para una cancha y horarios específicos.
# Auto-descubre la cámara y genera el vodBlock via la API.
# Corta en clips de 15s con timestamps en el nombre para buscar visualmente.
#
# USO MÍNIMO (defaults: Olimpicus 1, Cancha 3, lunes anterior 21hs y 22hs):
#   ./sportsreel_download.sh
#
# Con nombre personalizado:
#   ./sportsreel_download.sh "fulbo_martes"
#
# Fecha específica (YYYY-MM-DD):
#   ./sportsreel_download.sh "fulbito" 2026-07-06
#
# Horarios específicos (separados por coma):
#   ./sportsreel_download.sh "fulbito" 2026-07-06 "21,22"
#
# Cancha/establecimiento diferentes:
#   ./sportsreel_download.sh "fulbito" 2026-07-06 "21,22" 347 71
#
# Argumentos:
#   $1  Nombre (default: "fulbito")
#   $2  Fecha del partido YYYY-MM-DD (default: lunes anterior)
#   $3  Horarios separados por coma (default: "21,22")
#   $4  ID de cancha (default: 347 = cancha 3 Olimpicus)
#   $5  ID de establecimiento (default: 71 = Olimpicus 1)
#
# Archivos generados:
#   ~/Movies/20260706_fulbito/
#     20260706_fulbito_2100-2200.mp4       <- video completo 21-22hs
#     20260706_fulbito_2100-2200.m3u       <- playlist VLC
#     20260706_fulbito_2200-2300.mp4       <- video completo 22-23hs
#     20260706_fulbito_2200-2300.m3u
#     clips/
#       20260706_fulbito_2100-2200_00m00s.mp4
#       20260706_fulbito_2100-2200_00m15s.mp4
#       20260706_fulbito_2100-2200_00m30s.mp4
#       ...
#       20260706_fulbito_2200-2300_00m00s.mp4
#       ...

set -euo pipefail

# --- Validar dependencias ---
for cmd in ffmpeg curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' no está instalado." >&2
    exit 1
  fi
done

# --- Defaults ---
DEFAULT_CANCHA_ID=347
DEFAULT_ESTABLECIMIENTO_ID=71
DEFAULT_HORAS="21,22"

# --- Calcular lunes anterior ---
get_last_monday() {
  local dow
  dow=$(date +%u)  # 1=lunes, 7=domingo
  local days_back=$(( (dow - 1 + 7) % 7 ))
  # Si hoy es lunes, usar hoy mismo
  [[ $days_back -eq 0 ]] && days_back=0
  date -v-${days_back}d +%Y-%m-%d 2>/dev/null \
    || date -d "${days_back} days ago" +%Y-%m-%d
}

# --- Parsear argumentos ---
NAME="${1:-}"
FECHA="${2:-$(get_last_monday)}"
HORAS="${3:-$DEFAULT_HORAS}"
CANCHA_ID="${4:-$DEFAULT_CANCHA_ID}"
ESTABLECIMIENTO_ID="${5:-$DEFAULT_ESTABLECIMIENTO_ID}"

[[ -z "$NAME" ]] && NAME="fulbito"

# Formato de fecha compacto para nombres de archivo
FECHA_COMPACT=$(echo "$FECHA" | tr -d '-')

API_BASE="https://servicios.sportsreel.com.ar"

echo "============================================"
echo "  SportsReel Downloader"
echo "============================================"
echo "  Fecha:            $FECHA"
echo "  Horarios:         $HORAS hs"
echo "  Cancha ID:        $CANCHA_ID"
echo "  Establecimiento:  $ESTABLECIMIENTO_ID"
echo "  Nombre:           $NAME"
echo ""

# --- Obtener info de la cámara ---
echo "Consultando cámara para cancha $CANCHA_ID ..."
CAMARA_JSON=$(curl -sf "${API_BASE}/camara/getByCanchaId/${CANCHA_ID}")
CAMARA_NOMBRE=$(echo "$CAMARA_JSON" | jq -r '.camaras[0].Nombre')

if [[ -z "$CAMARA_NOMBRE" || "$CAMARA_NOMBRE" == "null" ]]; then
  echo "ERROR: No se encontró cámara para cancha $CANCHA_ID" >&2
  exit 1
fi
echo "  Cámara: $CAMARA_NOMBRE"

# --- Obtener VMS info ---
echo "Consultando establecimiento $ESTABLECIMIENTO_ID ..."
ESTAB_JSON=$(curl -sf "${API_BASE}/establecimiento/getById/${ESTABLECIMIENTO_ID}")
VMS_URL=$(echo "$ESTAB_JSON" | jq -r '.establecimiento.Vms.url')
VMS_PORT=$(echo "$ESTAB_JSON" | jq -r '.establecimiento.Vms.port')

if [[ -z "$VMS_URL" || "$VMS_URL" == "null" ]]; then
  echo "ERROR: No se encontró VMS para establecimiento $ESTABLECIMIENTO_ID" >&2
  exit 1
fi
echo "  VMS: ${VMS_URL}:${VMS_PORT}"

PROXY_BASE="https://${VMS_URL}:${VMS_PORT}"

# --- Preparar directorio de salida ---
OUTPUT_DIR="$HOME/Movies/${FECHA_COMPACT}_${NAME}"
mkdir -p "$OUTPUT_DIR"

# --- Descargar cada horario ---
IFS=',' read -ra HORA_ARRAY <<< "$HORAS"
TOTAL=${#HORA_ARRAY[@]}
COUNT=0

for HORA in "${HORA_ARRAY[@]}"; do
  HORA=$(echo "$HORA" | tr -d ' ')
  COUNT=$((COUNT + 1))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  [$COUNT/$TOTAL] Descargando video de las ${HORA}:00 hs"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Calcular epoch timestamps (Argentina = UTC-3)
  # fecha + hora en Argentina -> UTC epoch
  # macOS date vs GNU date
  if date -j &>/dev/null 2>&1; then
    # macOS
    EPOCH_START=$(date -j -f "%Y-%m-%d %H:%M:%S" "${FECHA} ${HORA}:00:00" +%s 2>/dev/null)
  else
    # GNU/Linux
    EPOCH_START=$(TZ="America/Argentina/Buenos_Aires" date -d "${FECHA} ${HORA}:00:00" +%s 2>/dev/null)
  fi

  EPOCH_AFTER=$((EPOCH_START - 1))
  EPOCH_BEFORE=$((EPOCH_START + 3600))

  echo "  Epoch: $EPOCH_AFTER → $EPOCH_BEFORE"

  # --- Crear vodBlock via API ---
  echo "  Creando vodBlock..."
  VOD_RESPONSE=$(curl -sf -X POST \
    "${PROXY_BASE}/api/recordings" \
    -H "Content-Type: application/json" \
    -d "{
      \"before\": ${EPOCH_BEFORE},
      \"after\": ${EPOCH_AFTER},
      \"cameras\": \"${CAMARA_NOMBRE}\",
      \"establecimientoId\": ${ESTABLECIMIENTO_ID},
      \"canchaId\": ${CANCHA_ID},
      \"create\": true
    }")

  VOD_UUID=$(echo "$VOD_RESPONSE" | jq -r '.vodBlock')
  REC_COUNT=$(echo "$VOD_RESPONSE" | jq '.recordings | length')

  if [[ -z "$VOD_UUID" || "$VOD_UUID" == "null" ]]; then
    echo "  ERROR: No se pudo crear vodBlock para las ${HORA}hs" >&2
    echo "  Response: $VOD_RESPONSE" >&2
    continue
  fi

  echo "  vodBlock: $VOD_UUID"
  echo "  Recordings: $REC_COUNT fragmentos"

  if [[ "$REC_COUNT" == "0" ]]; then
    echo "  AVISO: No hay grabaciones para este horario. Saltando." >&2
    continue
  fi

  # --- Nombres de archivo ---
  HORA_END=$((HORA + 1))
  HORA_TAG=$(printf "%02d00-%02d00" "$HORA" "$HORA_END")
  FILE_BASE="${FECHA_COMPACT}_${NAME}_${HORA_TAG}"

  # --- Descargar con ffmpeg ---
  M3U8_URL="${PROXY_BASE}/vod/${CAMARA_NOMBRE}/vodBlock/${VOD_UUID}/index.m3u8"
  OUTPUT_FILE="${OUTPUT_DIR}/${FILE_BASE}.mp4"

  echo "  Stream: $M3U8_URL"
  echo "  Destino: $OUTPUT_FILE"
  echo ""

  ffmpeg -y -i "$M3U8_URL" -c copy -bsf:a aac_adtstoasc "$OUTPUT_FILE" 2>&1 \
    | grep --line-buffered -E 'time=|error' \
    || true

  if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "  ERROR: La descarga falló para las ${HORA}hs" >&2
    continue
  fi

  DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$OUTPUT_FILE" | cut -d. -f1)
  SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
  echo "  ✓ Descargado: ${DURATION}s (~$((DURATION / 60)) min), ${SIZE}"

  # --- Cortar en clips de 15 segundos ---
  CLIPS_DIR="${OUTPUT_DIR}/clips"
  mkdir -p "$CLIPS_DIR"

  echo ""
  echo "  Cortando en clips de 15 segundos..."

  ffmpeg -y -i "$OUTPUT_FILE" \
    -c copy -map 0 \
    -segment_time 15 \
    -f segment \
    -reset_timestamps 1 \
    "${CLIPS_DIR}/${FILE_BASE}_clip_%03d.mp4" 2>&1 | tail -1

  # Renombrar clips: agregar timestamp legible
  for clip_file in "${CLIPS_DIR}/${FILE_BASE}_clip_"*.mp4; do
    [[ -f "$clip_file" ]] || continue
    clip_name=$(basename "$clip_file")
    # Extraer número de clip
    num=$(echo "$clip_name" | grep -oE 'clip_[0-9]+' | grep -oE '[0-9]+')
    num_int=$((10#$num))  # quitar leading zeros
    start_sec=$((num_int * 15))
    mins=$((start_sec / 60))
    secs=$((start_sec % 60))
    ts_tag=$(printf "%02dm%02ds" "$mins" "$secs")
    new_name="${FILE_BASE}_${ts_tag}.mp4"
    mv "$clip_file" "${CLIPS_DIR}/${new_name}"
  done

  CLIP_COUNT=$(ls -1 "${CLIPS_DIR}/${FILE_BASE}_"*.mp4 2>/dev/null | wc -l | tr -d ' ')
  echo "  $CLIP_COUNT clips generados en clips/"

  # --- Generar playlist M3U ---
  PLAYLIST="${OUTPUT_DIR}/${FILE_BASE}.m3u"
  echo "#EXTM3U" > "$PLAYLIST"
  for clip_file in $(ls -1 "${CLIPS_DIR}/${FILE_BASE}_"*.mp4 2>/dev/null | sort); do
    clip_name=$(basename "$clip_file")
    ts_label=$(echo "$clip_name" | grep -oE '[0-9]+m[0-9]+s')
    printf '#EXTINF:15,%s (%s)\n' "$clip_name" "$ts_label" >> "$PLAYLIST"
    echo "$clip_file" >> "$PLAYLIST"
  done
  echo "  Playlist: $PLAYLIST"

done

# --- Resumen ---
echo ""
echo "============================================"
echo "  ¡Listo!"
echo "  Directorio: $OUTPUT_DIR"
echo ""
echo "  Videos completos:"
ls -1 "$OUTPUT_DIR"/*.mp4 2>/dev/null | while read f; do
  SIZE=$(du -h "$f" | cut -f1)
  echo "    $(basename "$f") ($SIZE)"
done
echo ""
echo "  Clips en clips/:"
TOTAL_CLIPS=$(ls -1 "$OUTPUT_DIR"/clips/*.mp4 2>/dev/null | wc -l | tr -d ' ')
echo "    $TOTAL_CLIPS clips de 15s"
echo ""
echo "  Abrir en VLC:"
for pl in "$OUTPUT_DIR"/*.m3u; do
  [[ -f "$pl" ]] && echo "    open \"$pl\""
done
echo ""
echo "  En VLC: Ctrl+N = siguiente, Ctrl+P = anterior"
echo "============================================"
