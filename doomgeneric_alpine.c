// Capa de plataforma de doomgeneric para Alpine Launcher (Emscripten).
#include <stdint.h>
#include <string.h>
#include <emscripten.h>
#include "doomkeys.h"
#include "doomgeneric.h"
#include "d_event.h"

extern int I_GetTime(void);

// Si doomkeys.h define estas teclas, se usan; si no, valores por defecto de Doom.
#ifdef KEY_FIRE
#define K_FIRE KEY_FIRE
#else
#define K_FIRE KEY_RCTRL
#endif
#ifdef KEY_USE
#define K_USE KEY_USE
#else
#define K_USE ' '
#endif
#ifdef KEY_STRAFE_L
#define K_SL KEY_STRAFE_L
#else
#define K_SL ','
#endif
#ifdef KEY_STRAFE_R
#define K_SR KEY_STRAFE_R
#else
#define K_SR '.'
#endif

#define QSIZE 256
static unsigned short queue[QSIZE];
static int qr = 0, qw = 0;
static int cnt[256];

static void push(int pressed, unsigned char k) {
  int next = (qw + 1) % QSIZE;
  if (next == qr) return;
  queue[qw] = (pressed ? 0x100 : 0) | k;
  qw = next;
}

// Cada tecla lleva un contador: varias fuentes (botón, joystick) pueden compartirla.
static void kpress(unsigned char k, int p) {
  int before = cnt[k], after = before + (p ? 1 : -1);
  if (after < 0) after = 0;
  cnt[k] = after;
  if ((before == 0) != (after == 0)) push(after > 0, k);
}

static unsigned char map_key(int id) {
  switch (id) {
    case 0: return KEY_LEFTARROW;
    case 1: return KEY_RIGHTARROW;
    case 2: return KEY_UPARROW;
    case 3: return KEY_DOWNARROW;
    case 4: return K_FIRE;
    case 5: return K_USE;
    case 6: return KEY_RSHIFT;
    case 7: return K_SL;
    case 8: return K_SR;
    case 9: return KEY_ENTER;
    case 10: return KEY_ESCAPE;
    case 11: return KEY_TAB;
    case 12: return 'y';
    case 13: return 'n';
#ifdef KEY_F6
    case 14: return KEY_F6;
#endif
#ifdef KEY_F9
    case 15: return KEY_F9;
#endif
    default: if (id >= 20 && id <= 26) return '1' + (id - 20);
  }
  return 0;
}

EMSCRIPTEN_KEEPALIVE void alpine_key(int id, int pressed) {
  unsigned char k = map_key(id);
  if (k) kpress(k, pressed);
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
static void pwm_axis(float v, float *acc, int *state, unsigned char kneg, unsigned char kpos) {
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

/* ---- Salida de vídeo y plataforma ---- */
EM_JS(void, js_draw, (unsigned ptr, int n), {
  if (Module.alpineDraw) Module.alpineDraw(HEAPU32.subarray(ptr >> 2, (ptr >> 2) + n));
});

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

static int last_tic = -1;

// Se avanza solo cuando toca un tic nuevo: así el motor no se queda esperando en bucle.
static void frame(void) {
  int t = I_GetTime();
  if (t == last_tic) return;
  last_tic = t;

  pwm_axis(mx, &acc_x, &st_x, K_SL, K_SR);
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
  doomgeneric_Tick();
}

EMSCRIPTEN_KEEPALIVE void alpine_start(const char *iwad) {
  static char *argv[] = { "doom", "-iwad", NULL };
  argv[2] = strdup(iwad);
  doomgeneric_Create(3, argv);
  emscripten_set_main_loop(frame, 0, 0);
}

int main(void) { return 0; }
