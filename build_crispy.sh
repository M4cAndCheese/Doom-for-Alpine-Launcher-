#!/usr/bin/env bash
# Compila Crispy Doom a WebAssembly (ultrawide + sonido). Deja dist/doom.js y dist/index.html.
set -e
echo "=== Preparando Crispy Doom ==="
sudo apt-get update -qq || true
sudo apt-get install -y -qq cmake libsdl2-dev libsdl2-mixer-dev libsdl2-net-dev || true
rm -rf crispy
git clone --depth 1 --branch crispy-doom-7.0 https://github.com/fabiangreffrath/crispy-doom.git crispy \
  || git clone --depth 1 --branch crispy-doom-6.0 https://github.com/fabiangreffrath/crispy-doom.git crispy \
  || git clone --depth 1 https://github.com/fabiangreffrath/crispy-doom.git crispy
echo "Version de Crispy Doom: $(git -C crispy describe --tags --always 2>/dev/null || echo desconocida)"
# cmake nativo solo para generar config.h y la lista de archivos (no se compila nada nativo)
cmake -S crispy -B crispy/build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DENABLE_FLUIDSYNTH=OFF -DENABLE_LIBSAMPLERATE=OFF \
  -DENABLE_LIBPNG=OFF -DENABLE_ZLIB=OFF
cat > /tmp/crispy_build.py <<'PYEOF'
# Prepara y compila Crispy Doom a WebAssembly para Alpine Launcher.
import glob, json, os, re, shlex, subprocess, sys

R = 'crispy'


def rd(p):
    return open(p, encoding='utf-8', errors='replace').read()


def wr(p, s):
    open(p, 'w', encoding='utf-8').write(s)


