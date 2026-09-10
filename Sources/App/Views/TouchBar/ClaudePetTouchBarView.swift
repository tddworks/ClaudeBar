import AppKit
import CoreGraphics
import Domain
import Infrastructure

// MARK: - Particle

private struct Particle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var alpha: CGFloat
    let glyph: String
    let size: CGFloat
    var color: NSColor? = nil
}

// MARK: - Thought Bubble & Emotions

private enum ThoughtEmotion: CaseIterable {
    case happy      // ความสุข สดใส ร่าเริง ฉลอง
    case hyped      // พลังล้น ไฮป์ ไฟลุก มุ่งมั่น
    case curious    // ครุ่นคิด สงสัย ไอเดียปิ๊ง สติปัญญา
    case cool       // เท่ มั่นใจ มีสไตล์ เกมเมอร์
    case love       // อบอุ่น นุ่มฟู น่ารัก ส่งความรัก
    case silly      // ซน ขี้เล่น สนุกสนาน สแน็ค
    case zen        // ชิลล์ สบายๆ สงบใจ ผ่อนคลาย คาเฟ่
    case dramatic   // ตกใจ ตาโต ตาค้าง หวือหวา
    case sleepy     // ง่วง แบตหมด เหนื่อย งอแงนิดๆ

    var emojis: [String] {
        switch self {
        case .happy:
            return ["😊", "🥳", "😄", "✨", "🌟", "🎉", "😸", "🌈", "🌻", "🍀", "🧁", "🪄", "🎈", "☀️", "🍭", "🌸"]
        case .hyped:
            return ["🔥", "⚡", "🚀", "💥", "🦾", "💯", "🏆", "🏎️", "🤩", "🎯", "⚡️", "🥊", "💫", "🆙"]
        case .curious:
            return ["🤔", "💡", "🧐", "🔍", "🧠", "🧪", "🔮", "📡", "🪐", "💭", "🔬", "🧩", "📖", "🧭"]
        case .cool:
            return ["😎", "🕶️", "💎", "👑", "🛹", "🕹️", "🎧", "🪩", "🎩", "🥷", "🎸", "🪙"]
        case .love:
            return ["🥰", "💖", "💕", "😻", "💌", "🌸", "🍬", "🧸", "🪻", "💓", "🎀", "🌷", "🍰"]
        case .silly:
            return ["🤪", "😜", "👻", "🍕", "🍩", "🥑", "🌮", "🧋", "🎮", "👾", "🦄", "🍦", "🥐", "🍿", "🍔"]
        case .zen:
            return ["☕", "🍵", "🍃", "😌", "🎶", "🛋️", "🌿", "🌊", "☁️", "🧃", "🪴", "🎋", "🕯️"]
        case .dramatic:
            return ["😲", "🤯", "😱", "🛸", "🎭", "🌀", "👁️", "🙀", "💫", "🌪️", "🚨"]
        case .sleepy:
            return ["🥱", "💤", "😴", "🪫", "🫠", "😵‍💫", "😤", "🤨", "🌧️", "😮‍💨", "🐢", "🛌", "🌙"]
        }
    }
}

private struct ThoughtBubble {
    var text: String
    var expireTime: TimeInterval
}

// MARK: - Pet Antic State Machine

private enum PetAntic: Equatable {
    case normal
    case zoomies(endTime: TimeInterval)
    case moonwalk(endTime: TimeInterval)
    case tripAndFall(endTime: TimeInterval, phase: Int)
    case powerNap(endTime: TimeInterval)
    case joyHop(endTime: TimeInterval)
    case breakdance(endTime: TimeInterval)
    case backflip(endTime: TimeInterval)
    case skateboard(endTime: TimeInterval)
    case theWorm(endTime: TimeInterval)
    case ninjaVanish(endTime: TimeInterval, targetX: CGFloat)
    case glassKnock(endTime: TimeInterval)
    case quotaSnack(endTime: TimeInterval)
    case bellyRub(endTime: TimeInterval)
    case highFive(endTime: TimeInterval, succeeded: Bool)
    case laserChase(targetX: CGFloat, expireTime: TimeInterval)
}

// MARK: - Data Models

public struct TouchBarProviderGauge: Equatable, Sendable {
    public let providerId: String
    public let name: String
    public let percentUsed: Double
    public let resetText: String?
    public let status: QuotaStatus

    public init(
        providerId: String,
        name: String,
        percentUsed: Double,
        resetText: String?,
        status: QuotaStatus
    ) {
        self.providerId = providerId
        self.name = name
        self.percentUsed = percentUsed
        self.resetText = resetText
        self.status = status
    }
}

// MARK: - ClaudePetTouchBarView

/// Interactive Touch Bar view.
/// Renders an animated pixel mascot on the left and live provider usage gauges on the right.
@MainActor
public final class ClaudePetTouchBarView: NSView {
    public static let sceneW: CGFloat = 600.0
    public static let sceneH: CGFloat = 30.0

    // MARK: - Mood

    private enum Mood {
        case calm, brisk, tired, panic, depleted, sleeping

        /// Derive mood from quota data.
        static func from(maxUsage: Double, overallStatus: QuotaStatus, isSleeping: Bool = false) -> Mood {
            if isSleeping || overallStatus == .depleted || Int(maxUsage.rounded()) >= 100 || maxUsage >= 100.0 {
                return .sleeping
            }
            if maxUsage >= 85.0 { return .panic }
            if maxUsage >= 60.0 { return .tired }
            if maxUsage >= 30.0 { return .brisk }
            return .calm
        }

        var speed: CGFloat {
            switch self {
            case .calm:     return 12.0
            case .brisk:    return 24.0
            case .tired:    return 8.0
            case .panic:    return 48.0
            case .depleted: return 0.0
            case .sleeping: return 0.0
            }
        }
    }

    // MARK: - Mascot Position & Physics

    private var x: CGFloat = 40.0
    private var dir: CGFloat = 1.0
    private var phase: CGFloat = 0.0

    // Drag / throw
    private var dragging = false
    private var grabDX: CGFloat = 0.0
    private var dragVX: CGFloat = 0.0
    private var lastDragX: CGFloat = 0.0
    private var throwVX: CGFloat = 0.0
    private var wiggleT: CGFloat = 0.0
    private var somersaultAngle: CGFloat = 0.0

    // Jump (triggered on provider switch or antics)
    private var jumpVY: CGFloat = 0.0
    private var jumpY: CGFloat = 0.0

    // MARK: - Antics & Interaction State

    private var currentAntic: PetAntic = .normal
    private var nextAnticCheckTime: TimeInterval = 0
    private var anticAngle: CGFloat = 0.0

    // Thought Bubble
    private var currentThought: ThoughtBubble?
    private var nextThoughtCheckTime: TimeInterval = 0

    // Laser pointer
    private var laserDot: (x: CGFloat, expireTime: TimeInterval)?

    // Touch interaction tracking
    private var touchStartTime: TimeInterval = 0
    private var touchStartPos: CGFloat = 0
    private var isTickling: Bool = false

    // Ninja vanish transparency
    private var ninjaAlpha: CGFloat = 1.0

    // Ultra Panic state (Quota >= 95%)
    private var isUltraPanicJitter: (x: CGFloat, y: CGFloat) = (0, 0)
    private var nextUltraPanicSputter: TimeInterval = 0

