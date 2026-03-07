#pragma once
/*
 * doomgeneric_ios.h
 *
 * iOS platform interface for doomgeneric.
 * These functions are called from Swift via the ObjC bridging header.
 */
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Push a key event into the Doom key queue.
 * @param pressed  1 = key down, 0 = key up
 * @param doomKey  Key code from doomkeys.h (e.g. KEY_RCTRL = 0x80)
 * Thread-safe: may be called from any thread (designed for UI/main thread).
 */
void dg_ios_push_key(int pressed, unsigned char doomKey);

/**
 * Copy the latest rendered 320×200 BGRA frame into outBuffer if a new frame
 * is available since the last call. outBuffer must be at least
 * DOOMGENERIC_RESX * DOOMGENERIC_RESY * 4 bytes.
 *
 * Returns 1 if a new frame was copied, 0 if the frame has not changed.
 * Thread-safe: designed to be called from the Metal render thread.
 */
int dg_ios_copy_frame_if_new(uint8_t *outBuffer);

/**
 * Pause or resume the Doom game loop.
 * When paused, DG_DrawFrame() stalls the game thread with minimal CPU use.
 * Call with paused=1 when the app enters the background.
 */
void dg_ios_set_paused(int paused);

#ifdef __cplusplus
}
#endif
