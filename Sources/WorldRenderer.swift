import AppKit
import SceneKit
import simd

/// A single SceneKit camera moves between physical sets. The surveillance network never
/// incurs eight simultaneous render passes; distortion and telemetry are supplied by the HUD.
final class WorldRenderer {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let office = SCNNode()
    private var roomRoots: [Room: SCNNode] = [:]
    private var cameraPositions: [Room: SCNVector3] = [:]
    private var cameraTargets: [Room: SCNVector3] = [:]
    private var entityAnchors: [Room: SCNVector3] = [:]
    private var creatures: [EntityKind: SCNNode] = [:]
    private var articulated: [EntityKind: [SCNNode]] = [:]
    private var lights: [(SCNLight, CGFloat, Double)] = []
    private var officeLights: [SCNLight] = []
    private var fan = SCNNode()
    private var leftShutter = SCNNode()
    private var rightShutter = SCNNode()
    private var warningLamps: [SCNMaterial] = []
    private var monitorSurface = SCNMaterial()
    private var inspectionLight = SCNLight()
    private var emergencyLight = SCNLight()
    private var ventRotor = SCNNode()
    private var dust: SCNParticleSystem?
    private var settings = GameSettings()
    private var paint: SCNMaterial!
    private var wall: SCNMaterial!
    private var floor: SCNMaterial!
    private var metal: SCNMaterial!
    private var darkMetal: SCNMaterial!
    private var brass: SCNMaterial!
    private var ceramic: SCNMaterial!
    private var rubber: SCNMaterial!
    private var paper: SCNMaterial!
    private var wood: SCNMaterial!
    private var lastMonitor = false
    private var smoothLookX: Double = 0
    private var smoothLookY: Double = 0