def patch_loop(root, wipe_step=None):
    """Convierte el bucle infinito de D_DoomLoop en un bucle del navegador."""
    p = os.path.join(root, 'src', 'doom', 'd_main.c')
    s = rd(p)
    m = re.search(r'void\s+D_DoomLoop\s*\(\s*void\s*\)\s*\{', s)
    if not m:
        raise SystemExit('No se encontro la definicion de D_DoomLoop')
    mw = re.compile(r'while\s*\(\s*1\s*\)\s*\{').search(s, m.end())
    if not mw:
        raise SystemExit('No se encontro while(1) en D_DoomLoop')
    ob = mw.end() - 1
    depth, i = 0, ob
    while i < len(s):
        c = s[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = s[ob + 1:i]
    func = ((wipe_step or '') + 'static void alpine_loop_body(void)\n{\n'
            '    static int alpine_last_tic = -1;\n'
            '    int alpine_t = I_GetTime();\n'
            '    if (alpine_t == alpine_last_tic) return;\n'
            '    alpine_last_tic = alpine_t;\n'
            + ('    if (alpine_wipe_active) { alpine_wipe_step(); return; }\n' if wipe_step else '')
            + body + '\n}\n\n')
    s2 = s[:mw.start()] + 'emscripten_set_main_loop(alpine_loop_body, 0, 1);\n' + s[i + 1:]
    s2 = s2[:m.start()] + func + s2[m.start():]
    s2 = '#include <emscripten.h>\nextern int I_GetTime(void);\n' + s2
    wr(p, s2)
    print('PARCHE bucle principal: OK')


def patch_wipe(root):
    """Hace la transicion de pantalla (melt) sin bloquear: un paso por tic."""
    p = os.path.join(root, 'src', 'doom', 'd_main.c')
    s = rd(p)
    m = re.search(r'wipestart\s*=\s*I_GetTime\s*\(\s*\)\s*-\s*1\s*;', s)
    ml = re.compile(r'do\s*\{(.*?)\}\s*while\s*\(\s*!\s*done\s*\)\s*;', re.S).search(s, m.end()) if m else None
    md = re.search(r'done\s*=\s*wipe_ScreenWipe', ml.group(1)) if ml else None
    if not md:
        print('AVISO: no se encontro el bucle de transicion; las transiciones seran instantaneas')
        return None
    stmts = ml.group(1)[md.start():]
    step = ('static void alpine_wipe_step(void)\n{\n'
            '    int nowtime = I_GetTime();\n'
            '    int tics = nowtime - alpine_wipestart;\n'
            '    int done;\n'
            '    if (tics <= 0) return;\n'
            '    alpine_wipestart = nowtime;\n' + stmts + '\n'
            '    if (done) alpine_wipe_active = 0;\n}\n\n')
    s2 = s[:m.start()] + 'alpine_wipestart = I_GetTime () - 1;\n    alpine_wipe_active = 1;' + s[ml.end():]
    wr(p, 'static int alpine_wipe_active = 0;\nstatic int alpine_wipestart = 0;\n' + s2)
    print('PARCHE transiciones: OK')
    return step


def patch_savename(root, rel=('src', 'doom', 'm_menu.c')):
    """Al guardar, rellena un nombre ("PARTIDA N") para no necesitar teclado."""
    p = os.path.join(root, *rel)
    if not os.path.exists(p):
        print('AVISO: no se encontro m_menu.c; guardar pedira escribir un nombre')
        return
    s = rd(p)
    m = re.search(r'saveCharIndex\s*=\s*strlen\s*\(\s*savegamestrings\s*\[\s*choice\s*\]\s*\)\s*;', s)
    if not m or 'PARTIDA' in s:
        print('AVISO: no se pudo parchear el nombre de guardado')
        return
    ins = ('if (savegamestrings[choice][0] == 0)\n'
           '        snprintf(savegamestrings[choice], SAVESTRINGSIZE, "PARTIDA %d", choice + 1);\n    ')
    wr(p, '#include <stdio.h>\n' + s[:m.start()] + ins + s[m.start():])
    print('PARCHE nombre de guardado: OK')


def patch_hook(root):
    """Llama a alpine_tic_hook() al inicio de cada tic (entrada analogica)."""
    for f in sorted(glob.glob(os.path.join(root, 'src', '*.c'))):
        s = rd(f)
        m = re.search(r'void\s+I_StartTic\s*\(\s*void\s*\)\s*\{', s)
        if m:
            s = s[:m.end()] + '\n    alpine_tic_hook();\n' + s[m.end():]
            wr(f, 'extern void alpine_tic_hook(void);\n' + s)
            print('PARCHE I_StartTic: OK en', os.path.basename(f))
            return
    print('AVISO: no se encontro I_StartTic; el joystick y la camara analogicos no funcionaran')


def sanitize_config(root):
    """Quita librerias opcionales que el config.h nativo pudo activar."""
    p = os.path.join(root, 'build', 'config.h')
    if not os.path.exists(p):
        raise SystemExit('No se genero config.h')
    s = rd(p)
    s = re.sub(r'^\s*#\s*define\s+(HAVE_LIBSAMPLERATE|HAVE_FLUIDSYNTH|HAVE_LIBPNG|HAVE_ZLIB)\b.*$',
               r'/* desactivado: \1 */', s, flags=re.M)
    wr(p, s)
    print('config.h revisado')


def collect(root):
    cc = json.load(open(os.path.join(root, 'build', 'compile_commands.json')))
    skip = re.compile(r'heretic|hexen|strife|setup|server|midiread|fuzz|test')
    by_target = {}
    for e in cc:
        toks = shlex.split(e['command'])
        out = toks[toks.index('-o') + 1] if '-o' in toks else ''
        m = re.search(r'CMakeFiles/([^/]+)\.dir/', out)
        path = os.path.normpath(os.path.join(e['directory'], e['file']))
        by_target.setdefault(m.group(1) if m else '?', []).append((path, toks))
    print('Objetivos CMake:', {k: len(v) for k, v in by_target.items()})

    srcs, incs, defs, seen = [], [], [], set()
    for name, items in by_target.items():
        if skip.search(name):
            continue
        for path, toks in items:
            if path not in seen:
                seen.add(path)
                srcs.append(path)
            for t in toks:
                if t.startswith('-I') and not t[2:].startswith('/usr') and t[2:] not in incs:
                    incs.append(t[2:])
                elif t.startswith('-D') and t not in defs:
                    defs.append(t)
    # Solo un main(): el de i_main.c
    final = []
    for f in srcs:
        base = os.path.basename(f)
        if base != 'i_main.c' and re.search(r'^\s*(int|void)\s+main\s*\(', rd(f), re.M):
            print('Se omite (tiene otro main):', base)
            continue
        final.append(f)
    for extra in ('src', os.path.join('src', 'doom'), 'build'):
        p = os.path.abspath(os.path.join(root, extra))
        if p not in incs:
            incs.append(p)
    print('Archivos fuente:', len(final))
    if len(final) < 50:
        raise SystemExit('Muy pocos archivos fuente: seleccion de objetivos incorrecta')
    return final, incs, defs


def compile_all(srcs, incs, defs):
    cmd = (['emcc', '-O2', '-w', '-Wno-implicit-function-declaration', '-Wno-int-conversion',
            '-Wno-incompatible-pointer-types']
           + ['-I' + i for i in incs] + defs + ['alpine_crispy.c'] + srcs +
           ['-sUSE_SDL=2', '-sUSE_SDL_MIXER=2', '-sUSE_SDL_NET=2',
            '-sSINGLE_FILE=1', '-sALLOW_MEMORY_GROWTH=1', '-sINITIAL_MEMORY=128MB', '-sSTACK_SIZE=2MB',
            '-sFORCE_FILESYSTEM=1', '-lidbfs.js', '-sINVOKE_RUN=0', '-sEXIT_RUNTIME=0', '-sENVIRONMENT=web',
            '-sEXPORTED_FUNCTIONS=_main,_alpine_key,_alpine_move,_alpine_look,_alpine_mount',
            '-sEXPORTED_RUNTIME_METHODS=ccall,callMain',
            '-o', os.path.join('dist', 'doom.js')])
    print('Compilando con emcc (%d archivos)...' % len(srcs))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        raise SystemExit('emcc fallo (codigo %d)' % r.returncode)
    print('Tamano doom.js:', os.path.getsize(os.path.join('dist', 'doom.js')) // 1024, 'KB')


def main():
    step = patch_wipe(R)
    patch_loop(R, step)
    patch_savename(R)
    patch_hook(R)
    sanitize_config(R)
    srcs, incs, defs = collect(R)
    compile_all(srcs, incs, defs)


if __name__ == '__main__':
    main()
PYEOF
python3 /tmp/crispy_build.py
cp index_crispy.html dist/index.html
echo crispy > dist/motor.txt
