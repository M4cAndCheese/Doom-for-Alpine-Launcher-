// Entrada táctil analógica y guardados para Crispy Doom en Alpine Launcher (Emscripten).
#include <stdint.h>
#include <string.h>
#include <emscripten.h>
#include "doomkeys.h"
#include "d_event.h"

static int cnt[256];

static void post_key(int pressed, int k) {
  event_t ev;
  memset(&ev, 0, sizeof(ev));
  ev.type = pressed ? ev_keydown : ev_keyup;
  ev.data1 = k;
  ev.data2 = ev.data3 = (k >= 32 && k < 127) ? k : 0;
  D_PostEvent(&ev);
}

// Cada tecla lleva un contador: botón, joystick y cámara pueden compartirla.
static void kpress(int k, int p) {
  if (k < 0 || k > 255) return;
  int before = cnt[k], after = before + (p ? 1 : -1);
  if (after < 0) after = 0;
  cnt[k] = after;
  if ((before == 0) != (after == 0)) post_key(after > 0, k);
}

static int map_key(int id) {
  switch (id) {
    case 0: return KEY_LEFTARROW;
    case 1: return KEY_RIGHTARROW;
    case 2: return KEY_UPARROW;
    case 3: return KEY_DOWNARROW;
    case 4: return KEY_RCTRL;    // disparar
    case 5: return ' ';          // usar
    case 6: return KEY_RSHIFT;   // correr
    case 7: return ',';          // lateral izquierda
    case 8: return '.';          // lateral derecha
    case 9: return KEY_ENTER;
    case 10: return KEY_ESCAPE;
    case 11: return KEY_TAB;
    case 12: return 'y';
    case 13: return 'n';
    case 14: return KEY_F6;   // guardado rápido
    case 15: return KEY_F9;   // carga rápida
    default: if (id >= 20 && id <= 26) return '1' + (id - 20);
  }
  return -1;
}

EMSCRIPTEN_KEEPALIVE void alpine_key(int id, int pressed) {
  int k = map_key(id);
  if (k >= 0) kpress(k, pressed);
}

/* ---- Entrada analógica ---- */
static float mx = 0, my = 0;   // joystick: x = lateral, y = adelante (-1..1)
static float look = 0;         // giro de cámara acumulado
static float acc_x = 0, acc_y = 0;
static int st_x = 0, st_y = 0, auto_run = 0;

EMSCRIPTEN_KEEPALIVE void alpine_move(float x, float y) { mx = x; my = y; }
EMSCRIPTEN_KEEPALIVE void alpine_look(float dx) { look += dx; }

static float absf(float v) { return v < 0 ? -v : v; }

// Velocidad proporcional: la tecla se pulsa en una fracción de los tics (PWM).
static void pwm_axis(float v, float *acc, int *state, int kneg, int kpos) {
  float a = absf(v);
  int want = 0;
  if (a > 0.1f) {
    *acc += a;
    if (*acc >= 1.0f) { *acc -= 1.0f; want = v < 0 ? -1 : 1; }
  } else {
    *acc = 0;
  }
  if (want != *state) {
    if (*state < 0) kpress(kneg, 0);
    if (*state > 0) kpress(kpos, 0);
    if (want < 0) kpress(kneg, 1);
    if (want > 0) kpress(kpos, 1);
    *state = want;
  }
}

// Se llama al inicio de cada tic (parche en I_StartTic).
void alpine_tic_hook(void) {
  pwm_axis(mx, &acc_x, &st_x, ',', '.');
  pwm_axis(my, &acc_y, &st_y, KEY_DOWNARROW, KEY_UPARROW);
  int want_run = (absf(mx) > 0.85f || absf(my) > 0.85f);
  if (want_run != auto_run) { auto_run = want_run; kpress(KEY_RSHIFT, want_run); }

  int dx = (int)look;
  look -= dx;
  if (dx) {
    event_t ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = ev_mouse;
    ev.data2 = dx;
    D_PostEvent(&ev);
  }
}

/* ---- Guardados (IndexedDB) ---- */
EM_JS(void, js_mount, (void), {
  FS.mkdir('/saves');
  FS.mount(IDBFS, {}, '/saves');
  Module.alpineFS = {
    sync: function(populate, cb) { FS.syncfs(populate, cb || function() {}); },
    write: function(path, data) { FS.writeFile(path, data); },
    exists: function(path) { return FS.analyzePath(path).exists; }
  };
});
EMSCRIPTEN_KEEPALIVE void alpine_mount(void) { js_mount(); }
