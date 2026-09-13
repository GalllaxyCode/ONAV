import AppKit

enum OverlayScreen { case menu, briefing, game, pause, settings, archive, evidence, death, victory }

final class GameHUD: NSView {
    var snapshot = GameSnapshot()
    var settings = GameSettings()
    var save = SaveData()
    var screen: OverlayScreen = .menu
    var settingsReturn: OverlayScreen = .menu
    var selectedEvidence: LoreEntry?
    var archivePage = 0
    var time: Double = 0
    var toast = ""
    var toastUntil: Double = 0
    var code = ""
    var enteringCode = false
    var onAction: ((String) -> Void)?
    var onKey: ((NSEvent) -> Void)?
    var onLook: ((Double, Double) -> Void)?
    private var regions: [(CGRect, String)] = []
    private var hover = ""
    private var tracking: NSTrackingArea?
    private let ink = NSColor(calibratedRed: 0.73, green: 0.81, blue: 0.76, alpha: 1)
    private let muted = NSColor(calibratedRed: 0.40, green: 0.51, blue: 0.49, alpha: 1)
    private let amber = NSColor(calibratedRed: 0.94, green: 0.67, blue: 0.34, alpha: 1)
    private let red = NSColor(calibratedRed: 0.91, green: 0.34, blue: 0.27, alpha: 1)
    private let dark = NSColor(calibratedRed: 0.025, green: 0.041, blue: 0.041, alpha: 1)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var scale: CGFloat { min(bounds.width / 1440, bounds.height / 900) }
    private var offset: CGPoint { CGPoint(x: (bounds.width - 1440 * scale) / 2, y: (bounds.height - 900 * scale) / 2) }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        hover = regions.last(where: { $0.0.contains(p) })?.1 ?? ""
        onLook?((Double(p.x) / 1440 - 0.5) * 2, (Double(p.y) / 900 - 0.5) * 2)
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hover = ""; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        guard let region = regions.last(where: { $0.0.contains(p) }) else { return }
        if region.1.hasPrefix("slider:") {
            let fraction = max(0, min(1, (p.x - region.0.minX) / region.0.width))
            onAction?(region.1 + ":" + String(Double(fraction)))
        } else { onAction?(region.1) }
    }
    override func mouseDragged(with event: NSEvent) {
        if screen == .settings { mouseDown(with: event) }
        else { mouseMoved(with: event) }
    }
    override func keyDown(with event: NSEvent) { onKey?(event) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard scale > 0 else { return }
        regions.removeAll(keepingCapacity: true)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: offset.x, yBy: offset.y)
        transform.scale(by: scale)
        transform.concat()
        vignette()
        switch screen {
        case .menu: drawMenu()
        case .briefing: drawBriefing()
        case .game: drawGame()
        case .pause: drawGame(); shade(0.72); drawPause()
        case .settings: drawSettings()
        case .archive: drawArchive()
        case .evidence: drawGame(); shade(0.78); drawEvidence()
        case .death: drawDeath()
        case .victory: drawVictory()
        }
        if !toast.isEmpty && time < toastUntil && screen == .game {
            panel(CGRect(x: 370, y: 134, width: 700, height: 44), opacity: 0.94)
            text(toast, 390, 145, size: 13, color: amber, width: 660, align: .center)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func fill(_ rect: CGRect, _ color: NSColor) { color.setFill(); rect.fill() }
    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, color: NSColor, width: CGFloat = 1) {
        color.setStroke(); let p = NSBezierPath(); p.lineWidth = width; p.move(to: NSPoint(x: x1, y: y1)); p.line(to: NSPoint(x: x2, y: y2)); p.stroke()
    }
    private func text(_ value: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 14, color: NSColor? = nil, width: CGFloat = 1200, align: NSTextAlignment = .left, weight: NSFont.Weight = .regular, mono: Bool = true, spacing: CGFloat = 0) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineSpacing = size * 0.32
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? ink, .paragraphStyle: p, .kern: spacing]
        (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 800), withAttributes: attrs)
    }
    private func panel(_ rect: CGRect, opacity: CGFloat = 0.92) {
        fill(rect, dark.withAlphaComponent(opacity))
        muted.withAlphaComponent(0.33).setStroke(); NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        for p in [CGPoint(x: rect.minX + 8, y: rect.minY + 8), CGPoint(x: rect.maxX - 8, y: rect.minY + 8), CGPoint(x: rect.minX + 8, y: rect.maxY - 8), CGPoint(x: rect.maxX - 8, y: rect.maxY - 8)] {
            muted.withAlphaComponent(0.45).setFill(); NSBezierPath(ovalIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill()
        }
    }
    private func fittedText(_ value: String, in rect: CGRect, maximum: CGFloat = 18) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        var size = maximum
        var attributes: [NSAttributedString.Key: Any] = [:]
        while size >= 11 {
            attributes = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: ink, .paragraphStyle: paragraph]
            let height = (value as NSString).boundingRect(with: NSSize(width: rect.width, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height
            if height <= rect.height { break }
            size -= 0.5
        }
        (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
    private func button(_ title: String, _ action: String, _ rect: CGRect, key: String = "", active: Bool = false, danger: Bool = false, enabled: Bool = true) {
        let c = danger ? red : (active ? amber : ink)
        let h = hover == action
        fill(rect, (active ? NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.068, alpha: 0.97) : dark.withAlphaComponent(h ? 1 : 0.92)))
        (enabled ? c.withAlphaComponent(h ? 0.85 : 0.35) : muted.withAlphaComponent(0.2)).setStroke()
        NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        if active { fill(CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height), c) }
        if !key.isEmpty {
            fill(CGRect(x: rect.minX + 13, y: rect.midY - 12, width: 26, height: 24), c.withAlphaComponent(0.1))
            text(key, rect.minX + 13, rect.midY - 8, size: 12, color: enabled ? c : muted, width: 26, align: .center, weight: .medium)
        }
        let inset: CGFloat = key.isEmpty ? 18 : 52
        text(title, rect.minX + inset, rect.midY - 8, size: 13, color: enabled ? c : muted.withAlphaComponent(0.45), width: rect.width - inset - 10, weight: .medium)
        if enabled { regions.append((rect, action)) }
    }
    private func shade(_ opacity: CGFloat) { fill(CGRect(x: -3000, y: -3000, width: 8000, height: 8000), NSColor.black.withAlphaComponent(opacity)) }
    private func vignette() {
        let gradient = NSGradient(colorsAndLocations: (NSColor.clear, 0), (NSColor.black.withAlphaComponent(0.13), 0.45), (NSColor.black.withAlphaComponent(0.66), 1))!
        gradient.draw(in: NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1440, height: 900)), relativeCenterPosition: .zero)
    }
    private func label(_ value: String, _ x: CGFloat, _ y: CGFloat, color: NSColor? = nil) { text(value, x, y, size: 10, color: color ?? muted, spacing: 1.8) }
    private func bar(_ x: CGFloat, _ y: CGFloat, width: CGFloat, value: Double, color: NSColor) {
        fill(CGRect(x: x, y: y, width: width, height: 4), muted.withAlphaComponent(0.2))
        fill(CGRect(x: x, y: y, width: width * CGFloat(max(0, min(1, value))), height: 4), color)
    }
    private func masthead(_ section: String) {
        label("MORROW  /  LISTENING INSTITUTE", 60, 43)
        text(section, 970, 43, size: 10, color: muted, width: 410, align: .right, spacing: 1.4)
        line(60, 68, 1380, 68, color: muted.withAlphaComponent(0.3))
    }

    private func drawMenu() {
        let gradient = NSGradient(starting: NSColor.black.withAlphaComponent(0.88), ending: NSColor.black.withAlphaComponent(0.08))!
        gradient.draw(in: CGRect(x: 0, y: 0, width: 1440, height: 900), angle: 0)
        masthead("NIGHT OPERATIONS  /  TERMINAL 09")
        label("AN ORIGINAL SURVEILLANCE HORROR GAME", 87, 182, color: amber)
        text("HOLLOW", 80, 216, size: 86, color: ink, weight: .ultraLight, mono: false, spacing: 9)
        text("SIGNAL", 80, 308, size: 86, color: ink, weight: .ultraLight, mono: false, spacing: 13)
        line(87, 430, 164, 430, color: amber, width: 2)
        text("Someone left the building listening.", 87, 456, size: 17, color: ink.withAlphaComponent(0.7), width: 520, mono: false)
        button(save.completedNights > 0 ? "RETURN TO THE NIGHT" : "BEGIN THE NIGHT", "start", CGRect(x: 87, y: 527, width: 370, height: 57), key: "↵")
        button("OVERTIME SHIFT", "overtime", CGRect(x: 87, y: 597, width: 370, height: 47), enabled: save.completedNights > 0)
        button("RECOVERED EVIDENCE  ·  \(save.discovered.count)/8", "archive", CGRect(x: 87, y: 654, width: 370, height: 47))
        button("CALIBRATION", "settings", CGRect(x: 87, y: 711, width: 220, height: 47))
        button("QUIT", "quit", CGRect(x: 319, y: 711, width: 138, height: 47))
        label("HEADPHONES RECOMMENDED  /  ONE SHIFT: 8 MINUTES", 87, 823)
        text(save.alternateEnding ? "RETURN CHANNEL: OPEN" : "RECEIVING . . .", 1060, 823, size: 10, color: amber.withAlphaComponent(0.6 + 0.3 * sin(time)), width: 290, align: .right, spacing: 2)
        if save.completedNights > 0 { label("\(save.completedNights) SHIFTS CLEARED", 1040, 780) }
    }

    private func drawBriefing() {
        shade(0.79); masthead("EMPLOYEE HANDOVER  /  READ BEFORE TAKING POST")
        text("KEEP THE LINE OPEN.", 100, 111, size: 44, weight: .light, mono: false, spacing: 2)
        text("You are Mara Vale. Your mother’s last recording is still in this building.\nKeep the archive running until the 6:00 AM transfer completes.", 102, 176, size: 18, color: ink.withAlphaComponent(0.8), width: 1140, mono: false)
        let cards: [(String, String, String, String)] = [
            ("01 / THE SURVEYOR", "It moves between frames.", "Find its pale mask in the gallery, workshop, or west passage. A live feed holds its attention. At the west doorway, close the LEFT shutter until it leaves.", "SPACE  cameras     A  left shutter"),
            ("02 / THE CHORUS", "It follows a working circuit.", "Listen for the three-note call on the right. Send a RELAY PULSE in Intake or Archive to lure it away. At the east doorway, close the RIGHT shutter. Purging draws its attention.", "R  relay pulse     D  right shutter"),
            ("03 / THE SEAM", "The duct is not empty.", "Watch duct pressure and listen overhead. Run a short PURGE to drive it back; stop before the motor overheats. Shutters cannot stop it. The cycle needs time to cool.", "V  purge fan       F  doorway lights")
        ]
        for (i, c) in cards.enumerated() {
            let x = CGFloat(102 + i * 417)
            panel(CGRect(x: x, y: 287, width: 397, height: 292), opacity: 0.85)
            label(c.0, x + 24, 311, color: amber)
            text(c.1, x + 24, 348, size: 24, width: 349, weight: .light, mono: false)
            text(c.2, x + 24, 399, size: 15, color: ink.withAlphaComponent(0.77), width: 344, mono: false)
            text(c.3, x + 24, 546, size: 11, color: amber, width: 350)
        }
        text("POWER IS FINITE.  Every closed shutter, camera, lamp and purge draws from the same reserve.\nUse lights for a quick look. Open shutters after a threat retreats. Reset a failed signal with X.\nInspect papers or camera details with E. Escape pauses the shift, including while reading evidence.", 108, 617, size: 15, color: ink.withAlphaComponent(0.78), width: 1190)
        button("TAKE THE CHAIR", "begin", CGRect(x: 100, y: 773, width: 369, height: 56), key: "↵")
        button("BACK", "menu", CGRect(x: 488, y: 773, width: 165, height: 56), key: "⎋")
        text("\(snapshot.difficulty == .overtime ? "OVERTIME" : "STANDARD")  /  12:00—6:00 AM", 900, 790, size: 12, color: muted, width: 430, align: .right)
    }

    private func drawGame() {
        if snapshot.monitor { drawCameraTexture() }
        drawTelemetry()
        if snapshot.monitor {
            text("CAM \(snapshot.selectedCamera.code)", 65, 166, size: 37, color: ink, weight: .light)
            label(snapshot.selectedCamera.label, 68, 216, color: ink)
            text(snapshot.signalLost ? "SIGNAL LOST  /  RESET NETWORK [X]" : (snapshot.transition > 0 ? "ACQUIRING CARRIER…" : "●  LIVE  /  14 FPS  /  ARCHIVE LINK"), 67, 251, size: 12, color: snapshot.signalLost ? red : muted)
            drawMap()
            label("LOCAL RECORDING  /  17.04.94", 66, 687)
            text(snapshot.clockText, 67, 713, size: 20, color: ink)
            if snapshot.signalLost {
                text("NO CARRIER", 380, 346, size: 54, color: ink.withAlphaComponent(0.55), width: 680, align: .center, weight: .ultraLight, mono: false, spacing: 8)
                text("NETWORK RESET REQUIRED  [X]", 410, 419, size: 12, color: amber, width: 620, align: .center)
            }
            if snapshot.anomalyTime > 0 && !snapshot.signalLost {
                let hints = ["", "04 / RETURN", "DO NOT ERASE THE WITNESS", "17 CALLS HELD", "THE EXIT WAS OPEN", "M. VALE / PRESENT"]
                text(hints[abs(snapshot.anomaly) % hints.count], 381, 520, size: 15, color: ink.withAlphaComponent(0.5), width: 600, align: .center, spacing: 4)
            }
        } else {
            if snapshot.lightOn {
                if snapshot.entities.contains(where: { $0.kind == .surveyor && $0.room == .westPassage && $0.threat > 0.45 }) { label("MOVEMENT / WEST", 88, 414, color: red) }
                if snapshot.entities.contains(where: { $0.kind == .chorus && $0.room == .eastPassage && $0.threat > 0.45 }) { text("MOVEMENT / EAST", 1110, 414, size: 10, color: red, width: 245, align: .right, spacing: 1.5) }
            }
            if snapshot.elapsed < 35 {
                panel(CGRect(x: 483, y: 588, width: 474, height: 93), opacity: 0.8)
                text("FIRST, FIND THE PALE MASK.", 505, 607, size: 14, color: amber, width: 430, align: .center)
                text("SPACE → camera 02. Keep your visits brief.", 501, 638, size: 12, width: 438, align: .center)
            }
            if snapshot.blackout { text("BACKUP EXHAUSTED", 370, 356, size: 40, color: red.withAlphaComponent(0.7), width: 700, align: .center, spacing: 6) }
        }
        if settings.subtitles && snapshot.messageTime > 0 && !snapshot.message.isEmpty {
            panel(CGRect(x: 357, y: 696, width: 726, height: 39), opacity: 0.92)
            text(snapshot.message, 373, 706, size: 12, color: ink, width: 694, align: .center)
        }
        drawConsole()
        if enteringCode { drawCode() }
    }

    private func drawTelemetry() {
        panel(CGRect(x: 40, y: 30, width: 516, height: 88), opacity: 0.89)
        label("MAINS RESERVE", 61, 47)
        text(String(format: "%02.0f", max(0, snapshot.power)) + "%", 62, 65, size: 26, color: snapshot.power < 20 ? red : ink, weight: .light)
        bar(156, 89, width: 113, value: snapshot.power / 100, color: snapshot.power < 20 ? red : amber)
        label("LOAD", 162, 48)
        for i in 0..<6 { fill(CGRect(x: 162 + i * 17, y: 68, width: 11, height: 9), Double(i) < snapshot.load ? amber : muted.withAlphaComponent(0.2)) }
        line(292, 49, 292, 98, color: muted.withAlphaComponent(0.3))
        let pressure = snapshot.entities.first(where: { $0.kind == .seam })?.threat ?? 0
        label("DUCT PRESSURE", 315, 47)
        text(pressure < 0.35 ? "NOMINAL" : (pressure < 0.72 ? "RISING" : "CRITICAL"), 315, 70, size: 14, color: pressure > 0.72 ? red : (pressure > 0.35 ? amber : ink))
        bar(315, 97, width: 211, value: pressure, color: pressure > 0.72 ? red : amber)
        panel(CGRect(x: 1142, y: 30, width: 258, height: 88), opacity: 0.89)
        text(snapshot.clockText, 1166, 51, size: 25, width: 208, align: .right, weight: .light)
        text("TRANSFER AT 06:00", 1166, 88, size: 9, color: muted, width: 208, align: .right, spacing: 1.4)
        if snapshot.monitor {
            panel(CGRect(x: 883, y: 30, width: 243, height: 88), opacity: 0.89)
            label("CARRIER INTEGRITY", 902, 47)
            text(String(format: "%.0f", snapshot.signal) + "%", 902, 70, size: 18, color: snapshot.signalLost ? red : ink)
            bar(966, 85, width: 137, value: snapshot.signal / 100, color: snapshot.signalLost ? red : ink)
        }
    }

    private func drawConsole() {
        panel(CGRect(x: 22, y: 755, width: 1396, height: 125), opacity: 0.97)
        line(41, 776, 1396, 776, color: muted.withAlphaComponent(0.18))
        label("LOCAL DEFENSE / MANUAL OVERRIDE", 46, 765)
        label("SURVEILLANCE / ROUTING", 563, 765)
        label("AUXILIARY", 1047, 765)
        button(snapshot.leftClosed ? "WEST / SHUT" : "WEST / OPEN", "left", CGRect(x: 42, y: 795, width: 175, height: 51), key: "A", active: snapshot.leftClosed)
        button(snapshot.rightClosed ? "EAST / SHUT" : "EAST / OPEN", "right", CGRect(x: 227, y: 795, width: 175, height: 51), key: "D", active: snapshot.rightClosed)
        button("LIGHTS", "light", CGRect(x: 412, y: 795, width: 134, height: 51), key: "F", active: snapshot.lightOn)
        button(snapshot.monitor ? "LOWER MONITOR" : "RAISE MONITOR", "monitor", CGRect(x: 565, y: 795, width: 239, height: 51), key: "␣", active: snapshot.monitor)
        button(snapshot.lureCooldown > 0 ? String(format: "PULSE / %02.0fs", snapshot.lureCooldown) : "RELAY PULSE", "lure", CGRect(x: 814, y: 795, width: 215, height: 51), key: "R", active: snapshot.lureCooldown > 0, enabled: snapshot.monitor && snapshot.lureCooldown <= 0 && !snapshot.signalLost)
        button(snapshot.ventLockout > 0 ? String(format: "COOL / %02.0fs", snapshot.ventLockout) : (snapshot.ventOn ? "PURGING…" : "PURGE"), "vent", CGRect(x: 1048, y: 795, width: 167, height: 51), key: "V", active: snapshot.ventOn, enabled: snapshot.ventLockout <= 0)
        button("RESET", "reset", CGRect(x: 1225, y: 795, width: 170, height: 51), key: "X", enabled: snapshot.resetCooldown <= 0)
        text("E  INSPECT", 45, 858, size: 9, color: muted)
        regions.append((CGRect(x: 39, y: 848, width: 159, height: 28), "inspect"))
        text("C  SERVICE CODE", 226, 858, size: 9, color: muted)
        regions.append((CGRect(x: 223, y: 848, width: 174, height: 28), "code"))
        text("ESC  PAUSE", 1273, 858, size: 9, color: muted, width: 123, align: .right)
        regions.append((CGRect(x: 1249, y: 848, width: 147, height: 28), "pause"))
        text(String(format: "THERMAL LOAD  %.0f°", snapshot.heat), 1049, 858, size: 9, color: snapshot.heat > 65 ? amber : muted)
    }

    private func drawMap() {
        let area = CGRect(x: 1029, y: 316, width: 371, height: 413)
        panel(area, opacity: 0.94)
        label("SIGNAL ROUTING / FLOOR −01", 1050, 336)
        text("SELECT A FEED  [1–7]", 1050, 361, size: 10, color: muted)
        let points: [Room: CGPoint] = [.intake: CGPoint(x: 1074, y: 404), .gallery: CGPoint(x: 1242, y: 404), .workshop: CGPoint(x: 1242, y: 478), .resonance: CGPoint(x: 1074, y: 478), .westPassage: CGPoint(x: 1242, y: 552), .eastPassage: CGPoint(x: 1074, y: 552), .duct: CGPoint(x: 1158, y: 635), .returnChamber: CGPoint(x: 1310, y: 635)]
        for edge: (Room, Room) in [(.intake, .gallery), (.gallery, .workshop), (.intake, .resonance), (.workshop, .westPassage), (.resonance, .eastPassage), (.eastPassage, .duct), (.westPassage, .duct)] {
            let a = points[edge.0]!, b = points[edge.1]!
            line(a.x + 48, a.y + 23, b.x + 48, b.y + 23, color: muted.withAlphaComponent(0.35))
        }
        for room in Room.allCases where room != .returnChamber {
            let p = points[room]!
            let rect = CGRect(x: p.x, y: p.y, width: 110, height: 50)
            let selected = snapshot.selectedCamera == room
            fill(rect, selected ? NSColor(calibratedRed: 0.17, green: 0.21, blue: 0.17, alpha: 1) : dark)
            (selected ? amber : muted.withAlphaComponent(0.5)).setStroke(); NSBezierPath(rect: rect).stroke()
            text("\(room.rawValue + 1) / CAM \(room.code)", p.x + 8, p.y + 9, size: 9, color: selected ? amber : ink)
            text(room.short, p.x + 8, p.y + 29, size: 9, color: selected ? ink : muted)
            regions.append((rect, "camera:\(room.rawValue)"))
        }
        if snapshot.hiddenCameraUnlocked {
            line(1129, 529, 1336, 630, color: amber.withAlphaComponent(0.28))
            let rect = CGRect(x: 1291, y: 636, width: 90, height: 49)
            fill(rect, dark); amber.setStroke(); NSBezierPath(rect: rect).stroke()
            text("8 / CAM 04", 1298, 645, size: 9, color: amber)
            text("RETURN", 1298, 663, size: 9, color: ink)
            regions.append((rect, "camera:7"))
        } else {
            text("04 —", 1321, 648, size: 10, color: muted.withAlphaComponent(0.35))
        }
        text("▼  CONTROL  /  YOU", 1051, 704, size: 10, color: amber)
    }

    private func drawCameraTexture() {
        fill(CGRect(x: 23, y: 127, width: 1394, height: 621), NSColor(calibratedRed: 0.06, green: 0.17, blue: 0.12, alpha: 0.08))
        for y in stride(from: 127, to: 749, by: 4) { fill(CGRect(x: 23, y: y, width: 1394, height: 1), NSColor.black.withAlphaComponent(0.15)) }
        let interference = snapshot.signalLost || snapshot.transition > 0
        let seed = Int(time * (interference ? 23 : 12))
        for i in 0..<(interference ? 95 : 19) {
            let y = 130 + abs((i * 1777 + seed * 431) % 610)
            let x = 25 + abs((i * 1531 + seed * 103) % 1380)
            let w = interference ? 100 + abs((i * 317) % 760) : 4 + abs(i * 191 % 52)
            fill(CGRect(x: x, y: y, width: min(w, 1415-x), height: interference ? 2 : 1), ink.withAlphaComponent(interference ? 0.12 : 0.07))
        }
        if interference {
            fill(CGRect(x: 24, y: 129, width: 1392, height: 617), dark.withAlphaComponent(snapshot.signalLost ? 0.87 : (settings.reducedFlashes ? 0.5 : 0.42)))
            if !settings.reducedFlashes {
                let y = 128 + Int(time * 520) % 590
                fill(CGRect(x: 24, y: y, width: 1392, height: 23), ink.withAlphaComponent(0.08))
            }
        }
        muted.withAlphaComponent(0.45).setStroke(); NSBezierPath(rect: CGRect(x: 23, y: 127, width: 1394, height: 621)).stroke()
        for x: CGFloat in [38, 1398] {
            line(x, 143, x, 173, color: ink.withAlphaComponent(0.4)); line(x, 704, x, 732, color: ink.withAlphaComponent(0.4))
        }
    }

    private func drawPause() {
        panel(CGRect(x: 465, y: 203, width: 510, height: 501))
        label("SHIFT SUSPENDED", 508, 243, color: amber)
        text("Hold the silence.", 505, 278, size: 40, weight: .light, mono: false)
        text("Time and all systems are paused.", 509, 342, size: 13, color: muted)
        button("RESUME SHIFT", "resume", CGRect(x: 508, y: 394, width: 424, height: 55), key: "⎋")
        button("CALIBRATION", "settings", CGRect(x: 508, y: 462, width: 424, height: 50))
        button("RECOVERED EVIDENCE", "archive", CGRect(x: 508, y: 525, width: 424, height: 50))
        button("END SHIFT / MAIN MENU", "menu", CGRect(x: 508, y: 608, width: 424, height: 50))
    }

    private func slider(_ title: String, _ key: String, _ x: CGFloat, _ y: CGFloat, value: Double, display: String? = nil) {
        label(title, x, y)
        text(display ?? String(format: "%.0f%%", value * 100), x + 300, y - 3, size: 14, color: ink, width: 115, align: .right)
        fill(CGRect(x: x, y: y + 40, width: 415, height: 3), muted.withAlphaComponent(0.28))
        fill(CGRect(x: x, y: y + 40, width: 415 * CGFloat(value), height: 3), amber.withAlphaComponent(0.8))
        fill(CGRect(x: x + 415 * CGFloat(value) - 4, y: y + 32, width: 8, height: 19), amber)
        regions.append((CGRect(x: x, y: y + 24, width: 415, height: 37), "slider:\(key)"))
    }
    private func drawSettings() {
        shade(0.87); masthead("CALIBRATION / SAVED AUTOMATICALLY")
        text("Make yourself comfortable.", 105, 117, size: 42, weight: .light, mono: false)
        label("AUDIO", 110, 217, color: amber)
        slider("MASTER VOLUME", "master", 110, 257, value: settings.masterVolume)
        slider("ROOM & MACHINERY", "ambience", 110, 350, value: settings.ambienceVolume)
        slider("CUES & EQUIPMENT", "effects", 110, 443, value: settings.effectsVolume)
        label("DISPLAY & INPUT", 777, 217, color: amber)
        slider("EXPOSURE", "brightness", 777, 257, value: (settings.brightness - 0.6) / 1.0, display: String(format: "%.2f", settings.brightness))
        slider("LOOK SENSITIVITY", "sensitivity", 777, 350, value: settings.sensitivity)
        let quality = ["LOW", "BALANCED", "HIGH"][max(0, min(2, settings.graphicsQuality))]
        button("GRAPHICS / \(quality)", "quality", CGRect(x: 777, y: 445, width: 415, height: 50))
        button(settings.reducedFlashes ? "REDUCED FLASHES / ON" : "REDUCED FLASHES / OFF", "flashes", CGRect(x: 110, y: 559, width: 415, height: 50), active: settings.reducedFlashes)
        button(settings.subtitles ? "SOUND CAPTIONS / ON" : "SOUND CAPTIONS / OFF", "subtitles", CGRect(x: 110, y: 626, width: 415, height: 50), active: settings.subtitles)
        button(settings.fullscreen ? "FULLSCREEN / ON" : "FULLSCREEN / OFF", "fullscreen", CGRect(x: 777, y: 559, width: 415, height: 50), active: settings.fullscreen)
        text("Stereo headphones reveal direction.\nAll critical threats also have visible tells.\nSettings are stored locally on this Mac.", 777, 634, size: 12, color: muted, width: 450)
        button("RETURN", "settingsBack", CGRect(x: 108, y: 772, width: 310, height: 55), key: "⎋")
        text("F11 OR ⌃⌘F  FULLSCREEN", 860, 794, size: 10, color: muted, width: 450, align: .right)
    }

    private func drawArchive() {
        shade(0.90); masthead("RECOVERED EVIDENCE / LOCAL COPIES")
        text("The archive remembers.", 100, 114, size: 42, weight: .light, mono: false)
        text("\(save.discovered.count) OF 8 RECORDS RECOVERED", 103, 180, size: 11, color: amber, spacing: 2)
        for (i, entry) in LoreCatalog.entries.enumerated() {
            let y = CGFloat(245 + i * 57)
            let found = save.discovered.contains(entry.id)
            button(found ? entry.title : "[ UNRECOVERED RECORD ]", "evidence:\(entry.id)", CGRect(x: 101, y: y, width: 490, height: 47), enabled: found)
        }
        panel(CGRect(x: 648, y: 244, width: 679, height: 451), opacity: 0.73)
        if let entry = selectedEvidence, save.discovered.contains(entry.id) {
            label(entry.subtitle.uppercased(), 680, 276, color: amber)
            text(entry.title, 680, 325, size: 28, width: 609, weight: .light, mono: false)
            fittedText(entry.text, in: CGRect(x: 680, y: 389, width: 603, height: 283), maximum: 16)
        } else {
            text("Every system keeps a record.\nEven the ones built to forget.", 691, 340, size: 28, color: muted, width: 590, weight: .light, mono: false)
            text("Inspect the control desk and camera feeds with E.\nSome records appear only under unusual conditions.\nThe skipped room has not been demolished.", 692, 466, size: 13, color: muted, width: 580)
        }
        button("RETURN", "archiveBack", CGRect(x: 101, y: 773, width: 310, height: 55), key: "⎋")
        if save.overtimeCompleted { text("OVERTIME CLEARED", 970, 795, size: 11, color: amber, width: 356, align: .right) }
    }

    private func drawEvidence() {
        panel(CGRect(x: 300, y: 120, width: 840, height: 660), opacity: 0.99)
        label("COPIED TO YOUR EVIDENCE FILE  /  SHIFT PAUSED", 342, 157, color: amber)
        if let entry = selectedEvidence {
            text(entry.title, 341, 206, size: 33, width: 756, weight: .light, mono: false)
            text(entry.subtitle.uppercased(), 342, 263, size: 10, color: muted, width: 751, spacing: 1.5)
            line(342, 298, 1095, 298, color: muted.withAlphaComponent(0.3))
            fittedText(entry.text, in: CGRect(x: 342, y: 327, width: 754, height: 348), maximum: 18)
        }
        button("PUT DOWN / RESUME", "closeEvidence", CGRect(x: 341, y: 701, width: 756, height: 48), key: "E")
    }

    private func drawCode() {
        fill(CGRect(x: 0, y: 130, width: 1440, height: 613), NSColor.black.withAlphaComponent(0.61))
        panel(CGRect(x: 451, y: 252, width: 538, height: 317), opacity: 0.99)
        label("MAINTENANCE / MISSING CIRCUIT", 482, 283, color: amber)
        text("SERVICE AUTHORIZATION", 481, 328, size: 21)
        text((code + String(repeating: "_", count: max(0, 4-code.count))).map(String.init).joined(separator: "  "), 483, 376, size: 46, color: ink, width: 474, align: .center)
        text("ENTER 4 DIGITS, THEN RETURN   /   ESC TO CLOSE", 483, 459, size: 10, color: muted, width: 474, align: .center)
        button("AUTHORIZE", "submitCode", CGRect(x: 482, y: 500, width: 299, height: 43), key: "↵")
        button("CLOSE", "closeCode", CGRect(x: 795, y: 500, width: 164, height: 43))
    }

    private func drawDeath() {
        let t = snapshot.deathTime
        shade(t < 1.5 ? 0.26 : 0.89)
        if t > 0.65 {
            label("TRANSFER INTERRUPTED", 102, 224, color: red)
            text("THE LINE WENT DEAD.", 98, 274, size: 58, weight: .ultraLight, mono: false, spacing: 2)
            let advice: String
            switch snapshot.killer {
            case .surveyor: advice = "The Surveyor reached the west doorway. Watch its live camera to slow it.\nWhen it is close, shut the west shutter until the footsteps recede."
            case .chorus: advice = "The Chorus followed the circuit to the east doorway. A relay pulse can\ndraw it into Intake or Archive. Close the east shutter when it reaches you."
            case .seam: advice = "The Seam entered through the overhead duct. Watch duct pressure.\nShort purge cycles drive it back; shutters cannot stop it."
            case nil: advice = "The reserve ran dry. Brief camera checks and short defenses save power.\nKeeping both shutters closed cannot carry you through the night."
            }
            text(advice, 103, 385, size: 18, color: ink.withAlphaComponent(0.78), width: 1130, mono: false)
            text("LAST CONTACT  \(snapshot.clockText)  /  RESERVE \(Int(snapshot.power))%", 104, 486, size: 11, color: muted, spacing: 1.2)
            button("TAKE THE CHAIR AGAIN", "restart", CGRect(x: 103, y: 557, width: 387, height: 58), key: "↵")
            button("MAIN MENU", "menu", CGRect(x: 507, y: 557, width: 235, height: 58), key: "⎋")
        }
    }

    private func drawVictory() {
        shade(0.62)
        label(snapshot.alternateEnding ? "RETURN CHANNEL ESTABLISHED" : "SCHEDULED TRANSFER COMPLETE", 103, 181, color: amber)
        text("06:00", 92, 230, size: 119, weight: .ultraLight, mono: false, spacing: 8)
        text(snapshot.alternateEnding ? "This time, someone heard her." : "Morning found you.", 102, 384, size: 39, weight: .light, mono: false)
        text(snapshot.alternateEnding ? "The machines fall silent one by one. Your mother’s voice leaves\nthe building on the return line. In the recording, she says your name.\nOutside, for the first time, the birds are louder than the fans." : "The shutters release. Somewhere beyond the concrete, a bird calls.\nThe archive reports a successful transfer. Your mother’s file is empty.\nBut circuit 04 is still drawing power.", 104, 457, size: 18, color: ink.withAlphaComponent(0.82), width: 1170, mono: false)
        text("RESERVE \(Int(snapshot.power))%   /   \(save.discovered.count) RECORDS RECOVERED   /   OVERTIME UNLOCKED", 105, 598, size: 11, color: amber, spacing: 1)
        button("RETURN TO THE SURFACE", "menu", CGRect(x: 104, y: 675, width: 422, height: 58), key: "↵")
        button("EXAMINE EVIDENCE", "archive", CGRect(x: 543, y: 675, width: 326, height: 58))
        label("THE BUILDING WILL REMEMBER THIS SHIFT.", 106, 825)
    }
}
