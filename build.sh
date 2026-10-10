#!/usr/bin/env bash
# Uso: bash build.sh [CARPETA_CON_DOOM.WAD]
# Intenta Crispy Doom (ultrawide); si falla, usa doomgeneric (la version estable).
set -o pipefail
rm -rf dist && mkdir -p dist/wad
if bash build_crispy.sh 2>&1 | tee crispy.log; then
  echo "=== MOTOR: Crispy Doom ==="
else
  echo "=== MOTOR: Crispy Doom fallo; se usa doomgeneric (4:3) ==="
  rm -rf dist && mkdir -p dist/wad
  tail -n 400 crispy.log > dist/crispy_error.txt 2>/dev/null || true
  bash build_doomgeneric.sh
fi
set -e
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
