/*
 * doomgeneric_ios.c
 *
 * iOS platform implementation for doomgeneric.
 * Implements the 6 required platform functions:
 *   DG_Init, DG_DrawFrame, DG_SleepMs, DG_GetTicksMs, DG_GetKey, DG_SetWindowTitle
 *
 * Also provides dg_ios_push_key() and dg_ios_get_framebuffer() for the Swift layer.
 */

#include "doomgeneric.h"
#include "doomgeneric_ios.h"

#include <time.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdatomic.h>

/* ─── Framebuffer ──────────────────────────────────────────────────────────── */

/*
 * Local copy of the doomgeneric framebuffer (320×200, each pixel is RGBA 8888).
 * DG_DrawFrame() memcpy's DG_ScreenBuffer here and then publishes the pointer
 * atomically so the Metal renderer can read it on the main thread.
 */
static uint32_t s_framebuffer[DOOMGENERIC_RESX * DOOMGENERIC_RESY];
static _Atomic(uint32_t *) s_readyBuffer = (uint32_t *)0; /* NULL without cast warnings */

/* ─── Key Queue ────────────────────────────────────────────────────────────── */

#define KEY_QUEUE_SIZE 32

typedef struct {
    int           pressed;
    unsigned char key;
} KeyEvent;

static KeyEvent   s_keyQueue[KEY_QUEUE_SIZE];
static atomic_int s_keyHead = 0;
static atomic_int s_keyTail = 0;

/* ─── Timing ───────────────────────────────────────────────────────────────── */

static uint64_t s_startMs = 0;

static uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
}

/* ═══════════════════════════════════════════════════════════════════════════ */
/* doomgeneric platform interface                                              */
/* ═══════════════════════════════════════════════════════════════════════════ */

void DG_Init(void) {
    s_startMs = now_ms();
    atomic_store(&s_readyBuffer, (uint32_t *)0);
    atomic_store(&s_keyHead, 0);
    atomic_store(&s_keyTail, 0);
}

void DG_DrawFrame(void) {
    /* Copy the engine's framebuffer and publish it atomically */
    memcpy(s_framebuffer, DG_ScreenBuffer,
           DOOMGENERIC_RESX * DOOMGENERIC_RESY * sizeof(uint32_t));
    atomic_store(&s_readyBuffer, s_framebuffer);
}

void DG_SleepMs(uint32_t ms) {
    usleep((useconds_t)ms * 1000u);
}

uint32_t DG_GetTicksMs(void) {
    return (uint32_t)(now_ms() - s_startMs);
}

int DG_GetKey(int *pressed, unsigned char *doomKey) {
    int head = atomic_load(&s_keyHead);
    int tail = atomic_load(&s_keyTail);
    if (head == tail) {
        return 0; /* queue empty */
    }
    *pressed = s_keyQueue[head].pressed;
    *doomKey  = s_keyQueue[head].key;
    atomic_store(&s_keyHead, (head + 1) % KEY_QUEUE_SIZE);
    return 1;
}

void DG_SetWindowTitle(const char *title) {
    (void)title; /* No window title on iOS */
}

/* ═══════════════════════════════════════════════════════════════════════════ */
/* iOS-specific helpers (called from Swift)                                   */
/* ═══════════════════════════════════════════════════════════════════════════ */

void dg_ios_push_key(int pressed, unsigned char doomKey) {
    int tail = atomic_load(&s_keyTail);
    int next = (tail + 1) % KEY_QUEUE_SIZE;
    if (next != atomic_load(&s_keyHead)) {
        s_keyQueue[tail].pressed = pressed;
        s_keyQueue[tail].key     = doomKey;
        atomic_store(&s_keyTail, next);
    }
    /* If queue is full, the event is silently dropped */
}

uint32_t *dg_ios_get_framebuffer(void) {
    return atomic_load(&s_readyBuffer);
}