    // RGB Gamer Mode easter egg
    private var rgbGamerEndTime: TimeInterval = 0
    private var nextGamerModeCheck: TimeInterval = 0

    // Keystroke typing sync
    private var keystrokeTimestamps: [TimeInterval] = []

    // MARK: - Event Timers

    /// Body flashes white for this duration (seconds) when status degrades.
    private var flashWhiteT: CGFloat = 0.0
    /// Spinning '?' orbits above head during a quota refresh.
    private var refreshPulseT: CGFloat = 0.0
    private var spinAngle: CGFloat = 0.0

    // MARK: - Idle Tracking

    private var lastActivityTime: TimeInterval = 0
    private var idleElapsed: TimeInterval = 0

    // MARK: - Delta Detection (event reactions)

    private var prevStatus: QuotaStatus = .healthy
    private var prevProviderId: String = ""

    // MARK: - Particles

    private var particles: [Particle] = []

    // MARK: - Cached Context (set on @MainActor, read in draw)

    private var isChristmasTheme: Bool = false
    private var isNightMode: Bool = false
    private var lastNightStarEmit: TimeInterval = 0
    private var lastZzzEmit: TimeInterval = 0

    // MARK: - External Signals

    /// Set by PersistentTouchBarDriver: true when a Claude Code session is active.
    public var sessionActive: Bool = false {
        didSet { needsDisplay = true }
    }

    /// Record a keystroke from GlobalKeyboardMonitor for typing cadence sync.
    public func recordKeystroke() {
        let now = Date.timeIntervalSinceReferenceDate
        markActivity()
        keystrokeTimestamps.append(now)
    }

    // MARK: - Gauges + Icons

    public var gauges: [TouchBarProviderGauge] = [] {
        didSet {
            let newStatus = worstStatus(from: gauges)
            let newProviderId = gauges.first?.providerId ?? ""

            // Detect status level transitions
            if prevStatus != newStatus {
                let oldSev = severity(of: prevStatus)
                let newSev = severity(of: newStatus)
                if newSev > oldSev {
                    // Quota degraded → ! alarm particle + body flash
                    spawnParticle(glyph: "⚠️", x: x + CGFloat.random(in: -4...4),
                                  y: 24, vx: 0, vy: 0.7, size: 10, color: .systemRed)
                    flashWhiteT = 0.12
                    // Interrupt any playful antic
                    currentAntic = .normal
                } else if newSev < oldSev && oldSev > 0 {
                    // Quota improved (reset) → sparkle particles + Confetti celebration!
                    spawnParticle(glyph: "✨", x: x - 5, y: 24, vx: -0.3, vy: 0.6, size: 9, color: .systemYellow)
                    spawnParticle(glyph: "✨", x: x + 6, y: 22, vx: 0.3,  vy: 0.7, size: 7, color: .systemOrange)

                    // Confetti explosion 🎉
                    let confettiColors: [NSColor] = [
                        NSColor(srgbRed: 0.98, green: 0.25, blue: 0.45, alpha: 1.0),
                        NSColor(srgbRed: 0.95, green: 0.85, blue: 0.20, alpha: 1.0),
                        NSColor(srgbRed: 0.20, green: 0.85, blue: 0.95, alpha: 1.0),
                        NSColor(srgbRed: 0.40, green: 0.95, blue: 0.45, alpha: 1.0),
                        NSColor(srgbRed: 0.75, green: 0.40, blue: 0.95, alpha: 1.0)
                    ]
                    for _ in 0..<12 {
                        let glyph = ["🎉", "✨", "🎊", "⭐", "🌟"].randomElement() ?? "✨"
                        let color = confettiColors.randomElement() ?? .systemPink
                        spawnParticle(
                            glyph: glyph,
                            x: x + CGFloat.random(in: -8...8),
                            y: 15,
                            vx: CGFloat.random(in: -1.2...1.2),
                            vy: CGFloat.random(in: 0.8...1.7),
                            size: CGFloat.random(in: 6...9),
                            color: color
                        )
                    }
                    currentThought = ThoughtBubble(text: "🎉", expireTime: Date.timeIntervalSinceReferenceDate + 2.5)
                }
                prevStatus = newStatus
            }

            // Detect provider switch → jump
            if !prevProviderId.isEmpty && prevProviderId != newProviderId {
                jumpVY = 85.0
                dir = -dir  // face new direction
                markActivity()
                spawnParticle(glyph: "✨", x: x, y: 24, vx: 0, vy: 0.6, size: 9)
            }
            prevProviderId = newProviderId

            // Sync Christmas flag (safe: in @MainActor didSet)
            isChristmasTheme = AppSettings.shared.themeMode == "christmas"

            cachedIcons = gauges.map { loadProviderIcon(for: $0.providerId) }
            if x > petRightBoundary {
                x = petRightBoundary
                dir = -1
            }
            needsDisplay = true
        }
    }
    private var cachedIcons: [NSImage?] = []

    // MARK: - Layout Metrics

    private var cellGap: CGFloat { 12.0 }

    private var readoutWidth: CGFloat {
        guard !gauges.isEmpty else { return 0 }
        let n = CGFloat(gauges.count)
        let desired = n * 170.0 + (n - 1) * cellGap
        return min(380.0, max(200.0, desired))
    }

    private var readoutStartX: CGFloat {
        guard !gauges.isEmpty else { return bounds.width }
        return bounds.width - readoutWidth - 8.0
    }

    /// Safe boundary for Clawd so he turns around comfortably before hitting the progress bar or provider icon
    private var petRightBoundary: CGFloat {
        return max(40.0, readoutStartX - 42.0)
    }

    // MARK: - Frame Timer

    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    // MARK: - Clawd 20x20 Base Sprite Grid

