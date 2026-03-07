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
 */
void dg_ios_push_key(int pressed, unsigned char doomKey);

/**
 * Returns a pointer to the latest rendered 320x200 RGBA framebuffer,
 * or NULL if no frame has been rendered yet.
 * The pointer is valid until the next call to DG_DrawFrame().
 */
uint32_t *dg_ios_get_framebuffer(void);

#ifdef __cplusplus
}
#endif