    init() {
        buildMaterials()
        scene.background.contents = NSColor(calibratedRed: 0.005, green: 0.011, blue: 0.014, alpha: 1)
        scene.fogColor = NSColor(calibratedRed: 0.012, green: 0.023, blue: 0.024, alpha: 1)
        scene.fogStartDistance = 5
        scene.fogEndDistance = 25
        scene.fogDensityExponent = 1.7
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.41, alpha: 1)
        ambient.light!.intensity = 125
        scene.rootNode.addChildNode(ambient)
        let camera = SCNCamera()
        camera.fieldOfView = 65
        camera.zNear = 0.035
        camera.zFar = 31
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.35
        camera.bloomIntensity = 0.26
        camera.bloomThreshold = 1.05
        camera.bloomBlurRadius = 5
        camera.vignettingIntensity = 0.42
        camera.vignettingPower = 1.0
        camera.colorFringeIntensity = 0.12
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(office)
        buildOffice()
        for room in Room.allCases { buildRoom(room) }
        for kind in EntityKind.allCases {
            let node: SCNNode
            switch kind {
            case .surveyor: node = buildSurveyor()
            case .chorus: node = buildChorus()
            case .seam: node = buildSeam()
            }
            creatures[kind] = node
            scene.rootNode.addChildNode(node)
        }
        createDust()
        update(GameSnapshot(), time: 0, lookX: 0, lookY: 0)
    }

    func apply(settings: GameSettings) {
        self.settings = settings
        cameraNode.camera?.exposureOffset = settings.brightness - 0.65
        cameraNode.camera?.bloomIntensity = settings.graphicsQuality == 0 ? 0 : 0.26
        for (light, _, _) in lights {
            light.shadowMapSize = CGSize(width: settings.graphicsQuality > 1 ? 1536 : 1024,
                                         height: settings.graphicsQuality > 1 ? 1536 : 1024)
            light.shadowSampleCount = settings.graphicsQuality > 1 ? 8 : 4
        }
        dust?.birthRate = settings.graphicsQuality == 0 ? 3 : 12
    }

    func update(_ snapshot: GameSnapshot, time: Double, lookX: Double, lookY: Double) {
        let remote = snapshot.monitor && (snapshot.phase == .playing || snapshot.phase == .paused)
        office.isHidden = remote
        for (room, root) in roomRoots { root.isHidden = !remote || room != snapshot.selectedCamera }
        smoothLookX += (lookX - smoothLookX) * 0.10
        smoothLookY += (lookY - smoothLookY) * 0.10
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        if remote, let pos = cameraPositions[snapshot.selectedCamera], let target = cameraTargets[snapshot.selectedCamera] {
            let jitter = settings.reducedFlashes ? 0 : sin((time * 18).rounded(.down) * 8.43) * 0.0012
            cameraNode.position = SCNVector3(pos.x + CGFloat(jitter), pos.y, pos.z)
            cameraNode.look(at: target)
            cameraNode.camera?.fieldOfView = snapshot.selectedCamera == .duct ? 78 : 70
            scene.fogStartDistance = 3
            scene.fogEndDistance = snapshot.selectedCamera == .duct ? 13 : 23
        } else {
            cameraNode.position = SCNVector3(CGFloat(smoothLookX * 0.06), 1.62 + CGFloat(smoothLookY * 0.025), 3.65)
            cameraNode.look(at: SCNVector3(CGFloat(smoothLookX * 1.35), 1.48 + CGFloat(smoothLookY * 0.85), -4))
            cameraNode.camera?.fieldOfView = 65
            scene.fogStartDistance = 7
            scene.fogEndDistance = 25
        }
        // Physical shutter descent is quick enough to match the engine's immediate protection.
        let ly: CGFloat = snapshot.leftClosed ? 1.38 : 4.13
        let ry: CGFloat = snapshot.rightClosed ? 1.38 : 4.13
        leftShutter.position.y += (ly - leftShutter.position.y) * 0.25
        rightShutter.position.y += (ry - rightShutter.position.y) * 0.25
        fan.eulerAngles.z = CGFloat(time * (snapshot.blackout ? 0.4 : 13))
        ventRotor.eulerAngles.z = CGFloat(time * (snapshot.ventOn ? 27 : 2))
        inspectionLight.intensity = snapshot.lightOn && !snapshot.blackout ? 1500 : 0
        emergencyLight.intensity = snapshot.blackout ? (75 + 20 * sin(time * 0.55)) : 14
        monitorSurface.emission.intensity = snapshot.blackout ? 0.04 : (remote ? 1.4 : 0.75)
        for (index, item) in lights.enumerated() {
            let (light, base, phase) = item
            let subtle = 0.97 + 0.025 * sin(time * 19 + phase) + 0.012 * sin(time * 61 + phase)
            let dip = !settings.reducedFlashes && sin(time * 0.79 + phase) > 0.995 ? 0.60 : 1.0
            let isOffice = officeLights.contains { $0 === light }
            let off = snapshot.blackout && isOffice
            light.intensity = off ? 0 : base * subtle * dip
            if index > 100 { break }
        }
        if warningLamps.count == 3 {
            warningLamps[0].emission.contents = snapshot.leftClosed ? NSColor.orange : NSColor(calibratedRed: 0.05, green: 0.75, blue: 0.54, alpha: 1)
            warningLamps[1].emission.contents = snapshot.rightClosed ? NSColor.orange : NSColor(calibratedRed: 0.05, green: 0.75, blue: 0.54, alpha: 1)
            warningLamps[2].emission.contents = snapshot.ventOn ? NSColor.cyan : NSColor(calibratedRed: 0.25, green: 0.08, blue: 0.035, alpha: 1)
        }
        for kind in EntityKind.allCases {
            guard let creature = creatures[kind] else { continue }
            creature.isHidden = true
            creature.scale = SCNVector3(1, 1, 1)
            guard let entity = snapshot.entities.first(where: { $0.kind == kind }) else { continue }
            creature.eulerAngles = SCNVector3Zero
            if remote {
                if entity.room == snapshot.selectedCamera, entity.state != .dormant,
                   let anchor = entityAnchors[entity.room] {
                    creature.isHidden = false
                    creature.position = anchor
                    creature.eulerAngles.y = CGFloat(sin(time * 0.14 + Double(kind == .surveyor ? 0 : 2)) * 0.15)
                }
            } else if snapshot.phase == .dead, snapshot.killer == kind {
                creature.isHidden = false
                let t = min(1, snapshot.deathTime / 0.6)
                creature.position = SCNVector3(0, kind == .seam ? 0.85 : -0.45, CGFloat(1.0 + t * 1.05))
                creature.eulerAngles.z = CGFloat(sin(time * 23) * (settings.reducedFlashes ? 0.015 : 0.05))
                if kind == .seam { creature.eulerAngles.x = -.pi / 2.5 }
            } else if entity.state == .waiting || entity.state == .approaching || entity.state == .attacking {
                if kind == .surveyor && entity.room == .westPassage {
                    creature.isHidden = false
                    creature.position = SCNVector3(-3.23, 0, -5.7 + CGFloat(entity.threat) * 0.7)
                } else if kind == .chorus && entity.room == .eastPassage {
                    creature.isHidden = false
                    creature.position = SCNVector3(3.23, 0, -5.6 + CGFloat(entity.threat) * 0.6)
                } else if kind == .seam && entity.threat > 0.55 {
                    creature.isHidden = false
                    creature.position = SCNVector3(0, 3.00, -3.95)
                    creature.eulerAngles.x = .pi / 2
                    creature.scale = SCNVector3(0.65, 0.65, 0.65)
                }
            }
            if !creature.isHidden {
                animateCreature(kind, time: time, threat: entity.threat)
            }
        }
        if snapshot.phase == .menu || snapshot.phase == .briefing {
            cameraNode.position.x = CGFloat(sin(time * 0.10) * 0.08)
        }
        lastMonitor = remote
        SCNTransaction.commit()
    }

    private func buildMaterials() {
        paint = textured("paint", base: (0.18, 0.28, 0.27), metallic: 0.40, rough: 0.76)
        wall = textured("plaster", base: (0.35, 0.37, 0.32), metallic: 0, rough: 0.98)
        floor = textured("floor", base: (0.20, 0.24, 0.23), metallic: 0.16, rough: 0.84)
        metal = textured("steel", base: (0.31, 0.36, 0.34), metallic: 0.80, rough: 0.48)
        darkMetal = textured("iron", base: (0.075, 0.09, 0.088), metallic: 0.73, rough: 0.65)
        brass = textured("brass", base: (0.47, 0.32, 0.13), metallic: 0.77, rough: 0.44)
        ceramic = textured("ceramic", base: (0.71, 0.70, 0.57), metallic: 0.05, rough: 0.51)
        rubber = textured("rubber", base: (0.032, 0.038, 0.038), metallic: 0, rough: 0.97)
        paper = textured("paper", base: (0.58, 0.54, 0.39), metallic: 0, rough: 1)
        wood = textured("wood", base: (0.25, 0.13, 0.064), metallic: 0, rough: 0.7)
    }

    private func textured(_ key: String, base: (Double, Double, Double), metallic: CGFloat, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = key
        m.lightingModel = .physicallyBased
        m.diffuse.contents = makeTexture(key, base: base)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.roughness.contents = rough
        m.metalness.contents = metallic
        m.normal.contents = makeNormalTexture(seed: key.count)
        m.normal.intensity = key == "plaster" ? 0.4 : 0.16
        m.normal.wrapS = .repeat
        m.normal.wrapT = .repeat
        return m
    }

    private func solid(_ color: NSColor, emission: CGFloat = 0, metallic: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = 0.65
        m.metalness.contents = metallic
        if emission > 0 { m.emission.contents = color; m.emission.intensity = emission }
        return m
    }

    private func makeTexture(_ key: String, base: (Double, Double, Double)) -> NSImage {
        let n = 512
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        var state: UInt64 = UInt64(key.utf8.reduce(17) { $0 + Int($1) })
        func random() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        for y in 0..<n {
            for x in 0..<n {
                let xf = Double(x), yf = Double(y)
                let grain = (random() - 0.5) * (key == "plaster" ? 0.28 : 0.13)
                let patch = sin(xf * 0.031 + sin(yf * 0.027) * 2.1) * sin(yf * 0.037 + cos(xf * 0.019))
                let stain = max(0, sin(xf * 0.047 + sin(yf * 0.014))) * max(0, sin(yf * 0.020 + 0.8))
                var f = 0.79 + grain + patch * 0.13 - stain * 0.22
                if key == "wood" { f += sin(yf * 0.3 + sin(xf * 0.02) * 2) * 0.12 }
                if key == "steel" || key == "iron" || key == "paint" {
                    f += sin(yf * 2.7) * 0.027
                    if random() > 0.998 { f = 1.7 }
                }
                if key == "floor" && (x % 128 < 3 || y % 128 < 3) { f *= 0.30 }
                let rust = (key == "paint" || key == "steel" || key == "iron") ? max(0, patch - 0.24) * 0.33 : 0
                let p = (y * n + x) * 4
                let values = [base.0 * f + rust * 0.14, base.1 * f * (1-rust*0.5), base.2 * f * (1-rust*0.8)]
                for c in 0..<3 { data[p + c] = UInt8(max(0, min(255, values[c] * 255))) }
                data[p + 3] = 255
            }
        }
        let image = NSImage(size: NSSize(width: n, height: n))
        image.addRepresentation(rep)
        return image
    }

    private func makeNormalTexture(seed: Int) -> NSImage {
        let n = 128
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        for y in 0..<n { for x in 0..<n {
            let p = (y * n + x) * 4
            data[p] = UInt8(128 + Int(sin(Double(x * 43 + y * 17 + seed)) * 17))
            data[p + 1] = UInt8(128 + Int(cos(Double(x * 19 + y * 47 + seed)) * 17))
            data[p + 2] = 249; data[p + 3] = 255
        } }
        let image = NSImage(size: NSSize(width: n, height: n)); image.addRepresentation(rep)
        return image
    }

    @discardableResult private func box(_ parent: SCNNode, _ size: (CGFloat, CGFloat, CGFloat), _ position: (CGFloat, CGFloat, CGFloat), _ material: SCNMaterial, bevel: CGFloat = 0.015) -> SCNNode {
        let g = SCNBox(width: size.0, height: size.1, length: size.2, chamferRadius: bevel)
        g.chamferSegmentCount = bevel > 0 ? 2 : 1
        if material.name != nil && max(size.0, size.1, size.2) > 2 {
            let texturedMaterial = material.copy() as! SCNMaterial
            let lengths = [size.0,size.1,size.2].sorted(by: >)
            let transform = SCNMatrix4MakeScale(lengths[0]/1.6, lengths[1]/1.6, 1)
            texturedMaterial.diffuse.contentsTransform = transform
            texturedMaterial.normal.contentsTransform = transform
            g.materials = [texturedMaterial]
        } else { g.materials = [material] }
        let node = SCNNode(geometry: g); node.position = SCNVector3(position.0, position.1, position.2)
        parent.addChildNode(node); return node
    }

    @discardableResult private func cylinder(_ parent: SCNNode, radius: CGFloat, height: CGFloat, at p: SCNVector3, material: SCNMaterial, axis: String = "y", segments: Int = 16) -> SCNNode {
        let g = SCNCylinder(radius: radius, height: height); g.radialSegmentCount = segments; g.heightSegmentCount = 1; g.materials = [material]
        let node = SCNNode(geometry: g); node.position = p
        if axis == "z" { node.eulerAngles.x = .pi / 2 }
        if axis == "x" { node.eulerAngles.z = .pi / 2 }
        parent.addChildNode(node); return node
    }

    @discardableResult private func sphere(_ parent: SCNNode, radius: CGFloat, at p: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1), material: SCNMaterial) -> SCNNode {
        let g = SCNSphere(radius: radius); g.segmentCount = 20; g.materials = [material]
        let node = SCNNode(geometry: g); node.position = p; node.scale = scale; parent.addChildNode(node); return node
    }

    private func rod(_ parent: SCNNode, from a: SCNVector3, to b: SCNVector3, radius: CGFloat, material: SCNMaterial) {
        let delta = SIMD3<Float>(Float(b.x - a.x), Float(b.y - a.y), Float(b.z - a.z))
        let len = simd_length(delta)
        let node = cylinder(parent, radius: radius, height: CGFloat(len), at: SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2), material: material, segments: 8)
        if len > 0.0001 { node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: delta / len) }
    }

    private func cable(_ parent: SCNNode, points: [SCNVector3], radius: CGFloat = 0.015, material: SCNMaterial? = nil) {
        guard points.count > 1 else { return }
        for i in 1..<points.count { rod(parent, from: points[i - 1], to: points[i], radius: radius, material: material ?? rubber) }
    }

    private func torus(_ parent: SCNNode, ring: CGFloat, pipe: CGFloat, at p: SCNVector3, material: SCNMaterial, facing: Bool = true) -> SCNNode {
        let g = SCNTorus(ringRadius: ring, pipeRadius: pipe); g.ringSegmentCount = 28; g.pipeSegmentCount = 8; g.materials = [material]
        let node = SCNNode(geometry: g); node.position = p
        if facing { node.eulerAngles.x = .pi / 2 }
        parent.addChildNode(node); return node
    }

    private func sign(_ parent: SCNNode, text: String, width: CGFloat, height: CGFloat, at p: SCNVector3, color: NSColor = NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.63, alpha: 1), background: NSColor = NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.10, alpha: 1), emission: CGFloat = 0) -> SCNNode {
        let pixels = NSSize(width: width * 300, height: height * 300)
        let image = NSImage(size: pixels)
        image.lockFocus()
        background.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: pixels)).fill()
        color.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(rect: NSRect(x: 5, y: 5, width: pixels.width - 10, height: pixels.height - 10)); border.lineWidth = 2; border.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let lines = text.components(separatedBy: "\n").count
        let longest = CGFloat(text.components(separatedBy: "\n").map(\.count).max() ?? 1)
        let fontSize = min((pixels.height - 20) / CGFloat(lines) * 0.76, pixels.width / max(1, longest) * 1.46)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph]
        let str = NSAttributedString(string: text, attributes: attrs)
        let h = str.boundingRect(with: NSSize(width: pixels.width - 18, height: 1000), options: [.usesLineFragmentOrigin]).height
        str.draw(in: NSRect(x: 9, y: (pixels.height - h) / 2, width: pixels.width - 18, height: h + 2))
        // Age is applied to each sign instead of a uniform clean graphic treatment.
        for i in 0..<13 {
            let x = CGFloat((i * 83 + 19) % max(1, Int(pixels.width)))
            background.withAlphaComponent(0.15).setFill()
            NSBezierPath(rect: NSRect(x: x, y: CGFloat((i * 71) % max(1, Int(pixels.height))), width: CGFloat(3 + i % 5), height: 1)).fill()
        }
        image.unlockFocus()
        let m = SCNMaterial(); m.diffuse.contents = image; m.roughness.contents = 0.85
        if emission > 0 { m.emission.contents = image; m.emission.intensity = emission }
        let node = box(parent, (width, height, 0.012), (p.x,p.y,p.z), m, bevel: 0.004)
        return node
    }

    private func spot(_ parent: SCNNode, at p: SCNVector3, target: SCNVector3, color: NSColor, intensity: CGFloat, cone: CGFloat = 90, shadows: Bool = true, isOffice: Bool = false, phase: Double = 0) -> SCNLight {
        let node = SCNNode(); node.position = p
        let light = SCNLight(); light.type = .spot; light.color = color; light.intensity = intensity
        light.spotInnerAngle = cone * 0.55; light.spotOuterAngle = cone
        light.attenuationStartDistance = 0.4; light.attenuationEndDistance = 14
        light.castsShadow = shadows; light.shadowColor = NSColor(white: 0, alpha: 0.78)
        light.shadowRadius = 4; light.shadowBias = 1.2; light.shadowMapSize = CGSize(width: 1024, height: 1024)
        light.shadowMode = .deferred; light.shadowSampleCount = 4
        node.light = light; parent.addChildNode(node); node.look(at: parent.convertPosition(target, to: nil))
        lights.append((light, intensity, phase))
        if isOffice { officeLights.append(light) }
        return light
    }

    private func omni(_ parent: SCNNode, at p: SCNVector3, color: NSColor, intensity: CGFloat, range: CGFloat = 5) -> SCNLight {
        let n = SCNNode(); n.position = p; let l = SCNLight(); l.type = .omni; l.color = color; l.intensity = intensity
        l.attenuationStartDistance = 0.1; l.attenuationEndDistance = range; n.light = l; parent.addChildNode(n); return l
    }

    private func fluorescent(_ parent: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat, length: CGFloat = 2, office: Bool = false, warm: Bool = false, phase: Double = 0) {
        box(parent, (length + 0.16, 0.08, 0.29), (x,y,z), darkMetal)
        let glow = solid(warm ? NSColor(calibratedRed: 0.88, green: 0.57, blue: 0.26, alpha: 1) : NSColor(calibratedRed: 0.52, green: 0.82, blue: 0.73, alpha: 1), emission: 2)
        for d: CGFloat in [-0.075, 0.075] { cylinder(parent, radius: 0.028, height: length, at: SCNVector3(x,y-0.06,z+d), material: glow, axis: "x") }
        _ = spot(parent, at: SCNVector3(x,y-0.12,z), target: SCNVector3(x,0,z-0.7), color: warm ? NSColor(calibratedRed: 1, green: 0.62, blue: 0.32, alpha: 1) : NSColor(calibratedRed: 0.57, green: 0.84, blue: 0.76, alpha: 1), intensity: office ? 750 : 920, cone: 115, isOffice: office, phase: phase)
    }

    private func createDust() {
        let p = SCNParticleSystem(); p.birthRate = 12; p.particleLifeSpan = 13; p.particleLifeSpanVariation = 4
        p.particleSize = 0.009; p.particleSizeVariation = 0.006; p.particleColor = NSColor(calibratedRed: 0.54, green: 0.61, blue: 0.57, alpha: 0.27)
        p.particleVelocity = 0.025; p.particleVelocityVariation = 0.017; p.spreadingAngle = 180
        p.emitterShape = SCNBox(width: 7, height: 2, length: 6, chamferRadius: 0)
        p.acceleration = SCNVector3(0.002,-0.003,0); p.blendMode = .alpha; p.isLightingEnabled = true
        let emitter = SCNNode(); emitter.position = SCNVector3(0,1.7,-0.5); emitter.addParticleSystem(p); office.addChildNode(emitter); dust = p
    }

    private func buildOffice() {
        box(office, (9,0.18,13), (0,-0.12,-1.8), floor)
        box(office, (9,0.18,9), (0,3.65,-0.8), darkMetal)
        for x: CGFloat in [-4.55,4.55] {
            box(office, (0.18,3.7,9), (x,1.78,-0.8), wall)
            box(office, (0.20,1.25,9), (x,0.61,-0.8), paint)
            box(office, (0.23,0.05,9), (x,1.28,-0.8), brass)
        }
        // The wall is genuinely open behind each door, with deep hallways beyond it.
        box(office, (4.8,3.65,0.24), (0,1.77,-4.35), wall)
        box(office, (4.85,1.28,0.27), (0,0.62,-4.31), paint)
        box(office, (4.9,0.06,0.29), (0,1.28,-4.29), brass)
        box(office, (9,0.80,0.3), (0,3.25,-4.35), darkMetal)
        for x: CGFloat in [-4.28,4.28] { box(office, (0.56,3.65,0.3), (x,1.77,-4.35), paint) }
        for side: CGFloat in [-1,1] {
            let x = side * 3.25
            for edge: CGFloat in [-0.87,0.87] {
                box(office, (0.12,2.85,0.43), (x+edge,1.40,-4.17), metal)
                box(office, (0.052,2.65,0.052), (x+edge-side*0.04,1.34,-3.94), brass)
            }
            box(office, (1.95,0.14,0.45), (x,2.81,-4.17), metal)
            box(office, (1.8,0.05,4.8), (x,0.015,-6.4), darkMetal)
            for edge: CGFloat in [-1,1] { box(office, (0.12,3,5), (x+edge,1.5,-6.6), paint) }
            box(office, (2,3,0.1), (x,1.5,-9), darkMetal)
            for zz: CGFloat in [-5.5,-7.5] {
                box(office, (2,0.08,0.11), (x,2.65,zz), metal)
                cylinder(office, radius: 0.045, height: 2.4, at: SCNVector3(x + side*0.84,1.3,zz), material: brass)
            }
            let shutter = SCNNode(); shutter.position = SCNVector3(x,4.13,-4.27); office.addChildNode(shutter)
            box(shutter, (1.65,2.75,0.10), (0,0,0), metal)
            for i in 0..<22 { box(shutter, (1.66,0.025,0.028), (0,CGFloat(i)*0.123-1.28,0.065), darkMetal, bevel: 0.002) }
            box(shutter, (1.72,0.1,0.18), (0,-1.35,0.015), darkMetal)
            _ = sign(shutter, text: side < 0 ? "W-06\nISOLATION GATE" : "E-07\nISOLATION GATE", width: 0.85, height: 0.28, at: SCNVector3(0,0.4,0.065))
            if side < 0 { leftShutter = shutter } else { rightShutter = shutter }
            _ = sign(office, text: side < 0 ? "WEST ACCESS / 06" : "EAST ACCESS / 07", width: 1.8, height: 0.23, at: SCNVector3(x,2.98,-4.14), color: .init(calibratedRed: 0.76, green: 0.64, blue: 0.39, alpha: 1))
            let lm = solid(.systemGreen, emission: 1.4); warningLamps.append(lm)
            box(office, (0.16,0.34,0.13), (x-side*1.08,1.37,-4.08), darkMetal)
            sphere(office, radius: 0.046, at: SCNVector3(x-side*1.08,1.45,-3.99), scale: SCNVector3(1,1,0.35), material: lm)
            sphere(office, radius: 0.046, at: SCNVector3(x-side*1.08,1.29,-3.99), scale: SCNVector3(1,1,0.35), material: solid(.init(calibratedRed: 0.22,green: 0.05,blue: 0.025,alpha: 1)))
            _ = spot(office, at: SCNVector3(x,2.55,-5.4), target: SCNVector3(x,0.8,-4.3), color: NSColor(calibratedRed: 0.49, green: 0.68, blue: 0.56, alpha: 1), intensity: 110, cone: 72, shadows: false, isOffice: true, phase: Double(side)*2)
        }
        // Exposed services span the room, with mismatched supports and a hanging repair loop.
        for (i,x) in [-3.8, -3.52, 2.9, 3.25].enumerated() {
            cylinder(office, radius: i < 2 ? 0.07 : 0.11, height: 9.0, at: SCNVector3(CGFloat(x),3.35,-0.8), material: i % 2 == 0 ? brass : metal, axis: "z")
            for z: CGFloat in [-3,-0.2,2.2] {
                box(office, (0.26,0.05,0.08), (CGFloat(x),3.24,z), darkMetal)
                rod(office, from: SCNVector3(CGFloat(x),3.4,z), to: SCNVector3(CGFloat(x),3.63,z), radius: 0.015, material: darkMetal)
            }
        }
        for i in 0..<4 {
            cable(office, points: [SCNVector3(-2.3+CGFloat(i)*0.06,3.45,-4),SCNVector3(-1.8+CGFloat(i)*0.08,3.04,-2.8),SCNVector3(-1.55+CGFloat(i)*0.09,2.9,-1.6),SCNVector3(-1.7+CGFloat(i)*0.08,3.35,0.6)])
        }
        fluorescent(office, x: -0.6, y: 3.40, z: -0.8, length: 2.5, office: true, phase: 0)
        fluorescent(office, x: 2.9, y: 3.39, z: 1.9, length: 1.1, office: true, warm: true, phase: 3.8)
        let reflectedOffice = omni(office, at: SCNVector3(0,2.5,-3.15), color: NSColor(calibratedRed:0.47,green:0.63,blue:0.55,alpha:1), intensity: 100, range: 8)
        lights.append((reflectedOffice,100,5)); officeLights.append(reflectedOffice)
        _ = sign(office, text: "M O R R O W\nL I S T E N I N G   I N S T I T U T E", width: 2.78, height: 0.49, at: SCNVector3(-0.10,2.53,-4.16), color: NSColor(calibratedRed: 0.70, green: 0.66, blue: 0.48, alpha: 1))
        _ = sign(office, text: "NIGHT OPERATIONS\nDO NOT ACKNOWLEDGE UNVERIFIED VOICES", width: 2.55, height: 0.34, at: SCNVector3(0,1.93,-4.15))
        buildDesk()
        buildVent()
        buildBreaker()
        // Ceiling-mounted flood illuminates both thresholds only while the player's light is held.
        let inspection = SCNNode(); inspection.position = SCNVector3(0,2.7,1.1); inspection.light = inspectionLight
        inspectionLight.type = .spot; inspectionLight.color = NSColor(calibratedRed: 0.94, green: 0.79, blue: 0.55, alpha: 1)
        inspectionLight.spotInnerAngle = 58; inspectionLight.spotOuterAngle = 100
        inspectionLight.attenuationEndDistance = 15; inspectionLight.castsShadow = true
        inspectionLight.shadowMapSize = CGSize(width: 1024,height: 1024); inspectionLight.shadowRadius = 3
        office.addChildNode(inspection); inspection.look(at: SCNVector3(0,1.15,-5.5))
        let e = SCNNode(); e.position = SCNVector3(0,2.65,-3.6); e.light = emergencyLight
        emergencyLight.type = .omni; emergencyLight.color = NSColor(calibratedRed: 0.82, green: 0.10, blue: 0.03, alpha: 1)
        emergencyLight.attenuationEndDistance = 8; office.addChildNode(e)
        // Mess on the floor, from real geometry instead of isolated empty room planes.
        for i in 0..<11 {
            let sheet = box(office, (0.21,0.003,0.28), (CGFloat(sin(Double(i)*5.17))*3.8,0.002,CGFloat(cos(Double(i)*3.71))*2.6-1), paper, bevel: 0)
            sheet.eulerAngles.y = CGFloat(i) * 1.18
        }
        for i in 0..<4 {
            cable(office, points: [SCNVector3(-1.4+CGFloat(i)*0.07,0.6,-1.3),SCNVector3(-1.9+CGFloat(i)*0.10,0.05,-1.6),SCNVector3(-2.3+CGFloat(i)*0.12,0.02,-0.9),SCNVector3(-2.6+CGFloat(i)*0.08,0.02,0.1),SCNVector3(-4.3,0.04,0.8+CGFloat(i)*0.08)], radius: 0.012)
        }
        cylinder(office, radius: 0.25, height: 0.47, at: SCNVector3(2.62,0.23,-0.9), material: darkMetal)
        _ = torus(office, ring: 0.25, pipe: 0.015, at: SCNVector3(2.62,0.47,-0.9), material: metal, facing: false)
        for i in 0..<7 { sphere(office, radius: 0.075, at: SCNVector3(2.62+CGFloat(sin(Double(i)*2))*0.14,0.46, -0.9+CGFloat(cos(Double(i)*2))*0.12), scale: SCNVector3(1,0.6,1), material: paper) }
    }

    private func buildDesk() {
        box(office, (4.8,0.11,1.65), (0,0.77,-1.31), paint, bevel: 0.04)
        box(office, (4.75,0.065,0.06), (0,0.78,-0.47), metal)
        for x: CGFloat in [-2.05,2.05] {
            box(office, (0.55,0.72,1.35), (x,0.35,-1.34), darkMetal)
            for i in 0..<3 {
                box(office, (0.5,0.19,0.035), (x,0.16+CGFloat(i)*0.21,-0.642), paint)
                box(office, (0.14,0.016,0.035), (x,0.20+CGFloat(i)*0.21,-0.609), metal)
            }
        }
        // CRT case has a deep curved screen, bezel, glass sheen, feet, dials and rear vents.
        let crt = SCNNode(); crt.position = SCNVector3(-0.80,0.83,-1.54); office.addChildNode(crt)
        box(crt, (1.48,1.02,0.88), (0,0.56,-0.17), darkMetal, bevel: 0.11)
        box(crt, (1.39,0.95,0.10), (0,0.56,0.27), paint, bevel: 0.075)
        box(crt, (1.10,0.74,0.06), (-0.09,0.59,0.335), rubber, bevel: 0.065)
        monitorSurface = solid(NSColor(calibratedRed: 0.052, green: 0.28, blue: 0.23, alpha: 1), emission: 1)
        monitorSurface.roughness.contents = 0.18; monitorSurface.metalness.contents = 0.15
        box(crt, (0.99,0.63,0.057), (-0.09,0.60,0.372), monitorSurface, bevel: 0.075)
        _ = sign(crt, text: "M L I   /   NIGHT RELAY\n\n● STANDBY\n\n[ SPACE ] CONNECT", width: 0.89, height: 0.52, at: SCNVector3(-0.09,0.60,0.405), color: NSColor(calibratedRed: 0.36, green: 0.72, blue: 0.55, alpha: 1), background: NSColor(calibratedRed: 0.01, green: 0.046, blue: 0.035, alpha: 1), emission: 0.7)
        for y: CGFloat in [0.47,0.68] {
            cylinder(crt, radius: 0.063, height: 0.055, at: SCNVector3(0.566,y,0.37), material: rubber, axis: "z")
            box(crt, (0.009,0.045,0.004), (0.566,y,0.401), paper)
        }
        for i in 0..<7 { box(crt, (0.13,0.009,0.025), (0.564,0.26+CGFloat(i)*0.021,0.33), rubber) }
        sphere(crt, radius: 0.017, at: SCNVector3(0.567,0.79,0.34), material: solid(.systemGreen, emission: 2))
        for x: CGFloat in [-0.48,0.48] { box(crt, (0.19,0.09,0.33), (x,0.02,-0.01), rubber) }
        let screenGlow = omni(office, at: SCNVector3(-0.8,1.45,-0.95), color: NSColor(calibratedRed: 0.10,green: 0.56,blue: 0.38,alpha: 1), intensity: 58, range: 3)
        lights.append((screenGlow,58,8)); officeLights.append(screenGlow)
        // Relay switchboard on an inclined panel below the monitor.
        let console = SCNNode(); console.position = SCNVector3(-0.7,0.88,-0.57); console.eulerAngles.x = -.pi/9; office.addChildNode(console)
        box(console, (1.83,0.095,0.46), (0,0,0), darkMetal)
        for row in 0..<3 { for col in 0..<12 {
            box(console, (0.102,0.034,0.071), (-0.68+CGFloat(col)*0.122,0.061,-0.14+CGFloat(row)*0.106), col == 11 ? brass : ceramic, bevel: 0.008)
        } }
        // Clipboard bearing the first clue, with a normal legible header on a worn sheet.
        let clipboard = SCNNode(); clipboard.position = SCNVector3(0.85,0.837,-0.96); clipboard.eulerAngles.x = -.pi/2; clipboard.eulerAngles.z = -0.13; office.addChildNode(clipboard)
        box(clipboard, (0.50,0.69,0.018), (0,0,0), wood)
        _ = sign(clipboard, text: "M. VALE\nTEMPORARY ACCESS\n\nRETURN ALL VOICES\nTO THEIR OWNERS.\n\n04 / seventeen calls\n\n[ E ] EXAMINE", width: 0.43, height: 0.61, at: SCNVector3(0,-0.014,0.015), color: .init(calibratedWhite: 0.13,alpha: 1), background: .init(calibratedRed: 0.65,green: 0.61,blue: 0.45,alpha: 1))
        box(clipboard, (0.21,0.053,0.035), (0,0.30,0.027), metal)
        // A reel recorder and a handset echo the institute's original machinery.
        box(office, (0.74,0.19,0.49), (1.48,0.90,-1.70), darkMetal)
        for x: CGFloat in [1.29,1.64] {
            cylinder(office, radius: 0.14, height: 0.028, at: SCNVector3(x,1.015,-1.74), material: metal)
            cylinder(office, radius: 0.085, height: 0.032, at: SCNVector3(x,1.022,-1.74), material: rubber)
            cylinder(office, radius: 0.016, height: 0.037, at: SCNVector3(x,1.028,-1.74), material: brass)
        }
        for i in 0..<4 { box(office, (0.082,0.018,0.10), (1.28+CGFloat(i)*0.13,1.006,-1.52), i == 0 ? brass : ceramic) }
        buildFan(office, at: SCNVector3(-1.98,0.84,-1.43))
        cylinder(office, radius: 0.09, height: 0.16, at: SCNVector3(0.49,0.91,-1.81), material: ceramic)
        _ = torus(office, ring: 0.065, pipe: 0.017, at: SCNVector3(0.603,0.92,-1.81), material: ceramic)
        cylinder(office, radius: 0.076, height: 0.004, at: SCNVector3(0.49,0.995,-1.81), material: rubber)
        rod(office, from: SCNVector3(0.19,0.842,-0.80), to: SCNVector3(0.42,0.842,-0.9), radius: 0.007, material: brass)
    }

    private func buildFan(_ parent: SCNNode, at p: SCNVector3) {
        let n = SCNNode(); n.position = p; parent.addChildNode(n)
        box(n, (0.40,0.07,0.31), (0,0.03,0), darkMetal, bevel: 0.06)
        cylinder(n, radius: 0.035, height: 0.39, at: SCNVector3(0,0.25,0), material: metal)
        cylinder(n, radius: 0.13, height: 0.20, at: SCNVector3(0,0.54,-0.06), material: paint, axis: "z")
        for r: CGFloat in [0.10,0.18,0.26,0.32] { _ = torus(n, ring: r, pipe: 0.007, at: SCNVector3(0,0.54,0.10), material: metal) }
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            rod(n, from: SCNVector3(sin(a)*0.06,0.54+cos(a)*0.06,0.115), to: SCNVector3(sin(a)*0.32,0.54+cos(a)*0.32,0.08), radius: 0.004, material: metal)
        }
        fan.position = SCNVector3(0,0.54,0.056); n.addChildNode(fan)
        for i in 0..<3 {
            let blade = sphere(fan, radius: 0.18, at: SCNVector3(0,0.13,0), scale: SCNVector3(0.44,1,0.045), material: paint)
            let pivot = SCNNode(); blade.removeFromParentNode(); pivot.addChildNode(blade); pivot.eulerAngles.z = CGFloat(i)*(.pi*2/3); fan.addChildNode(pivot)
        }
        cylinder(n, radius: 0.05, height: 0.035, at: SCNVector3(0,0.54,0.14), material: brass, axis: "z")
    }

    private func buildVent() {
        box(office, (1.28,0.75,0.72), (0,3.13,-4.07), metal, bevel: 0.025)
        box(office, (1.03,0.53,0.04), (0,3.10,-3.68), rubber)
        for i in 0..<10 { box(office, (1.05,0.024,0.055), (0,2.87+CGFloat(i)*0.05,-3.635), metal, bevel: 0.002) }
        for x: CGFloat in [-0.57,0.57] { for y: CGFloat in [2.87,3.40] {
            cylinder(office, radius: 0.019, height: 0.024, at: SCNVector3(x,y,-3.68), material: brass, axis: "z", segments: 6)
        } }
        _ = sign(office, text: "V-08  /  POSITIVE PRESSURE", width: 1.17, height: 0.12, at: SCNVector3(0,3.48,-3.67))
        let m = solid(NSColor(calibratedRed: 0.25,green: 0.08,blue: 0.035,alpha: 1), emission: 1.5); warningLamps.append(m)
        sphere(office, radius: 0.025, at: SCNVector3(0.57,2.82,-3.61), material: m)
    }

    private func buildBreaker() {
        let panel = SCNNode(); panel.position = SCNVector3(2.01,1.75,-4.09); office.addChildNode(panel)
        box(panel, (0.61,0.94,0.18), (0,0,0), darkMetal)
        box(panel, (0.54,0.83,0.035), (0,0,0.12), paint)
        _ = sign(panel, text: "AUXILIARY\n110 V / MLI", width: 0.45, height: 0.17, at: SCNVector3(0,0.29,0.145))
        for i in 0..<3 { for j in 0..<2 {
            box(panel, (0.16,0.12,0.034), (-0.12+CGFloat(j)*0.25,-0.01-CGFloat(i)*0.18,0.15), rubber)
            box(panel, (0.032,0.08,0.04), (-0.12+CGFloat(j)*0.25,-0.005-CGFloat(i)*0.18,0.18), ceramic)
        } }
        cylinder(office, radius: 0.029, height: 0.85, at: SCNVector3(2.04,2.73,-4.14), material: metal)
        // Cork notice board: the crossed out fourth camera is a diegetic gap in the map.
        box(office, (1.31,0.77,0.06), (-1.45,1.52,-4.10), wood)
        _ = sign(office, text: "NETWORK REGISTER\n01  02  03  --  05\n06  07  08\n\n04 IS NOT A STORAGE ROOM", width: 1.15, height: 0.60, at: SCNVector3(-1.45,1.53,-4.06), color: .init(calibratedWhite: 0.14,alpha: 1), background: .init(calibratedRed: 0.61,green: 0.58,blue: 0.43,alpha: 1))
    }

    private func buildRoom(_ room: Room) {
        let root = SCNNode(); root.name = room.label
        root.position = SCNVector3(CGFloat(room.rawValue + 1) * 40,0,0)
        scene.rootNode.addChildNode(root); roomRoots[room] = root
        if room == .duct { buildDuct(root, room: room); return }
        let corridor = room == .westPassage || room == .eastPassage
        let halfWidth: CGFloat = corridor ? 2 : 4.7
        let height: CGFloat = room == .returnChamber ? 5 : 3.8
        box(root, (CGFloat(halfWidth*2),0.14,14), (0,-0.09,-1.5), floor)
        box(root, (CGFloat(halfWidth*2),0.14,14), (0,height,-1.5), darkMetal)
        for side: CGFloat in [-1,1] {
            box(root, (0.18,CGFloat(height),14), (side*halfWidth,height/2,-1.5), wall)
            box(root, (0.22,1.25,14), (side*halfWidth,0.61,-1.5), paint)
            box(root, (0.25,0.06,14), (side*halfWidth,1.28,-1.5), brass)
            cylinder(root, radius: 0.055, height: 13, at: SCNVector3(side*(halfWidth-0.28),height-0.32,-1.5), material: brass, axis: "z")
            cylinder(root, radius: 0.10, height: 13, at: SCNVector3(side*(halfWidth-0.53),height-0.22,-1.5), material: metal, axis: "z")
            for z: CGFloat in [-6.8,-3.6,-0.4,2.8] {
                box(root, (0.17,CGFloat(height),0.20), (side*(halfWidth-0.14),height/2,z), darkMetal)
            }
        }
        box(root, (CGFloat(halfWidth-1),CGFloat(height),0.25), (-(halfWidth+1)/2,height/2,-8.4), paint)
        box(root, (CGFloat(halfWidth-1),CGFloat(height),0.25), ((halfWidth+1)/2,height/2,-8.4), paint)
        box(root, (2,CGFloat(height-2.6),0.25), (0,2.6+(height-2.6)/2,-8.4), paint)
        box(root, (2.2,3,0.13), (0,1.5,-10.3), darkMetal)
        for x: CGFloat in [-1.04,1.04] { box(root, (0.12,2.65,0.4), (x,1.3,-8.2), metal) }
        _ = sign(root, text: "MLI  /  " + room.code + "\n" + room.label, width: corridor ? 2.8 : 3.1, height: 0.45, at: SCNVector3(0,3.12,-8.18))
        fluorescent(root, x: corridor ? 0 : -1.6, y: height-0.24, z: -2.2, length: corridor ? 1.2 : 2, warm: room == .workshop || room == .returnChamber, phase: Double(room.rawValue)*4.7)
        fluorescent(root, x: corridor ? 0 : 2.1, y: height-0.24, z: -6.8, length: 1.1, warm: room == .eastPassage, phase: Double(room.rawValue)*3.1+1)
        let reflected = omni(root, at: SCNVector3(0,2.4,-4.9), color: NSColor(calibratedRed:0.40,green:0.53,blue:0.46,alpha:1), intensity: 80, range: 10)
        lights.append((reflected,80,Double(room.rawValue)))
        // Small debris and scuffed expansion seams anchor the large empty walking space.
        for i in 0..<13 {
            let x = CGFloat(sin(Double(i*17+room.rawValue)))*(halfWidth-0.6)
            let z = CGFloat(cos(Double(i*7+room.rawValue)))*5-2
            let sheet = box(root, (0.19,0.005,0.27), (x,0.003,z), i % 3 == 0 ? rubber : paper, bevel: 0)
            sheet.eulerAngles.y = CGFloat(i)*0.78
        }
        for z: CGFloat in [-7,-3,1] { box(root, (CGFloat(halfWidth*2),0.006,0.022), (0,0.007,z), darkMetal, bevel: 0) }
        entityAnchors[room] = SCNVector3(root.position.x,0,-3.8)
        var position = SCNVector3(-halfWidth+0.6,2.75,4.0)
        var target = SCNVector3(0,1.0,-3.5)
        switch room {
        case .intake: buildIntake(root)
        case .gallery: buildGallery(root)
        case .workshop: buildWorkshop(root)
        case .resonance: buildResonance(root)
        case .westPassage, .eastPassage:
            buildPassage(root, west: room == .westPassage)
            position = SCNVector3(room == .westPassage ? -1.55 : 1.55,2.9,4.2)
            target = SCNVector3(0,0.9,-4)
            entityAnchors[room] = SCNVector3(root.position.x,0,-2.5)
        case .returnChamber:
            buildReturn(root)
            position = SCNVector3(-3.8,2.9,4.1); target = SCNVector3(0,1.2,-3)
        case .duct: break
        }
        cameraPositions[room] = root.convertPosition(position,to:nil)
        cameraTargets[room] = root.convertPosition(target,to:nil)
    }

    private func buildIntake(_ root: SCNNode) {
        // Reception's rounded observation booth, empty queue and coat hooks establish scale.
        box(root, (3.0,1.14,1.4), (-2.85,0.56,-5.0), wood, bevel: 0.08)
        box(root, (3.14,0.08,1.52), (-2.85,1.17,-5.0), metal, bevel: 0.035)
        _ = sign(root, text: "WELCOME TO MORROW\nA BETTER WORLD BEGINS WITH LISTENING", width: 3.45, height: 0.75, at: SCNVector3(-2.63,2.28,-7.94), color: .init(calibratedRed: 0.65,green: 0.74,blue: 0.57,alpha: 1))
        for x: CGFloat in [-3.7,-2.55,-1.4] {
            box(root, (0.89,0.065,0.60), (x,0.44,-0.9), wood)
            let back = box(root, (0.89,0.56,0.052), (x,0.72,-1.18), wood); back.eulerAngles.x = -0.10
            for a: CGFloat in [-0.34,0.34] { rod(root,from:SCNVector3(x+a,0,-0.67),to:SCNVector3(x+a,0.72,-1.11),radius:0.027,material:metal) }
        }
        for x: CGFloat in [1.3,3.05] {
            cylinder(root, radius: 0.045, height: 0.9, at: SCNVector3(x,0.45,-0.5), material: brass)
            cylinder(root, radius: 0.22, height: 0.055, at: SCNVector3(x,0.028,-0.5), material: darkMetal)
            sphere(root,radius:0.075,at:SCNVector3(x,0.93,-0.5),material:brass)
        }
        cable(root,points:[SCNVector3(1.3,0.89,-0.5),SCNVector3(1.73,0.73,-0.5),SCNVector3(2.18,0.69,-0.5),SCNVector3(2.62,0.73,-0.5),SCNVector3(3.05,0.89,-0.5)],radius:0.043,material:rubber)
        box(root,(1.48,2.25,0.17),(3.75,1.12,-5.2),paint)
        _ = sign(root,text:"THE LISTENING YEARS\n1978 — 1994\n\nPLEASE LEAVE YOUR NAME.\nWE WILL REMEMBER IT.",width:1.22,height:1.73,at:SCNVector3(3.75,1.20,-5.10),color:.init(calibratedRed:0.63,green:0.66,blue:0.49,alpha:1))
        cylinder(root,radius:0.25,height:0.36,at:SCNVector3(-3.4,1.39,-5),material:darkMetal)
        // Wall clock remains stopped at the incident's recurring seventeen-minute mark.
        cylinder(root,radius:0.31,height:0.045,at:SCNVector3(3.2,2.95,-8.14),material:ceramic,axis:"z")
        rod(root,from:SCNVector3(3.2,2.95,-8.10),to:SCNVector3(3.26,3.13,-8.10),radius:0.01,material:rubber)
        rod(root,from:SCNVector3(3.2,2.95,-8.09),to:SCNVector3(3.40,2.91,-8.09),radius:0.008,material:rubber)
        for i in 0..<6 { box(root,(0.055,0.07,0.12),(-3.7+CGFloat(i)*0.37,1.95,-8.07),brass) }
    }

    private func buildGallery(_ root: SCNNode) {
        // Original museum exhibits: acoustic pinnae, suspended tuning forks, resonance rings.
        for (index,x) in [CGFloat(-3.2),CGFloat(3.15)].enumerated() {
            for (j,z) in [CGFloat(-1.4),CGFloat(-5.6)].enumerated() {
                box(root,(1.24,0.70,1.1),(x,0.35,z),paint)
                box(root,(1.34,0.075,1.2),(x,0.75,z),metal)
                let exhibit = SCNNode(); exhibit.position = SCNVector3(x,0.8,z); root.addChildNode(exhibit)
                if index == j {
                    let ear = SCNNode(); ear.eulerAngles.z = 0.2; exhibit.addChildNode(ear)
                    _ = torus(ear,ring:0.43,pipe:0.075,at:SCNVector3(0,0.53,0),material:ceramic)
                    _ = torus(ear,ring:0.25,pipe:0.055,at:SCNVector3(0,0.53,0.04),material:brass)
                    sphere(ear,radius:0.15,at:SCNVector3(0.09,0.32,0.03),scale:SCNVector3(0.8,1.3,0.6),material:ceramic)
                    cylinder(exhibit,radius:0.033,height:0.38,at:SCNVector3(0,0.18,0),material:metal)
                } else {
                    cylinder(exhibit,radius:0.045,height:0.3,at:SCNVector3(0,0.15,0),material:brass)
                    for dx: CGFloat in [-0.15,0.15] { box(exhibit,(0.055,1.00,0.07),(dx,0.78,0),metal) }
                    box(exhibit,(0.35,0.08,0.08),(0,0.29,0),metal)
                }
                _ = sign(root,text:index == j ? "02 / THE LISTENING BODY" : "VIBRATION IS MEMORY",width:1.11,height:0.16,at:SCNVector3(x,0.62,z+0.56))
                _ = spot(root,at:SCNVector3(x,3.25,z+0.3),target:SCNVector3(x,0.7,z),color:.init(calibratedRed:0.60,green:0.79,blue:0.65,alpha:1),intensity:180,cone:44,shadows:false,phase:Double(j+index))
            }
        }
        _ = sign(root,text:"CAN A ROOM REMEMBER YOU?\n\nA. VOSS / EXPERIMENT 17",width:3.1,height:0.87,at:SCNVector3(-2.74,2.2,-8.15))
        let hanging = SCNNode(); hanging.position = SCNVector3(2.6,2.66,-7); root.addChildNode(hanging)
        for i in 0..<4 {
            let r = CGFloat(0.25+Double(i)*0.15)
            let ring = torus(hanging,ring:r,pipe:0.019,at:SCNVector3Zero,material:brass)
            ring.eulerAngles.y = CGFloat(i)*0.55
        }
        rod(root,from:SCNVector3(2.6,3.8,-7),to:SCNVector3(2.6,2.65,-7),radius:0.008,material:metal)
        for i in 0..<6 {
            box(root,(0.22,0.009,0.04),(-0.28+CGFloat(i)*0.12,0.014,-6.0+CGFloat(i)*0.08),brass)
        }
    }

    private func workbench(_ root: SCNNode, at p: SCNVector3, width: CGFloat = 2.2) {
        box(root,(width,0.13,1.05),(p.x,p.y+0.88,p.z),wood,bevel:0.025)
        for x: CGFloat in [-CGFloat(width)*0.43,CGFloat(width)*0.43] { for z: CGFloat in [-0.40,0.40] {
            box(root,(0.06,0.86,0.06),(p.x+x,p.y+0.42,p.z+z),metal)
        } }
        box(root,(width-0.14,0.055,0.8),(p.x,p.y+0.21,p.z),darkMetal)
    }

    private func buildWorkshop(_ root: SCNNode) {
        workbench(root,at:SCNVector3(-3.05,0,-3.1),width:2.8)
        workbench(root,at:SCNVector3(3.0,0,-6.35),width:2.7)
        // A lathe, drill press and suspended empty harness leave suggestive human-scale negatives.
        box(root,(1.51,0.13,0.45),(-3.04,1.01,-3.1),metal)
        box(root,(0.35,0.56,0.52),(-3.56,1.27,-3.1),paint)
        cylinder(root,radius:0.16,height:0.34,at:SCNVector3(-3.27,1.37,-3.1),material:metal,axis:"x")
        cylinder(root,radius:0.055,height:0.80,at:SCNVector3(-2.81,1.37,-3.1),material:brass,axis:"x")
        box(root,(0.22,0.38,0.37),(-2.45,1.20,-3.1),paint)
        _ = torus(root,ring:0.13,pipe:0.018,at:SCNVector3(-3.6,1.19,-2.80),material:brass)
        cylinder(root,radius:0.08,height:1.0,at:SCNVector3(3.4,1.45,-6.48),material:metal)
        box(root,(0.56,0.31,0.55),(3.19,1.92,-6.48),paint)
        cylinder(root,radius:0.03,height:0.35,at:SCNVector3(3.01,1.62,-6.48),material:metal)
        box(root,(1.95,1.18,0.10),(-3.16,2.22,-4.0),darkMetal)
        for i in 0..<9 {
            let x = -3.96+CGFloat(i)*0.20
            rod(root,from:SCNVector3(x,2.47,-3.92),to:SCNVector3(x+0.04,1.99+CGFloat(i%3)*0.08,-3.92),radius:0.018,material:metal)
            _ = torus(root,ring:0.045,pipe:0.014,at:SCNVector3(x,2.49,-3.92),material:brass)
        }
        _ = sign(root,text:"MAINTENANCE / 17 APRIL\nNEVER SEAL BOTH RETURNS.\nPURGE HEAT. LISTEN FOR THE DUCT.",width:2.55,height:0.50,at:SCNVector3(-2.90,2.81,-4.0))
        for i in 0..<4 {
            let crate = box(root,(0.58,0.43,0.60),(2.5+CGFloat(i%2)*0.65,0.215+CGFloat(i/2)*0.44,-0.35),wood)
            for y: CGFloat in [-0.13,0.13] { box(crate,(0.59,0.025,0.615),(0,y,0),metal) }
        }
        cylinder(root,radius:0.27,height:0.93,at:SCNVector3(-3.9,0.47,-6.7),material:paint)
        for y: CGFloat in [0.12,0.81] { _ = torus(root,ring:0.275,pipe:0.016,at:SCNVector3(-3.9,y,-6.7),material:metal,facing:false) }
        rod(root,from:SCNVector3(0.4,3.70,-5.9),to:SCNVector3(0.4,2.27,-5.9),radius:0.015,material:metal)
        _ = torus(root,ring:0.34,pipe:0.025,at:SCNVector3(0.4,2.0,-5.9),material:darkMetal)
        for s: CGFloat in [-1,1] { cable(root,points:[SCNVector3(0.4+s*0.25,1.90,-5.9),SCNVector3(0.4+s*0.32,1.42,-5.87),SCNVector3(0.4+s*0.27,1.17,-5.8)],radius:0.036) }
    }

    private func buildResonance(_ root: SCNNode) {
        // Dense shelves of labeled magnetic reels create occlusion without hiding the central route.
        for side: CGFloat in [-1,1] {
            for z: CGFloat in [-1.5,-5.3] {
                let rack = SCNNode(); rack.position = SCNVector3(side*3.1,0,z); root.addChildNode(rack)
                for x: CGFloat in [-1.1,1.1] { box(rack,(0.07,2.70,0.65),(x,1.35,0),darkMetal) }
                for level in 0..<5 {
                    let y = 0.22+CGFloat(level)*0.5
                    box(rack,(2.24,0.065,0.65),(0,y,0),metal)
                    for i in 0..<8 {
                        let reel = cylinder(rack,radius:0.19,height:0.13,at:SCNVector3(-0.92+CGFloat(i)*0.26,y+0.22,0.05),material:i%3 == 0 ? brass : darkMetal,axis:"z")
                        _ = torus(reel,ring:0.135,pipe:0.012,at:SCNVector3(0,-0.075,0),material:metal,facing:false)
                        if i % 2 == 0 { box(rack,(0.095,0.08,0.008),(-0.92+CGFloat(i)*0.26,y+0.22,0.125),paper) }
                    }
                }
                _ = sign(rack,text:side < 0 ? "VOSS / VOICE RETENTION" : "PARTICIPANTS / 1978–94",width:2.16,height:0.16,at:SCNVector3(0,2.67,0.34))
            }
        }
        box(root,(1.55,0.95,1.0),(0,0.47,-6.45),darkMetal)
        let pedestal = SCNNode(); pedestal.position = SCNVector3(0,1.13,-6.38); root.addChildNode(pedestal)
        for x: CGFloat in [-0.42,0.42] {
            cylinder(pedestal,radius:0.30,height:0.06,at:SCNVector3(x,0.20,0),material:metal,axis:"z")
            cylinder(pedestal,radius:0.045,height:0.09,at:SCNVector3(x,0.20,0.06),material:brass,axis:"z")
            for i in 0..<3 { let a = CGFloat(i)*(.pi*2/3); sphere(pedestal,radius:0.057,at:SCNVector3(x+cos(a)*0.16,0.20+sin(a)*0.16,0.04),scale:SCNVector3(1,1,0.15),material:rubber) }
        }
        _ = sign(root,text:"CONTINUITY TAKES PRECEDENCE\nOVER EVACUATION\n\nOVERRIDE WITHHELD: 17 CALLS",width:2.55,height:0.62,at:SCNVector3(0,2.56,-8.14),color:.init(calibratedRed:0.74,green:0.61,blue:0.38,alpha:1))
        for i in 0..<3 { cable(root,points:[SCNVector3(-0.8+CGFloat(i)*0.20,1.0,-6.4),SCNVector3(-1+CGFloat(i)*0.2,0.03,-5.7),SCNVector3(-0.8+CGFloat(i)*0.23,0.03,-4.5),SCNVector3(-2.2,0.03,-3.7)],radius:0.018) }
    }

    private func buildPassage(_ root: SCNNode, west: Bool) {
        for i in 0..<4 {
            let z = 2.3-CGFloat(i)*2.6
            for x: CGFloat in [-1.8,1.8] { box(root,(0.11,2.92,0.19),(x,1.46,z),metal) }
            box(root,(3.72,0.12,0.19),(0,2.96,z),metal)
        }
        for side: CGFloat in [-1,1] {
            for z: CGFloat in [-1,-5.4] {
                let door = SCNNode(); door.position = SCNVector3(side*1.86,0,z); door.eulerAngles.y = side < 0 ? .pi/2 : -.pi/2; root.addChildNode(door)
                box(door,(1.14,2.32,0.07),(0,1.17,0),darkMetal)
                box(door,(1.00,2.22,0.08),(0,1.17,0.04),paint)
                _ = sign(door,text:west ? "SURVEY\nAUTHORIZED STAFF" : "ARCHIVE\nKEEP SILENT",width:0.78,height:0.31,at:SCNVector3(0,1.78,0.09))
                box(door,(0.16,0.027,0.06),(0.33,1.08,0.10),brass)
            }
        }
        for z: CGFloat in [-7,-4.2,-1.4,1.4] {
            box(root,(0.075,0.008,1.7),(-0.75,0.015,z),brass,bevel:0)
            box(root,(0.075,0.008,1.7),(0.75,0.015,z),brass,bevel:0)
        }
        _ = sign(root,text:west ? "CONTROL / W-06\nYOU ARE BEING MEASURED" : "CONTROL / E-07\nQUIET ZONE",width:1.80,height:0.44,at:SCNVector3(0,2.21,-8.15))
        // Grating and a low reservoir create highlights under the otherwise dry corridor.
        for i in 0..<13 { box(root,(1.1,0.013,0.025),(0,0.017,-6.1+CGFloat(i)*0.09),metal,bevel:0) }
        let puddle = solid(.init(calibratedRed:0.035,green:0.075,blue:0.068,alpha:1),metallic:0.6); puddle.roughness.contents = 0.13
        sphere(root,radius:0.75,at:SCNVector3(0.55,0.009,-0.6),scale:SCNVector3(0.72,0.004,1.6),material:puddle)
        cable(root,points:[SCNVector3(-1.7,3.2,-3),SCNVector3(-1.6,2.65,-3),SCNVector3(-1.4,1.8,-3),SCNVector3(-1.5,1.5,-3.1)],radius:0.025)
    }

    private func buildDuct(_ root: SCNNode, room: Room) {
        box(root,(2.9,0.12,18),(0,-0.08,-4),metal)
        box(root,(2.9,0.12,18),(0,2.42,-4),metal)
        for x: CGFloat in [-1.47,1.47] { box(root,(0.12,2.5,18),(x,1.18,-4),metal) }
        for i in 0..<12 {
            let z = 3.5-CGFloat(i)*1.4
            for x: CGFloat in [-1.4,1.4] { box(root,(0.055,2.38,0.08),(x,1.16,z),darkMetal) }
            for y: CGFloat in [0.03,2.34] { box(root,(2.78,0.055,0.08),(0,y,z),darkMetal) }
            for x: CGFloat in [-1.36,1.36] { for y: CGFloat in [0.12,2.23] {
                cylinder(root,radius:0.025,height:0.05,at:SCNVector3(x,y,z+0.045),material:brass,axis:"z",segments:6)
            } }
        }
        box(root,(2.9,2.5,0.05),(0,1.20,-12.8),rubber)
        _ = torus(root,ring:0.97,pipe:0.08,at:SCNVector3(0,1.2,-10.8),material:metal)
        ventRotor.position = SCNVector3(0,1.2,-10.8); root.addChildNode(ventRotor)
        for i in 0..<5 {
            let pivot = SCNNode(); pivot.eulerAngles.z = CGFloat(i)*(.pi*2/5); ventRotor.addChildNode(pivot)
            let blade = sphere(pivot,radius:0.58,at:SCNVector3(0,0.44,0),scale:SCNVector3(0.45,1,0.035),material:darkMetal); blade.eulerAngles.y = 0.35
        }
        cylinder(root,radius:0.18,height:0.13,at:SCNVector3(0,1.2,-10.7),material:metal,axis:"z")
        for i in 0..<6 { rod(root,from:SCNVector3(-1.3,0.3+CGFloat(i)*0.34,-10.4),to:SCNVector3(1.3,0.3+CGFloat(i)*0.34,-10.4),radius:0.012,material:metal) }
        _ = spot(root,at:SCNVector3(0.1,1.9,3.4),target:SCNVector3(0,0.9,-8),color:.init(calibratedRed:0.40,green:0.72,blue:0.58,alpha:1),intensity:650,cone:80,shadows:true,phase:8)
        _ = spot(root,at:SCNVector3(-0.9,2.1,-7),target:SCNVector3(0,0,-9),color:.init(calibratedRed:0.87,green:0.38,blue:0.11,alpha:1),intensity:170,cone:80,shadows:false,phase:6)
        _ = sign(root,text:"V-08 / RETURN AIR\n17.04.94 — DO NOT REVERSE",width:1.55,height:0.30,at:SCNVector3(0,2.07,-10.35))
        for i in 0..<4 {
            cable(root,points:[SCNVector3(-1.25+CGFloat(i)*0.08,0.07,3),SCNVector3(-1.1+CGFloat(i)*0.07,0.03,-2),SCNVector3(-1.2+CGFloat(i)*0.08,0.03,-8)],radius:0.016)
        }
        cameraPositions[room] = root.convertPosition(SCNVector3(-0.52,1.48,3.6),to:nil)
        cameraTargets[room] = root.convertPosition(SCNVector3(0,0.7,-7),to:nil)
        entityAnchors[room] = root.convertPosition(SCNVector3(0,0.15,-3.5),to:nil)
    }

    private func buildReturn(_ root: SCNNode) {
        // The absent camera sees a purpose-built listening well, not a generic secret closet.
        cylinder(root,radius:2.18,height:0.22,at:SCNVector3(0,0.11,-3.5),material:darkMetal,segments:48)
        for r: CGFloat in [1.6,1.86,2.16] { _ = torus(root,ring:r,pipe:0.022,at:SCNVector3(0,0.24,-3.5),material:brass,facing:false) }
        let ring = torus(root,ring:1.47,pipe:0.12,at:SCNVector3(0,2.13,-4.3),material:metal)
        ring.eulerAngles.y = -0.15
        for i in 0..<17 {
            let a = CGFloat(i)*(.pi*2/17)
            let x = sin(a)*1.47, y = 2.13+cos(a)*1.47
            cylinder(root,radius:0.10,height:0.28,at:SCNVector3(x,y,-4.24),material:brass,axis:"z")
            cylinder(root,radius:0.075,height:0.03,at:SCNVector3(x,y,-4.07),material:rubber,axis:"z")
        }
        for x: CGFloat in [-1.15,1.15] { rod(root,from:SCNVector3(x,0.24,-4.3),to:SCNVector3(x,1.23,-4.3),radius:0.10,material:metal) }
        box(root,(0.75,0.57,0.68),(0,0.57,-3.4),paint)
        cylinder(root,radius:0.32,height:0.05,at:SCNVector3(0,0.91,-3.4),material:metal)
        sphere(root,radius:0.11,at:SCNVector3(0,0.99,-3.4),scale:SCNVector3(1,0.35,1),material:solid(.init(calibratedRed:0.29,green:0.72,blue:0.62,alpha:1),emission:1.4))
        _ = sign(root,text:"04 / RETURN\nWITNESS CHANNEL\nSEND, NOT STORE.",width:2.7,height:0.61,at:SCNVector3(0,3.83,-8.14),color:.init(calibratedRed:0.80,green:0.70,blue:0.45,alpha:1))
        for side: CGFloat in [-1,1] {
            box(root,(1.2,2.35,0.65),(side*3.2,1.18,-6.4),darkMetal)
            for i in 0..<8 {
                box(root,(1.06,0.21,0.05),(side*3.2,0.2+CGFloat(i)*0.27,-6.04),paint)
                sphere(root,radius:0.014,at:SCNVector3(side*3.2-0.39,0.2+CGFloat(i)*0.27,-5.995),material:solid(.init(calibratedRed:0.56,green:0.71,blue:0.33,alpha:1),emission:1.2))
            }
        }
        for i in 0..<8 { cable(root,points:[SCNVector3(sin(CGFloat(i))*1.5,0.22,-4.3),SCNVector3(-0.5+CGFloat(i)*0.14,0.03,-1.7),SCNVector3(-2.4+CGFloat(i)*0.05,0.02,0.7),SCNVector3(-4.3,0.04,1.6+CGFloat(i)*0.07)],radius:0.023) }
        _ = spot(root,at:SCNVector3(1,4.55,-3.4),target:SCNVector3(0,1,-3.4),color:.init(calibratedRed:0.58,green:0.81,blue:0.72,alpha:1),intensity:640,cone:50,shadows:true,phase:14)
    }

    private func buildSurveyor() -> SCNNode {
        let root = SCNNode(); root.name = "Surveyor / optical survey apparatus"
        // The three bent surveying legs meet a narrow, almost human shoulder mechanism.
        for i in 0..<3 {
            let a = CGFloat(i) * .pi * 2 / 3 + .pi / 6
            let hip = SCNVector3(sin(a)*0.16,1.34,cos(a)*0.14)
            let knee = SCNVector3(sin(a)*0.53,0.67,cos(a)*0.48)
            let foot = SCNVector3(sin(a)*0.61,0.055,cos(a)*0.66)
            rod(root,from:hip,to:knee,radius:0.038,material:metal)
            rod(root,from:SCNVector3(hip.x+0.045,hip.y,hip.z),to:SCNVector3(knee.x+0.04,knee.y,knee.z),radius:0.016,material:brass)
            rod(root,from:knee,to:foot,radius:0.024,material:darkMetal)
            sphere(root,radius:0.073,at:knee,material:brass)
            box(root,(0.11,0.045,0.24),(foot.x,foot.y,foot.z),rubber)
            for j in 0..<4 { cylinder(root,radius:0.031,height:0.035,at:SCNVector3(foot.x+(knee.x-foot.x)*CGFloat(j+1)/6,foot.y+(knee.y-foot.y)*CGFloat(j+1)/6,foot.z+(knee.z-foot.z)*CGFloat(j+1)/6),material:metal) }
        }
        sphere(root,radius:0.24,at:SCNVector3(0,1.43,0),scale:SCNVector3(0.81,1.28,0.61),material:darkMetal)
        cylinder(root,radius:0.077,height:0.76,at:SCNVector3(0,1.66,-0.01),material:brass)
        for i in 0..<7 {
            let r = CGFloat(0.15 + sin(Double(i) / 7 * .pi) * 0.10)
            let rib = torus(root,ring:r,pipe:0.018,at:SCNVector3(0,1.38+CGFloat(i)*0.09,0),material:ceramic,facing:false)
            rib.scale = SCNVector3(1,1,0.68)
        }
        rod(root,from:SCNVector3(-0.42,1.89,0),to:SCNVector3(0.42,1.89,0),radius:0.04,material:metal)
        var moving: [SCNNode] = []
        for side: CGFloat in [-1,1] {
            let arm = SCNNode(); arm.position = SCNVector3(side*0.40,1.86,0); root.addChildNode(arm); moving.append(arm)
            sphere(arm,radius:0.095,at:.init(0,0,0),material:ceramic)
            rod(arm,from:.init(0,0,0),to:.init(side*0.15,-0.57,0.08),radius:0.027,material:darkMetal)
            rod(arm,from:.init(side*0.15,-0.57,0.08),to:.init(side*0.19,-0.96,0.26),radius:0.021,material:metal)
            sphere(arm,radius:0.055,at:.init(side*0.15,-0.57,0.08),material:brass)
            for j in 0..<3 {
                let offset = CGFloat(j-1)*0.047
                cable(arm,points:[.init(side*0.19,-0.96,0.26),.init(side*0.19+offset,-1.10,0.32),.init(side*0.20+offset*1.7,-1.22,0.44)],radius:0.012,material:brass)
            }
            cable(root,points:[.init(side*0.17,1.67,-0.1),.init(side*0.40,1.76,-0.1),.init(side*0.49,1.31,-0.02),.init(side*0.39,1.21,0.02)],radius:0.013)
        }
        let head = SCNNode(); head.position = SCNVector3(0,2.18,0.045); root.addChildNode(head); moving.append(head)
        cylinder(head,radius:0.057,height:0.22,at:SCNVector3(0,-0.17,0),material:darkMetal)
        sphere(head,radius:0.28,at:SCNVector3(0,0.10,0),scale:SCNVector3(0.77,1.20,0.52),material:ceramic)
        // A single deep horizontal optical cut and offset porcelain halves avoid a mascot face.
        box(head,(0.34,0.046,0.045),(0,0.115,0.134),rubber,bevel:0.011)
        for side: CGFloat in [-1,1] {
            sphere(head,radius:0.018,at:SCNVector3(side*0.084,0.113,0.164),scale:SCNVector3(1,0.50,0.30),material:solid(.init(calibratedRed:0.73,green:0.87,blue:0.67,alpha:1),emission:1.6))
        }
        cable(head,points:[.init(0.04,0.33,0.07),.init(0.021,0.19,0.149),.init(0.043,0.01,0.144),.init(0.019,-0.14,0.081)],radius:0.004,material:darkMetal)
        for i in 0..<6 { box(head,(0.06,0.006,0.008),(-0.10,-0.008-CGFloat(i)*0.021,0.144-CGFloat(i)*0.005),darkMetal,bevel:0.001) }
        for side: CGFloat in [-1,1] { cylinder(head,radius:0.055,height:0.04,at:.init(side*0.218,0.08,0),material:brass,axis:"x") }
        _ = sign(root,text:"S / 17",width:0.15,height:0.10,at:SCNVector3(0,1.58,0.164))
        articulated[.surveyor] = moving
        return root
    }

    /// Open flared bell mesh, with thickness, a dark throat, and a rolled lip.
    private func horn(_ parent: SCNNode, radius: CGFloat, length: CGFloat, at p: SCNVector3) -> SCNNode {
        let node = SCNNode(); node.position = p; parent.addChildNode(node)
        var vertices: [SCNVector3] = []; var normals: [SCNVector3] = []; var indices: [Int32] = []
        let rings = 10, sides = 32
        for j in 0...rings {
            let t = CGFloat(j)/CGFloat(rings)
            let r = CGFloat(radius) * (0.18 + 0.82 * t*t*t)
            let slope = CGFloat(radius)*2.46*t*t/CGFloat(length)
            for i in 0...sides {
                let a = CGFloat(i) * .pi*2/CGFloat(sides)
                vertices.append(.init(cos(a)*r,sin(a)*r,t*CGFloat(length)))
                let normal = simd_normalize(SIMD3<Float>(Float(cos(a)),Float(sin(a)),Float(-slope)))
                normals.append(.init(normal.x,normal.y,normal.z))
            }
        }
        for j in 0..<rings { for i in 0..<sides {
            let a = Int32(j*(sides+1)+i), b = a+Int32(sides+1)
            indices += [a,b,a+1,a+1,b,b+1]
        } }
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let bellMaterial = brass.copy() as! SCNMaterial; bellMaterial.isDoubleSided = true; geometry.materials = [bellMaterial]
        node.addChildNode(SCNNode(geometry:geometry))
        _ = torus(node,ring:radius,pipe:0.014,at:.init(0,0,CGFloat(length)),material:brass)
        cylinder(node,radius:radius*0.17,height:0.008,at:.init(0,0,0.002),material:rubber,axis:"z")
        for j in 0..<3 { _ = torus(node,ring:radius*(0.18+CGFloat(j)*0.012),pipe:0.012,at:.init(0,0,CGFloat(j)*0.035),material:metal) }
        return node
    }

    private func buildChorus() -> SCNNode {
        let root = SCNNode(); root.name = "Chorus / mobile public address array"
        box(root,(1.0,0.18,0.77),(0,0.32,-0.03),darkMetal,bevel:0.075)
        for x: CGFloat in [-0.47,0.47] { for z: CGFloat in [-0.31,0.31] {
            cylinder(root,radius:0.23,height:0.13,at:.init(x,0.23,z),material:rubber,axis:"x")
            cylinder(root,radius:0.125,height:0.14,at:.init(x,0.23,z),material:metal,axis:"x")
            cylinder(root,radius:0.035,height:0.155,at:.init(x,0.23,z),material:brass,axis:"x")
        } }
        sphere(root,radius:0.48,at:.init(0,0.82,-0.05),scale:.init(0.90,1.13,0.72),material:paint)
        for y: CGFloat in [0.52,0.91,1.13] { let ring = torus(root,ring:0.39,pipe:0.022,at:.init(0,y,-0.05),material:brass,facing:false); ring.scale.z = 0.76 }
        box(root,(0.40,0.48,0.037),(0,0.84,0.30),darkMetal)
        for i in 0..<9 { box(root,(0.34,0.015,0.025),(0,0.66+CGFloat(i)*0.044,0.33),brass,bevel:0.003) }
        for side: CGFloat in [-1,1] { cable(root,points:[.init(side*0.31,1.13,0),.init(side*0.54,1.17,-0.1),.init(side*0.58,0.67,-0.1),.init(side*0.30,0.51,0)],radius:0.039) }
        cylinder(root,radius:0.095,height:0.60,at:.init(0,1.36,0),material:darkMetal)
        for i in 0..<9 { _ = torus(root,ring:0.11,pipe:0.015,at:.init(0,1.13+CGFloat(i)*0.055,0),material:metal,facing:false) }
        let array = SCNNode(); array.position = .init(0,1.55,0); root.addChildNode(array)
        box(array,(1.07,0.08,0.11),(0,0.12,-0.03),metal)
        let placements: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [(-0.43,0.20,0,0.245),(0,0.30,0.02,0.29),(0.43,0.19,-0.01,0.245),(-0.28,0.69,-0.04,0.23),(0.29,0.66,-0.03,0.23),(0,0.98,-0.10,0.19)]
        var moving = [array]
        for (i,p) in placements.enumerated() {
            rod(array,from:.init(0,0,-0.05),to:.init(p.0,p.1,-0.02),radius:0.027,material:metal)
            let h = horn(array,radius:p.3,length:0.40,at:.init(p.0,p.1,p.2))
            h.eulerAngles.y = p.0*0.35; h.eulerAngles.x = -p.1*0.12
            h.name = "bell\(i)"; moving.append(h)
        }
        sphere(root,radius:0.022,at:.init(-0.10,1.05,0.33),material:solid(.init(calibratedRed:0.96,green:0.42,blue:0.08,alpha:1),emission:1.7))
        _ = sign(root,text:"LISTEN / REPEAT",width:0.44,height:0.10,at:.init(0,0.47,0.34))
        articulated[.chorus] = moving
        return root
    }

    private func buildSeam() -> SCNNode {
        let root = SCNNode(); root.name = "Seam / duct inspection chain"
        var moving: [SCNNode] = []
        for i in 0..<13 {
            let segment = SCNNode(); segment.position = .init(0,0.24,-CGFloat(i)*0.18); root.addChildNode(segment); moving.append(segment)
            let size = max(0.10,0.27-CGFloat(i)*0.012)
            sphere(segment,radius:CGFloat(size),at:.init(0,0,0),scale:.init(1,0.60,0.63),material:i%3 == 0 ? ceramic : darkMetal)
            let band = torus(segment,ring:CGFloat(size)*0.87,pipe:0.017,at:.init(0,0,0.01),material:brass); band.scale.y = 0.6
            cylinder(segment,radius:0.045,height:0.22,at:.init(0,0,-0.06),material:rubber,axis:"z")
            if i < 10 {
                for side: CGFloat in [-1,1] {
                    cable(segment,points:[.init(side*size*0.73,-0.04,0),.init(side*(size+0.14),-0.08,-0.06),.init(side*(size+0.22),-0.23,0.05)],radius:0.013,material:metal)
                    sphere(segment,radius:0.026,at:.init(side*(size+0.14),-0.08,-0.06),material:brass)
                }
            }
        }
        let head = SCNNode(); head.position = .init(0,0.31,0.26); root.addChildNode(head); moving.append(head)
        sphere(head,radius:0.30,at:.init(0,0.055,0),scale:.init(0.9,0.46,1.20),material:ceramic)
        sphere(head,radius:0.26,at:.init(0,-0.06,0.035),scale:.init(0.95,0.19,1.35),material:metal)
        box(head,(0.34,0.065,0.20),(0,-0.019,0.24),rubber,bevel:0.03)
        for i in 0..<7 {
            let x = CGFloat(i-3)*0.045
            rod(head,from:.init(x,0.017,0.31),to:.init(x*0.85,-0.052,0.36),radius:0.008,material:brass)
        }
        for side: CGFloat in [-1,1] {
            sphere(head,radius:0.023,at:.init(side*0.16,0.099,0.235),scale:.init(1,0.50,0.7),material:solid(.init(calibratedRed:0.62,green:0.78,blue:0.63,alpha:1),emission:1.2))
            cable(head,points:[.init(side*0.19,0.06,0.05),.init(side*0.32,0.20,0.20),.init(side*0.39,0.29,0.44)],radius:0.009,material:brass)
        }
        articulated[.seam] = moving
        return root
    }

    private func animateCreature(_ kind: EntityKind, time: Double, threat: Double) {
        guard let parts = articulated[kind] else { return }
        switch kind {
        case .surveyor:
            guard parts.count == 3 else { return }
            parts[0].eulerAngles.z = CGFloat(sin(time*0.83)*0.06)
            parts[1].eulerAngles.z = CGFloat(sin(time*0.67+1.2)*0.07)
            parts[2].eulerAngles.z = CGFloat(sin(time*0.39)*0.12 + (threat > 0.5 ? 0.13 : 0))
            parts[2].eulerAngles.y = CGFloat(sin(time*0.27)*0.16)
        case .chorus:
            parts[0].eulerAngles.y = CGFloat(sin(time*0.43)*0.23)
            for i in 1..<parts.count { parts[i].eulerAngles.z = CGFloat(sin(time*(0.51+Double(i)*0.07)+Double(i))*0.055) }
        case .seam:
            for i in 0..<min(13,parts.count) {
                parts[i].position.x = CGFloat(sin(time*2.8-Double(i)*0.62))*0.11
                parts[i].position.y = 0.24 + CGFloat(sin(time*2.1-Double(i)*0.45))*0.035
                parts[i].eulerAngles.y = CGFloat(cos(time*2.8-Double(i)*0.62))*0.19
            }
            parts.last?.eulerAngles.y = CGFloat(sin(time*1.7))*0.13
            parts.last?.position.y = 0.31 + CGFloat(sin(time*2.1))*0.025
        }
    }
}
