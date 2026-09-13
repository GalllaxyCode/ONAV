import Foundation
import AVFoundation

/// Entirely original synthesis. Buffers are built once, then mixed by AVAudioEngine;
/// no work is performed on a real-time render callback and no microphone is opened.
final class AudioSystem {
    private let engine = AVAudioEngine()
    private let ambienceMixer = AVAudioMixerNode()
    private let effectsMixer = AVAudioMixerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var loops: [AVAudioPlayerNode] = []
    private var voices: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var settings = GameSettings()
    private var voiceCursor = 0
    private var prepared = false
    private var previousPhase: GamePhase = .menu
    private(set) var available = false
    private(set) var lastError: String?
    #if DEBUG
    private var outputProbe: AudioOutputProbe?
    #endif

    init() { }

    func start() {
        guard !engine.isRunning else { return }
        if !prepared { prepare() }
        do {
            try engine.start()
            available = true
            lastError = nil
            for (index, name) in ["room_hum", "air_fan", "screen_hiss", "substructure", "fluorescent"].enumerated() {
                if let buffer = buffers[name] {
                    loops[index].scheduleBuffer(buffer, at: nil, options: .loops)
                    loops[index].play()
                }
            }
            apply(settings: settings)
            update(GameSnapshot())
        } catch {
            available = false
            lastError = "Audio device unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        #if DEBUG
        if outputProbe != nil { _ = finishDebugOutputProbe() }
        #endif
        for node in loops + voices { node.stop() }
        engine.stop()
        available = false
    }

    func apply(settings: GameSettings) {
        self.settings = settings
        engine.mainMixerNode.outputVolume = Float(min(1, max(0, settings.masterVolume)))
        ambienceMixer.outputVolume = Float(min(1, max(0, settings.ambienceVolume)))
        effectsMixer.outputVolume = Float(min(1, max(0, settings.effectsVolume)))
    }

    func update(_ snapshot: GameSnapshot) {
        guard available, loops.count == 5 else { return }
        let playing = snapshot.phase == .playing || snapshot.phase == .briefing
        let paused = snapshot.phase == .paused || snapshot.phase == .settings || snapshot.phase == .archive
        let roomGain: Float = paused ? 0.12 : (playing ? 1 : 0.35)
        let isDead = snapshot.phase == .dead
        let blackout = snapshot.blackout || isDead
        loops[0].volume = (blackout ? 0.015 : 0.35 + Float(snapshot.load) * 0.018) * roomGain
        loops[1].volume = (blackout ? 0 : (snapshot.ventOn ? 0.65 : 0.065)) * roomGain
        loops[2].volume = (snapshot.monitor && playing ? (snapshot.signalLost ? 0.24 : 0.045) : 0.006) * roomGain
        loops[3].volume = (blackout ? 0.37 : 0.1 + Float(snapshot.hour) * 0.018) * roomGain
        loops[4].volume = (blackout ? 0 : (snapshot.lightOn ? 0.23 : 0.095)) * roomGain
        // Pausing immediately halts transient movement cues, rather than letting them
        // leak information or imply that the simulation continues behind the menu.
        if snapshot.phase != previousPhase && paused {
            for node in voices { node.stop() }
        }
        previousPhase = snapshot.phase
    }

    func handle(_ events: [GameEvent]) {
        guard available else { return }
        let explicitDiscoveryCue = events.contains {
            if case .sound("discovery", _) = $0 { return true }
            return false
        }
        for event in events {
            switch event {
            case .sound(let name, let pan): play(name, pan: pan)
            case .attack(let kind):
                for node in voices { node.stop() }
                play("attack_\(kind.rawValue)", volume: 0.88)
            case .victory(let alternate):
                for node in voices { node.stop() }
                play(alternate ? "dawn_return" : "dawn", volume: 0.8)
            case .hour(let hour):
                if hour > 0 && hour < 6 { play("hour", volume: 0.48) }
            case .discovered: if !explicitDiscoveryCue { play("discovery", volume: 0.4) }
            case .defense, .message: break
            }
        }
    }

    private func play(_ name: String, pan: Double = 0, volume: Float = 0.7) {
        let aliases: [String: String] = [
            "camera_switch": "camera", "switch": "camera", "monitor_open": "monitor",
            "monitor_close": "monitor", "door": "shutter", "ventilation": "vent",
            "surveyor": "surveyor_step", "chorus": "chorus_step", "seam": "seam_move",
            "static": "camera", "alarm": "failure", "footstep": "surveyor_step",
            "signal_loss": "failure", "signal": "reset", "success": "discovery"
        ]
        let key = aliases[name] ?? name
        guard let buffer = buffers[key] ?? buffers["relay"], !voices.isEmpty else { return }
        let index = voices.firstIndex(where: { !$0.isPlaying }) ?? voiceCursor
        voiceCursor = (index + 1) % voices.count
        let node = voices[index]
        node.stop()
        node.pan = Float(min(1, max(-1, pan)))
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil)
        node.play()
    }

