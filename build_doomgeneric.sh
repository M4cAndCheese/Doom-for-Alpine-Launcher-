#!/usr/bin/env bash
# Motor de respaldo (doomgeneric, 4:3). Deja dist/doom.js y dist/index.html.
set -e
[ -d doomgeneric ] || git clone --depth 1 https://github.com/ozkl/doomgeneric.git
SRC=doomgeneric/doomgeneric
python3 - <<'PYEOF'
import re
p = 'doomgeneric/doomgeneric/m_menu.c'
s = open(p, encoding='utf-8', errors='replace').read()
m = re.search(r'saveCharIndex\s*=\s*strlen\s*\(\s*savegamestrings\s*\[\s*choice\s*\]\s*\)\s*;', s)
if m and 'PARTIDA' not in s:
    ins = 'if (savegamestrings[choice][0] == 0)\n        snprintf(savegamestrings[choice], SAVESTRINGSIZE, "PARTIDA %d", choice + 1);\n    '
    open(p, 'w', encoding='utf-8').write('#include <stdio.h>\n' + s[:m.start()] + ins + s[m.start():])
    print('PARCHE nombre de guardado: OK')
else:
    print('AVISO: no se pudo parchear el nombre de guardado')
PYEOF
BASE=$(ls $SRC/*.c | grep -vE 'doomgeneric_[a-z]+\.c$|i_(sdl|allegro)(sound|music)\.c$' || true)
CFLAGS="-O2 -w -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -I$SRC"
LFLAGS="-sSINGLE_FILE=1 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sFORCE_FILESYSTEM=1 -lidbfs.js -sEXPORTED_FUNCTIONS=_main,_alpine_start,_alpine_key,_alpine_mount,_alpine_move,_alpine_look -sEXPORTED_RUNTIME_METHODS=ccall -sEXIT_RUNTIME=0 -sENVIRONMENT=web"

# Primero con sonido (SDL_mixer); si falla, sin sonido.
if [ -f $SRC/i_sdlsound.c ] && [ -f $SRC/i_sdlmusic.c ] && \
   emcc $CFLAGS -DFEATURE_SOUND -sUSE_SDL=2 -sUSE_SDL_MIXER=2 $BASE $SRC/i_sdlsound.c $SRC/i_sdlmusic.c doomgeneric_alpine.c -o dist/doom.js $LFLAGS; then
  echo SI > dist/sonido.txt
  echo "=== SONIDO: SI ==="
else
  echo "=== SONIDO: la compilacion con sonido fallo; compilando sin sonido ==="
  emcc $CFLAGS $BASE doomgeneric_alpine.c -o dist/doom.js $LFLAGS
  echo NO > dist/sonido.txt
fi
cp index.html dist/index.html
echo doomgeneric > dist/motor.txt
