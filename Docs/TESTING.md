# Release verification

Verified locally on an Apple M2 Mac running macOS 27, with a 2× Retina display. The executable is built for arm64 (macOS 12+) and x86_64 (macOS 14+). The Intel slice was also launched under Rosetta, confirmed as `X86-64 (translated)` by a process sample, and exercised through new game, camera selection, rendering, keyboard and mouse defenses, and evidence. Older supported operating-system versions and physical Intel hardware are not available for direct testing here.

## Automated simulation

`Tests/run-core-tests.sh` passes **289 checks**, including **104 complete seeded nights** across Standard and Overtime. Tests cover actual routes, observation, attacks from every entity, correct and incorrect defenses, power depletion, ventilation lockouts, signal acquisition/failure/reset, pause/resume, restart, both victories, all evidence triggers, deterministic timing, and two fixed input-timing exploits.

The conservative policy survives 64/64 nights with 35.5–38.1% reserve. The imperfect policy survives 40/40 with five-second reactions, missed camera visits, extra shutter time, and occasionally forgotten lamps; minimum reserve is 21.2%. No invincibility is used by those balance tests. Idle players and permanently active defenses fail. See `GAMEPLAY.md` for methodology and mechanics.

## Audio and persistence

`Scripts/test-audio-save.sh` passes settings roundtrip and boundaries, missing-save defaults, older-field migration, atomic save recovery, damaged-primary quarantine, evidence IDs, real audio startup/playback, pause, stop, and restart.

The procedural library has 32 buffers occupying 17.30 MiB. Startup measured about 0.30 seconds. A real AVAudioEngine mixer probe observed 220,800 finite, nonzero output samples with no clipping (RMS 0.05009, peak 0.28267 in that run). The five ambient loops and sixteen transient voices are bounded. These audio probes are DEBUG-only.

## Native application integration

The DEBUG `--ui-smoke` run passes all 20 checks through the same controller used by native input:

- Startup, briefing, new shift, camera selection and feed transitions.
- West/east shutters, inspection lights, ventilation, relay pulse and network reset.
- Pause/resume, settings persistence, document discovery and automatic reading pause.
- Service code, restored camera, alternate transmission, 6:00 AM victory and progression save.
- Enemy attack/death, quick restart and zero-power behavior.
- Window resizing, fullscreen, 2× Retina backing, evidence persistence and audio availability.

It additionally renders each creature's failure sequence, low-power office, menus, settings, evidence and victory to screenshots under `build/qa`. The test uses an isolated temporary save directory. Debug controls force the long-duration transition checks; full-duration AI/resource balance is independently tested by the 104 complete simulation runs above.

A SceneKit render callback measured approximately 60 FPS for the office, menus, death, and victory at 1280×800 points on this Mac. Camera feeds intentionally use a 12 FPS render cadence; the simulation and controls run independently. These measurements are short local samples, not a guarantee for every supported Mac. Graphics settings control antialiasing, shadows, bloom and dust.

## Live release checks

The signed `.app` was launched through the native application launcher. Manual keyboard interaction verified new-game entry, camera selection, visible Surveyor, evidence inspection and pause, both shutters, lights, ventilation, a relay pulse, duct view, and pause. The recorded walkthrough is under `build/Walkthrough`.

Visual inspection led to changes for wall visibility, physically scaled wear textures, readable signs, evidence fitting, overlapping HUD labels, subtitle/map separation, a visible dormant Surveyor for onboarding, and stable camera orientation when returning to the office. Dawn introduces warm light and removes active creature poses. The release bundle is verified with `codesign --verify --deep --strict` and contains both CPU architectures.

## Distribution scope

The app is locally ad-hoc signed. It is not Developer ID notarized; distributing a downloaded copy to another Mac may invoke that Mac's normal security review. No third-party runtime, network connection, microphone permission or asset download is required. The source, private lore, tests and development notes are outside the application bundle. The release excludes debug cheats, audio probes and the scripted QA runner.

This is a complete small procedural 3D game. Its original mechanical models and materials are stylized industrial art; it does not contain scanned environments, motion capture, or professionally recorded voice acting.
