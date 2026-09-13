# Hollow Signal

A native macOS survival-horror game set inside the closed **Morrow Listening Institute**. Work an eight-minute shift from midnight to six, recover a suppressed recording, and keep three broken acoustic machines out of the control room.

## Play

Open **`build/Hollow Signal.app`** in Finder. No browser, engine installation, internet connection, or downloaded assets are required. The release executable contains Apple Silicon and Intel slices and requires macOS 12 or newer. Apple Silicon is the primary tested platform.

Choose **Begin the Night**, read the handover, then **Take the Chair**. Progress and settings save automatically. An unfinished shift restarts from midnight; evidence survives failed attempts. Completing a shift unlocks Overtime. There are two endings and eight recoverable records.

## Controls

- **Mouse:** buttons, camera map, and subtle view movement. The normal Mac cursor remains visible.
- **Space / M:** raise or lower the surveillance monitor.
- **1–7:** open the corresponding camera. The keyboard numbers are printed on the map; they differ from the building's camera labels because one room is missing.
- **A / D:** west / east shutter.
- **F:** toggle doorway inspection lights.
- **V:** start or stop a ventilation purge. Short cycles preserve power and avoid motor lockout.
- **R:** send a relay pulse through the selected live camera.
- **X:** reset the camera network.
- **E:** inspect the desk or current camera for evidence. Reading pauses the shift.
- **C:** service authorization terminal.
- **Escape:** pause, resume, or return from a panel.
- **Return:** confirm menu selections or quickly restart after death.
- **Control–Command–F / F11:** fullscreen. **Command–Q:** quit.

The handover explains each enemy's distinct rule. Camera observation is useful only when the feed is live. Shutters, lights, cameras and ventilation all draw power; a permanently sealed office will not last until morning. Sound captions are enabled by default. Exposure, volume, graphics quality, view sensitivity, fullscreen and reduced flashes are configurable in **Calibration**.

## Build

Requires Apple's Command Line Tools (or Xcode) and its macOS SDK. There are no package dependencies.

```sh
xcode-select --install       # only if the tools are not already installed
./Scripts/build.sh           # optimized universal release
open "build/Hollow Signal.app"
```

The build uses Swift 5 language mode for compatibility with the macOS 12 APIs, links AppKit, SceneKit, AVFoundation and QuartzCore, then signs the bundle locally. It is ad-hoc signed, not Developer ID notarized. The local build launches directly; distribution to other Macs may require the recipient's normal macOS Open Anyway flow.

To regenerate the original app icon:

```sh
swift Scripts/GenerateIcon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

For development and tests:

```sh
./Tests/run-core-tests.sh
./Scripts/test-audio-save.sh
./Scripts/build.sh debug
"build/Hollow Signal.app/Contents/MacOS/HollowSignal" --ui-smoke
```

The debug UI smoke run uses an isolated temporary save directory, exercises the real controller and renderer, and writes screenshots and `integration.json` to `build/qa`. Debug-only state controls are excluded from the release executable. **Control–T** advances one minute in a debug build; it is intentionally unsafe without understanding the simulation. See `Docs/TESTING.md` for final verification and limitations.

## Architecture

- `Shared.swift`: typed phases, actions, snapshots, settings and progress.
- `GameCore.swift`: deterministic fixed-step simulation, three AI state machines, routes, resources, hour events, counterplay, lore triggers and both endings. Independent of graphics and audio.
- `WorldRenderer.swift`: original modeled industrial spaces, creatures, procedural materials, lights, shadows, animated equipment, particles, fog and SceneKit camera control. One view renders the active location; camera feeds run at 14 FPS.
- `GameHUD.swift`: custom AppKit equipment interface, surveillance map, menus, settings and readable evidence panels, scaled for Retina and different window sizes.
- `AppMain.swift`: native application lifecycle, input routing, pause on loss of focus, simulation/render integration and persistence.
- `AudioSystem.swift`: bounded procedural sound buffers, layered ambience and stereo entity/equipment cues through AVAudioEngine.
- `SaveStore.swift`: versioned JSON, atomic writes, previous-save recovery, corrupt-file quarantine and setting migration.
- `LoreCatalog.swift`: discoverable evidence. The complete story and clue meanings are in **`Docs/LORE_PRIVATE.md`**, which is intentionally excluded from the application bundle.

Local data lives in `~/Library/Application Support/Morrow Listening Institute/`. The game uses neither networking nor a microphone. All required visual and audio assets are generated from the included source; see `ASSET_CREDITS.md`.
