#!/usr/bin/env bash
# Depois de cada git pull: garante o Godot, os sprites da wiki, o cache de classes do projeto e os modelos voxel derivados (assets/models/gen/). Sem o passo do
# cache o jogo pode abrir com erro do tipo "Identifier ... not declared" quando chega script novo (class_name).
# Idempotente e rápido quando nada mudou. Uso:
#   git pull && scripts/update.sh && .tools/godot
set -uo pipefail
cd "$(dirname "$0")/.."
scripts/setup-godot.sh || exit 1
scripts/fetch-sprites.sh || echo "aviso: faltam sprites (a wiki limita o ritmo): rode scripts/update.sh de novo daqui a uns minutos. O jogo funciona sem eles."
out=$(.tools/godot --headless --import 2>&1)
if echo "$out" | grep -E "SCRIPT ERROR|Parse Error" >/dev/null; then
	echo "$out" | grep -E "SCRIPT ERROR|Parse Error|at: " | head -20
	echo "ERRO ao importar o projeto (acima). Me mande esta saída."
	exit 1
fi
.tools/godot --headless -s scripts/voxel/build.gd 2>&1 | grep -E "modelos voxel|SCRIPT ERROR|Parse Error" || echo "aviso: modelos voxel não gerados (o jogo usa as receitas em memória)"
echo "pronto. Jogar: .tools/godot   |   testes: .tools/godot --headless -s tests/run.gd"