    private static let baseGrid: [UInt8] = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 2, 1, 1, 1, 1, 1, 2, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ]

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.sceneW, height: Self.sceneH))
        self.allowedTouchTypes = [.direct]
        lastActivityTime = Date.timeIntervalSinceReferenceDate
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool { false }
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Animation Control

    public func startAnimation() {
        guard timer == nil else { return }
        lastTick = Date.timeIntervalSinceReferenceDate
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.step()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - External Trigger

    /// Called by PersistentTouchBarDriver to show a refresh animation while quotas reload.
    public func triggerRefreshPulse() {
        refreshPulseT = 1.5
        spinAngle = 0
    }

    // MARK: - Animation Step

    private func step() {
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.1, max(0.001, now - lastTick))
        lastTick = now

        // Track idle elapsed time
        idleElapsed = now - lastActivityTime

        // Night mode (22:00–04:59 local time)
        let hour = Calendar.current.component(.hour, from: Date())
        isNightMode = hour >= 22 || hour < 5

        let maxUsage = gauges.map(\.percentUsed).max() ?? 0
        let overallSt = worstStatus(from: gauges)
        let mood = Mood.from(maxUsage: maxUsage, overallStatus: overallSt)
        let isSleeping = (mood == .sleeping)

        // Typing cadence multiplier from recent keystrokes
        keystrokeTimestamps = keystrokeTimestamps.filter { now - $0 <= 3.0 }
        let typingBoost: CGFloat = keystrokeTimestamps.count >= 8 ? 1.4 : 1.0

        // Speed modifiers
        let sessionMult: CGFloat = sessionActive ? 1.5 : 1.0
        let nightMult: CGFloat   = isNightMode   ? 0.6 : 1.0

        // Decay event timers
        if flashWhiteT > 0   { flashWhiteT   = max(0, flashWhiteT   - CGFloat(dt)) }
        if refreshPulseT > 0 {
            refreshPulseT = max(0, refreshPulseT - CGFloat(dt))
            spinAngle += CGFloat(dt) * CGFloat.pi * 5.0
        }

        // Update particles (move + fade)
        particles = particles.compactMap { var p = $0
            p.x += p.vx
            p.y += p.vy
            p.alpha -= 0.028
            return p.alpha > 0 ? p : nil
        }

        // Jump physics
        if jumpVY != 0 || jumpY > 0 {
            jumpVY -= 300.0 * CGFloat(dt)
            jumpY   = max(0, jumpY + jumpVY * CGFloat(dt))
            if jumpY <= 0 { jumpY = 0; jumpVY = 0 }
        }

        // Night star emission (every ~4 s)
        if isNightMode && now - lastNightStarEmit > 4.0 {
            lastNightStarEmit = now
            spawnParticle(glyph: "⭐",
                          x: x + CGFloat.random(in: -4...8),
                          y: 22, vx: CGFloat.random(in: 0.1...0.4), vy: 0.5, size: 7)
        }

        // Zzz emission when sleeping (every 2 s)
        if isSleeping && now - lastZzzEmit > 2.0 {
            lastZzzEmit = now
            spawnParticle(glyph: "💤", x: x + dir * 8.0, y: 22, vx: dir * 0.2, vy: 0.5, size: 8)
        }

        // RGB Gamer Mode cycle check
        if now > nextGamerModeCheck {
            nextGamerModeCheck = now + 90.0
            if Double.random(in: 0...1) < 0.35 {
                rgbGamerEndTime = now + 3.5
                spawnParticle(glyph: "🌈", x: x, y: 24, vx: 0, vy: 0.6, size: 9)
            }
        }

        // Thought Bubble expiration / trigger
        if let thought = currentThought, now > thought.expireTime {
            currentThought = nil
        }
        if currentThought == nil && now > nextThoughtCheckTime && !isSleeping && mood != .depleted {
            nextThoughtCheckTime = now + Double.random(in: 10.0...18.0)
            rollNextThought(now: now, mood: mood)
        }

        // Laser dot expiration
        if let laser = laserDot, now > laser.expireTime {
            laserDot = nil
        }

        // Ultra Panic jitter & flame sputters (Quota >= 95%)
        if mood == .panic && maxUsage >= 95.0 {
            isUltraPanicJitter = (CGFloat.random(in: -1.5...1.5), CGFloat.random(in: -1.0...1.0))
            if now > nextUltraPanicSputter {
                nextUltraPanicSputter = now + 0.22
                spawnParticle(
                    glyph: Bool.random() ? "💥" : "🔥",
                    x: x + CGFloat.random(in: -6...6),
                    y: 24,
                    vx: CGFloat.random(in: -0.3...0.3),
                    vy: 0.85,
                    size: 9
                )
            }
        } else {
            isUltraPanicJitter = (0, 0)
        }

        let rightLimit = petRightBoundary
        let pad: CGFloat = 24.0

        // Depleted: Clawd lies flat, no movement
        if mood == .depleted {
            currentAntic = .normal
            needsDisplay = true
            return
        }

        if dragging {
            currentAntic = .normal
            phase += dt * (isTickling ? 25.0 : 17.0)
            wiggleT += dt
            needsDisplay = true
            return
        }

        // Throw physics + somersault in mid-air
        if abs(throwVX) > 1.0 {
            currentAntic = .normal
            x += throwVX * CGFloat(dt)
            throwVX *= 0.92
            if abs(throwVX) > 15.0 {
                somersaultAngle += (throwVX > 0 ? 1 : -1) * CGFloat(dt) * (abs(throwVX) / 5.0)
            } else {
                somersaultAngle = 0
            }
            if x < pad        { x = pad;        throwVX = -throwVX * 0.5; dir =  1 }
            if x > rightLimit { x = rightLimit; throwVX = -throwVX * 0.5; dir = -1 }
            phase += CGFloat(dt) * (abs(throwVX) / 9.0)
            needsDisplay = true
            return
        } else {
            somersaultAngle = 0
        }

        // Sleeping: stand still
        if isSleeping {
            currentAntic = .normal
            needsDisplay = true
            return
        }

        // MARK: - Update Active Antic
        anticAngle = 0.0
        ninjaAlpha = 1.0

        switch currentAntic {
        case .normal:
            // Check if we should start a random antic
            if now > nextAnticCheckTime {
                nextAnticCheckTime = now + Double.random(in: 4.5...8.0)
                if Double.random(in: 0...1) < 0.65 {
                    rollNextAntic(now: now, mood: mood, maxUsage: maxUsage)
                }
            }

            // Normal walking
            let finalSpeed = mood.speed * sessionMult * nightMult * typingBoost
            x += dir * finalSpeed * CGFloat(dt)
            if x > rightLimit { x = rightLimit; dir = -1 }
            if x < pad        { x = pad;        dir =  1 }
            phase += CGFloat(dt) * (finalSpeed / 9.0)

        case .zoomies(let endTime):
            if now >= endTime {
                currentAntic = .normal
                spawnParticle(glyph: "💧", x: x + 6, y: 24, vx: 0, vy: 0.5, size: 8, color: .systemTeal)
            } else {
                let zoomSpeed: CGFloat = 95.0
                x += dir * zoomSpeed * CGFloat(dt)
                if x > rightLimit { x = rightLimit; dir = -1 }
                if x < pad        { x = pad;        dir =  1 }
                phase += CGFloat(dt) * 22.0
                if Bool.random() {
                    spawnParticle(glyph: "💨", x: x - dir * 10, y: 4, vx: -dir * 0.4, vy: 0.1, size: 8)
                }
            }

        case .moonwalk(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                // Moves opposite to dir!
                let moonSpeed: CGFloat = 18.0
                x -= dir * moonSpeed * CGFloat(dt)
                if x > rightLimit { x = rightLimit; dir = 1 }
                if x < pad        { x = pad;        dir = -1 }
                phase += CGFloat(dt) * 12.0
                if Bool.random() {
                    spawnParticle(glyph: "✨", x: x - dir * 4, y: 3, vx: 0, vy: 0.3, size: 8)
                }
            }

        case .tripAndFall(let endTime, let fPhase):
            if now >= endTime {
                currentAntic = .normal
            } else if fPhase == 0 {
                // Fallen on face
                if endTime - now < 0.7 {
                    // Transition to getting up
                    currentAntic = .tripAndFall(endTime: endTime, phase: 1)
                    jumpVY = 35.0
                    spawnParticle(glyph: "💫", x: x, y: 22, vx: 0, vy: 0.6, size: 9)
                }
            }

        case .powerNap(let endTime):
            if now >= endTime {
                currentAntic = .normal
                jumpVY = 50.0
                spawnParticle(glyph: "💡", x: x, y: 24, vx: 0, vy: 0.7, size: 9)
            } else {
                if Bool.random() && Int(now * 2) % 2 == 0 {
                    spawnParticle(glyph: "💤", x: x + 6, y: 20, vx: 0.2, vy: 0.4, size: 8)
                }
            }

        case .joyHop(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                if jumpY == 0 && jumpVY == 0 {
                    jumpVY = 65.0
                    let g = ["💖", "🎶", "✨"].randomElement() ?? "✨"
                    spawnParticle(glyph: g, x: x, y: 22, vx: 0, vy: 0.6, size: 9)
                }
            }

        case .breakdance(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                anticAngle += CGFloat(dt) * 14.0
                if Bool.random() {
                    spawnParticle(glyph: "✨", x: x + CGFloat.random(in: -8...8), y: 12, vx: 0, vy: 0.5, size: 8)
                }
            }

        case .backflip(let endTime):
            if now >= endTime {
                currentAntic = .normal
                anticAngle = 0
            } else {
                let progress = 1.0 - (endTime - now) / 1.2
                anticAngle = progress * 2.0 * .pi * (dir > 0 ? 1 : -1)
                if jumpY == 0 && jumpVY == 0 && progress < 0.2 {
                    jumpVY = 85.0
                }
            }

        case .skateboard(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                let skateSpeed: CGFloat = 55.0
                x += dir * skateSpeed * CGFloat(dt)
                if x > rightLimit { x = rightLimit; dir = -1 }
                if x < pad        { x = pad;        dir =  1 }
                if Bool.random() {
                    spawnParticle(glyph: "✨", x: x - dir * 10, y: 2, vx: -dir * 0.4, vy: 0.2, size: 7)
                }
            }

        case .theWorm(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                x += dir * 14.0 * CGFloat(dt)
                if x > rightLimit { x = rightLimit; dir = -1 }
                if x < pad        { x = pad;        dir =  1 }
                phase += CGFloat(dt) * 10.0
            }

        case .ninjaVanish(let endTime, let targetX):
            if now >= endTime {
                currentAntic = .normal
                ninjaAlpha = 1.0
                spawnParticle(glyph: "✨", x: x, y: 20, vx: 0, vy: 0.6, size: 9)
            } else {
                let remaining = endTime - now
                if remaining > 1.2 {
                    // Poofing away
                    ninjaAlpha = 0.0
                } else if remaining > 0.4 {
                    // Teleporting
                    x = targetX
                    ninjaAlpha = 0.0
                } else {
                    ninjaAlpha = 1.0
                }
            }

        case .glassKnock(let endTime):
            if now >= endTime {
                currentAntic = .normal
            }

        case .quotaSnack(let endTime):
            if now >= endTime {
                currentAntic = .normal
            } else {
                // Walk right to boundary
                if x < rightLimit - 4 {
                    x = min(rightLimit, x + 25.0 * CGFloat(dt))
                    dir = 1
                }
                if Bool.random() && Int(now * 3) % 2 == 0 {
                    spawnParticle(glyph: "✨", x: rightLimit + 4, y: 8, vx: -0.2, vy: -0.3, size: 6)
                }
            }

        case .bellyRub(let endTime):
            if now >= endTime {
                currentAntic = .normal
            }

        case .highFive(let endTime, let succeeded):
            if now >= endTime {
                currentAntic = .normal
            } else if !succeeded {
                // Waiting for high five
                currentThought = ThoughtBubble(text: "✋", expireTime: now + 0.5)
            }

        case .laserChase(let targetX, let expireTime):
            if now >= expireTime || abs(x - targetX) < 4.0 {
                currentAntic = .normal
                jumpVY = 45.0
                spawnParticle(glyph: "🎯", x: x, y: 22, vx: 0, vy: 0.6, size: 9)
            } else {
                dir = (targetX > x) ? 1 : -1
                x += dir * 55.0 * CGFloat(dt)
                phase += CGFloat(dt) * 16.0
            }
        }

        needsDisplay = true
    }

    // MARK: - Antics Roller

    private func rollNextAntic(now: TimeInterval, mood: Mood, maxUsage: Double) {
        guard mood != .sleeping && mood != .depleted else { return }

        // Panic mode antics
        if mood == .panic {
            let panicChoices: [(PetAntic, Int)] = [
                (.zoomies(endTime: now + 2.5), 5),
                (.tripAndFall(endTime: now + 1.8, phase: 0), 3)
            ]
            if let chosen = weightedRandom(from: panicChoices) {
                startAntic(chosen, now: now)
            }
            return
        }

        var anticsPool: [(PetAntic, Int)] = [
            (.zoomies(endTime: now + 2.8), 4),
            (.moonwalk(endTime: now + 2.5), 4),
            (.tripAndFall(endTime: now + 1.8, phase: 0), 3),
            (.powerNap(endTime: now + 2.5), 3),
            (.joyHop(endTime: now + 1.5), 4),
            (.breakdance(endTime: now + 2.2), 3),
            (.backflip(endTime: now + 1.2), 4),
            (.skateboard(endTime: now + 3.0), 4),
            (.theWorm(endTime: now + 2.5), 3),
            (.ninjaVanish(endTime: now + 1.8, targetX: CGFloat.random(in: 40...max(40, petRightBoundary - 20))), 3),
            (.glassKnock(endTime: now + 2.0), 3),
            (.quotaSnack(endTime: now + 2.2), 3),
            (.bellyRub(endTime: now + 3.0), 3),
            (.highFive(endTime: now + 3.2, succeeded: false), 3)
        ]

        let hour = Calendar.current.component(.hour, from: Date())
        if hour == 12 {
            anticsPool.append((.quotaSnack(endTime: now + 3.0), 6))
        }

        if let chosen = weightedRandom(from: anticsPool) {
            startAntic(chosen, now: now)
        }
    }

    private func startAntic(_ antic: PetAntic, now: TimeInterval) {
        currentAntic = antic

        // Specific particle or effect per antic
        switch antic {
        case .ninjaVanish:
            spawnParticle(glyph: "💨", x: x, y: 18, vx: 0, vy: 0.5, size: 9)
        case .glassKnock:
            spawnParticle(glyph: "👋", x: x, y: 22, vx: 0, vy: 0.6, size: 8)
        default:
            break
        }
    }

    private func weightedRandom<T>(from items: [(T, Int)]) -> T? {
        let totalWeight = items.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        var roll = Int.random(in: 0..<totalWeight)
        for (item, weight) in items {
            if roll < weight { return item }
            roll -= weight
        }
        return items.first?.0
    }

    private func rollNextThought(now: TimeInterval, mood: Mood) {
        let weights: [(ThoughtEmotion, Int)]
        switch mood {
        case .panic:
            weights = [
                (.dramatic, 30), (.hyped, 25), (.sleepy, 20),
                (.curious, 10), (.zen, 5), (.happy, 5), (.silly, 5)
            ]
        case .tired:
            weights = [
                (.sleepy, 35), (.zen, 25), (.curious, 10),
                (.dramatic, 10), (.happy, 10), (.silly, 5), (.love, 5)
            ]
        case .brisk:
            weights = [
                (.hyped, 30), (.happy, 20), (.cool, 15),
                (.curious, 15), (.silly, 10), (.zen, 5), (.dramatic, 5)
            ]
        case .calm:
            weights = [
                (.happy, 15), (.curious, 15), (.cool, 15),
                (.zen, 15), (.love, 15), (.silly, 15),
                (.hyped, 5), (.dramatic, 3), (.sleepy, 2)
            ]
        case .depleted, .sleeping:
            weights = [(.sleepy, 50), (.zen, 50)]
        }

        let emotion = weightedRandom(from: weights) ?? (ThoughtEmotion.allCases.randomElement() ?? .happy)
        let emoji = emotion.emojis.randomElement() ?? "✨"
        currentThought = ThoughtBubble(text: emoji, expireTime: now + 2.5)
    }

    // MARK: - Touch Interaction

    public override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .any, in: self).first else { return }
        let tx = touch.location(in: self).x

        // Tap on readout area → open ClaudeBar
        if tx >= readoutStartX - 10.0 {
            NSWorkspace.shared.open(URL(string: "claudebar://open")!)
            return
        }

        markActivity()
        touchStartTime = Date.timeIntervalSinceReferenceDate
        touchStartPos = tx

        // Grab Clawd if close
        if abs(tx - x) < 36.0 {
            // High-five success tap
            if case .highFive(let endTime, let succeeded) = currentAntic, !succeeded {
                currentAntic = .highFive(endTime: endTime, succeeded: true)
                currentThought = ThoughtBubble(text: "👏", expireTime: Date.timeIntervalSinceReferenceDate + 1.5)
                spawnParticle(glyph: "✨", x: x, y: 22, vx: -0.5, vy: 0.8, size: 10)
                spawnParticle(glyph: "✨", x: x, y: 22, vx: 0.5, vy: 0.8, size: 10)
                spawnParticle(glyph: "💥", x: x, y: 25, vx: 0, vy: 0.6, size: 10)
                jumpVY = 65.0
                return
            }

            // Belly rub reaction
            if case .bellyRub = currentAntic {
                spawnParticle(glyph: "💖", x: x + CGFloat.random(in: -6...6), y: 20, vx: CGFloat.random(in: -0.2...0.2), vy: 0.6, size: 9)
                return
            }

            dragging  = true
            grabDX    = tx - x
            dragVX    = 0
            lastDragX = tx
            isTickling = false
        } else {
            // Tapped on empty area → Laser pointer chase!
            let now = Date.timeIntervalSinceReferenceDate
            let target = min(petRightBoundary, max(24.0, tx))
            laserDot = (x: target, expireTime: now + 4.0)
            currentAntic = .laserChase(targetX: target, expireTime: now + 4.0)
            spawnParticle(glyph: "🔴", x: target, y: 5, vx: 0, vy: 0.2, size: 8)
        }
    }

    public override func touchesMoved(with event: NSEvent) {
        guard dragging, let touch = event.touches(matching: .any, in: self).first else { return }
        let tx = touch.location(in: self).x
        let nx = tx - grabDX
        dragVX    = tx - lastDragX
        lastDragX = tx

        // If finger stayed close to touchStartPos, it's a tickle!
        if abs(tx - touchStartPos) < 6.0 {
            isTickling = true
            currentThought = ThoughtBubble(text: "🥰", expireTime: Date.timeIntervalSinceReferenceDate + 0.8)
            if Bool.random() {
                spawnParticle(glyph: "💖", x: x + CGFloat.random(in: -8...8), y: 22, vx: CGFloat.random(in: -0.3...0.3), vy: 0.5, size: 9)
            }
        } else {
            isTickling = false
        }

        x = max(24.0, min(nx, petRightBoundary))

        if abs(dragVX) > 0.5 { dir = (dragVX > 0) ? 1 : -1 }
        needsDisplay = true
    }

    public override func touchesEnded(with event: NSEvent)    { releaseDrag() }
    public override func touchesCancelled(with event: NSEvent) { releaseDrag() }

    private func releaseDrag() {
        guard dragging else { return }
        dragging = false
        isTickling = false
        let now = Date.timeIntervalSinceReferenceDate
        let duration = now - touchStartTime

        if duration < 0.25 && abs(dragVX) < 1.0 {
            // Quick tap: surprise hop!
            jumpVY = 60.0
            spawnParticle(glyph: "⭐", x: x, y: 24, vx: 0, vy: 0.6, size: 8)
        } else {
            throwVX = dragVX * 12.0
            if abs(throwVX) > 25.0 {
                // High velocity toss: mid-air somersault!
                jumpVY = 40.0
            }
        }
        markActivity()
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let maxUsage = gauges.map(\.percentUsed).max() ?? 0
        let overallSt = worstStatus(from: gauges)
        let mood = Mood.from(maxUsage: maxUsage, overallStatus: overallSt)

        // Ground line across the Touch Bar
        NSColor(white: 1.0, alpha: 0.14).set()
        NSRect(x: 0, y: 1.0, width: bounds.width, height: 1.0).fill()

        drawLaserDot()
        drawMascot(mood: mood, maxUsage: maxUsage)
        drawReadout()
    }

    // MARK: - Laser Dot Drawing

    private func drawLaserDot() {
        guard let laser = laserDot else { return }
        let lx = laser.x
        // Red core
        NSColor(srgbRed: 1.0, green: 0.1, blue: 0.1, alpha: 0.9).set()
        NSBezierPath(ovalIn: NSRect(x: lx - 2.5, y: 2.5, width: 5, height: 5)).fill()
        // Outer halo
        NSColor(srgbRed: 1.0, green: 0.2, blue: 0.2, alpha: 0.35).set()
        NSBezierPath(ovalIn: NSRect(x: lx - 5, y: 0.5, width: 10, height: 9)).fill()
    }

    // MARK: - Mascot Drawing

    private func drawMascot(mood: Mood, maxUsage: Double) {
        guard ninjaAlpha > 0 else {
            drawParticles()
            return
        }

        let px: CGFloat = 1.72
        let feetX: CGFloat = x + isUltraPanicJitter.x
        let baseGroundY: CGFloat = 2.2 + jumpY + isUltraPanicJitter.y

        // Session glow ring: subtle orange oval beneath feet when Claude Code is active
        if sessionActive {
            NSColor(srgbRed: 0.98, green: 0.55, blue: 0.0, alpha: 0.30).set()
            NSBezierPath(ovalIn: NSRect(x: feetX - 13, y: baseGroundY - 1.5, width: 26, height: 5)).fill()
        }

        // Depleted: Clawd lies flat on ground
        if mood == .depleted {
            drawDepletedMascot(x: feetX, y: baseGroundY, px: px)
            drawParticles()
            return
        }

        let isFlipped = dir < 0
        let isSitting  = false
        let isSleeping = mood == .sleeping

        // Body color
        let bodyColor: NSColor
        let now = Date.timeIntervalSinceReferenceDate
        if flashWhiteT > 0 {
            bodyColor = NSColor(white: 1.0, alpha: 0.95)
        } else if now < rgbGamerEndTime {
            // RGB Gamer Mode cycling hue!
            let hue = CGFloat((now * 0.7).truncatingRemainder(dividingBy: 1.0))
            bodyColor = NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.95, alpha: 1.0)
        } else {
            let activePid = gauges.first?.providerId ?? "claude"
            bodyColor = providerBodyColor(for: activePid, mood: mood)
        }
        let eyeColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1.0)

        // Bob: disabled when tired / sitting / sleeping or doing certain antics
        let isWorm: Bool = {
            if case .theWorm = currentAntic { return true }
            return false
        }()
        let bob: CGFloat
        if mood == .tired || isSitting || isSleeping || isWorm { bob = 0 }
        else { bob = ((Int(phase * 2.0) & 1) == 1) ? 0.7 : 0 }
        let feetY = baseGroundY + bob

        // Panic motion streaks
        if mood == .panic {
            bodyColor.withAlphaComponent(0.28).set()
            for i in 1...3 {
                let sx = feetX - dir * (20.0 * px * 0.4 + CGFloat(i) * 5.0)
                NSRect(x: min(sx, sx - dir * 4.0), y: feetY + 8.0, width: 4.0, height: 1.6).fill()
            }
        }

        // Build sprite frame, then apply mood & antics expressions
        let walkStep = (isSitting || isSleeping) ? 0 : Int(phase * 2.0)
        var sprite = Self.walkFrame(step: walkStep)
        applyExpression(&sprite, mood: mood, maxUsage: maxUsage)

        // Graphics Context Save for optional Rotation (Backflip / Breakdance / Somersault)
        NSGraphicsContext.saveGraphicsState()
        let totalAngle = somersaultAngle + anticAngle
        if totalAngle != 0, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.translateBy(x: feetX, y: feetY + 10.0)
            ctx.rotate(by: totalAngle)
            ctx.translateBy(x: -feetX, y: -(feetY + 10.0))
        }

        // Draw 20x20 pixel grid
        for r in 3...17 {
            for c in 0..<20 {
                let v = sprite[r * 20 + c]
                if v == 0 { continue }
                let ink = (v == 2) ? eyeColor : bodyColor
                ink.set()
                let cx = isFlipped ? (19 - c) : c
                let rowUp = CGFloat(17 - r)
                NSRect(
                    x: feetX + (CGFloat(cx) - 10.0) * px,
                    y: feetY + rowUp * px,
                    width: px + 0.4,
                    height: px + 0.4
                ).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        // Props & Antics Overlays
        drawAnticProps(feetX: feetX, feetY: feetY, px: px, flipped: isFlipped, now: now)

        // Tired sweat drop
        if mood == .tired {
            NSColor(srgbRed: 0.42, green: 0.70, blue: 0.94, alpha: 0.95).set()
            NSRect(x: feetX + 8.0, y: feetY + 13.0 * px * 0.9, width: 2.4, height: 3.4).fill()
        }

        // Christmas hat (when christmas theme is active)
        if isChristmasTheme {
            drawChristmasHat(centerX: feetX, feetY: feetY, px: px, flipped: isFlipped)
        }

        // Refresh pulse: '🔄' orbits above head
        if refreshPulseT > 0 {
            let headTopY   = feetY + 14.0 * px
            let orbitR: CGFloat = 7.0
            let qx = feetX + cos(spinAngle) * orbitR
            let qy = headTopY + sin(spinAngle) * orbitR * 0.5
            let pulseAlpha = min(1.0, refreshPulseT * 1.5)
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor(white: 1.0, alpha: pulseAlpha)
            ]
            ("🔄" as NSString).draw(at: NSPoint(x: qx - 4, y: qy), withAttributes: attr)
        }

        // Thought bubble
        if let thought = currentThought {
            drawThoughtBubble(x: feetX, y: feetY, thought: thought)
        }

        // Draw floating particles on top
        drawParticles()
    }

    // MARK: - Antic Props Drawing

    private func drawAnticProps(feetX: CGFloat, feetY: CGFloat, px: CGFloat, flipped: Bool, now: TimeInterval) {
        switch currentAntic {
        case .skateboard:
            let boardW: CGFloat = 22.0
            let boardH: CGFloat = 2.4
            let boardRect = NSRect(x: feetX - boardW / 2.0, y: feetY - 1.5, width: boardW, height: boardH)
            NSColor(srgbRed: 0.82, green: 0.50, blue: 0.22, alpha: 1.0).set()
            NSBezierPath(roundedRect: boardRect, xRadius: 1.2, yRadius: 1.2).fill()
            // Wheels
            NSColor(white: 0.25, alpha: 1.0).set()
            NSRect(x: feetX - 7.5, y: feetY - 3.2, width: 3.0, height: 2.2).fill()
            NSRect(x: feetX + 4.5, y: feetY - 3.2, width: 3.0, height: 2.2).fill()

        case .glassKnock(let endTime):
            let progress = 1.0 - (endTime - now) / 2.0
            let r = CGFloat(progress * 14.0)
            let ringRect = NSRect(x: feetX - r, y: feetY + 8 - r, width: r * 2, height: r * 2)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = 1.2
            NSColor(white: 1.0, alpha: max(0, 0.7 - progress)).set()
            ringPath.stroke()

        default:
            break
        }
    }

    // MARK: - Thought Bubble Drawing

    private func drawThoughtBubble(x: CGFloat, y: CGFloat, thought: ThoughtBubble) {
        let font = NSFont.systemFont(ofSize: 10.0, weight: .semibold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.10, alpha: 0.96)
        ]
        let str = thought.text as NSString
        let textSize = str.size(withAttributes: attr)
        let bubbleW = textSize.width + 10.0
        let bubbleH = max(13.0, textSize.height + 3.0)

        // Determine horizontal placement (left vs right of Clawd)
        // Prefer placing in the direction Clawd is facing (in front of him)
        let clawdHalfW: CGFloat = 17.2
        let gap: CGFloat = 7.0
        let rightCandidateX = x + clawdHalfW + gap
        let leftCandidateX = x - clawdHalfW - gap - bubbleW

        let onRight: Bool
        if dir >= 0 {
            // Facing right: place on right unless running out of space before gauges
            if rightCandidateX + bubbleW <= petRightBoundary {
                onRight = true
            } else if leftCandidateX >= 4.0 {
                onRight = false
            } else {
                onRight = true
            }
        } else {
            // Facing left: place on left unless running out of space at left wall
            if leftCandidateX >= 4.0 {
                onRight = false
            } else if rightCandidateX + bubbleW <= petRightBoundary {
                onRight = true
            } else {
                onRight = false
            }
        }

        let rawBubbleX = onRight ? rightCandidateX : leftCandidateX
        let bubbleX = max(4.0, min(rawBubbleX, petRightBoundary - bubbleW))

        // Position vertically around eye/chest level (well clear of ground and Touch Bar ceiling)
        let bubbleY: CGFloat = 8.5
        let bubbleMidY = bubbleY + bubbleH / 2.0

        NSGraphicsContext.saveGraphicsState()

        let bubbleRect = NSRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 4.0, yRadius: 4.0)
        NSColor(white: 0.98, alpha: 0.95).set()
        bubblePath.fill()

        // Subtle border
        NSColor(white: 0.70, alpha: 0.40).set()
        bubblePath.lineWidth = 0.6
        bubblePath.stroke()

        // Horizontal pointer tail pointing toward Clawd's head/face
        let tailPath = NSBezierPath()
        if onRight {
            let tailBaseX = bubbleX
            let tailTipX = max(x + clawdHalfW + 1.0, bubbleX - 5.0)
            tailPath.move(to: NSPoint(x: tailBaseX + 0.5, y: bubbleMidY + 2.5))
            tailPath.line(to: NSPoint(x: tailTipX, y: bubbleMidY))
            tailPath.line(to: NSPoint(x: tailBaseX + 0.5, y: bubbleMidY - 2.5))
            tailPath.close()
        } else {
            let tailBaseX = bubbleX + bubbleW
            let tailTipX = min(x - clawdHalfW - 1.0, bubbleX + bubbleW + 5.0)
            tailPath.move(to: NSPoint(x: tailBaseX - 0.5, y: bubbleMidY + 2.5))
            tailPath.line(to: NSPoint(x: tailTipX, y: bubbleMidY))
            tailPath.line(to: NSPoint(x: tailBaseX - 0.5, y: bubbleMidY - 2.5))
            tailPath.close()
        }
        NSColor(white: 0.98, alpha: 0.95).set()
        tailPath.fill()
        NSColor(white: 0.70, alpha: 0.40).set()
        tailPath.lineWidth = 0.6
        tailPath.stroke()

        // Text inside bubble
        let textOrigin = NSPoint(
            x: bubbleX + (bubbleW - textSize.width) / 2.0,
            y: bubbleY + (bubbleH - textSize.height) / 2.0
        )
        str.draw(at: textOrigin, withAttributes: attr)

        NSGraphicsContext.restoreGraphicsState()
    }

    /// Draw Clawd lying flat when all quota is depleted.
    private func drawDepletedMascot(x: CGFloat, y: CGFloat, px: CGFloat) {
        let bodyColor = NSColor(white: 0.50, alpha: 0.80)
        bodyColor.set()
        for c in 3...16 {
            NSRect(x: x + CGFloat(c - 10) * px, y: y + 3.5,              width: px + 0.4, height: px + 0.4).fill()
            NSRect(x: x + CGFloat(c - 10) * px, y: y + 3.5 + (px + 0.4), width: px + 0.4, height: px + 0.4).fill()
        }
        NSColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 0.7).set()
        NSRect(x: x - 4.5, y: y + 4.5, width: 3.8, height: 0.9).fill()
        NSRect(x: x + 1.5, y: y + 4.5, width: 3.8, height: 0.9).fill()
    }

    /// Draw a tiny pixel Santa hat above Clawd's head when Christmas theme is active.
    private func drawChristmasHat(centerX: CGFloat, feetY: CGFloat, px: CGFloat, flipped: Bool) {
        let headTopY: CGFloat = feetY + 14.5 * px
        let tipOffsetX: CGFloat = flipped ? 3.5 : -3.5

        NSColor(srgbRed: 0.80, green: 0.10, blue: 0.10, alpha: 1.0).set()
        let hatPath = NSBezierPath()
        hatPath.move(to: NSPoint(x: centerX - 7,          y: headTopY))
        hatPath.line(to: NSPoint(x: centerX + 7,          y: headTopY))
        hatPath.line(to: NSPoint(x: centerX + tipOffsetX, y: headTopY + 9))
        hatPath.close()
        hatPath.fill()

        NSColor(white: 0.92, alpha: 0.95).set()
        NSRect(x: centerX - 8, y: headTopY - 1, width: 16, height: 2.5).fill()

        NSColor(white: 0.95, alpha: 1.0).set()
        NSBezierPath(ovalIn: NSRect(
            x: centerX + tipOffsetX - 2.5,
            y: headTopY + 6.5,
            width: 5, height: 5
        )).fill()
    }

    // MARK: - Expression System

    /// Overwrite eye pixels (value == 2) in the sprite to reflect current mood and antics.
    private func applyExpression(_ sprite: inout [UInt8], mood: Mood, maxUsage: Double) {
        for i in 0..<sprite.count where sprite[i] == 2 { sprite[i] = 1 }

        func setEye(_ r: Int, _ c: Int) {
            let idx = r * 20 + c
            guard idx >= 0, idx < sprite.count else { return }
            sprite[idx] = 2
        }

        // Antics overrides
        switch currentAntic {
        case .powerNap:
            // Flat closed eyes
            setEye(7, 6);  setEye(7, 7);  setEye(7, 8)
            setEye(7, 12); setEye(7, 13); setEye(7, 14)
            return

        case .tripAndFall(_, let fPhase):
            if fPhase == 0 {
                // X eyes
                setEye(6, 7); setEye(7, 6); setEye(7, 8); setEye(8, 7)
                setEye(6, 13); setEye(7, 12); setEye(7, 14); setEye(8, 13)
                return
            }

        case .bellyRub, .joyHop:
            // Laughing/smiling caret eyes ^ ^
            setEye(6, 7); setEye(5, 8); setEye(6, 9)
            setEye(6, 11); setEye(5, 12); setEye(6, 13)
            return

        default:
            break
        }

        if isTickling {
            setEye(6, 7); setEye(5, 8); setEye(6, 9)
            setEye(6, 11); setEye(5, 12); setEye(6, 13)
            return
        }

        // Mood expressions
        switch mood {
        case .calm, .brisk:
            setEye(6, 7);  setEye(6, 13)

        case .tired:
            setEye(7, 7);  setEye(7, 13)

        case .panic:
            if maxUsage >= 95.0 {
                // Ultra panic: wide eyes + screaming open mouth
                setEye(6, 6);  setEye(6, 7)
                setEye(6, 13); setEye(6, 14)
                setEye(10, 9); setEye(10, 10); setEye(10, 11)
                setEye(11, 9); setEye(11, 10); setEye(11, 11)
            } else {
                setEye(6, 6);  setEye(6, 7)
                setEye(6, 13); setEye(6, 14)
            }

        case .depleted, .sleeping:
            setEye(7, 6);  setEye(7, 7);  setEye(7, 8)
            setEye(7, 12); setEye(7, 13); setEye(7, 14)
        }
    }

    // MARK: - Provider Body Color

    /// Clawd's body color: 100% active provider brand color (or default terracotta for Claude).
    private func providerBodyColor(for providerId: String, mood: Mood) -> NSColor {
        let base = NSColor(srgbRed: 0.804, green: 0.498, blue: 0.416, alpha: 1.0)

        let tint: NSColor?
        switch providerId.lowercased() {
        case "claude":
            tint = base
        case "gemini":
            tint = NSColor(srgbRed: 0.91, green: 0.72, blue: 0.27, alpha: 1.0)  // golden
        case "copilot":
            tint = NSColor(srgbRed: 0.38, green: 0.55, blue: 0.93, alpha: 1.0)  // indigo
        case "antigravity":
            tint = NSColor(srgbRed: 0.72, green: 0.35, blue: 0.85, alpha: 1.0)  // violet
        case "codex":
            tint = NSColor(srgbRed: 0.18, green: 0.72, blue: 0.68, alpha: 1.0)  // teal
        case "deepseek":
            tint = NSColor(srgbRed: 0.42, green: 0.52, blue: 1.00, alpha: 1.0)  // blue
        case "grok", "vercel", "vercel-gateway":
            tint = NSColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)  // near-white
        case "cursor":
            tint = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.82, alpha: 1.0)  // cyan
        case "kimi":
            tint = NSColor(srgbRed: 0.30, green: 0.65, blue: 0.95, alpha: 1.0)  // sky blue
        case "kiro":
            tint = NSColor(srgbRed: 0.55, green: 0.35, blue: 0.85, alpha: 1.0)  // purple
        case "bedrock":
            tint = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.20, alpha: 1.0)  // amber
        case "mistral":
            tint = NSColor(srgbRed: 1.00, green: 0.55, blue: 0.00, alpha: 1.0)  // orange
        case "minimax":
            tint = NSColor(srgbRed: 0.91, green: 0.27, blue: 0.42, alpha: 1.0)  // red-pink
        case "zai":
            tint = NSColor(srgbRed: 0.35, green: 0.60, blue: 1.00, alpha: 1.0)  // azure
        case "ampcode":
            tint = NSColor(srgbRed: 0.95, green: 0.30, blue: 0.25, alpha: 1.0)  // hot red
        case "omp":
            tint = NSColor(srgbRed: 0.30, green: 0.85, blue: 0.55, alpha: 1.0)  // mint
        case "opencode", "opencode-go":
            tint = NSColor(srgbRed: 0.52, green: 0.36, blue: 1.00, alpha: 1.0)  // lavender
        case "alibaba":
            tint = NSColor(srgbRed: 1.00, green: 0.60, blue: 0.00, alpha: 1.0)  // orange
        default:
            tint = nil
        }

        let bodyColor = tint ?? base

        if mood == .sleeping {
            let rgb = bodyColor.usingColorSpace(.sRGB) ?? bodyColor
            return NSColor(
                srgbRed: rgb.redComponent   * 0.82,
                green:  rgb.greenComponent  * 0.82,
                blue:   rgb.blueComponent   * 0.82,
                alpha:  1.0
            )
        }

        return bodyColor
    }

    // MARK: - Particle System

    private func spawnParticle(glyph: String, x: CGFloat, y: CGFloat,
                                vx: CGFloat, vy: CGFloat, size: CGFloat, color: NSColor? = nil) {
        particles.append(Particle(x: x, y: y, vx: vx, vy: vy, alpha: 1.0, glyph: glyph, size: size, color: color))
    }

    private func drawParticles() {
        for p in particles {
            let ink = p.color ?? NSColor(white: 1.0, alpha: p.alpha)
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: p.size, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(p.alpha)
            ]
            (p.glyph as NSString).draw(at: NSPoint(x: p.x - p.size * 0.25, y: p.y), withAttributes: attr)
        }
    }

    // MARK: - Helpers

    private func markActivity() {
        lastActivityTime = Date.timeIntervalSinceReferenceDate
    }

    /// Returns the most severe quota status across all gauges.
    private func worstStatus(from gauges: [TouchBarProviderGauge]) -> QuotaStatus {
        gauges.reduce(QuotaStatus.healthy) { worst, gauge in
            severity(of: gauge.status) > severity(of: worst) ? gauge.status : worst
        }
    }

    private func severity(of status: QuotaStatus) -> Int {
        switch status {
        case .healthy:  return 0
        case .warning:  return 1
        case .critical: return 2
        case .depleted: return 3
        }
    }

    // MARK: - Walk Frame

    private static func walkFrame(step: Int) -> [UInt8] {
        var buf = baseGrid
        for r in 14...16 {
            for c in 0..<20 {
                if buf[r * 20 + c] == 1 { buf[r * 20 + c] = 0 }
            }
        }
        let legX  = [5, 8, 12, 15]
        let swing = [
            [-1,  1, -1,  1],
            [ 0,  0,  0,  0],
            [ 1, -1,  1, -1],
            [ 0,  0,  0,  0]
        ]
        let lift = [
            [0, 1, 0, 1],
            [0, 0, 0, 0],
            [1, 0, 1, 0],
            [0, 0, 0, 0]
        ]
        let ph = step & 3
        for i in 0..<4 {
            let c = legX[i] + swing[ph][i]
            if c < 0 || c >= 20 { continue }
            let bottom = (lift[ph][i] == 1) ? 15 : 16
            for r in 14...bottom {
                buf[r * 20 + c] = 1
            }
        }
        return buf
    }

    // MARK: - Readout & Bars

    private func drawReadout() {
        guard !gauges.isEmpty else { return }

        let n = CGFloat(gauges.count)
        let totalReadoutW = readoutWidth
        let cellW = (totalReadoutW - cellGap * (n - 1)) / n
        let startX = readoutStartX

        for (i, gauge) in gauges.enumerated() {
            let cx = startX + CGFloat(i) * (cellW + cellGap)
            let icon = (i < cachedIcons.count) ? cachedIcons[i] : nil

            // Draw vertical separator | between cells
            if i > 0 {
                let sepX = cx - cellGap / 2.0
                NSColor(white: 1.0, alpha: 0.25).set()
                NSRect(x: sepX, y: 3.0, width: 1.0, height: 22.0).fill()
            }

            drawGaugeCell(gauge, icon: icon, x: cx, width: cellW)
        }
    }

    private func drawGaugeCell(_ gauge: TouchBarProviderGauge, icon: NSImage?, x: CGFloat, width: CGFloat) {
        let textY: CGFloat = 15.0
        let barY: CGFloat  = 3.0
        let barH: CGFloat  = 7.0

        let pct   = Int(gauge.percentUsed.rounded())
        let alarm = (pct >= 90)

        let ink: NSColor
        if alarm {
            ink = NSColor(srgbRed: 0.902, green: 0.208, blue: 0.180, alpha: 1.0) // Alert Red
        } else if pct >= 50 {
            ink = NSColor(srgbRed: 0.949, green: 0.706, blue: 0.161, alpha: 1.0) // Warning Amber
        } else {
            ink = NSColor(srgbRed: 0.173, green: 0.533, blue: 0.945, alpha: 1.0) // Healthy Blue
        }

        // 1. Draw Provider Icon
        var nameX = x
        let iconRect = NSRect(x: x, y: textY - 1.0, width: 14.0, height: 14.0)
        if let icon {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: iconRect, xRadius: 3.0, yRadius: 3.0)
            clip.addClip()
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            nameX += 18.0
        } else {
            let symName = ProviderVisualIdentityLookup.symbolIcon(for: gauge.providerId)
            if let sym = NSImage(systemSymbolName: symName, accessibilityDescription: nil) {
                let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                if let configSym = sym.withSymbolConfiguration(conf) {
                    configSym.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    nameX += 18.0
                }
            }
        }

        // 2. Draw Provider Name
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
        ]
        (gauge.name as NSString).draw(at: NSPoint(x: nameX, y: textY), withAttributes: nameAttr)
        let nameW = (gauge.name as NSString).size(withAttributes: nameAttr).width

        // 3. Draw Reset Countdown Note
        if let reset = gauge.resetText, !reset.isEmpty {
            let noteAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.55)
            ]
            (reset as NSString).draw(at: NSPoint(x: nameX + nameW + 5.0, y: textY + 1.0), withAttributes: noteAttr)
        }

        // 4. Draw Percentage + Alarm Right-aligned
        let numStr = alarm ? "\(pct)% !" : "\(pct)%"
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: ink
        ]
        let numW = (numStr as NSString).size(withAttributes: numAttr).width
        (numStr as NSString).draw(at: NSPoint(x: x + width - numW, y: textY - 1.0), withAttributes: numAttr)

        // 5. Progress Bar Track (100% reference)
        let trackRect = NSRect(x: x, y: barY, width: width, height: barH)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 2.0, yRadius: 2.0)
        NSColor(white: 1.0, alpha: 0.32).set()
        trackPath.fill()

        // 6. Filled Bar
        let fillW = max(0, min(width, width * CGFloat(pct) / 100.0))
        if fillW > 0 {
            let fillRect = NSRect(x: x, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2.0, yRadius: 2.0)
            ink.set()
            fillPath.fill()
        }
    }

    private func loadProviderIcon(for providerId: String) -> NSImage? {
        let pid = providerId.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userPath = home.appendingPathComponent(".claudebar/icons/\(pid).png").path
        if FileManager.default.fileExists(atPath: userPath), let img = NSImage(contentsOfFile: userPath) {
            return img
        }
        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: pid)
        if let img = NSImage(named: assetName) {
            return img
        }
        return nil
    }
}
