import Foundation

/// A fixed-step simulation. Rendering, audio and persistence consume snapshots/events,
/// so pausing never leaves an AI timer running on a dispatch queue.
final class GameModel {
    private(set) var snapshot = GameSnapshot()
    private var rng: NightRandom
    private let originalSeed: UInt64
    private var attempt: UInt64 = 0
    private var accumulator = 0.0
    private var pendingEvents: [GameEvent] = []
    private var enemies: [Enemy] = []
    private var signalOutTime = 0.0
    private var ventRunTime = 0.0
    private var ambientTimer = 17.0
    private var malfunctionTimer = 47.0
    private var lastHour = 0
    private var seamWarning = 0
    private var powerWarning = 0
    private var clueSwitches: [Room] = []
    private var lureTarget: Room?
    private var lureTravelTime = 0.0
    private var lowPowerSeconds = 0.0
    private let tick = 1.0 / 30.0

    #if DEBUG
    var debugInvincible = false
    var debugTimeScale = 1.0
    #endif

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max), discovered: Set<String> = []) {
        originalSeed = seed
        rng = NightRandom(seed: seed)
        snapshot.seed = seed
        snapshot.discovered = discovered
        snapshot.hiddenCameraUnlocked = discovered.contains("return")
    }

    func start(difficulty: Difficulty) {
        let discovered = snapshot.discovered
        let seed = originalSeed &+ attempt &* 0x9E3779B97F4A7C15
        attempt &+= 1
        rng = NightRandom(seed: seed)
        snapshot = GameSnapshot()
        snapshot.phase = .playing
        snapshot.difficulty = difficulty
        snapshot.seed = seed
        snapshot.discovered = discovered
        snapshot.hiddenCameraUnlocked = discovered.contains("return")
        accumulator = 0
        pendingEvents.removeAll(keepingCapacity: true)
        signalOutTime = 0
        ventRunTime = 0
        ambientTimer = rng.between(16, 24)
        malfunctionTimer = rng.between(43, 59)
        lastHour = 0
        seamWarning = 0
        powerWarning = 0
        clueSwitches.removeAll(keepingCapacity: true)
        lureTarget = nil
        lureTravelTime = 0
        lowPowerSeconds = 0
        enemies = [
            Enemy(kind: .surveyor, room: .gallery, timer: difficulty == .standard ? 28 : 17),
            Enemy(kind: .chorus, room: .intake, timer: difficulty == .standard ? 108 : 58),
            Enemy(kind: .seam, room: .duct, timer: difficulty == .standard ? 84 : 48)
        ]
        publishEnemies()
        show("12:00 — Watch the gallery. The old survey instrument stops when its lens meets yours.", for: 12)
        pendingEvents.append(.hour(0))
    }

    func returnToMenu() {
        snapshot.phase = .menu
        snapshot.monitor = false
        snapshot.lightOn = false
        snapshot.ventOn = false
        accumulator = 0
    }

    func drainEvents() -> [GameEvent] {
        let result = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return result
    }

    func update(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        if snapshot.phase == .dead {
            snapshot.deathTime += min(dt, 1)
            return
        }
        guard snapshot.phase == .playing else { return }
        var elapsed = min(dt, 60)
        #if DEBUG
        elapsed *= max(0, min(debugTimeScale, 60))
        #endif
        accumulator += elapsed
        while accumulator + 0.0000001 >= tick && snapshot.phase == .playing {
            accumulator -= tick
            step(tick)
        }
    }

    func act(_ action: GameAction) {
        switch action {
        case .pause:
            if snapshot.phase == .playing { snapshot.phase = .paused }
            return
        case .resume:
            if snapshot.phase == .paused { snapshot.phase = .playing }
            return
        default: break
        }
        guard snapshot.phase == .playing else { return }
        switch action {
        case .toggleMonitor:
            guard requirePower() else { return }
            snapshot.monitor.toggle()
            snapshot.transition = snapshot.monitor ? 0.38 : 0
            sound("monitor")
        case .camera(let room):
            guard requirePower() else { return }
            guard room != .returnChamber || snapshot.hiddenCameraUnlocked else {
                show("CAM 04 is absent from the public circuit. The service terminal accepts four digits.")
                return
            }
            guard snapshot.selectedCamera != room || !snapshot.monitor else { return }
            snapshot.monitor = true
            snapshot.selectedCamera = room
            snapshot.transition = 0.34
            snapshot.signal = max(0, snapshot.signal - 0.65)
            sound("camera")
            clueSwitches.append(room)
            if clueSwitches.count > 4 { clueSwitches.removeFirst() }
            if clueSwitches == [.gallery, .resonance, .gallery, .resonance] {
                snapshot.anomaly = 4
                snapshot.anomalyTime = 4
                show("FRAME ORDER ERROR / 03 · 04 · 05 / one room was removed, not demolished.", for: 8)
            }
        case .toggleLeft:
            guard requirePower() else { return }
            snapshot.leftClosed.toggle()
            sound("shutter", -0.8)
            shutterNoise()
        case .toggleRight:
            guard requirePower() else { return }
            snapshot.rightClosed.toggle()
            sound("shutter", 0.8)
            shutterNoise()
        case .toggleLight:
            guard requirePower() else { return }
            snapshot.lightOn.toggle()
            sound("light")
        case .toggleVent:
            guard requirePower() else { return }
            if snapshot.ventOn {
                stopVent(lockout: 6)
            } else if snapshot.ventLockout <= 0 {
                snapshot.ventOn = true
                ventRunTime = 0
                sound("vent")
                show("PURGE ACTIVE / duct pressure falling. The intake speaker is picking up the fan.", for: 4)
            } else {
                show("PURGE MOTOR COOLING / \(Int(ceil(snapshot.ventLockout)))s", for: 2)
            }
        case .lure:
            useLure()
        case .resetSignal:
            guard requirePower() else { return }
            if snapshot.resetCooldown > 0 {
                show("RELAY RECHARGING / \(Int(ceil(snapshot.resetCooldown)))s", for: 2)
                return
            }
            snapshot.power = max(0, snapshot.power - 1.5)
            snapshot.signal = min(100, snapshot.signal + 52)
            snapshot.resetCooldown = 16
            signalOutTime = 3.5
            snapshot.signalLost = true
            sound("reset")
            show("RELAY RESET / all pictures return in 3 seconds. The passage shutters remain local.", for: 5)
        case .inspect:
            inspect()
        case .enterCode(let code):
            guard requirePower() else { return }
            if code.filter(\.isNumber) == "0417" {
                snapshot.hiddenCameraUnlocked = true
                discover("return")
                show("CAM 04 / RETURN CHAMBER restored. Its speaker is still connected.", for: 9)
                sound("relay")
            } else {
                sound("failure")
                show("SERVICE KEY REJECTED / room index + withheld calls", for: 4)
            }
        case .pause, .resume: break
        }
        updateBlackout()
        publishEnemies()
    }

    private func step(_ dt: Double) {
        snapshot.elapsed = min(snapshot.duration, snapshot.elapsed + dt)
        snapshot.hour = min(6, Int((snapshot.elapsed + 0.00001) / (snapshot.duration / 6)))
        if snapshot.hour >= 6 {
            win()
            return
        }
        if snapshot.hour != lastHour {
            lastHour = snapshot.hour
            hourChanged(lastHour)
        }
        snapshot.transition = countdown(snapshot.transition, dt)
        snapshot.messageTime = max(0, snapshot.messageTime - dt)
        snapshot.anomalyTime = max(0, snapshot.anomalyTime - dt)
        if snapshot.anomalyTime == 0 { snapshot.anomaly = 0 }
        snapshot.lureCooldown = countdown(snapshot.lureCooldown, dt)
        snapshot.resetCooldown = countdown(snapshot.resetCooldown, dt)
        snapshot.ventLockout = countdown(snapshot.ventLockout, dt)
        signalOutTime = countdown(signalOutTime, dt)
        snapshot.signalLost = signalOutTime > 0 || snapshot.signal < 8 || snapshot.blackout
        resourceStep(dt)
        updateBlackout()
        for index in enemies.indices {
            switch enemies[index].kind {
            case .surveyor: surveyorStep(index, dt)
            case .chorus: chorusStep(index, dt)
            case .seam: seamStep(index, dt)
            }
            if snapshot.phase != .playing { break }
        }
        if snapshot.phase == .playing { environmentStep(dt) }
        publishEnemies()
    }

    private func resourceStep(_ dt: Double) {
        let doorCount = (snapshot.leftClosed ? 1.0 : 0) + (snapshot.rightClosed ? 1.0 : 0)
        let draw = 0.075 + doorCount * 0.20 + (snapshot.monitor ? 0.035 : 0)
            + (snapshot.lightOn ? 0.065 : 0) + (snapshot.ventOn ? 0.10 : 0)
        snapshot.load = draw / 0.075
        snapshot.power = max(0, snapshot.power - draw * dt)
        let wasteHeat = 0.012 + doorCount * (snapshot.hour >= 4 ? 0.14 : 0.08)
            + (snapshot.monitor ? 0.034 : 0) + (snapshot.lightOn ? 0.035 : 0)
        snapshot.heat = clamped(snapshot.heat + (wasteHeat - (snapshot.ventOn ? 1.8 : 0)) * dt, 0, 100)
        snapshot.signal = clamped(snapshot.signal + (snapshot.monitor ? -0.054 : 0.22) * dt, 0, 100)
        if snapshot.ventOn {
            ventRunTime += dt
            if ventRunTime >= 8 { stopVent(lockout: 10) }
        }
        let warning = snapshot.power < 10 ? 2 : (snapshot.power < 25 ? 1 : 0)
        if warning > powerWarning {
            powerWarning = warning
            show(warning == 1 ? "RESERVE 25% / idle shutters and lamps draw current."
                 : "RESERVE CRITICAL / the clock is on a separate circuit.", for: 7)
            sound("failure")
        }
        if snapshot.power < 5 {
            lowPowerSeconds += dt
            if lowPowerSeconds > 1.5 && !snapshot.discovered.contains("blackout") {
                discover("blackout")
                show("BACKUP DISPLAY / M. VALE — PARTICIPANT 017 — VOICEPRINT ACCEPTED", for: 9)
            }
        }
    }

    private func surveyorStep(_ i: Int, _ dt: Double) {
        if enemies[i].state == .dormant {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 { awaken(i) }
            return
        }
        if enemies[i].state == .retreating {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 {
                enemies[i].room = .gallery
                enemies[i].state = .stalking
                setMoveTimer(i)
            }
            return
        }
        let watched = liveCamera(enemies[i].room)
        if enemies[i].room == .westPassage {
            passageStep(i, dt, closed: snapshot.leftClosed, watched: watched)
            return
        }
        enemies[i].state = watched ? .watching : .stalking
        if !watched {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 {
                let next: Room = enemies[i].room == .gallery ? .workshop : .westPassage
                move(i, to: next)
            }
        }
    }

    private func chorusStep(_ i: Int, _ dt: Double) {
        if enemies[i].state == .dormant {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 { awaken(i) }
            return
        }
        if let target = lureTarget {
            lureTravelTime -= dt
            enemies[i].state = .wandering
            if lureTravelTime <= 0 {
                lureTarget = nil
                move(i, to: target)
                enemies[i].timer += 9
                enemies[i].interval += 9
            }
            return
        }
        if enemies[i].state == .retreating {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 {
                enemies[i].room = .intake
                enemies[i].state = .stalking
                setMoveTimer(i)
            }
            return
        }
        if enemies[i].room == .eastPassage {
            passageStep(i, dt, closed: snapshot.rightClosed, watched: false)
            return
        }
        enemies[i].state = .stalking
        let speed = snapshot.ventOn ? 1.75 : 1.0
        enemies[i].timer -= dt * speed
        if enemies[i].timer <= 0 {
            let next: Room
            switch enemies[i].room {
            case .intake: next = .resonance
            case .resonance: next = .eastPassage
            case .gallery: next = .intake
            case .workshop: next = .gallery
            case .westPassage: next = .workshop
            case .returnChamber: next = .resonance
            case .eastPassage, .duct: next = .intake
            }
            move(i, to: next)
        }
    }

    private func passageStep(_ i: Int, _ dt: Double, closed: Bool, watched: Bool) {
        if closed && !snapshot.blackout {
            if enemies[i].blockedFor == 0 { sound("knock", enemies[i].kind == .surveyor ? -0.9 : 0.9) }
            enemies[i].state = .waiting
            enemies[i].blockedFor += dt
            if enemies[i].blockedFor >= 3 {
                let kind = enemies[i].kind
                enemies[i].room = kind == .surveyor ? .workshop : .resonance
                enemies[i].state = .retreating
                enemies[i].timer = rng.between(9, 13)
                enemies[i].interval = enemies[i].timer
                enemies[i].blockedFor = 0
                enemies[i].threat = 0
                pendingEvents.append(.defense(kind == .surveyor ? "left" : "right"))
                show(kind == .surveyor ? "WEST / the measuring feet are receding. Shutter may be released."
                     : "EAST / the borrowed voices are moving away. Shutter may be released.", for: 5)
            }
        } else {
            enemies[i].blockedFor = 0
            enemies[i].state = watched ? .watching : .approaching
            if !watched { enemies[i].grace -= dt }
            if enemies[i].grace <= 0 { attack(enemies[i].kind) }
        }
    }

    private func seamStep(_ i: Int, _ dt: Double) {
        if enemies[i].state == .dormant {
            enemies[i].timer -= dt
            if enemies[i].timer <= 0 {
                enemies[i].state = .stalking
                enemies[i].threat = 0.12
                sound("seam_move")
                show("A seam in the overhead duct opens. Use a brief ventilation purge before pressure peaks.", for: 8)
            }
            return
        }
        let difficulty = snapshot.difficulty == .overtime ? 1.26 : 1.0
        let growth = (0.0016 + Double(snapshot.hour) * 0.00033 + snapshot.heat * 0.000035) * difficulty
        if snapshot.ventOn {
            enemies[i].threat = max(0, enemies[i].threat - 0.105 * dt)
            enemies[i].state = .retreating
            // A tiny toggle must not continually reset the last attack window.
            // Genuine pressure relief rearms the grace period.
            if enemies[i].threat <= 0.90 { enemies[i].grace = 9 }
        } else {
            enemies[i].threat = min(1, enemies[i].threat + growth * dt)
            enemies[i].state = enemies[i].threat > 0.70 ? .approaching : .stalking
        }
        let warning = enemies[i].threat > 0.85 ? 2 : (enemies[i].threat > 0.55 ? 1 : 0)
        if warning > seamWarning {
            sound(warning == 1 ? "seam_move" : "seam_near")
            show(warning == 1 ? "[Above you: slow fabric dragging over metal.]"
                 : "[The duct grille bows inward. Purge the air handler.]", for: 5)
        }
        seamWarning = warning
        if enemies[i].threat >= 1 {
            enemies[i].state = .attacking
            enemies[i].grace -= dt
            if enemies[i].grace <= 0 { attack(.seam) }
        }
    }

    private func awaken(_ i: Int) {
        enemies[i].state = .stalking
        setMoveTimer(i)
        if enemies[i].kind == .surveyor {
            sound("surveyor_step", -0.55)
            show("[Two measured taps behind the west wall.]", for: 5)
        } else {
            sound("whisper", 0.6)
            show("[A voice repeats the intake announcement. A second voice finishes it.]", for: 6)
        }
    }

    private func setMoveTimer(_ i: Int) {
        let hour = Double(snapshot.hour)
        let hard = snapshot.difficulty == .overtime ? 0.82 : 1.0
        let base = enemies[i].kind == .surveyor ? 27.0 : 30.0
        enemies[i].timer = rng.between(base - 3, base + 7) * max(0.62, 1 - hour * 0.055) * hard
        enemies[i].interval = enemies[i].timer
        enemies[i].grace = snapshot.difficulty == .overtime ? 10 : 12
    }

    private func move(_ i: Int, to room: Room) {
        enemies[i].room = room
        enemies[i].state = .stalking
        enemies[i].blockedFor = 0
        setMoveTimer(i)
        let kind = enemies[i].kind
        let atDoor = (kind == .surveyor && room == .westPassage) || (kind == .chorus && room == .eastPassage)
        if atDoor {
            enemies[i].state = .approaching
            sound(kind == .surveyor ? "surveyor_near" : "chorus_near", kind == .surveyor ? -0.95 : 0.95)
            show(kind == .surveyor ? "[West passage: metal feet stop just outside. Close the left shutter.]"
                 : "[East passage: a choir inhales. Close the right shutter or lure it back to the archive.]", for: 7)
        } else {
            sound(kind == .surveyor ? "surveyor_step" : "chorus_step", kind == .surveyor ? -0.45 : 0.45)
        }
    }

    private func useLure() {
        guard requirePower() else { return }
        guard snapshot.monitor && !snapshot.signalLost && snapshot.transition <= 0 else {
            show("A live camera is required to address its speaker.", for: 3)
            return
        }
        guard snapshot.lureCooldown <= 0 else {
            show("SPEAKER CAPACITOR / \(Int(ceil(snapshot.lureCooldown)))s", for: 2)
            return
        }
        let target = snapshot.selectedCamera
        guard target != .duct && target != .westPassage && target != .eastPassage else {
            show("NO RELAY SPEAKER / choose an adjoining room, away from the passages.", for: 4)
            return
        }
        let reserveBeforeLure = snapshot.power
        snapshot.power = max(0, snapshot.power - 1)
        snapshot.lureCooldown = 16
        sound("lure", target == .gallery || target == .workshop ? -0.5 : 0.5)
        if target == .returnChamber && snapshot.hiddenCameraUnlocked && snapshot.hour >= 4 && reserveBeforeLure >= 10 {
            snapshot.secretArmed = true
            discover("testimony")
            snapshot.anomaly = 5
            snapshot.anomalyTime = 6
            show("RETURN LINE OPEN / ADA VOSS: “Mara. Keep this channel alive until the morning bell.”", for: 12)
        } else {
            show("RELAY PLAYBACK / “Please return to your listening station.”", for: 4)
        }
        guard let index = enemies.firstIndex(where: { $0.kind == .chorus }),
              enemies[index].state != .dormant,
              neighbors(of: enemies[index].room).contains(target) else { return }
        lureTarget = target
        lureTravelTime = 1.1
        enemies[index].grace = 12
        enemies[index].blockedFor = 0
        enemies[index].state = .wandering
        pendingEvents.append(.defense("lure"))
    }

    private func inspect() {
        if snapshot.power < 5 {
            discover("blackout", replay: true)
            show("The backup CRT recognizes your childhood voiceprint: M. VALE / PARTICIPANT 017.", for: 8)
            return
        }
        if !snapshot.monitor {
            discover("desk", replay: true)
            show("MARA VALE / Temporary operator. Someone wrote “She is still on the return line” on your pass.", for: 9)
            return
        }
        guard !snapshot.signalLost && snapshot.transition <= 0 else {
            show("The image is too unstable to read.", for: 3)
            return
        }
        switch snapshot.selectedCamera {
        case .gallery:
            discover("gallery", replay: true)
            show("FLOOR PLAN: 01 · 02 · 03 · [04 painted over] · 05. RETURN is scratched beneath the paint.", for: 10)
        case .workshop:
            discover("maintenance", replay: true)
            show("17 calls withheld. Key format: missing room, then call count. — A. Voss / 17 APR 94", for: 10)
        case .resonance:
            let minutes = snapshot.elapsed / snapshot.duration * 360
            if abs(minutes - 197) <= 4 {
                discover("testimony", replay: true)
                snapshot.anomaly = 5
                snapshot.anomalyTime = 7
                show("03:17 / VOSS: “After four, send my voice back to the missing room. Leave ten cells for the line.”", for: 12)
            } else {
                discover("incident", replay: true)
                show("17 APR 1994 / Evacuation announcement replaced with familiar voices. Archive continuity: maintained.", for: 10)
            }
        case .returnChamber:
            discover("return", replay: true)
            show("RETURN LINE: opens after 04:00. Reserve ≥10. Route a voice here, then remain until the morning bell.", for: 10)
        case .intake:
            show("MORROW LISTENING INSTITUTE / Teaching machines to remember the people who leave.", for: 7)
        case .westPassage:
            show("MEASUREMENT IN PROGRESS / Direct observation suspends the survey cycle. Local shutter overrides.", for: 8)
        case .eastPassage:
            show("ACOUSTIC RETURN PATH / Remote speakers can redirect a voice through an adjacent room.", for: 8)
        case .duct:
            show("AIR HANDLER / Purge before pressure peaks. Shutters do not seal the overhead duct.", for: 8)
        }
    }

    private func hourChanged(_ hour: Int) {
        pendingEvents.append(.hour(hour))
        switch hour {
        case 1: show("01:00 / Intake playback has restarted. Voices follow adjacent speakers; the purge fan carries.", for: 11)
        case 2:
            snapshot.signal = max(0, snapshot.signal - 14)
            show("02:00 / CAMERA BUS DEGRADED. Use relay reset if a feed drops. It briefly interrupts every camera.", for: 10)
        case 3:
            snapshot.anomaly = 3
            snapshot.anomalyTime = 5
            show("03:00 / ARCHIVE REPLAY SCHEDULE: 03:17. The air handler is no longer cooling itself.", for: 10)
        case 4:
            snapshot.anomaly = 4
            snapshot.anomalyTime = 4
            show("04:00 / RETURN LINE AVAILABLE. Hot shutter coils now add to duct pressure.", for: 9)
        case 5:
            show("05:00 / AUTOMATIC EVACUATION TEST. Voices now investigate shutter motors. Dawn is one hour away.", for: 10)
            sound("whisper", 0.25)
        default: break
        }
    }

    private func environmentStep(_ dt: Double) {
        ambientTimer -= dt
        if ambientTimer <= 0 {
            ambientTimer = rng.between(20, 35)
            let event = rng.integer(5)
            sound(event == 0 ? "whisper" : (event == 1 ? "knock" : "creak"), rng.between(-0.8, 0.8))
            if event <= 1 {
                snapshot.anomaly = rng.integer(3) + 1
                snapshot.anomalyTime = rng.between(1.1, 2.8)
                if snapshot.messageTime < 1 { show("[Something shifts in a room with no movement on the circuit.]", for: 4) }
            }
        }
        if snapshot.hour >= 2 {
            malfunctionTimer -= dt
            if malfunctionTimer <= 0 {
                malfunctionTimer = rng.between(49, 78)
                signalOutTime = max(signalOutTime, rng.between(1.4, 2.6))
                snapshot.signalLost = true
                snapshot.anomaly = 2
                snapshot.anomalyTime = signalOutTime
                sound("failure")
                if snapshot.messageTime < 1 { show("CAMERA BUS / packet loss. Local defenses remain available.", for: 4) }
            }
        }
    }

    private func updateBlackout() {
        if snapshot.power <= 0 && !snapshot.blackout {
            snapshot.blackout = true
            snapshot.power = 0
            snapshot.monitor = false
            snapshot.leftClosed = false
            snapshot.rightClosed = false
            snapshot.lightOn = false
            snapshot.ventOn = false
            snapshot.signalLost = true
            sound("blackout")
            show("MAIN CIRCUIT LOST / the independent clock is still running.", for: 12)
            discover("blackout")
            // A last reserve prevents an off-camera instant death at power loss.
            for i in enemies.indices { enemies[i].grace = max(enemies[i].grace, 10) }
        }
    }

    private func stopVent(lockout: Double) {
        snapshot.ventOn = false
        snapshot.ventLockout = lockout
        ventRunTime = 0
        sound("vent")
    }

    private func shutterNoise() {
        if snapshot.hour >= 5, let i = enemies.firstIndex(where: { $0.kind == .chorus }),
           enemies[i].state == .stalking, enemies[i].room != .eastPassage {
            enemies[i].timer = max(0, enemies[i].timer - 1.4)
        }
    }

    private func attack(_ kind: EntityKind) {
        #if DEBUG
        if debugInvincible {
            if let i = enemies.firstIndex(where: { $0.kind == kind }) {
                enemies[i].grace = 12
                enemies[i].threat = 0.3
            }
            return
        }
        #endif
        guard snapshot.phase == .playing else { return }
        snapshot.phase = .dead
        snapshot.killer = kind
        snapshot.deathTime = 0
        snapshot.monitor = false
        snapshot.ventOn = false
        if let i = enemies.firstIndex(where: { $0.kind == kind }) { enemies[i].state = .attacking }
        pendingEvents.append(.attack(kind))
        switch kind {
        case .surveyor: show("THE SURVEYOR / Live observation stops its route. At the west passage, hold the left shutter until the footsteps retreat.", for: 1000)
        case .chorus: show("THE CHORUS / It follows neighboring room speakers and fan noise. Lure it back to the archive or hold the right shutter until it retreats.", for: 1000)
        case .seam: show("THE SEAM / Shutters cannot seal the duct. Purge pressure before it peaks; leave time for the motor to cool.", for: 1000)
        }
    }

    private func win() {
        snapshot.elapsed = snapshot.duration
        snapshot.hour = 6
        snapshot.phase = .victory
        snapshot.monitor = false
        snapshot.leftClosed = false
        snapshot.rightClosed = false
        snapshot.lightOn = false
        snapshot.ventOn = false
        snapshot.alternateEnding = snapshot.secretArmed && !snapshot.blackout
        if snapshot.alternateEnding { discover("ending") }
        show(snapshot.alternateEnding ? "06:00 / RETURN RECEIVED. For the first time, the voice finishes its sentence."
             : "06:00 / The morning relay clicks. Somewhere below, a recorded voice asks you to stay.", for: 1000)
        pendingEvents.append(.victory(snapshot.alternateEnding))
        publishEnemies()
    }

    private func discover(_ id: String, replay: Bool = false) {
        guard !snapshot.discovered.contains(id) else {
            if replay { pendingEvents.append(.discovered(id)) }
            return
        }
        snapshot.discovered.insert(id)
        pendingEvents.append(.discovered(id))
        sound("discovery")
    }

    private func requirePower() -> Bool {
        if snapshot.blackout { show("LOCAL CIRCUIT OFFLINE / wait for the morning relay.", for: 3); return false }
        return true
    }

    private func liveCamera(_ room: Room) -> Bool {
        snapshot.monitor && snapshot.selectedCamera == room && !snapshot.signalLost
            && !snapshot.blackout && snapshot.transition <= 0
    }

    private func publishEnemies() {
        snapshot.entities = enemies.map { enemy in
            let atDoor = (enemy.kind == .surveyor && enemy.room == .westPassage)
                || (enemy.kind == .chorus && enemy.room == .eastPassage)
            let threat: Double
            if enemy.kind == .seam { threat = enemy.threat }
            else if atDoor { threat = clamped(0.55 + (1 - enemy.grace / 12) * 0.45, 0.55, 1) }
            else if enemy.state == .dormant || enemy.state == .retreating { threat = 0 }
            else { threat = enemy.room == .workshop || enemy.room == .resonance ? 0.42 : 0.18 }
            return EntitySnapshot(kind: enemy.kind, room: enemy.room, state: enemy.state,
                                  threat: threat,
                                  progress: enemy.kind == .seam ? enemy.threat : clamped(1 - enemy.timer / max(1, enemy.interval), 0, 1))
        }
    }

    private func neighbors(of room: Room) -> Set<Room> {
        switch room {
        case .intake: return [.gallery, .resonance]
        case .gallery: return [.intake, .workshop]
        case .workshop: return [.gallery, .westPassage]
        case .resonance: return [.intake, .eastPassage, .returnChamber]
        case .westPassage: return [.workshop]
        case .eastPassage: return [.resonance]
        case .duct: return []
        case .returnChamber: return [.resonance]
        }
    }

    private func sound(_ name: String, _ pan: Double = 0) { pendingEvents.append(.sound(name, pan)) }

    private func show(_ text: String, for seconds: Double = 6) {
        snapshot.message = text
        snapshot.messageTime = seconds
        pendingEvents.append(.message(text))
    }

    #if DEBUG
    /// Development-only controls. These symbols are absent from the packaged release.
    func debugSetTime(_ seconds: Double) {
        snapshot.elapsed = clamped(seconds, 0, snapshot.duration)
        snapshot.hour = min(5, Int(snapshot.elapsed / 80))
        lastHour = snapshot.hour
        accumulator = 0
    }

    func debugSetResources(power: Double? = nil, heat: Double? = nil, signal: Double? = nil) {
        if let power = power { snapshot.power = clamped(power, 0, 100) }
        if let heat = heat { snapshot.heat = clamped(heat, 0, 100) }
        if let signal = signal { snapshot.signal = clamped(signal, 0, 100) }
        updateBlackout()
    }

    func debugPlace(_ kind: EntityKind, room: Room, state: AIState = .stalking,
                    moveIn: Double = 20, grace: Double = 12, threat: Double = 0.2) {
        guard let i = enemies.firstIndex(where: { $0.kind == kind }) else { return }
        enemies[i].room = room
        enemies[i].state = state
        enemies[i].timer = moveIn
        enemies[i].interval = max(1, moveIn)
        enemies[i].grace = grace
        enemies[i].threat = clamped(threat, 0, 1)
        enemies[i].blockedFor = 0
        publishEnemies()
    }

    func debugAttack(_ kind: EntityKind) { attack(kind); publishEnemies() }
    #endif
}

private struct Enemy {
    var kind: EntityKind
    var room: Room
    var state: AIState = .dormant
    var timer: Double
    var interval: Double = 30
    var grace: Double = 9
    var blockedFor: Double = 0
    var threat: Double = 0
}

/// SplitMix64 has explicit overflow semantics and reproducible seeds on both Mac CPUs.
private struct NightRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func between(_ a: Double, _ b: Double) -> Double {
        a + Double(next() >> 11) / 9_007_199_254_740_992 * (b - a)
    }
    mutating func integer(_ count: Int) -> Int { Int(next() % UInt64(max(1, count))) }
}

private func clamped(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }

private func countdown(_ value: Double, _ dt: Double) -> Double {
    let next = value - dt
    return next < 0.000001 ? 0 : next
}
