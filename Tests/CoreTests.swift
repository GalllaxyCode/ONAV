import Foundation

@main
struct CoreTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !condition() {
            fputs("FAIL: \(description)\n", stderr)
            exit(1)
        }
    }

    static func advance(_ game: GameModel, _ seconds: Double, frame: Double = 0.1) {
        var remaining = seconds
        while remaining > 0.000001 {
            let step = min(frame, remaining)
            game.update(dt: step)
            remaining -= step
        }
    }

    static func quietGame(seed: UInt64 = 17) -> GameModel {
        let game = GameModel(seed: seed)
        game.start(difficulty: .standard)
        for kind in EntityKind.allCases {
            game.debugPlace(kind, room: kind == .seam ? .duct : .intake, state: .dormant, moveIn: 1000)
        }
        _ = game.drainEvents()
        return game
    }

    static func entity(_ kind: EntityKind, _ game: GameModel) -> EntitySnapshot {
        game.snapshot.entities.first { $0.kind == kind }!
    }

    static func main() {
        lifecycleTests()
        cameraTests()
        surveyorTests()
        chorusTests()
        seamTests()
        powerTests()
        loreTests()
        determinismTests()
        balanceTests()
        noisyPlayerTests()
        print("PASS: \(checks) core checks, including 104 complete seeded standard/overtime nights.")
    }

    static func lifecycleTests() {
        let game = GameModel(seed: 9)
        expect(game.snapshot.phase == .menu, "starts at menu")
        game.start(difficulty: .standard)
        expect(game.snapshot.entities.count == 3, "three separate entities")
        expect(game.snapshot.phase == .playing, "start begins active gameplay")
        game.act(.toggleMonitor)
        advance(game, 3)
        game.act(.pause)
        let paused = game.snapshot
        game.act(.toggleLeft)
        advance(game, 15)
        expect(game.snapshot.elapsed == paused.elapsed, "pause freezes clock")
        expect(game.snapshot.power == paused.power, "pause freezes resources")
        expect(!game.snapshot.leftClosed, "paused gameplay actions ignored")
        game.act(.resume)
        advance(game, 1)
        expect(game.snapshot.elapsed > paused.elapsed, "resume advances simulation")
        expect(game.snapshot.monitor, "resume preserves camera mode")
        game.debugAttack(.chorus)
        expect(game.snapshot.phase == .dead && game.snapshot.killer == .chorus, "death identifies attacker")
        game.update(dt: 0.2)
        expect(game.snapshot.deathTime > 0, "death animation has a clock")
        game.start(difficulty: .overtime)
        expect(game.snapshot.elapsed == 0 && game.snapshot.power == 100 && game.snapshot.killer == nil, "restart fully resets run")
        expect(game.snapshot.difficulty == .overtime, "overtime starts")
        game.returnToMenu()
        expect(game.snapshot.phase == .menu, "return to menu")
        advance(game, 3)
        expect(game.snapshot.elapsed == 0, "menu does not simulate")
    }

    static func cameraTests() {
        let game = quietGame()
        game.act(.camera(.gallery))
        expect(game.snapshot.monitor && game.snapshot.selectedCamera == .gallery, "camera shortcut raises selected feed")
        expect(game.snapshot.transition > 0, "camera acquisition is tactile")
        advance(game, 0.4)
        expect(game.snapshot.transition == 0, "feed acquires")
        game.act(.camera(.returnChamber))
        expect(game.snapshot.selectedCamera == .gallery, "hidden room locked")
        game.debugSetResources(signal: 2)
        advance(game, 0.1)
        expect(game.snapshot.signalLost, "low signal loses picture")
        game.act(.resetSignal)
        expect(game.snapshot.signal > 50 && game.snapshot.signalLost, "reset restores signal after intentional outage")
        advance(game, 3.6)
        expect(!game.snapshot.signalLost, "reset reacquires signal")
        let reserve = game.snapshot.power
        game.act(.resetSignal)
        expect(game.snapshot.power == reserve, "reset cooldown prevents repeated charge")
        game.act(.toggleMonitor)
        let signal = game.snapshot.signal
        advance(game, 3)
        expect(game.snapshot.signal > signal, "closed monitor regenerates signal")
        for room in [Room.gallery, .resonance, .gallery, .resonance] { game.act(.camera(room)) }
        expect(game.snapshot.anomaly == 4, "alternating galleries reveals missing-camera anomaly")
    }

    static func surveyorTests() {
        let game = quietGame()
        game.debugPlace(.surveyor, room: .gallery, moveIn: 2)
        game.act(.camera(.gallery))
        advance(game, 10)
        expect(entity(.surveyor, game).room == .gallery && entity(.surveyor, game).state == .watching, "live observation freezes surveyor")
        game.act(.toggleMonitor)
        advance(game, 3)
        expect(entity(.surveyor, game).room == .workshop, "surveyor follows physical gallery-workshop route")
        game.debugPlace(.surveyor, room: .workshop, moveIn: 0.1)
        advance(game, 0.2)
        expect(entity(.surveyor, game).room == .westPassage, "surveyor reaches west passage")
        advance(game, 8)
        expect(game.snapshot.phase == .playing, "west arrival has readable grace")
        game.act(.toggleLeft)
        advance(game, 3.2)
        expect(entity(.surveyor, game).state == .retreating, "left shutter repels surveyor")
        expect(game.snapshot.phase == .playing, "timely shutter prevents attack")
        expect(game.drainEvents().contains { if case .defense("left") = $0 { return true }; return false }, "shutter gives safe-release cue")
        game.act(.toggleLeft)
        game.debugPlace(.surveyor, room: .westPassage, grace: 0.5)
        advance(game, 0.6)
        expect(game.snapshot.phase == .dead && game.snapshot.killer == .surveyor, "open west shutter leads to surveyor attack")
        let failedFeed = quietGame()
        failedFeed.debugPlace(.surveyor, room: .gallery, moveIn: 1)
        failedFeed.act(.camera(.gallery))
        failedFeed.debugSetResources(signal: 0)
        advance(failedFeed, 2)
        expect(entity(.surveyor, failedFeed).room == .workshop, "failed camera cannot freeze surveyor")
    }

    static func chorusTests() {
        let game = quietGame()
        game.debugPlace(.chorus, room: .intake, moveIn: 0.5)
        game.act(.camera(.intake))
        advance(game, 0.7)
        expect(entity(.chorus, game).room == .resonance, "watching does not stop chorus")
        game.act(.camera(.intake))
        advance(game, 0.4)
        game.act(.lure)
        advance(game, 1.2)
        expect(entity(.chorus, game).room == .intake, "adjacent room lure redirects chorus")
        expect(game.snapshot.lureCooldown > 0, "lure has cooldown")
        advance(game, 16)
        game.debugPlace(.chorus, room: .resonance, moveIn: 50)
        game.act(.camera(.workshop))
        advance(game, 0.4)
        game.act(.lure)
        advance(game, 1.2)
        expect(entity(.chorus, game).room == .resonance, "lure cannot teleport across disconnected rooms")
        game.debugPlace(.chorus, room: .eastPassage)
        game.act(.toggleRight)
        advance(game, 3.2)
        expect(entity(.chorus, game).state == .retreating, "right shutter repels chorus")
        game.act(.toggleRight)
        game.act(.toggleLeft)
        game.debugPlace(.chorus, room: .eastPassage, grace: 0.4)
        advance(game, 0.5)
        expect(game.snapshot.killer == .chorus, "wrong shutter does not defend chorus")
        let quiet = quietGame()
        let noisy = quietGame()
        quiet.debugPlace(.chorus, room: .intake, moveIn: 7)
        noisy.debugPlace(.chorus, room: .intake, moveIn: 7)
        noisy.act(.toggleVent)
        advance(quiet, 5)
        advance(noisy, 5)
        expect(entity(.chorus, quiet).room == .intake && entity(.chorus, noisy).room == .resonance, "ventilation acoustics accelerate chorus")
        let nearMove = quietGame()
        nearMove.debugSetTime(410)
        nearMove.debugPlace(.chorus, room: .intake, moveIn: 0.2)
        nearMove.act(.toggleLeft)
        advance(nearMove, 0.3)
        expect(entity(.chorus, nearMove).room == .resonance, "shutter noise cannot postpone an imminent Chorus move")
    }

    static func seamTests() {
        let game = quietGame()
        game.debugPlace(.seam, room: .duct, threat: 0.85)
        game.act(.toggleLeft)
        game.act(.toggleRight)
        game.act(.toggleVent)
        advance(game, 5)
        expect(entity(.seam, game).threat < 0.35, "purge repels seam quickly")
        advance(game, 3.2)
        expect(!game.snapshot.ventOn && game.snapshot.ventLockout > 0, "purge shuts down to cool after eight seconds")
        game.act(.toggleVent)
        expect(!game.snapshot.ventOn, "motor cannot bypass thermal lockout")
        advance(game, 10)
        game.act(.toggleVent)
        expect(game.snapshot.ventOn, "motor restarts after cooldown")
        let attackGame = quietGame()
        attackGame.act(.toggleLeft)
        attackGame.act(.toggleRight)
        attackGame.debugPlace(.seam, room: .duct, grace: 0.3, threat: 1)
        advance(attackGame, 0.4)
        expect(attackGame.snapshot.killer == .seam, "shutters do not protect against seam")
        let cool = quietGame()
        let hot = quietGame()
        cool.debugPlace(.seam, room: .duct, threat: 0.1)
        hot.debugPlace(.seam, room: .duct, threat: 0.1)
        hot.debugSetResources(heat: 90)
        advance(cool, 20)
        advance(hot, 20)
        expect(entity(.seam, hot).threat > entity(.seam, cool).threat + 0.04, "heat affects seam pressure")
        let tinyPulse = quietGame()
        tinyPulse.debugPlace(.seam, room: .duct, grace: 0.2, threat: 1)
        tinyPulse.act(.toggleVent)
        advance(tinyPulse, 1.0 / 30)
        tinyPulse.act(.toggleVent)
        advance(tinyPulse, 3)
        expect(tinyPulse.snapshot.killer == .seam, "single-tick purge cannot reset a full attack grace")
    }

    static func powerTests() {
        let idle = quietGame()
        let loaded = quietGame()
        loaded.act(.toggleLeft)
        loaded.act(.toggleRight)
        loaded.act(.toggleLight)
        loaded.act(.toggleMonitor)
        advance(idle, 30)
        advance(loaded, 30)
        expect(idle.snapshot.power > loaded.snapshot.power + 14, "defenses impose material resource cost")
        expect(loaded.snapshot.heat > idle.snapshot.heat, "closed doors and screens heat room")
        expect(loaded.snapshot.load > 6, "load meter represents real draw")
        loaded.debugSetResources(power: 0.05)
        advance(loaded, 1)
        expect(loaded.snapshot.blackout, "empty power enters blackout")
        expect(!loaded.snapshot.leftClosed && !loaded.snapshot.rightClosed && !loaded.snapshot.monitor && !loaded.snapshot.lightOn, "blackout releases powered devices")
        loaded.act(.toggleLeft)
        expect(!loaded.snapshot.leftClosed, "powered controls unavailable in blackout")
        expect(loaded.snapshot.discovered.contains("blackout"), "backup display clue is recorded")
        let lastMoment = quietGame()
        lastMoment.debugSetTime(478)
        lastMoment.debugSetResources(power: 0)
        advance(lastMoment, 2.1)
        expect(lastMoment.snapshot.phase == .victory, "dawn can arrive during blackout")
    }

    static func loreTests() {
        let game = quietGame()
        game.act(.inspect)
        expect(game.snapshot.discovered.contains("desk"), "office inspection records pass")
        _ = game.drainEvents()
        game.act(.inspect)
        expect(game.drainEvents().contains { if case .discovered("desk") = $0 { return true }; return false }, "repeat inspection reopens archived document")
        expect(game.snapshot.discovered.count == 1, "repeat inspection does not duplicate saved evidence")
        for (room, id) in [(Room.gallery, "gallery"), (.workshop, "maintenance"), (.resonance, "incident")] {
            game.act(.camera(room))
            advance(game, 0.4)
            game.act(.inspect)
            expect(game.snapshot.discovered.contains(id), "camera inspection discovers \(id)")
        }
        game.act(.enterCode("0404"))
        expect(!game.snapshot.hiddenCameraUnlocked, "incorrect code cannot unlock chamber")
        game.act(.enterCode("0417"))
        expect(game.snapshot.hiddenCameraUnlocked && game.snapshot.discovered.contains("return"), "combined missing-room and calls key unlocks hidden camera")
        game.debugSetTime(197.0 / 360 * 480)
        game.act(.camera(.resonance))
        advance(game, 0.4)
        game.act(.inspect)
        expect(game.snapshot.discovered.contains("testimony"), "03:17 archive replay exposes testimony")
        game.act(.camera(.returnChamber))
        advance(game, 0.4)
        game.act(.lure)
        expect(!game.snapshot.secretArmed, "return line cannot arm before four")
        advance(game, 16)
        game.debugSetTime(321)
        game.debugSetResources(power: 50)
        game.act(.lure)
        expect(game.snapshot.secretArmed, "hidden relay arms secret after four with reserve: \(game.snapshot.message), cooldown \(game.snapshot.lureCooldown), lost \(game.snapshot.signalLost)")
        game.debugSetTime(479)
        advance(game, 1.1)
        expect(game.snapshot.phase == .victory && game.snapshot.alternateEnding, "armed return line yields alternate ending at dawn")
        expect(game.snapshot.discovered.contains("ending"), "ending evidence persists")
        let discovered = game.snapshot.discovered
        game.start(difficulty: .standard)
        expect(game.snapshot.discovered == discovered && game.snapshot.hiddenCameraUnlocked, "new attempt preserves archive and unlocked camera")
        expect(!game.snapshot.secretArmed, "new attempt resets return transmission")
        let restored = GameModel(seed: 1, discovered: discovered)
        expect(restored.snapshot.hiddenCameraUnlocked, "saved evidence restores hidden camera")
        let powerFailure = quietGame()
        powerFailure.act(.enterCode("0417"))
        powerFailure.debugSetTime(330)
        powerFailure.act(.camera(.returnChamber))
        advance(powerFailure, 0.4)
        powerFailure.act(.lure)
        powerFailure.debugSetResources(power: 0)
        powerFailure.debugSetTime(479)
        advance(powerFailure, 1.1)
        expect(!powerFailure.snapshot.alternateEnding, "return transmission requires powered circuit until dawn")
    }

    static func determinismTests() {
        let a = GameModel(seed: 9)
        let b = GameModel(seed: 9)
        a.start(difficulty: .standard)
        b.start(difficulty: .standard)
        advance(a, 40, frame: 1.0 / 60)
        advance(b, 40, frame: 0.2)
        expect(abs(a.snapshot.power - b.snapshot.power) < 0.00001, "fixed step makes resources independent of frame rate")
        expect(abs(a.snapshot.elapsed - b.snapshot.elapsed) < 0.00001, "fixed step makes clock independent of frame rate")
        expect(abs(entity(.surveyor, a).progress - entity(.surveyor, b).progress) < 0.00001, "seeded AI deterministic across frame rates")
        let oldSeed = a.snapshot.seed
        a.start(difficulty: .standard)
        expect(a.snapshot.seed != oldSeed, "restart varies seeded playthrough")
        let game = quietGame()
        let power = game.snapshot.power
        game.update(dt: .infinity)
        game.update(dt: .nan)
        game.update(dt: -2)
        expect(game.snapshot.power == power, "invalid deltas cannot corrupt simulation")
    }

    /// A controller reacting to audible passage cues, periodic camera patrols and
    /// the air-handler meter. It does not read hidden AI timers or use invincibility.
    static func balanceTests() {
        var minReserve = 100.0
        var maxReserve = 0.0
        var totalDefenses = 0
        for difficulty in Difficulty.allCases {
            for seed in 1...32 {
                let game = GameModel(seed: UInt64(seed))
                game.start(difficulty: difficulty)
                var nextCamera = 0.0
                var patrol = 0
                var pendingLeft = 0.0
                var pendingRight = 0.0
                let rooms: [Room] = [.gallery, .workshop, .intake, .resonance, .duct]
                while game.snapshot.phase == .playing {
                    let state = game.snapshot
                    for event in game.drainEvents() {
                        switch event {
                        case .sound("surveyor_near", _): pendingLeft = state.elapsed + 2
                        case .sound("chorus_near", _): pendingRight = state.elapsed + 2
                        case .defense("left"):
                            totalDefenses += 1
                            if game.snapshot.leftClosed { game.act(.toggleLeft) }
                        case .defense("right"):
                            totalDefenses += 1
                            if game.snapshot.rightClosed { game.act(.toggleRight) }
                        default: break
                        }
                    }
                    if pendingLeft > 0 && state.elapsed >= pendingLeft {
                        if !game.snapshot.leftClosed { game.act(.toggleLeft) }
                        pendingLeft = 0
                    }
                    if pendingRight > 0 && state.elapsed >= pendingRight {
                        if !game.snapshot.rightClosed { game.act(.toggleRight) }
                        pendingRight = 0
                    }
                    if state.elapsed >= nextCamera {
                        game.act(.camera(rooms[patrol % rooms.count]))
                        patrol += 1
                        nextCamera = state.elapsed + 7
                    }
                    if state.signal < 24 && state.resetCooldown <= 0 { game.act(.resetSignal) }
                    let pressure = entity(.seam, game).threat
                    if pressure > 0.69 && !state.ventOn && state.ventLockout <= 0 { game.act(.toggleVent) }
                    if pressure < 0.13 && state.ventOn { game.act(.toggleVent) }
                    game.update(dt: 0.25)
                }
                expect(game.snapshot.phase == .victory, "cue-based controller survives \(difficulty.rawValue) seed \(seed), killer=\(String(describing: game.snapshot.killer))")
                expect(!game.snapshot.blackout, "efficient defense sustains power for \(difficulty.rawValue) seed \(seed)")
                minReserve = min(minReserve, game.snapshot.power)
                maxReserve = max(maxReserve, game.snapshot.power)
            }
        }
        expect(totalDefenses > 300, "balance simulation exercised repeated real attacks and defenses")
        print(String(format: "BALANCE: 64/64 reactive-policy wins; reserves %.1f–%.1f%%; %d repelled approaches.", minReserve, maxReserve, totalDefenses))
        let unattended = GameModel(seed: 12)
        unattended.start(difficulty: .standard)
        advance(unattended, 200)
        expect(unattended.snapshot.phase == .dead, "unattended player cannot win")
        let turtle = GameModel(seed: 12)
        turtle.start(difficulty: .standard)
        turtle.act(.toggleLeft)
        turtle.act(.toggleRight)
        turtle.act(.toggleLight)
        advance(turtle, 480)
        expect(turtle.snapshot.phase == .dead, "permanent defenses cannot win")
    }
    static func noisyPlayerTests() {
        var wins = 0
        var minPower = 100.0
        var firstDeathMin = 480.0
        var firstDeathMax = 0.0
        for difficulty in Difficulty.allCases {
            for seed in 101...120 {
                let game = GameModel(seed: UInt64(seed))
                game.start(difficulty: difficulty)
                var leftAt = 0.0, rightAt = 0.0, openLeftAt = 0.0, openRightAt = 0.0
                var nextPatrol = 0.0, nextPurge = 0.0, purgeEnds = 0.0
                var patrolIndex = 0
                while game.snapshot.phase == .playing {
                    let s = game.snapshot
                    for event in game.drainEvents() {
                        switch event {
                        case .sound("surveyor_near", _): leftAt = s.elapsed + 5
                        case .sound("chorus_near", _): rightAt = s.elapsed + 5
                        case .defense("left"): openLeftAt = s.elapsed + 5
                        case .defense("right"): openRightAt = s.elapsed + 5
                        default: break
                        }
                    }
                    if leftAt > 0 && s.elapsed >= leftAt {
                        if !game.snapshot.leftClosed { game.act(.toggleLeft) }
                        leftAt = 0
                    }
                    if rightAt > 0 && s.elapsed >= rightAt {
                        if !game.snapshot.rightClosed { game.act(.toggleRight) }
                        rightAt = 0
                    }
                    if openLeftAt > 0 && s.elapsed >= openLeftAt {
                        if game.snapshot.leftClosed { game.act(.toggleLeft) }
                        openLeftAt = 0
                    }
                    if openRightAt > 0 && s.elapsed >= openRightAt {
                        if game.snapshot.rightClosed { game.act(.toggleRight) }
                        openRightAt = 0
                    }
                    if s.elapsed >= nextPatrol {
                        let rooms: [Room] = [.gallery, .workshop, .intake, .resonance, .duct]
                        // Missing every third visit leaves the monitor down for 14s.
                        if patrolIndex % 3 == 2 {
                            if s.monitor { game.act(.toggleMonitor) }
                        } else { game.act(.camera(rooms[patrolIndex % rooms.count])) }
                        patrolIndex += 1
                        nextPatrol = s.elapsed + 14
                        // Forget the doorway lamps on for one patrol every four visits.
                        if patrolIndex % 4 == 0 && !game.snapshot.lightOn { game.act(.toggleLight) }
                        if patrolIndex % 4 == 1 && game.snapshot.lightOn { game.act(.toggleLight) }
                    }
                    if s.signal < 16 && s.resetCooldown <= 0 { game.act(.resetSignal) }
                    if entity(.seam, game).threat >= 0.70 && nextPurge == 0 && !s.ventOn {
                        nextPurge = s.elapsed + 5
                    }
                    if nextPurge > 0 && s.elapsed >= nextPurge && !s.ventOn && s.ventLockout <= 0 {
                        game.act(.toggleVent)
                        purgeEnds = s.elapsed + 2
                        nextPurge = 0
                    }
                    if purgeEnds > 0 && s.elapsed >= purgeEnds {
                        if game.snapshot.ventOn { game.act(.toggleVent) }
                        purgeEnds = 0
                    }
                    game.update(dt: 0.25)
                }
                expect(game.snapshot.phase == .victory, "five-second reactions and short purges survive \(difficulty.rawValue) seed \(seed)")
                if game.snapshot.phase == .victory { wins += 1 }
                minPower = min(minPower, game.snapshot.power)
            }
        }
        for seed in 101...120 {
            let game = GameModel(seed: UInt64(seed))
            game.start(difficulty: .standard)
            while game.snapshot.phase == .playing { game.update(dt: 0.25) }
            firstDeathMin = min(firstDeathMin, game.snapshot.elapsed)
            firstDeathMax = max(firstDeathMax, game.snapshot.elapsed)
            expect(game.snapshot.killer == .surveyor, "first failure teaches first introduced enemy seed \(seed)")
            expect(game.snapshot.elapsed > 80, "first attempt has over80 seconds before possible failure seed \(seed)")
        }
        print(String(format: "NOISY PLAYER: %d/40 wins, minimum reserve %.1f%%; unattended standard first failure %.1f–%.1fs.", wins, minPower, firstDeathMin, firstDeathMax))
    }

}
