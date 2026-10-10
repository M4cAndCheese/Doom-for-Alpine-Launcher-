#!/usr/bin/env bash
# Uso: bash build.sh [CARPETA_CON_DOOM.WAD]
# Motor unico: Crispy Doom (ultrawide, sin estirar). Si falla, deja dist/crispy_error.txt.
set -o pipefail
rm -rf dist && mkdir -p dist/wad
if ! bash build_crispy.sh 2>&1 | tee crispy.log; then
  mkdir -p dist
  tail -n 400 crispy.log > dist/crispy_error.txt
  echo "=== ERROR: Crispy Doom fallo. Revisa dist/crispy_error.txt ==="
  exit 1
fi
echo "=== MOTOR: Crispy Doom ==="
echo "Pon aqui tu DOOM.WAD renombrado a doom.wad (minusculas)." > dist/wad/LEEME.txt
if [ -n "$1" ]; then
  WAD=$(find "$1" -maxdepth 1 \( -iname doom.wad -o -iname doom1.wad \) | head -1)
  [ -n "$WAD" ] || { echo "No hay DOOM.WAD ni DOOM1.WAD en $1"; exit 1; }
  cp "$WAD" "dist/wad/$(basename "$WAD" | tr 'A-Z' 'a-z')"
fi
cp manifest.json icon.png dist/
python3 -c "import shutil;shutil.make_archive('doom-native','zip','dist')"
du -sh dist
echo "Motor usado: $(cat dist/motor.txt)"
