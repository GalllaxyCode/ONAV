# Hollow Signal: gameplay and simulation notes

This is an internal development reference. It describes actual implemented behavior and contains secret-trigger details. It is not copied into the application bundle.

## Playing the shift

One shift lasts 480 seconds of active simulation: midnight to 6:00 AM, with an in-game hour every 80 real seconds. Menus, pause, reading evidence, and the service-code prompt freeze the clock, enemy logic, resources, and cooldowns. The application also pauses when its window loses focus. Death permits a quick restart after its initial 0.65-second visual beat. Clearing a shift unlocks Overtime.

Controls use the same `GameAction` entry point whether triggered by a key or an equipment button:

- Space or M: raise/lower the monitor.
- 1–7: select the seven public feeds in map order. Their printed camera numbers intentionally skip 04; key 4 selects CAM 05. Key 8 selects the restored hidden feed.
- A / D: toggle west / east shutters.
- F: toggle doorway inspection lamps.
- V: start or stop the air-handler purge.
- R: transmit a lure through the selected camera's speaker.
- X: reset the camera relay.
- E: inspect the desk or the selected live camera. Repeated inspections reopen recovered evidence.
- C: enter a service code. Return submits, Escape cancels.
- Escape: pause/resume or return from an overlay.
- F11 or Control-Command-F: macOS fullscreen.

The moving view is an office look offset controlled by pointer position and the sensitivity setting. It preserves the native cursor. Camera feeds use a reduced rendering cadence and acquisition interference; input and simulation continue independently.

## Physical routes and counterplay

The public floor connects Intake to Gallery and Resonance Archive. Gallery connects to Fabrication, then West Passage. Resonance connects to East Passage and the hidden Return Chamber. The overhead air-handler route is separate from acoustic relay routing.

**Surveyor:** dormant in the Gallery for the first 28 seconds of Standard, then moves Gallery → Fabrication → West Passage. A live, acquired camera showing its current room freezes its travel or approach. Static, a dead feed, and a switching camera do not count as observation. On reaching the west passage, it gives a distinct left-panned cue and a 12-second approach window. Hold the west shutter for three seconds to repel it. A retreat cue tells the player the shutter can be released. It retreats through Fabrication, waits 9–13 seconds, then returns to the Gallery.

**Chorus:** activates in Intake at 108 seconds in Standard. It travels Intake → Resonance → East Passage; looking at it does not stop it. A live-camera relay pulse draws it into an adjacent room with an installed speaker. It takes 1.1 seconds to follow the lure, then waits nine additional seconds before resuming its route. A pulse cannot teleport it across the floor or into the control room. Passages and the air-handler have no usable lure speaker. At the east passage, use the right shutter for three seconds or lure it back to Resonance. Purging advances its travel 1.75 times as quickly because it follows the fan noise.

**Seam:** activates in the air-handler at 84 seconds in Standard. Its pressure builds with elapsed hours and retained heat, independently of the two floor routes. The pressure meter, fabric-dragging cue, and bowed grille provide increasing warnings. A purge removes 10.5 percentage points of pressure per second. At maximum pressure there is a final nine-second attack window; shutters offer no protection. A purge can run for eight seconds before a ten-second thermal lockout, or be stopped manually with a six-second lockout. A two-second purge at roughly 70% is a viable conservative policy. A genuine drop below 90% rearms the final attack grace; tapping the purge for a single simulation tick cannot repeatedly postpone an imminent attack.

Overtime activates the three threats earlier, shortens floor travel intervals, reduces passage approach windows to ten seconds, and increases pressure growth. It preserves the same rules and routes.

## Resource economy and hourly changes

Power begins at 100. Continuous per-second draw is 0.075 idle, plus 0.20 per closed shutter, 0.035 for the monitor, 0.065 for the lamps, and 0.10 while purging. Each lure additionally costs one unit and has a 16-second cooldown. A relay reset costs 1.5 units, restores 52 signal points up to 100, interrupts all pictures for 3.5 seconds, and has a 16-second cooldown. Resetting does not disable local shutters.

Signal loses 0.054 points per second while watching and 0.65 per camera switch. Lowering the monitor restores 0.22 points per second. Below eight points, pictures fail until recovery or reset. Brief intermittent outages begin after 2:00 AM. Heat grows with electrical use and falls during purging. After 4:00, shutter coils produce more heat.

At 1:00, the acoustic threat and ventilation guidance enter the shift. At 2:00, the camera bus loses an initial 14 signal points and begins intermittent failures. At 3:00, the archive advertises its unusual 03:17 replay. At 4:00, the return line becomes usable and shutter heat worsens. At 5:00, the Chorus also reacts to shutter motors: toggles advance its travel when it is still on its route. Floor movement becomes quicker across the night, while these system changes alter the combinations the player manages.

At zero power the monitor, lamps, purge, and shutters lose power. The independent clock continues, so a blackout moments before dawn can still be survived. Existing approaches receive at least ten seconds of grace at power loss; there is no automatic instantaneous blackout death. Keeping defenses permanently active cannot sustain a night.