    private func prepare() {
        engine.attach(ambienceMixer)
        engine.attach(effectsMixer)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: nil)
        engine.connect(effectsMixer, to: engine.mainMixerNode, format: nil)
        for pan: Float in [-0.25, 0.25, 0, -0.65, 0.6] {
            let node = AVAudioPlayerNode()
            node.volume = 0
            node.pan = pan
            engine.attach(node)
            engine.connect(node, to: ambienceMixer, format: format)
            loops.append(node)
        }
        // A fixed pool bounds memory and permits overlapping footsteps and equipment.
        for _ in 0..<16 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectsMixer, format: format)
            voices.append(node)
        }
        synthesize()
        engine.prepare()
        prepared = true
    }

    private func synthesize() {
        make("room_hum", seconds: 8, loop: true) { t, _, _ in
            let drift = 0.76 + 0.12 * sin(t * .pi / 2) + 0.08 * sin(t * .pi / 4)
            return drift * (0.14 * tone(50, t) + 0.06 * tone(100, t) + 0.018 * tone(150, t))
        }
        make("air_fan", seconds: 8, loop: true) { t, noise, low in
            let rotor = 0.75 + 0.2 * tone(13.5, t)
            return rotor * (low * 0.32 + noise * 0.024 + tone(81, t) * 0.03)
        }
        make("screen_hiss", seconds: 6, loop: true) { t, noise, _ in
            let roll = pow(max(0, tone(0.5, t)), 22)
            return noise * (0.2 + 0.24 * roll) + tone(812, t) * 0.012
        }
        make("substructure", seconds: 12, loop: true) { t, _, low in
            let breathing = 0.5 + 0.3 * tone(1.0 / 12.0, t)
            return breathing * (tone(38, t) * 0.17 + tone(57.25, t) * 0.07 + low * 0.08)
        }
        make("fluorescent", seconds: 8, loop: true) { t, noise, _ in
            let stutter = 0.3 + 0.7 * pow(abs(tone(1.125, t)), 0.25)
            return (tone(100, t) * 0.075 + tone(400, t) * 0.018 + noise * 0.05) * stutter
        }
        make("camera", seconds: 0.44) { t, noise, _ in
            let acquire = exp(-t * 12)
            let sweep = sin(2 * .pi * (820 * t - 700 * t * t))
            let click = exp(-t * 100) * tone(1450, t)
            return noise * acquire * 0.33 + sweep * acquire * 0.085 + click * 0.2
        }
        make("monitor", seconds: 0.48) { t, noise, low in
            return low * 0.5 * exp(-t * 13) + tone(74, t) * 0.26 * exp(-t * 19)
                + noise * 0.09 * exp(-abs(t - 0.19) * 60)
        }
        make("relay", seconds: 0.22) { t, noise, _ in
            return (tone(930, t) * 0.17 + noise * 0.16) * exp(-t * 75)
                + tone(370, t) * 0.09 * exp(-abs(t - 0.08) * 70)
        }
        make("shutter", seconds: 1.15) { t, noise, low in
            let roll = sin(.pi * min(1, t / 0.85))
            let slam = exp(-abs(t - 0.83) * 24)
            return (low * 0.34 + noise * 0.05 + tone(97, t) * 0.06) * roll
                + (tone(52, t) * 0.3 + tone(113, t) * 0.1 + noise * 0.12) * slam
        }
        make("light", seconds: 0.34) { t, noise, _ in
            let strike = exp(-t * 65) + 0.5 * exp(-abs(t - 0.11) * 65)
            return (noise * 0.22 + tone(300, t) * 0.1) * strike
        }
        make("vent", seconds: 1.5) { t, noise, low in
            let rise = min(1, t * 8) * exp(-t * 2.5)
            return (low * 0.6 + noise * 0.13 + sin(2 * .pi * (48 * t + 18 * t * t)) * 0.06) * rise
        }
        make("lure", seconds: 1.65) { t, noise, _ in
            let first = exp(-pow((t - 0.22) / 0.13, 4))
            let second = exp(-pow((t - 0.62) / 0.17, 4))
            let vowel = exp(-pow((t - 1.12) / 0.25, 2))
            return tone(440, t) * first * 0.18 + tone(349.23, t) * second * 0.15
                + (tone(146, t) + tone(584, t) * 0.34 + tone(1168, t) * 0.12) * vowel * 0.045
                + noise * (first + second + vowel) * 0.015
        }
        make("reset", seconds: 1.15) { t, noise, _ in
            let chatter = pow(max(0, tone(17, t)), 12)
            return noise * chatter * 0.12 * exp(-t * 3)
                + tone(t < 0.65 ? 390 : 585, t) * 0.08 * exp(-pow((t - 0.73) / 0.3, 4))
        }
        make("failure", seconds: 0.85) { t, noise, _ in
            return (tone(188, t) * 0.18 + noise * 0.035) * exp(-t * 5)
                + tone(141, t) * 0.12 * exp(-abs(t - 0.35) * 14)
        }
        make("blackout", seconds: 3.2) { t, noise, low in
            let motor = sin(2 * .pi * (62 * t - 8 * t * t)) * max(0, 1 - t / 3)
            return motor * 0.19 + low * 0.33 * exp(-t * 1.8) + noise * 0.25 * exp(-t * 45)
        }
        make("knock", seconds: 1.35) { t, noise, _ in
            let knocks = exp(-t * 18) + 0.65 * exp(-max(0, t - 0.47) * 20) * (t > 0.47 ? 1 : 0)
            return (tone(84, t) * 0.3 + tone(173, t) * 0.09 + noise * 0.1) * knocks
        }
        make("creak", seconds: 2.7) { t, noise, low in
            let swell = pow(sin(.pi * t / 2.7), 2)
            let bend = sin(2 * .pi * (117 * t + 21 * sin(t * 2)))
            return swell * (bend * 0.05 + low * 0.22 + noise * 0.013) * (0.7 + 0.3 * tone(9, t))
        }
        make("whisper", seconds: 2.8) { t, noise, low in
            let breath = pow(sin(.pi * t / 2.8), 3) * (0.65 + 0.35 * sin(t * 9))
            return breath * (noise * 0.07 + low * 0.19 + tone(413, t) * 0.018)
        }
        make("anomaly", seconds: 1.8) { t, noise, _ in
            let backward = pow(sin(.pi * t / 1.8), 5)
            return backward * (tone(217, t) * 0.09 + tone(224, t) * 0.08 + noise * 0.025)
        }
        make("surveyor_step", seconds: 1.4) { t, noise, low in
            let foot = exp(-t * 13)
            let drag = exp(-pow((t - 0.57) / 0.28, 2))
            return (tone(61, t) * 0.32 + tone(122, t) * 0.08 + noise * 0.07) * foot
                + (low * 0.17 + tone(817, t) * 0.025) * drag
        }
        make("surveyor_near", seconds: 2.2) { t, noise, low in
            let beat = exp(-t * 15) + (t > 0.72 ? exp(-(t - 0.72) * 15) * 0.8 : 0)
            return (tone(59, t) * 0.32 + noise * 0.05) * beat
                + (tone(173, t) * 0.05 + low * 0.16) * exp(-pow((t - 1.4) / 0.45, 2))
        }
        make("chorus_step", seconds: 1.9) { t, noise, low in
            let roll = pow(sin(.pi * t / 1.9), 3)
            let hum = tone(196, t) * 0.05 + tone(247, t) * 0.035 + tone(294, t) * 0.035
            return roll * (hum + low * 0.16 + noise * 0.009) * (0.7 + 0.3 * tone(6, t))
        }
        make("chorus_near", seconds: 2.5) { t, noise, _ in
            let breath = pow(sin(.pi * t / 2.5), 2)
            let phrase = 0.5 + 0.5 * sin(t * 8 + sin(t * 3))
            let throat = tone(123.47, t) * 0.07 + tone(246.94, t) * 0.04 + tone(740.82, t) * 0.02
            return breath * phrase * (throat + noise * 0.04)
        }
        make("seam_move", seconds: 1.8) { t, noise, low in
            let ticks = pow(max(0, sin(t * 59 + sin(t * 17) * 3)), 18)
            return sin(.pi * t / 1.8) * (noise * ticks * 0.2 + low * 0.13 + tone(1270, t) * ticks * 0.035)
        }
        make("seam_near", seconds: 2.3) { t, noise, low in
            let squeeze = pow(sin(.pi * t / 2.3), 2)
            let chatter = pow(max(0, tone(13, t)), 10)
            return squeeze * (noise * 0.14 * chatter + low * 0.22 + tone(690, t) * 0.03 * chatter)
        }
        make("attack_surveyor", seconds: 2.6) { t, noise, low in
            let hit = exp(-t * 3.7)
            let motor = sin(2 * .pi * (94 * t + 57 * t * t))
            return hit * (tone(42, t) * 0.4 + noise * 0.16 + low * 0.25)
                + motor * 0.12 * exp(-t * 1.7) * (0.7 + 0.3 * tone(14, t))
        }
        make("attack_chorus", seconds: 3.0) { t, noise, _ in
            let envelope = min(1, t * 20) * exp(-t * 1.55)
            let throat = tone(147, t) * 0.17 + tone(155.56, t) * 0.12 + tone(622.24, t) * 0.055
            return envelope * (throat + noise * 0.2) * (0.8 + 0.2 * tone(22, t))
        }
        make("attack_seam", seconds: 2.7) { t, noise, low in
            let crush = exp(-t * 2.4)
            let sheet = sin(2 * .pi * (390 * t - 39 * t * t)) * 0.12
            return crush * (sheet + tone(62, t) * 0.27 + low * 0.22 + noise * 0.12 * abs(tone(19, t)))
        }
        make("hour", seconds: 1.9) { t, _, _ in
            let main = (tone(523.25, t) * 0.12 + tone(1047.2, t) * 0.04) * exp(-t * 3)
            let tail = t > 0.45 ? tone(392, t) * 0.09 * exp(-(t - 0.45) * 3) : 0
            return main + tail
        }
        make("discovery", seconds: 0.9) { t, noise, _ in
            return tone(880, t) * 0.05 * exp(-t * 7) + noise * 0.025 * exp(-t * 30)
                + (t > 0.13 ? tone(660, t) * 0.06 * exp(-(t - 0.13) * 8) : 0)
        }
        make("dawn", seconds: 8) { t, _, low in
            let open = min(1, t * 2) * max(0, 1 - t / 8)
            let bell = tone(261.63, t) * 0.13 + tone(392, t) * 0.065 + tone(523.25, t) * 0.045
            let unresolved = tone(277.18, t) * max(0, t - 4) * 0.01
            return open * (bell + low * 0.025 + unresolved)
        }
        make("dawn_return", seconds: 10) { t, _, low in
            let open = min(1, t) * max(0, 1 - t / 10)
            let harmony = tone(261.63, t) * 0.11 + tone(329.63, t) * 0.06 + tone(392, t) * 0.05
            let reply = t > 2 ? tone(523.25, t) * 0.07 * exp(-(t - 2) * 0.4) : 0
            return open * (harmony + reply + low * 0.02)
        }
    }

    private func make(_ name: String, seconds: Double, loop: Bool = false,
                      sample: (Double, Double, Double) -> Double) {
        let count = Int(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let output = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        var rng: UInt64 = 0x4D4F52524F570417
        for byte in name.utf8 { rng = rng &* 6364136223846793005 &+ UInt64(byte) &+ 1 }
        var filtered = 0.0
        for i in 0..<count {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Double(rng & 0xFFFF) / 32767.5 - 1
            filtered = filtered * 0.975 + noise * 0.025
            let t = Double(i) / format.sampleRate
            let fade: Double
            if loop {
                fade = 1
            } else {
                fade = min(1, t / 0.004) * min(1, (seconds - t) / 0.025)
            }
            output[i] = Float(max(-0.8, min(0.8, sample(t, noise, filtered * 6) * fade)))
        }
        if loop {
            // Join long noise loops smoothly without clicks. The short raised-cosine
            // edge is masked by the other independently sized ambience layers.
            let seam = min(256, count / 8)
            for i in 0..<seam {
                let envelope = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(seam)))
                output[i] *= envelope
                output[count - 1 - i] *= envelope
            }
        }
        buffers[name] = buffer
    }

    #if DEBUG
    func debugLibraryDiagnostics() -> AudioLibraryDiagnostics {
        var result = AudioLibraryDiagnostics()
        result.bufferCount = buffers.count
        result.loopVoices = loops.count
        result.effectVoices = voices.count
        for buffer in buffers.values {
            let count = Int(buffer.frameLength)
            result.frames += count
            guard let samples = buffer.floatChannelData?[0] else { continue }
            for index in 0..<count {
                let sample = Double(samples[index])
                if sample.isFinite { result.peak = max(result.peak, abs(sample)) }
                else { result.nonFiniteSamples += 1 }
            }
        }
        return result
    }

    /// A test-only tap reads the already mixed output. It never opens an input device.
    func beginDebugOutputProbe() {
        guard available, outputProbe == nil else { return }
        let probe = AudioOutputProbe()
        outputProbe = probe
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            probe.receive(buffer)
        }
    }

    @discardableResult
    func finishDebugOutputProbe() -> AudioOutputStatistics {
        guard let probe = outputProbe else { return AudioOutputStatistics() }
        engine.mainMixerNode.removeTap(onBus: 0)
        outputProbe = nil
        return probe.statistics()
    }
    #endif
}

