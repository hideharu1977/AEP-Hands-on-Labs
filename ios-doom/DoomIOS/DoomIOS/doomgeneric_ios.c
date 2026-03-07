/*
 * doomgeneric_ios.c
 *
 * iOS platform implementation for doomgeneric.
 * Implements the 6 required platform functions:
 *   DG_Init, DG_DrawFrame, DG_SleepMs, DG_GetTicksMs, DG_GetKey, DG_SetWindowTitle
 *
 * Also exposes the helper API declared in doomgeneric_ios.h for Swift.
 */

#include "doomgeneric.h"
#include "doomgeneric_ios.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <stdatomic.h>

/* ─── Key queue (lock-free SPSC) ─────────────────────────────────────────── */
/*
 * The UI/main thread is the sole producer (dg_ios_push_key).
 * The game thread is the sole consumer (DG_GetKey).
 * Each slot packs: upper byte = pressed (1/0), lower byte = doom key code.
 */
#define KEY_QUEUE_SIZE  64      /* must be power of 2 */
#define KEY_QUEUE_MASK  (KEY_QUEUE_SIZE - 1)

static uint16_t         s_keyQueue[KEY_QUEUE_SIZE];
static _Atomic uint32_t s_keyHead = 0;   /* next slot to write (UI thread) */
static _Atomic uint32_t s_keyTail = 0;   /* next slot to read  (game thread) */

void dg_ios_push_key(int pressed, unsigned char doomKey) {
    uint32_t head = atomic_load_explicit(&s_keyHead, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&s_keyTail, memory_order_acquire);
    if ((head - tail) >= KEY_QUEUE_SIZE) return;  /* drop if full */
    s_keyQueue[head & KEY_QUEUE_MASK] =
        (uint16_t)(((uint16_t)(pressed ? 1u : 0u) << 8) | (uint16_t)doomKey);
    atomic_store_explicit(&s_keyHead, head + 1u, memory_order_release);
}

/* ─── Framebuffer double-buffering ────────────────────────────────────────── */
/*
 * doomgeneric pixel layout: 0xAARRGGBB (little-endian uint32, i.e. byte
 * order in memory is B, G, R, A).
 * MTLPixelFormatBGRA8Unorm expects the same byte order: B, G, R, A.
 *
 * So a direct memcpy is correct — no byte-swap is needed.
 *
 * The mutex protects s_renderBuffer. s_frameReady is an atomic fast-path
 * guard so the Metal render thread (running at 60 Hz) avoids locking when
 * Doom (running at ~35 Hz) has not produced a new frame yet.
 */
static uint8_t          s_renderBuffer[DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4];
static pthread_mutex_t  s_frameMutex  = PTHREAD_MUTEX_INITIALIZER;
static _Atomic int      s_frameReady  = 0;

int dg_ios_copy_frame_if_new(uint8_t *outBuffer) {
    if (!atomic_load_explicit(&s_frameReady, memory_order_acquire))
        return 0;
    pthread_mutex_lock(&s_frameMutex);
    memcpy(outBuffer, s_renderBuffer, DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4);
    atomic_store_explicit(&s_frameReady, 0, memory_order_release);
    pthread_mutex_unlock(&s_frameMutex);
    return 1;
}

/* ─── Pause flag ─────────────────────────────────────────────────────────── */

static _Atomic int s_paused = 0;

void dg_ios_set_paused(int paused) {
    atomic_store(&s_paused, paused);
}

/* ─── Timing ─────────────────────────────────────────────────────────────── */

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
    memset(s_renderBuffer, 0, sizeof(s_renderBuffer));
    atomic_store(&s_keyHead, 0u);
    atomic_store(&s_keyTail, 0u);
    atomic_store(&s_frameReady, 0);
    atomic_store(&s_paused, 0);
    fprintf(stderr, "[DoomIOS] DG_Init: %dx%d\n",
            DOOMGENERIC_RESX, DOOMGENERIC_RESY);
}

void DG_DrawFrame(void) {
    /* Stall the game thread while the app is backgrounded */
    while (atomic_load(&s_paused)) {
        usleep(16000);  /* ~60 Hz polling interval */
    }

    /*
     * doomgeneric stores pixels as uint32 with byte layout B,G,R,A in memory
     * (i.e. 0xAARRGGBB in little-endian). MTLPixelFormatBGRA8Unorm expects
     * the same byte order, so a plain memcpy is correct.
     */
    pthread_mutex_lock(&s_frameMutex);
    memcpy(s_renderBuffer, DG_ScreenBuffer,
           DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4);
    pthread_mutex_unlock(&s_frameMutex);

    atomic_store_explicit(&s_frameReady, 1, memory_order_release);
}

void DG_SleepMs(uint32_t ms) {
    usleep((useconds_t)ms * 1000u);
}

uint32_t DG_GetTicksMs(void) {
    return (uint32_t)(now_ms() - s_startMs);
}

int DG_GetKey(int *pressed, unsigned char *doomKey) {
    uint32_t tail = atomic_load_explicit(&s_keyTail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&s_keyHead, memory_order_acquire);
    if (tail == head) return 0;  /* queue empty */
    uint16_t entry = s_keyQueue[tail & KEY_QUEUE_MASK];
    *pressed = (entry >> 8) & 0xFF;
    *doomKey  =  entry       & 0xFF;
    atomic_store_explicit(&s_keyTail, tail + 1u, memory_order_release);
    return 1;
}

void DG_SetWindowTitle(const char *title) {
    fprintf(stderr, "[DoomIOS] title: %s\n", title ? title : "(null)");
}