## Evidence and alternate transmission

Eight evidence identifiers are persisted: `desk`, `gallery`, `maintenance`, `incident`, `return`, `testimony`, `blackout`, and `ending`. Evidence discovery emits an event, while a set prevents duplicate saved records. Inspecting a previously recovered record emits a repeat event so the UI can reopen it without changing progression.

The missing camera and withheld-call clues combine into service key `0417`. Accepting it restores CAM 04 and saves the `return` record, so the hidden camera remains available after relaunch. At Resonance, inspection from 3:13 through 3:21 produces the time-aligned testimony instead of the usual incident record. Repeatedly alternating Gallery and Resonance also reveals a harmless missing-frame anomaly.

After 4:00, send a live-camera lure through the Return Chamber with at least ten power units available before the one-unit pulse. This arms the clean transmission. Survive to dawn with the electrical circuit still powered to reach the alternate ending and recover the final receipt. Dropping below five units reveals the residual low-voltage evidence; this is a different discovery from the powered alternate transmission. Normal victory, death, and restart preserve recovered records but reset a shift's transmission state. Full narrative interpretation is in `LORE_PRIVATE.md`.

## Simulation architecture

`Sources/GameCore.swift` imports Foundation only. `GameModel` owns the current phase, enemy states, camera network, resource integration, environmental schedule, and lore predicates. Its public surface is initialization, `start(difficulty:)`, `act(_:)`, `update(dt:)`, `drainEvents()`, `returnToMenu()`, and a read-only snapshot.

Simulation runs at a fixed 30 Hz. It retains fractional frame time and integrates only while playing. A SplitMix64 generator controls travel intervals and environmental variation with explicit overflow arithmetic, making a given seed reproducible on either Mac CPU. Restart derives another seed to vary the next attempt. Invalid frame deltas are ignored. No AI uses asynchronous timers, rendering callbacks, or audio completion as its authority.

`AppMain.swift` maps native input to actions, consumes sound/evidence/hour events, persists progress, and selects HUD overlays. SceneKit and AVFoundation read snapshots; they cannot independently advance a hostile entity. Acquisition delay and lure cooldown are deliberate gameplay constraints, including in UI smoke tests. Test drivers must let simulation time pass between selecting a new camera and transmitting a pulse.

Development hooks exist only under `#if DEBUG`: `debugSetTime`, `debugSetResources`, `debugPlace`, `debugAttack`, `debugInvincible`, and `debugTimeScale`. Release builds exclude these hooks and `QARunner`. The debug application also supports Control-T time advancement, which preserves ordinary threats and may kill an undefended player.

## Reproducible checks

From the repository root:

```sh
sh Tests/run-core-tests.sh
sh Scripts/test-audio-save.sh
bash Scripts/build.sh debug
"build/Hollow Signal.app/Contents/MacOS/HollowSignal" --ui-smoke
bash Scripts/build.sh release
```

The core runner builds its own debug executable and needs no window, audio device, package download, or test framework. UI smoke output is written to `build/qa`, and that run uses a separate temporary save directory. The release build produces a universal arm64/x86_64 macOS application and does not copy these development notes or the private lore document into the bundle.

Core verification on 13 September 2026 passed **289 checks**:

- Lifecycle, pause freezing, restart reset, and menu inactivity.
- Camera acquisition, signal loss/recovery, locked camera routing, and frame anomaly.
- Physical enemy movement, observation effects, every lethal attack, each correct defense, wrong-shutter failure, adjacent-only lures, and fan-noise acceleration.
- Pressure growth, purge reduction, thermal lockout, resource draw, blackout release, and dawn during blackout. Regression checks prevent tiny purge taps from indefinitely resetting attack grace and prevent shutter-noise reactions from postponing an already-imminent Chorus move.
- Every evidence path, repeat inspection, timed testimony, service code, alternate victory, transmission failure on power loss, and restored discovery state.
- Seed and fixed-step agreement across 60 FPS and five FPS update delivery; rejection of nonfinite and negative deltas.
- **64/64 complete reactive-policy wins** across Standard and Overtime, with 780 shutter approaches repelled and 35.5–38.1% power remaining. This controller reacts after two seconds, patrols every seven seconds, and uses the visible pressure meter; it does not read hidden timers or enable invincibility.
- **40/40 complete imperfect-policy wins**, across 20 seeds for each difficulty: five-second reactions, every third camera visit missed, two-second purges at 70% pressure after a five-second delay, shutters left closed five extra seconds, and lamps occasionally forgotten. Minimum reserve was 21.2%.
- Twenty unattended Standard runs died first to the Surveyor after 91.7–103.5 seconds. Permanent shutters and lamps also fail to survive. The first two minutes therefore introduce a learnable primary threat before the later combination becomes dangerous.

These simulations validate rules, fairness margins, and available resource strategies. They do not substitute for native visual, audio, fullscreen, Retina, save/relaunch, and complete manual-playthrough checks of the packaged application.
