/*
 * DoomBridge.h — Objective-C Bridging Header
 *
 * Exposes C functions from the doomgeneric engine and our iOS platform layer
 * to Swift code. Xcode uses this file as the "Objective-C Bridging Header"
 * build setting (SWIFT_OBJC_BRIDGING_HEADER).
 */

#import <Foundation/Foundation.h>

// Our iOS platform helpers
#import "doomgeneric_ios.h"

// doomgeneric entry points
// (declared here so Swift can call them without C interop gymnastics)
extern void doomgeneric_Create(int argc, char **argv);
extern void doomgeneric_Tick(void);
