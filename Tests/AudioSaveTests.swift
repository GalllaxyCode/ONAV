import Foundation
@main
struct AudioSaveTests {
    static func main() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MorrowSmoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SaveStore(directory: dir)
        precondition(store.load().settings.masterVolume == 0.75)
        var save = SaveData()
        save.completedNights = 3
        save.discovered = ["desk", "testimony"]
        save.settings.masterVolume = 0.34
        store.save(save)
        precondition(store.lastError == nil)
        let read = SaveStore(directory: dir).load()
        precondition(read.completedNights == 3 && read.discovered == save.discovered)
        precondition(abs(read.settings.masterVolume - 0.34) < 0.001)
        save.settings.brightness = .nan
        save.settings.graphicsQuality = 99
        store.save(save)
        precondition(store.load().settings.brightness == 1)
        precondition(store.load().settings.graphicsQuality == 2)
        save.settings.sensitivity = 0
        save.settings.brightness = 0.6
        store.save(save)
        precondition(store.load().settings.sensitivity == 0)
        precondition(store.load().settings.brightness == 0.6)
        save.settings.sensitivity = 2
        save.settings.brightness = 3
        store.save(save)
        precondition(store.load().settings.sensitivity == 1)
        precondition(store.load().settings.brightness == 1.6)
        try Data("{invalid".utf8).write(to: dir.appendingPathComponent("progress.json"))
        precondition(store.load().completedNights == 3)
        let recoveredFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        precondition(recoveredFiles.contains { $0.contains("corrupt-") })
        try Data("{\"completedNights\":2,\"settings\":{\"masterVolume\":0.5}}".utf8).write(to: dir.appendingPathComponent("progress.json"))
        let old = store.load()
        precondition(old.completedNights == 2 && old.settings.masterVolume == 0.5 && old.settings.subtitles)
        precondition(Set(LoreCatalog.entries.map(\.id)).count == 8)
        precondition(LoreCatalog.entries.allSatisfy { !$0.title.isEmpty && !$0.text.isEmpty })
        print("PASS save defaults, atomic roundtrip, nonfinite clamping, corrupted backup recovery, old field migration, lore IDs")
        if CommandLine.arguments.contains("--skip-audio") {
            print("Audio playback explicitly skipped.")
            return
        }
        let audio = AudioSystem()
        let begin = Date()
        audio.start()
        print("Audio started: \(audio.available); startup \(Date().timeIntervalSince(begin))s; error \(audio.lastError ?? "none")")
        precondition(audio.available)
        #if DEBUG
        let library = audio.debugLibraryDiagnostics()
        precondition(library.bufferCount >= 30 && library.frames > 1_000_000)
        precondition(library.loopVoices == 5 && library.effectVoices == 16)
        precondition(library.nonFiniteSamples == 0 && library.peak > 0.1 && library.peak <= 0.801)
        precondition(library.bytes < 32 * 1024 * 1024)
        print(String(format: "Audio library: %d original buffers, %.2f MiB, peak %.4f, %d nonfinite samples", library.bufferCount, Double(library.bytes) / 1_048_576, library.peak, library.nonFiniteSamples))
        audio.beginDebugOutputProbe()
        #endif
        var snapshot = GameSnapshot()
        snapshot.phase = .playing
        audio.update(snapshot)
        let sounds = ["camera","monitor","shutter","light","vent","lure","reset","surveyor_step","chorus_step","seam_move","anomaly"]
        for (i, key) in sounds.enumerated() {
            audio.handle([.sound(key, Double(i % 3) - 1)])
            RunLoop.current.run(until: Date().addingTimeInterval(0.16))
        }
        snapshot.ventOn = true
        snapshot.monitor = true
        audio.update(snapshot)
        audio.handle([.attack(.seam)])
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        snapshot.phase = .paused
        audio.update(snapshot)
        audio.apply(settings: GameSettings())
        #if DEBUG
        let output = audio.finishDebugOutputProbe()
        precondition(output.samples > 44_100 && output.rms > 0.0001)
        precondition(output.peak < 1 && output.nonFiniteSamples == 0)
        print(String(format: "Real mixer output: %d samples, RMS %.5f, peak %.5f, no clipping or nonfinite samples", output.samples, output.rms, output.peak))
        #endif
        audio.stop()
        precondition(!audio.available)
        audio.start()
        precondition(audio.available)
        audio.stop()
        print("PASS audio graph, cue playback, pan, pause, settings, stop, restart")
    }
}
