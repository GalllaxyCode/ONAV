import Foundation

enum GamePhase: String, Codable { case menu, briefing, playing, paused, dead, victory, settings, archive }
enum Difficulty: String, Codable, CaseIterable { case standard, overtime }
enum Room: Int, Codable, CaseIterable {
    case intake, gallery, workshop, resonance, westPassage, eastPassage, duct, returnChamber
    var label: String { ["INTAKE HALL", "EXHIBIT GALLERY", "FABRICATION", "RESONANCE ARCHIVE", "WEST PASSAGE", "EAST PASSAGE", "AIR HANDLER", "RETURN CHAMBER"][rawValue] }
    var code: String { ["01", "02", "03", "05", "06", "07", "08", "04"][rawValue] }
    var short: String { ["INTAKE", "GALLERY", "WORKSHOP", "ARCHIVE", "WEST", "EAST", "DUCT", "RETURN"][rawValue] }
}
enum EntityKind: String, Codable, CaseIterable { case surveyor, chorus, seam
    var title: String { switch self { case .surveyor: return "THE SURVEYOR"; case .chorus: return "THE CHORUS"; case .seam: return "THE SEAM" } }
}
enum AIState: String, Codable { case dormant, wandering, watching, stalking, approaching, waiting, attacking, retreating, sabotaging }
struct EntitySnapshot {
    var kind: EntityKind
    var room: Room
    var state: AIState
    var threat: Double
    var progress: Double
}
enum GameAction {
    case toggleMonitor, camera(Room), toggleLeft, toggleRight, toggleLight, toggleVent
    case lure, resetSignal, inspect, enterCode(String), pause, resume
}
enum GameEvent {
    case sound(String, Double)
    case message(String)
    case discovered(String)
    case hour(Int)
    case attack(EntityKind)
    case victory(Bool)
    case defense(String)
}
struct GameSnapshot {
    var phase: GamePhase = .menu
    var difficulty: Difficulty = .standard
    var elapsed: Double = 0
    var duration: Double = 480
    var hour: Int = 0
    var power: Double = 100
    var heat: Double = 12
    var signal: Double = 100
    var monitor: Bool = false
    var selectedCamera: Room = .intake
    var leftClosed: Bool = false
    var rightClosed: Bool = false
    var lightOn: Bool = false
    var ventOn: Bool = false
    var blackout: Bool = false
    var signalLost: Bool = false
    var transition: Double = 0
    var lureCooldown: Double = 0
    var resetCooldown: Double = 0
    var ventLockout: Double = 0
    var load: Double = 1
    var entities: [EntitySnapshot] = []
    var message: String = ""
    var messageTime: Double = 0
    var killer: EntityKind? = nil
    var discovered: Set<String> = []
    var hiddenCameraUnlocked: Bool = false
    var secretArmed: Bool = false
    var alternateEnding: Bool = false
    var anomaly: Int = 0
    var anomalyTime: Double = 0
    var deathTime: Double = 0
    var seed: UInt64 = 1
    var clockText: String {
        let minutes = min(360, Int(elapsed / duration * 360))
        let h = minutes / 60
        return String(format: "%02d:%02d AM", h == 0 ? 12 : h, minutes % 60)
    }
}
struct GameSettings: Codable {
    var masterVolume: Double = 0.75
    var ambienceVolume: Double = 0.65
    var effectsVolume: Double = 0.85
    var sensitivity: Double = 0.65
    var brightness: Double = 1.0
    var graphicsQuality: Int = 1
    var reducedFlashes: Bool = false
    var subtitles: Bool = true
    var fullscreen: Bool = false
}
struct SaveData: Codable {
    var version: Int = 1
    var settings = GameSettings()
    var completedNights: Int = 0
    var overtimeCompleted: Bool = false
    var alternateEnding: Bool = false
    var discovered: Set<String> = []
    var bestPower: Double = 0
}
struct LoreEntry {
    let id: String
    let title: String
    let subtitle: String
    let text: String
}