#if DEBUG
struct AudioLibraryDiagnostics {
    var bufferCount = 0
    var frames = 0
    var loopVoices = 0
    var effectVoices = 0
    var peak = 0.0
    var nonFiniteSamples = 0
    var bytes: Int { frames * MemoryLayout<Float>.size }
}

struct AudioOutputStatistics {
    var samples = 0
    var sumSquares = 0.0
    var peak = 0.0
    var nonFiniteSamples = 0
    var rms: Double { samples > 0 ? sqrt(sumSquares / Double(samples)) : 0 }
}

private final class AudioOutputProbe {
    private let lock = NSLock()
    private var value = AudioOutputStatistics()

    func receive(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        var next = AudioOutputStatistics()
        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channels[channel]
            for index in 0..<Int(buffer.frameLength) {
                let sample = Double(data[index])
                if sample.isFinite {
                    next.sumSquares += sample * sample
                    next.peak = max(next.peak, abs(sample))
                    next.samples += 1
                } else { next.nonFiniteSamples += 1 }
            }
        }
        lock.lock()
        value.samples += next.samples
        value.sumSquares += next.sumSquares
        value.peak = max(value.peak, next.peak)
        value.nonFiniteSamples += next.nonFiniteSamples
        lock.unlock()
    }

    func statistics() -> AudioOutputStatistics {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
#endif

private func tone(_ frequency: Double, _ time: Double) -> Double {
    sin(2 * Double.pi * frequency * time)
}
