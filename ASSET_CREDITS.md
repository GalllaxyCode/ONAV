# Asset credits and dependencies

Hollow Signal's setting, characters, evidence, text, procedural sounds, and procedural visual construction are original to this project. No Five Nights at Freddy's character models, textures, branding, sound recordings, or other assets are included. Surveillance-survival mechanics are the inspiration; the Morrow Listening Institute and its story are original.

## Audio

`Sources/AudioSystem.swift` synthesizes the complete sound library into in-memory PCM buffers at startup. There are no downloaded samples, spoken recordings, commercial sound-library files, or third-party music tracks.

The synthesis includes electrical hum, fluorescent buzz, ventilation, low structural vibration, security-feed hiss, relays, shutters, metal knocks, creaks, noise-based breath textures, separate acoustic signatures for the three entities, failure sequences, and original tonal morning cues. Voice-like sounds are mixtures of tones and filtered noise and are not recordings of people. All sound is played through AVAudioEngine. The application does not request microphone access.

## Visuals and interface

The scene is constructed from original procedural geometry and materials in the source. Industrial labels and evidence use original text. Interface text uses fonts supplied by macOS; no font software is redistributed. Consult any additional asset-specific note added here if a future version introduces imported artwork.

## Runtime frameworks

- Apple AppKit, SceneKit, AVFoundation, Foundation, CoreGraphics, and related system frameworks are provided by macOS and are not copied into this repository as third-party libraries.
- Swift runtime support is supplied by the supported macOS versions and Apple's toolchain.
- The project requires no third-party package manager or runtime engine installation to play.

## License scope

This document records asset provenance; it does not grant a license to Apple's frameworks or trademarks. Original project code and generated material remain available under the repository owner's chosen distribution terms. No external asset attribution obligations were introduced by the procedural audio and evidence system.
