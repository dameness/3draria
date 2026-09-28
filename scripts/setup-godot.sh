#!/usr/bin/env bash
# Baixa o Godot fixado em .tools/godot, se ainda não existir. Idempotente.
set -euo pipefail
VERSION=4.7.2-stable
DIR="$(cd "$(dirname "$0")/.." && pwd)/.tools"
BIN="$DIR/Godot_v${VERSION}_linux.x86_64"
[ -x "$BIN" ] && [ -e "$DIR/godot" ] && exit 0
mkdir -p "$DIR"
curl -fsSL -o "$DIR/godot.zip" \
  "https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip"
unzip -oq "$DIR/godot.zip" -d "$DIR" && rm "$DIR/godot.zip"
chmod +x "$BIN" && ln -sf "$(basename "$BIN")" "$DIR/godot"
echo "Godot $VERSION em $DIR/godot"
