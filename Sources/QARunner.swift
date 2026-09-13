#if DEBUG
import AppKit
import SceneKit

/// Scripted integration checks use the same controller actions as the actual controls.
/// This entire file is eliminated from release builds.
final class QARunner {
    weak var controller: GameController?
    private var time = 0.0
    private var step = 0
    private var results: [[String: Any]] = []
    private let directory: URL
    init(controller: GameController) {
        self.controller = controller
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/qa")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func tick(dt: Double) {
        guard let c = controller else { return }
        time += dt
        guard time >= 1.6 else { return }
        time = 0
        switch step {
        case 0: capture("01-menu"); record("startup", c.hud.screen == .menu); c.handle("start")
        case 1: capture("02-handover"); c.handle("begin"); record("start", c.model.snapshot.phase == .playing)
        case 2: capture("03-office"); c.handle("monitor"); c.handle("camera:1"); record("camera selection", c.model.snapshot.monitor && c.model.snapshot.selectedCamera == .gallery)
        case 3: capture("04-gallery"); c.handle("left"); c.handle("right"); c.handle("light"); c.handle("vent"); record("all defenses", c.model.snapshot.leftClosed && c.model.snapshot.rightClosed && c.model.snapshot.lightOn && c.model.snapshot.ventOn)
        case 4:
            capture("05-defenses"); c.handle("left"); c.handle("right"); c.handle("light"); c.handle("vent")
            c.handle("camera:0"); c.model.update(dt: 0.5); c.handle("lure"); record("relay pulse", c.model.snapshot.lureCooldown > 0)
            c.model.debugSetResources(signal: 1); c.model.update(dt: 0.2); c.handle("reset"); record("network reset", c.model.snapshot.signal > 50)
            c.handle("pause"); record("pause", c.model.snapshot.phase == .paused)
        case 5: capture("06-pause"); c.handle("settings"); c.handle("slider:master:0.37"); c.handle("flashes"); record("settings saved", abs(c.store.load().settings.masterVolume - 0.37) < 0.001)
        case 6:
            capture("07-settings"); c.handle("settingsBack"); c.handle("resume"); record("resume", c.model.snapshot.phase == .playing)
            if c.model.snapshot.monitor { c.handle("monitor") }; c.handle("inspect")
            record("document inspection pauses", c.hud.screen == .evidence && c.model.snapshot.phase == .paused)
        case 7:
            capture("08-document"); c.handle("closeEvidence"); c.handle("code"); c.hud.code = "0417"; c.handle("submitCode")
            record("missing camera unlocked", c.model.snapshot.hiddenCameraUnlocked)
            c.handle("monitor"); c.handle("camera:7")
        case 8:
            capture("09-return"); c.model.debugSetTime(330); c.model.debugSetResources(power: 80)
            for _ in 0..<170 { c.model.update(dt: 0.1) }
            c.model.act(.lure); record("secret route armed", c.model.snapshot.secretArmed)
            c.model.debugSetTime(479.8); c.model.update(dt: 0.3)
        case 9: capture("10-victory"); record("6 AM victory", c.model.snapshot.phase == .victory && c.saved.completedNights > 0); c.handle("restart"); c.model.debugPlace(.surveyor, room: .westPassage, state: .approaching, moveIn: 0, grace: 0.1, threat: 0.99)
        case 10: capture("11-death"); record("attack and death", c.model.snapshot.phase == .dead); c.handle("restart"); record("quick restart", c.model.snapshot.phase == .playing && c.model.snapshot.power > 99)
        case 11: c.model.debugAttack(.chorus)
        case 12: capture("12-chorus-death"); c.handle("restart"); c.model.debugAttack(.seam)
        case 13: capture("13-seam-death"); c.handle("restart"); c.model.debugSetResources(power: 0); record("power exhausted", c.model.snapshot.blackout && !c.model.snapshot.leftClosed && !c.model.snapshot.monitor)
        case 14: capture("14-blackout"); c.handle("pause"); c.window.setContentSize(NSSize(width: 960, height: 650))
        case 15: capture("15-resized"); record("resizing", c.hud.bounds.width >= 900); c.window.toggleFullScreen(nil)
        case 16: capture("16-fullscreen"); record("fullscreen", c.window.styleMask.contains(.fullScreen)); c.window.toggleFullScreen(nil)
        case 17:
            c.handle("menu"); c.handle("archive"); capture("17-archive"); record("evidence saved", c.store.load().discovered.contains("desk")); record("audio engine", c.audio.available)
            c.handle("archiveBack"); c.handle("menu")
            let json: [String: Any] = ["checks": results, "passed": results.allSatisfy { $0["passed"] as? Bool == true }, "backingScale": c.window.backingScaleFactor, "audioAvailable": c.audio.available, "saveDirectory": c.store.directory.path]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("integration.json")) }
            print("UI_QA_COMPLETE \(directory.path)")
            c.qa = nil
        default: break
        }
        step += 1
    }
    private func record(_ name: String, _ passed: Bool) {
        results.append(["name": name, "passed": passed]); print("UI_QA \(passed ? "PASS" : "FAIL") \(name)")
    }
    private func capture(_ name: String) {
        guard let c = controller else { return }
        let image = c.view.snapshot()
        guard let overlay = c.hud.bitmapImageRepForCachingDisplay(in: c.hud.bounds) else { return }
        c.hud.cacheDisplay(in: c.hud.bounds, to: overlay)
        let overlayImage = NSImage(size: c.hud.bounds.size)
        overlayImage.addRepresentation(overlay)
        let composite = NSImage(size: c.hud.bounds.size)
        composite.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: composite.size))
        overlayImage.draw(in: CGRect(origin: .zero, size: composite.size))
        composite.unlockFocus()
        if let tiff = composite.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}
#endif
