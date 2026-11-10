#!/usr/bin/env bash
# Grava um clipe de jogo sem tela (xvfb + OpenGL por CPU): scripts/clip.sh [roteiro] → textures/clip_<roteiro>.mp4
# Roteiros em tests/clip.gd (CLIPS). O carregamento do mundo é cortado do começo.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-passeio}"
mkdir -p textures
log=$(xvfb-run -a -s "-screen 0 1280x720x24" .tools/godot --write-movie textures/clip_raw.avi --fixed-fps 30 -s tests/clip.gd -- "$name" 2>&1) || { echo "$log" | tail -20; exit 1; }
start=$(echo "$log" | awk '/^clip_inicio/ {print $2}')
ffmpeg -loglevel error -y -ss "$(awk "BEGIN {print ${start:-0} / 30}")" -i textures/clip_raw.avi -an -vf scale=960:-2 -c:v libx264 -crf 26 -pix_fmt yuv420p "textures/clip_$name.mp4"
rm -f textures/clip_raw.avi textures/clip_raw.wav
echo "salvo textures/clip_$name.mp4"
