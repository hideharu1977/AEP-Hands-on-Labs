# Doom for iOS

A fully open-source iOS port of Doom built on:

| Component | Source |
|-----------|--------|
| **Engine** | [doomgeneric](https://github.com/ozkl/doomgeneric) — portable C Doom engine |
| **Game content** | [Freedoom Phase 1](https://freedoom.github.io/) — free, BSD-licensed WAD |
| **Renderer** | Metal (MTKView + 320×200 texture upload) |
| **Input** | Virtual touch gamepad (D-pad + action buttons) |
| **Language** | Swift 5 + C (Objective-C bridging header) |

---

## Prerequisites

- macOS 13+ with **Xcode 15** or later
- `git`, `curl`, `unzip` (all pre-installed on macOS)
- An iOS device or simulator (iPhone/iPad, iOS 15+)

---

## Quick Start

```bash
# 1. From the ios-doom directory, run setup to fetch engine sources + WAD
cd ios-doom
./setup.sh

# 2. Open the Xcode project
open DoomIOS/DoomIOS.xcodeproj

# 3. Select a simulator or device target and press ▶ Run
```

That's it. The first build compiles all doomgeneric C sources into a static library
automatically via a build script phase.

---

## How It Works

### Architecture

```
┌──────────────────────────────────────────────────────┐
│  iOS App (Swift)                                     │
│  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │ GameViewController│  │   TouchControlsView      │  │
│  │  • Starts Doom   │  │  • D-pad (move/turn)     │  │
│  │    on bg thread  │  │  • A = Fire, B = Use     │  │
│  └────────┬─────────┘  │  • Y = Run, ⏸ = Escape  │  │
│           │             └──────────┬───────────────┘  │
│  ┌────────▼──────────┐            │ dg_ios_push_key() │
│  │  DoomRenderer     │            │                   │
│  │  • MTKView        │◄───────────┘                   │
│  │  • 320×200 tex    │                                 │
│  │  • fullscreen quad│                                 │
│  └────────▲──────────┘                                │
└───────────┼──────────────────────────────────────────┘
            │ dg_ios_get_framebuffer()
┌───────────┼──────────────────────────────────────────┐
│  doomgeneric_ios.c  (C platform layer)               │
│  • DG_Init / DG_DrawFrame / DG_SleepMs               │
│  • DG_GetTicksMs / DG_GetKey / DG_SetWindowTitle     │
└───────────┼──────────────────────────────────────────┘
            │
┌───────────▼──────────────────────────────────────────┐
│  doomgeneric (C engine)                              │
│  • Full Doom engine (GPL v2)                         │
│  • WAD loading, game logic, rendering pipeline       │
└──────────────────────────────────────────────────────┘
```

### Threading Model

- **Main thread**: Metal rendering via `MTKView` at 35 fps
- **Background thread** (`DispatchQueue.global(.userInteractive)`): Doom game loop
- **Shared state**: Framebuffer pointer exchanged atomically via `_Atomic(uint32_t *)`
- **Key queue**: Lock-free circular buffer with atomic head/tail indices

### Rendering Pipeline

1. Doom renders a 320×200 RGBA framebuffer into `DG_ScreenBuffer`
2. `DG_DrawFrame()` copies it and atomically publishes the pointer
3. `DoomRenderer.draw(in:)` reads it and uploads to a `MTLTexture` (`bgra8Unorm`)
4. A fullscreen quad with nearest-neighbour sampling displays it at native resolution

---

## Controls

| Button | Action |
|--------|--------|
| ▲ (D-pad up) | Move forward |
| ▼ (D-pad down) | Move backward |
| ◀ (D-pad left) | Turn left |
| ▶ (D-pad right) | Turn right |
| **A** | Fire weapon |
| **B** | Use / Open door |
| **Y** | Run (hold) |
| **⏸** | Pause / Escape / Menu |

---

## File Structure

```
ios-doom/
├── setup.sh                         ← Run this first
├── README.md
├── .gitignore
└── DoomIOS/
    ├── DoomIOS.xcodeproj/
    │   └── project.pbxproj
    └── DoomIOS/
        ├── AppDelegate.swift
        ├── SceneDelegate.swift
        ├── GameViewController.swift  ← Game lifecycle + threading
        ├── DoomRenderer.swift        ← Metal rendering
        ├── TouchControlsView.swift   ← Virtual gamepad
        ├── DoomBridge.h              ← ObjC bridging header
        ├── doomgeneric_ios.h         ← iOS platform API
        ├── doomgeneric_ios.c         ← 6 doomgeneric platform functions
        ├── Shaders/
        │   └── DoomShaders.metal     ← Vertex + fragment shaders
        ├── Assets.xcassets/
        ├── Info.plist
        ├── doomgeneric/              ← Added by setup.sh (git-ignored)
        └── freedoom1.wad             ← Added by setup.sh (git-ignored)
```

---

## Licenses

| Component | License |
|-----------|---------|
| Doom engine (via doomgeneric) | [GPL v2](https://github.com/ozkl/doomgeneric/blob/master/LICENSE) |
| Freedoom game content | [BSD 3-Clause](https://github.com/freedoom/freedoom/blob/master/COPYING.adoc) |
| iOS platform layer (this repo) | MIT |

This project does **not** include any original id Software assets. Freedoom provides
a complete free content replacement that is fully compatible with the Doom engine.

---

## Troubleshooting

**"Missing Game Data" alert on launch**
→ Run `./setup.sh` first, then rebuild the project so `freedoom1.wad` is bundled.

**Build error: "doomgeneric sources not found"**
→ Run `./setup.sh` to clone the engine sources into `DoomIOS/DoomIOS/doomgeneric/`.

**Implicit declaration warnings from doomgeneric**
→ Normal — the original Doom C code predates C99 prototypes. Warnings are suppressed
  via `-Wno-implicit-function-declaration` in the build settings.

**Simulator runs slowly**
→ Metal simulation is CPU-bound. Use a physical device for smooth 35 fps gameplay.
