#!/usr/bin/env bash
# Uso: bash build.sh [CARPETA_CON_DOOM.WAD]   (requiere emcc, git, python3)
# Sin carpeta: compila igual y deja dist/ sin WAD (para añadirlo después).
set -e
[ -d doomgeneric ] || git clone --depth 1 https://github.com/ozkl/doomgeneric.git
SRC=doomgeneric/doomgeneric
FILES=$(ls $SRC/*.c | grep -vE 'doomgeneric_[a-z]+\.c$|i_(sdl|allegro)(sound|music)\.c$' || true)
rm -rf dist && mkdir -p dist/wad
emcc -O2 -w -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -I$SRC $FILES doomgeneric_alpine.c -o dist/doom.js \
  -sSINGLE_FILE=1 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sFORCE_FILESYSTEM=1 -lidbfs.js \
  -sEXPORTED_FUNCTIONS=_main,_alpine_start,_alpine_key,_alpine_mount \
  -sEXPORTED_RUNTIME_METHODS=ccall -sEXIT_RUNTIME=0 -sENVIRONMENT=web
echo "Pon aqui tu DOOM.WAD renombrado a doom.wad (minusculas)." > dist/wad/LEEME.txt
if [ -n "$1" ]; then
  WAD=$(find "$1" -maxdepth 1 \( -iname doom.wad -o -iname doom1.wad \) | head -1)
  [ -n "$WAD" ] || { echo "No hay DOOM.WAD ni DOOM1.WAD en $1"; exit 1; }
  cp "$WAD" "dist/wad/$(basename "$WAD" | tr 'A-Z' 'a-z')"
fi
cp index.html manifest.json icon.png dist/
python3 -c "import shutil;shutil.make_archive('doom-native','zip','dist')"
du -sh dist
