import AppKit
import SceneKit
import QuartzCore

final class GameController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let view: SCNView
    let hud = GameHUD()
    let world = WorldRenderer()
    let audio = AudioSystem()
    let store: SaveStore
    let model: GameModel
    var saved: SaveData
    var timer: Timer?
    var previousTime = CACurrentMediaTime()
    var frameCounter = 0
    var lookX = 0.0
    var lookY = 0.0
    var targetLookX = 0.0
    var targetLookY = 0.0
    var pendingDifficulty: Difficulty = .standard
    var archiveReturn: OverlayScreen = .menu
    var inspectRequested = false
    var codeWasPaused = false
    var didRecordVictory = false
    #if DEBUG
    var qa: QARunner?
    #endif

    override init() {
        #if DEBUG
        let qaMode = CommandLine.arguments.contains("--ui-smoke")
        store = SaveStore(directory: qaMode ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("HollowSignal-QA-\(ProcessInfo.processInfo.processIdentifier)") : nil)
        #else
        store = SaveStore()
        #endif
        saved = store.load()
        model = GameModel(seed: UInt64(Date().timeIntervalSince1970 * 1000), discovered: saved.discovered)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        super.init()
        window.title = "Hollow Signal"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.minSize = NSSize(width: 960, height: 650)
        window.aspectRatio = NSSize(width: 16, height: 10)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let container = NSView(frame: view.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        view.autoresizingMask = [.width, .height]
        view.scene = world.scene
        view.pointOfView = world.cameraNode
        view.backgroundColor = .black
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        container.addSubview(view)
        hud.frame = container.bounds
        hud.autoresizingMask = [.width, .height]
        container.addSubview(hud)
        window.contentView = container
        hud.onAction = { [weak self] action in self?.handle(action) }
        hud.onKey = { [weak self] event in self?.key(event) }
        hud.onLook = { [weak self] x, y in self?.targetLookX = x; self?.targetLookY = y }
        applySettings()
        audio.start()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hud)
        NSApp.activate(ignoringOtherApps: true)
        if saved.settings.fullscreen { window.toggleFullScreen(nil) }
        timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        #if DEBUG
        if qaMode { qa = QARunner(controller: self) }
        #endif
    }

    @objc func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0, now - previousTime))
        previousTime = now
        model.update(dt: dt)
        consumeEvents()
        let s = model.snapshot
        if s.phase == .dead && hud.screen != .death { hud.enteringCode = false; hud.screen = .death }
        if s.phase == .victory && !didRecordVictory {
            didRecordVictory = true
            saved.completedNights += 1
            saved.overtimeCompleted = saved.overtimeCompleted || s.difficulty == .overtime
            saved.alternateEnding = saved.alternateEnding || s.alternateEnding
            saved.bestPower = max(saved.bestPower, s.power)
            saveProgress()
            hud.enteringCode = false; hud.screen = .victory
        }
        let smoothing = min(1, dt * 4)
        lookX += (targetLookX - lookX) * smoothing
        lookY += (targetLookY - lookY) * smoothing
        world.update(s, time: now, lookX: lookX * saved.settings.sensitivity, lookY: lookY * saved.settings.sensitivity)
        let desiredFPS = s.monitor && s.phase == .playing ? 14 : 60
        if view.preferredFramesPerSecond != desiredFPS { view.preferredFramesPerSecond = desiredFPS }
        audio.update(s)
        hud.snapshot = s
        hud.snapshot.difficulty = pendingDifficulty
        hud.time = now
        hud.save = saved
        frameCounter += 1
        if frameCounter % 2 == 0 { hud.needsDisplay = true }
        #if DEBUG
        qa?.tick(dt: dt)
        #endif
    }

    func consumeEvents() {
        let events = model.drainEvents()
        audio.handle(events)
        for e in events {
            switch e {
            case .discovered(let id):
                saved.discovered.insert(id)
                saveProgress()
                if inspectRequested, let entry = LoreCatalog.entries.first(where: { $0.id == id }) {
                    hud.selectedEvidence = entry
                    model.act(.pause)
                    hud.screen = .evidence
                    inspectRequested = false
                } else { showToast("RECORD RECOVERED  /  " + (LoreCatalog.entries.first(where: { $0.id == id })?.title ?? id)) }
            case .hour(let h): showToast(h == 6 ? "ARCHIVE TRANSFER COMPLETE" : String(format: "%02d:00 AM  /  SHIFT IN PROGRESS", h == 0 ? 12 : h))
            case .victory: break
            default: break
            }
        }
    }

    func showToast(_ text: String) { hud.toast = text; hud.toastUntil = CACurrentMediaTime() + 4.5 }
    func saveProgress() { saved.discovered.formUnion(model.snapshot.discovered); store.save(saved); hud.save = saved }
    func applySettings() {
        world.apply(settings: saved.settings)
        audio.apply(settings: saved.settings)
        hud.settings = saved.settings
        view.antialiasingMode = saved.settings.graphicsQuality == 0 ? .none : (saved.settings.graphicsQuality == 2 ? .multisampling4X : .multisampling2X)
    }
    func begin() {
        didRecordVictory = false
        hud.enteringCode = false
        hud.toast = ""
        model.start(difficulty: pendingDifficulty)
        hud.screen = .game
        previousTime = CACurrentMediaTime()
        window.makeFirstResponder(hud)
    }

    func handle(_ action: String) {
        if action.hasPrefix("slider:") {
            let parts = action.split(separator: ":")
            guard parts.count == 3, let value = Double(parts[2]) else { return }
            switch parts[1] {
            case "master": saved.settings.masterVolume = value
            case "ambience": saved.settings.ambienceVolume = value
            case "effects": saved.settings.effectsVolume = value
            case "brightness": saved.settings.brightness = 0.6 + value
            case "sensitivity": saved.settings.sensitivity = value
            default: break
            }
            applySettings(); store.save(saved); return
        }
        if action.hasPrefix("camera:"), let value = Int(action.dropFirst(7)), let room = Room(rawValue: value) {
            model.act(.camera(room)); consumeEvents(); return
        }
        if action.hasPrefix("evidence:"), let entry = LoreCatalog.entries.first(where: { $0.id == String(action.dropFirst(9)) }) {
            hud.selectedEvidence = entry; hud.needsDisplay = true; return
        }
        audio.handle([.sound("click", 0)])
        switch action {
        case "start", "overtime":
            pendingDifficulty = action == "overtime" ? .overtime : .standard
            if pendingDifficulty == .overtime && saved.completedNights == 0 { return }
            hud.snapshot.difficulty = pendingDifficulty; hud.screen = .briefing
        case "begin", "restart": begin()
        case "menu":
            saveProgress(); model.returnToMenu(); hud.screen = .menu; hud.enteringCode = false
        case "quit": saveProgress(); NSApp.terminate(nil)
        case "monitor": model.act(.toggleMonitor)
        case "left": model.act(.toggleLeft)
        case "right": model.act(.toggleRight)
        case "light": model.act(.toggleLight)
        case "vent": model.act(.toggleVent)
        case "lure": model.act(.lure)
        case "reset": model.act(.resetSignal)
        case "pause": if model.snapshot.phase == .playing { model.act(.pause); hud.screen = .pause }
        case "resume": model.act(.resume); hud.screen = .game
        case "inspect":
            guard model.snapshot.phase == .playing else { break }
            inspectRequested = true; model.act(.inspect); consumeEvents(); inspectRequested = false
        case "closeEvidence": model.act(.resume); hud.screen = .game
        case "settings":
            if model.snapshot.phase == .playing { model.act(.pause); hud.settingsReturn = .pause }
            else { hud.settingsReturn = hud.screen }
            hud.screen = .settings
        case "settingsBack": hud.screen = hud.settingsReturn; store.save(saved)
        case "archive":
            archiveReturn = hud.screen
            if model.snapshot.phase == .playing { model.act(.pause); archiveReturn = .pause }
            hud.screen = .archive
        case "archiveBack": hud.screen = archiveReturn
        case "quality": saved.settings.graphicsQuality = (saved.settings.graphicsQuality + 1) % 3; applySettings(); store.save(saved)
        case "flashes": saved.settings.reducedFlashes.toggle(); applySettings(); store.save(saved)
        case "subtitles": saved.settings.subtitles.toggle(); applySettings(); store.save(saved)
        case "fullscreen": window.toggleFullScreen(nil)
        case "code":
            guard model.snapshot.phase == .playing else { break }
            model.act(.pause); codeWasPaused = true; hud.code = ""; hud.enteringCode = true
        case "submitCode":
            if codeWasPaused { model.act(.resume); codeWasPaused = false }
            model.act(.enterCode(hud.code)); hud.enteringCode = false
        case "closeCode":
            if codeWasPaused { model.act(.resume); codeWasPaused = false }
            hud.enteringCode = false
        default: break
        }
        consumeEvents()
        hud.needsDisplay = true
    }

    func key(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 103 { handle("fullscreen"); return }
        if hud.enteringCode {
            if event.keyCode == 53 { handle("closeCode") }
            else if event.keyCode == 36 || event.keyCode == 76 { handle("submitCode") }
            else if event.keyCode == 51 { if !hud.code.isEmpty { hud.code.removeLast() } }
            else if chars.count == 1 && chars.first!.isNumber && hud.code.count < 4 { hud.code += chars }
            hud.needsDisplay = true; return
        }
        if event.keyCode == 53 {
            switch hud.screen {
            case .game: handle("pause")
            case .pause: handle("resume")
            case .settings: handle("settingsBack")
            case .archive: handle("archiveBack")
            case .evidence: handle("closeEvidence")
            default: handle("menu")
            }
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            switch hud.screen {
            case .menu: handle("start")
            case .briefing: handle("begin")
            case .death: if model.snapshot.deathTime > 0.65 { handle("restart") }
            case .victory: handle("menu")
            default: break
            }
            return
        }
        if hud.screen == .evidence && (chars == "e" || chars == " ") { handle("closeEvidence"); return }
        guard hud.screen == .game else { return }
        switch chars {
        case " ", "m": handle("monitor")
        case "a": handle("left")
        case "d": handle("right")
        case "f": handle("light")
        case "v": handle("vent")
        case "r": handle("lure")
        case "x": handle("reset")
        case "e": handle("inspect")
        case "c": handle("code")
        case "1", "2", "3", "4", "5", "6", "7", "8":
            if !model.snapshot.monitor { model.act(.toggleMonitor) }
            handle("camera:\((Int(chars) ?? 1) - 1)")
        default: break
        }
        #if DEBUG
        if chars == "t" && event.modifierFlags.contains(.control) { for _ in 0..<600 { model.update(dt: 0.1) }; consumeEvents() }
        #endif
    }
    func windowDidResignKey(_ notification: Notification) {
        #if DEBUG
        if qa != nil { return }
        #endif
        if model.snapshot.phase == .playing { handle("pause") }
    }
    func windowWillClose(_ notification: Notification) { saveProgress(); audio.stop(); timer?.invalidate() }
    func windowDidEnterFullScreen(_ notification: Notification) { saved.settings.fullscreen = true; hud.settings = saved.settings; store.save(saved) }
    func windowDidExitFullScreen(_ notification: Notification) { saved.settings.fullscreen = false; hud.settings = saved.settings; store.save(saved) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: GameController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Hollow Signal", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hollow Signal", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Hollow Signal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let windowMenu = NSMenu(title: "Window"); let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); windowItem.submenu = windowMenu
        let fullscreen = windowMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"); fullscreen.keyEquivalentModifierMask = [.control, .command]
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        controller = GameController()
    }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Hollow Signal", .applicationVersion: "1.0", .credits: NSAttributedString(string: "An original survival-horror game.\nAll models, materials, sounds and writing created for this release.\nSee ASSET_CREDITS.md in the source distribution.")])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { controller?.saveProgress(); controller?.audio.stop() }
}

@main
enum HollowSignalApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
