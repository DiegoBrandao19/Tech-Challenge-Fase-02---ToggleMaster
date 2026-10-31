#!/usr/bin/env bash
# Monta o vídeo final: corta trechos dos vídeos gravados (local e AWS), acelera esperas e junta tudo.
# Uso: ./scripts/montar-video.sh      (edite a seção CONFIGURAÇÃO abaixo)
# Requer: ffmpeg  (sudo apt install ffmpeg)
set -euo pipefail

############################ CONFIGURAÇÃO ############################
LOCAL="local.mp4"        # vídeo gravado da parte local (Docker Compose)
AWS="aws.mp4"            # vídeo gravado da parte AWS (pode ser vários: veja trechos)
SAIDA="video-final.mp4"
RES="1920:1080"          # todos os trechos são padronizados nesta resolução
FPS=30

# Cada linha de TRECHOS: arquivo | início | fim | velocidade
#   - tempos em hh:mm:ss  (ex.: 00:02:10)
#   - velocidade 1 = normal (mantém o áudio). 2, 4, 8 = acelerado (SEM áudio, p/ esperas)
# A ordem das linhas é a ordem do vídeo final.
TRECHOS=(
  "$LOCAL | 00:00:00 | 00:01:30 | 1"     # abertura / arquitetura (ajuste)
  "$LOCAL | 00:01:30 | 00:05:00 | 4"     # build / compose up (acelerado)
  "$LOCAL | 00:05:00 | 00:09:00 | 1"     # testes locais
  "$AWS   | 00:00:00 | 00:03:00 | 1"     # tour do Console AWS
  "$AWS   | 00:03:00 | 00:06:00 | 1"     # cluster, pods, testes
  "$AWS   | 00:06:00 | 00:09:00 | 1"     # carga e HPA
)
#######################################################################

command -v ffmpeg >/dev/null || { echo "ffmpeg não encontrado: sudo apt install ffmpeg"; exit 1; }
TMP=$(mktemp -d)
LISTA="$TMP/lista.txt"
: > "$LISTA"
i=0
for linha in "${TRECHOS[@]}"; do
  IFS='|' read -r arq ini fim vel <<<"$linha"
  arq=$(echo "$arq" | xargs); ini=$(echo "$ini" | xargs); fim=$(echo "$fim" | xargs); vel=$(echo "$vel" | xargs)
  i=$((i+1)); out="$TMP/p$(printf %02d $i).mp4"
  vf="scale=$RES:force_original_aspect_ratio=decrease,pad=${RES/:/:}:(ow-iw)/2:(oh-ih)/2,fps=$FPS,setsar=1"
  if [ "$vel" = "1" ]; then
    ffmpeg -loglevel error -y -ss "$ini" -to "$fim" -i "$arq" -vf "$vf" \
      -c:v libx264 -preset veryfast -crf 23 -c:a aac -ar 44100 -ac 2 "$out"
  else
    ffmpeg -loglevel error -y -ss "$ini" -to "$fim" -i "$arq" \
      -vf "setpts=PTS/$vel,$vf" -an -c:v libx264 -preset veryfast -crf 23 "$out.tmp.mp4"
    # adiciona áudio mudo para manter o concat consistente
    ffmpeg -loglevel error -y -i "$out.tmp.mp4" -f lavfi -i anullsrc=r=44100:cl=stereo \
      -shortest -c:v copy -c:a aac "$out"
    rm -f "$out.tmp.mp4"
  fi
  echo "file '$out'" >> "$LISTA"
  echo "trecho $i ok ($arq $ini -> $fim x$vel)"
done

ffmpeg -loglevel error -y -f concat -safe 0 -i "$LISTA" -c copy "$SAIDA"
dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$SAIDA")
printf 'Pronto: %s  duração: %d min %02d s\n' "$SAIDA" $((${dur%.*}/60)) $((${dur%.*}%60))
[ "${dur%.*}" -le 1200 ] && echo "OK: dentro do limite de 20 min" || echo "ATENÇÃO: passou de 20 min, corte mais"
rm -rf "$TMP"
