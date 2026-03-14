// doom_ios_shims.h — iOS build compatibility for doomgeneric
//
// Included via -include in the doomgeneric shell-script build phase.
// system() is not available on iOS; it is only used by doomgeneric's
// Linux-only Zenity error-dialog code, which is unreachable on iOS.

#pragma once

#if defined(__APPLE__)
  #include <TargetConditionals.h>
  #if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    static __attribute__((unused)) int _doom_noop_system(const char *cmd) {
        (void)cmd; return 0;
    }
    #define system(x) _doom_noop_system(x)
  #endif
#endif
