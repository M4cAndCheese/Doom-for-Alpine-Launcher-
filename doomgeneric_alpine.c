// Capa de plataforma de doomgeneric para Alpine Launcher (Emscripten).
#include <stdint.h>
#include <string.h>
#include <emscripten.h>
#include "doomkeys.h"
#include "doomgeneric.h"

#define QSIZE 256
static unsigned short queue[QSIZE];
static int qr = 0, qw = 0;

static unsigned char map_key(int id) {
  switch (id) {
    case 0: return KEY_LEFTARROW;
    case 1: return KEY_RIGHTARROW;
    case 2: return KEY_UPARROW;
    case 3: return KEY_DOWNARROW;
    case 4: return KEY_RCTRL;
    case 5: return ' ';
    case 6: return KEY_RSHIFT;
    case 7: return ',';
    case 8: return '.';
    case 9: return KEY_ENTER;
    case 10: return KEY_ESCAPE;
    case 11: return KEY_TAB;
    case 12: return 'y';
    default: if (id >= 20 && id <= 26) return '1' + (id - 20);
  }
  return 0;
}

EMSCRIPTEN_KEEPALIVE void alpine_key(int id, int pressed) {
  unsigned char k = map_key(id);
  int next = (qw + 1) % QSIZE;
  if (!k || next == qr) return;
  queue[qw] = (pressed ? 0x100 : 0) | k;
  qw = next;
}

EM_JS(void, js_draw, (unsigned ptr, int n), {
  if (Module.alpineDraw) Module.alpineDraw(HEAPU32.subarray(ptr >> 2, (ptr >> 2) + n));
});

void DG_Init(void) {}
void DG_DrawFrame(void) { js_draw((unsigned)(uintptr_t)DG_ScreenBuffer, DOOMGENERIC_RESX * DOOMGENERIC_RESY); }
void DG_SleepMs(uint32_t ms) { (void)ms; }
uint32_t DG_GetTicksMs(void) { return (uint32_t)emscripten_get_now(); }
void DG_SetWindowTitle(const char *t) { (void)t; }

int DG_GetKey(int *pressed, unsigned char *key) {
  if (qr == qw) return 0;
  unsigned short e = queue[qr];
  qr = (qr + 1) % QSIZE;
  *pressed = e >> 8;
  *key = e & 0xff;
  return 1;
}

EM_JS(void, js_mount, (void), {
  FS.mkdir('/saves');
  FS.mount(IDBFS, {}, '/saves');
  Module.alpineFS = {
    sync: function(populate, cb) { FS.syncfs(populate, cb || function() {}); },
    write: function(path, data) { FS.writeFile(path, data); },
    chdir: function(path) { FS.chdir(path); }
  };
});
EMSCRIPTEN_KEEPALIVE void alpine_mount(void) { js_mount(); }

static void frame(void) { doomgeneric_Tick(); }

EMSCRIPTEN_KEEPALIVE void alpine_start(const char *iwad) {
  static char *argv[] = { "doom", "-iwad", NULL };
  argv[2] = strdup(iwad);
  doomgeneric_Create(3, argv);
  emscripten_set_main_loop(frame, 0, 0);
}

int main(void) { return 0; }
