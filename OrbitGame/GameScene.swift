import SpriteKit
import UIKit

final class GameScene: SKScene {
    private enum Phase {
        case ready
        case playing
        case gameOver
    }

    private enum GameMode: String {
        case normal
        case daily
    }

    private enum PanelKind {
        case missions
        case themes
        case stats
        case settings
    }

    private enum ObstacleKind {
        case standard
        case wide
        case fast
        case drifting
        case pulse
        case phase
    }

    private enum FlowEvent {
        case none
        case surge
        case calm
    }

    private enum ThemeID: String, CaseIterable {
        case classic
        case neon
        case solar
        case ice
        case matrix
        case void

        var displayName: String {
            switch self {
            case .classic: return "CLASSIC"
            case .neon: return "NEON"
            case .solar: return "SOLAR"
            case .ice: return "ICE"
            case .matrix: return "MATRIX"
            case .void: return "VOID"
            }
        }
    }

    private enum MissionKind: CaseIterable {
        case score
        case nearMisses
        case combo
        case runs
        case survive
    }

    private struct ThemePalette {
        let background: UIColor
        let backgroundHue: CGFloat
        let backgroundSaturation: CGFloat
        let backgroundBrightness: CGFloat
        let orbit: UIColor
        let activeOrbit: UIColor
        let player: UIColor
        let accent: UIColor
        let accentSoft: UIColor
        let secondaryAccent: UIColor
    }

    private struct Mission {
        let kind: MissionKind
        let target: Int

        var title: String {
            switch kind {
            case .score: return "Faça \(target) pontos em uma partida"
            case .nearMisses: return "Faça \(target) near misses hoje"
            case .combo: return "Alcance combo ×\(target)"
            case .runs: return "Jogue \(target) partidas hoje"
            case .survive: return "Sobreviva \(target) segundos"
            }
        }
    }

    private struct PendingSpawn {
        var remaining: TimeInterval
        let ringIndex: Int
        let lead: CGFloat
        let kind: ObstacleKind
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }

    private final class OrbitObstacle {
        let node: SKShapeNode
        let ringIndex: Int
        let kind: ObstacleKind
        let collisionAngle: CGFloat
        let baseAngularVelocity: CGFloat
        let oscillationAmplitude: CGFloat
        var angle: CGFloat
        var age: TimeInterval = 0
        var scored = false

        init(
            ringIndex: Int,
            kind: ObstacleKind,
            angle: CGFloat,
            angularVelocity: CGFloat,
            color: UIColor
        ) {
            self.ringIndex = ringIndex
            self.kind = kind
            self.angle = angle

            let width: CGFloat
            let height: CGFloat
            let glow: CGFloat
            let speedMultiplier: CGFloat

            switch kind {
            case .standard:
                width = 46
                height = 12
                glow = 3
                collisionAngle = 0.115
                speedMultiplier = 1
                oscillationAmplitude = 0

            case .wide:
                width = 72
                height = 13
                glow = 5
                collisionAngle = 0.155
                speedMultiplier = 0.92
                oscillationAmplitude = 0

            case .fast:
                width = 40
                height = 11
                glow = 4
                collisionAngle = 0.105
                speedMultiplier = 1.65
                oscillationAmplitude = 0

            case .drifting:
                width = 52
                height = 12
                glow = 4
                collisionAngle = 0.12
                speedMultiplier = 0.95
                oscillationAmplitude = 0.18

            case .pulse:
                width = 50
                height = 11
                glow = 6
                collisionAngle = 0.115
                speedMultiplier = 1.08
                oscillationAmplitude = 0

            case .phase:
                width = 44
                height = 10
                glow = 5
                collisionAngle = 0.105
                speedMultiplier = 1.22
                oscillationAmplitude = 0
            }

            baseAngularVelocity = angularVelocity * speedMultiplier

            let node = SKShapeNode()
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            node.path = CGPath(
                roundedRect: rect,
                cornerWidth: height / 2,
                cornerHeight: height / 2,
                transform: nil
            )
            node.fillColor = color
            node.strokeColor = .clear
            node.glowWidth = glow
            node.zPosition = 20
            self.node = node
        }

        func angularVelocity() -> CGFloat {
            guard oscillationAmplitude > 0 else { return baseAngularVelocity }
            let wave = sin(CGFloat(age) * 3.1) * oscillationAmplitude
            return baseAngularVelocity + wave
        }
    }

    // MARK: - Storage

    private let defaults = UserDefaults.standard

    private enum StorageKey {
        static let bestScore = "orbit.bestScore"
        static let selectedTheme = "orbit.selectedTheme"
        static let totalRuns = "orbit.stats.totalRuns"
        static let totalPoints = "orbit.stats.totalPoints"
        static let totalNearMisses = "orbit.stats.totalNearMisses"
        static let bestCombo = "orbit.stats.bestCombo"
        static let longestRun = "orbit.stats.longestRun"
        static let soundEnabled = "orbit.settings.soundEnabled"
        static let hapticsEnabled = "orbit.settings.hapticsEnabled"

        static let dailyDay = "orbit.daily.day"
        static let dailyAttempts = "orbit.daily.attempts"
        static let dailyBest = "orbit.daily.best"
        static let dailyMissionBestScore = "orbit.daily.missionBestScore"
        static let dailyRuns = "orbit.daily.runs"
        static let dailyNearMisses = "orbit.daily.nearMisses"
        static let dailyBestCombo = "orbit.daily.bestCombo"
        static let dailyLongestRun = "orbit.daily.longestRun"
    }

    // MARK: - Layers

    private let worldLayer = SKNode()
    private let hudLayer = SKNode()
    private let readyControlsLayer = SKNode()
    private let panelLayer = SKNode()

    // MARK: - Scene nodes

    private let innerOrbit = SKShapeNode()
    private let outerOrbit = SKShapeNode()
    private let centerDot = SKShapeNode(circleOfRadius: 4)
    private let player = SKShapeNode(circleOfRadius: 10)
    private let playerGlow = SKShapeNode(circleOfRadius: 18)

    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let bestLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let subtitleLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let instructionLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let feedbackLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let gameOverMenuLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let gameOverShareLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    private let normalModeLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let dailyModeLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let missionSummaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let themesSummaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let rankingSummaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let statsSummaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let settingsSummaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")

    // MARK: - Game state

    private var phase: Phase = .ready
    private var gameMode: GameMode = .normal
    private var activePanel: PanelKind?

    private var orbitCenter: CGPoint = .zero
    private var innerRadius: CGFloat = 86
    private var outerRadius: CGFloat = 146
    private var currentRadius: CGFloat = 146
    private var targetRadius: CGFloat = 146
    private var playerAngle: CGFloat = -.pi / 2

    private var angularSpeed: CGFloat = 1.72
    private var score = 0
    private var bestScore: Int
    private var comboCount = 0
    private var comboMultiplier = 1
    private var runBestCombo = 1
    private var runNearMisses = 0
    private var runSwitches = 0
    private var spawnIndex = 0

    private var lastUpdateTime: TimeInterval = 0
    private var spawnTimer: TimeInterval = 0
    private var nextSpawnDelay: TimeInterval = 1.15
    private var elapsedPlayingTime: TimeInterval = 0
    private var switchCooldown: TimeInterval = 0
    private var trailTimer: TimeInterval = 0
    private var slowMotionTimer: TimeInterval = 0
    private var activeFlowEvent: FlowEvent = .none
    private var flowEventTimer: TimeInterval = 0
    private var nextFlowEventAt: TimeInterval = 13

    private var obstacles: [OrbitObstacle] = []
    private var pendingSpawns: [PendingSpawn] = []
    private var dailyGenerator = SeededGenerator(seed: 1)
    private var dailyFlowGenerator = SeededGenerator(seed: 2)

    private var selectedThemeID: ThemeID
    private var themeHitRects: [(ThemeID, CGRect)] = []
    private var soundSettingRect: CGRect = .zero
    private var hapticsSettingRect: CGRect = .zero

#if !targetEnvironment(simulator)
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
#endif

    // MARK: - Lifecycle

    override init(size: CGSize) {
        UserDefaults.standard.register(defaults: [
            StorageKey.soundEnabled: true,
            StorageKey.hapticsEnabled: true
        ])
        bestScore = UserDefaults.standard.integer(forKey: StorageKey.bestScore)
        selectedThemeID = ThemeID(
            rawValue: UserDefaults.standard.string(forKey: StorageKey.selectedTheme) ?? ""
        ) ?? .classic

        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = palette.background
    }

    required init?(coder aDecoder: NSCoder) {
        UserDefaults.standard.register(defaults: [
            StorageKey.soundEnabled: true,
            StorageKey.hapticsEnabled: true
        ])
        bestScore = UserDefaults.standard.integer(forKey: StorageKey.bestScore)
        selectedThemeID = ThemeID(
            rawValue: UserDefaults.standard.string(forKey: StorageKey.selectedTheme) ?? ""
        ) ?? .classic
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 120

        ensureDailyState()
        if !isThemeUnlocked(selectedThemeID) {
            selectedThemeID = .classic
            defaults.set(selectedThemeID.rawValue, forKey: StorageKey.selectedTheme)
        }

        NotificationCenter.default.removeObserver(self, name: .orbitGameCenterDidDismiss, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gameCenterDidDismiss),
            name: .orbitGameCenterDidDismiss,
            object: nil
        )

        setupScene()
        layoutScene()
        applyTheme()
        showReadyState()
        prepareHaptics()
        if soundEnabled {
            OrbitAudioEngine.shared.prepare()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard oldSize != .zero else { return }
        layoutScene()
    }

    func setAppActive(_ active: Bool) {
        isPaused = !active
        if active {
            ensureDailyState()
            lastUpdateTime = 0

            if phase == .ready {
                rebuildReadyControlsLayer()
                readyControlsLayer.isHidden = false
                readyControlsLayer.alpha = 1
                showReadyControls(true)
                refreshReadyUI()
            } else {
                refreshReadyUIIfNeeded()
            }
        }
    }

    @objc private func gameCenterDidDismiss() {
        guard phase == .ready else { return }
        rebuildReadyControlsLayer()
        showReadyControls(true)
        refreshReadyUI()
    }

    // MARK: - Theme

    private var palette: ThemePalette {
        switch selectedThemeID {
        case .classic:
            return ThemePalette(
                background: UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1),
                backgroundHue: 0.625,
                backgroundSaturation: 0.42,
                backgroundBrightness: 0.075,
                orbit: UIColor(white: 1, alpha: 0.16),
                activeOrbit: UIColor(white: 1, alpha: 0.58),
                player: .white,
                accent: UIColor(red: 1.0, green: 0.28, blue: 0.36, alpha: 1),
                accentSoft: UIColor(red: 1.0, green: 0.47, blue: 0.40, alpha: 1),
                secondaryAccent: UIColor(red: 0.92, green: 0.34, blue: 0.58, alpha: 1)
            )

        case .neon:
            return ThemePalette(
                background: UIColor(red: 0.025, green: 0.018, blue: 0.075, alpha: 1),
                backgroundHue: 0.72,
                backgroundSaturation: 0.70,
                backgroundBrightness: 0.09,
                orbit: UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.22),
                activeOrbit: UIColor(red: 0.45, green: 0.92, blue: 1.0, alpha: 0.72),
                player: .white,
                accent: UIColor(red: 0.98, green: 0.20, blue: 0.84, alpha: 1),
                accentSoft: UIColor(red: 0.58, green: 0.32, blue: 1.0, alpha: 1),
                secondaryAccent: UIColor(red: 0.20, green: 0.92, blue: 1.0, alpha: 1)
            )

        case .solar:
            return ThemePalette(
                background: UIColor(red: 0.07, green: 0.025, blue: 0.012, alpha: 1),
                backgroundHue: 0.055,
                backgroundSaturation: 0.78,
                backgroundBrightness: 0.10,
                orbit: UIColor(red: 1.0, green: 0.76, blue: 0.30, alpha: 0.18),
                activeOrbit: UIColor(red: 1.0, green: 0.82, blue: 0.34, alpha: 0.72),
                player: UIColor(red: 1.0, green: 0.95, blue: 0.83, alpha: 1),
                accent: UIColor(red: 1.0, green: 0.30, blue: 0.12, alpha: 1),
                accentSoft: UIColor(red: 1.0, green: 0.58, blue: 0.13, alpha: 1),
                secondaryAccent: UIColor(red: 1.0, green: 0.76, blue: 0.18, alpha: 1)
            )

        case .ice:
            return ThemePalette(
                background: UIColor(red: 0.018, green: 0.055, blue: 0.085, alpha: 1),
                backgroundHue: 0.55,
                backgroundSaturation: 0.64,
                backgroundBrightness: 0.10,
                orbit: UIColor(red: 0.55, green: 0.86, blue: 1.0, alpha: 0.20),
                activeOrbit: UIColor(red: 0.70, green: 0.93, blue: 1.0, alpha: 0.78),
                player: .white,
                accent: UIColor(red: 0.22, green: 0.72, blue: 1.0, alpha: 1),
                accentSoft: UIColor(red: 0.50, green: 0.88, blue: 1.0, alpha: 1),
                secondaryAccent: UIColor(red: 0.42, green: 0.57, blue: 1.0, alpha: 1)
            )

        case .matrix:
            return ThemePalette(
                background: UIColor(red: 0.008, green: 0.04, blue: 0.018, alpha: 1),
                backgroundHue: 0.35,
                backgroundSaturation: 0.82,
                backgroundBrightness: 0.07,
                orbit: UIColor(red: 0.18, green: 1.0, blue: 0.42, alpha: 0.17),
                activeOrbit: UIColor(red: 0.23, green: 1.0, blue: 0.48, alpha: 0.72),
                player: UIColor(red: 0.83, green: 1.0, blue: 0.87, alpha: 1),
                accent: UIColor(red: 0.15, green: 0.95, blue: 0.38, alpha: 1),
                accentSoft: UIColor(red: 0.38, green: 1.0, blue: 0.58, alpha: 1),
                secondaryAccent: UIColor(red: 0.02, green: 0.73, blue: 0.26, alpha: 1)
            )

        case .void:
            return ThemePalette(
                background: UIColor(red: 0.006, green: 0.006, blue: 0.012, alpha: 1),
                backgroundHue: 0.78,
                backgroundSaturation: 0.35,
                backgroundBrightness: 0.028,
                orbit: UIColor(white: 1, alpha: 0.10),
                activeOrbit: UIColor(white: 1, alpha: 0.50),
                player: UIColor(white: 1, alpha: 1),
                accent: UIColor(red: 0.60, green: 0.40, blue: 1.0, alpha: 1),
                accentSoft: UIColor(red: 0.82, green: 0.70, blue: 1.0, alpha: 1),
                secondaryAccent: UIColor(red: 0.34, green: 0.22, blue: 0.75, alpha: 1)
            )
        }
    }

    // MARK: - Setup

    private func setupScene() {
        removeAllChildren()

        worldLayer.zPosition = 0
        hudLayer.zPosition = 100
        readyControlsLayer.zPosition = 20
        panelLayer.zPosition = 500
        addChild(worldLayer)
        addChild(hudLayer)
        hudLayer.addChild(readyControlsLayer)
        addChild(panelLayer)

        innerOrbit.fillColor = .clear
        innerOrbit.lineWidth = 2
        innerOrbit.glowWidth = 1
        innerOrbit.zPosition = 1
        worldLayer.addChild(innerOrbit)

        outerOrbit.fillColor = .clear
        outerOrbit.lineWidth = 2
        outerOrbit.glowWidth = 1
        outerOrbit.zPosition = 1
        worldLayer.addChild(outerOrbit)

        centerDot.strokeColor = .clear
        centerDot.glowWidth = 5
        centerDot.zPosition = 5
        worldLayer.addChild(centerDot)

        playerGlow.strokeColor = .clear
        playerGlow.zPosition = 9
        worldLayer.addChild(playerGlow)

        player.lineWidth = 1
        player.glowWidth = 7
        player.zPosition = 10
        worldLayer.addChild(player)

        scoreLabel.fontSize = 56
        configureHUDLabel(scoreLabel)
        hudLayer.addChild(scoreLabel)

        bestLabel.fontSize = 13
        configureHUDLabel(bestLabel)
        hudLayer.addChild(bestLabel)

        comboLabel.fontSize = 13
        configureHUDLabel(comboLabel)
        comboLabel.alpha = 0
        hudLayer.addChild(comboLabel)

        titleLabel.fontSize = 46
        configureHUDLabel(titleLabel)
        hudLayer.addChild(titleLabel)

        subtitleLabel.fontSize = 16
        configureHUDLabel(subtitleLabel)
        hudLayer.addChild(subtitleLabel)

        instructionLabel.fontSize = 13
        configureHUDLabel(instructionLabel)
        hudLayer.addChild(instructionLabel)

        feedbackLabel.fontSize = 15
        configureHUDLabel(feedbackLabel)
        feedbackLabel.alpha = 0
        hudLayer.addChild(feedbackLabel)

        gameOverMenuLabel.fontSize = 13
        configureHUDLabel(gameOverMenuLabel)
        gameOverMenuLabel.text = "MENU"
        gameOverMenuLabel.fontColor = UIColor(white: 1, alpha: 0.60)
        gameOverMenuLabel.isHidden = true
        hudLayer.addChild(gameOverMenuLabel)

        gameOverShareLabel.fontSize = 13
        configureHUDLabel(gameOverShareLabel)
        gameOverShareLabel.text = "COMPARTILHAR"
        gameOverShareLabel.fontColor = UIColor(white: 1, alpha: 0.60)
        gameOverShareLabel.isHidden = true
        hudLayer.addChild(gameOverShareLabel)

        normalModeLabel.fontSize = 13
        configureHUDLabel(normalModeLabel)

        dailyModeLabel.fontSize = 13
        configureHUDLabel(dailyModeLabel)

        missionSummaryLabel.fontSize = 11
        configureHUDLabel(missionSummaryLabel)

        themesSummaryLabel.fontSize = 11
        configureHUDLabel(themesSummaryLabel)

        rankingSummaryLabel.fontSize = 12
        configureHUDLabel(rankingSummaryLabel)

        statsSummaryLabel.fontSize = 10
        configureHUDLabel(statsSummaryLabel)

        settingsSummaryLabel.fontSize = 10
        configureHUDLabel(settingsSummaryLabel)

        rebuildReadyControlsLayer()
        panelLayer.isHidden = true
    }

    private func configureHUDLabel(_ label: SKLabelNode) {
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
    }

    private func layoutScene() {
        orbitCenter = CGPoint(x: size.width / 2, y: size.height * 0.47)

        let shortSide = min(size.width, size.height)
        innerRadius = min(92, shortSide * 0.23)
        outerRadius = min(154, shortSide * 0.39)

        innerOrbit.path = CGPath(
            ellipseIn: CGRect(
                x: orbitCenter.x - innerRadius,
                y: orbitCenter.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ),
            transform: nil
        )

        outerOrbit.path = CGPath(
            ellipseIn: CGRect(
                x: orbitCenter.x - outerRadius,
                y: orbitCenter.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            ),
            transform: nil
        )

        centerDot.position = orbitCenter

        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 84)
        bestLabel.position = CGPoint(x: size.width / 2, y: size.height - 126)
        comboLabel.position = CGPoint(x: size.width / 2, y: size.height - 151)

        titleLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y + 18)
        subtitleLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y - 28)
        feedbackLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y + outerRadius + 42)
        // Keep the instruction clearly separated from the Home controls.
        // On devices with a shorter screen we lift the orbit slightly instead of
        // squeezing the footer rows together.
        let compactHeight = size.height < 720
        if compactHeight {
            orbitCenter.y = size.height * 0.50

            innerOrbit.path = CGPath(
                ellipseIn: CGRect(
                    x: orbitCenter.x - innerRadius,
                    y: orbitCenter.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                ),
                transform: nil
            )

            outerOrbit.path = CGPath(
                ellipseIn: CGRect(
                    x: orbitCenter.x - outerRadius,
                    y: orbitCenter.y - outerRadius,
                    width: outerRadius * 2,
                    height: outerRadius * 2
                ),
                transform: nil
            )
            centerDot.position = orbitCenter
            titleLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y + 18)
            subtitleLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y - 28)
            feedbackLabel.position = CGPoint(x: size.width / 2, y: orbitCenter.y + outerRadius + 42)
        }

        let safeBottom = view?.safeAreaInsets.bottom ?? 0
        let utilityY = max(58, safeBottom + 27)
        let rankingY = utilityY + 42
        let modeY = rankingY + 43
        let instructionY = modeY + 46
        instructionLabel.position = CGPoint(x: size.width / 2, y: instructionY)

        let gameOverActionY = max(104, size.height * 0.125)
        gameOverShareLabel.position = CGPoint(x: size.width * 0.34, y: gameOverActionY)
        gameOverMenuLabel.position = CGPoint(x: size.width * 0.66, y: gameOverActionY)

        layoutReadyControls()

        if phase != .playing {
            currentRadius = outerRadius
            targetRadius = outerRadius
        }

        updatePlayerPosition()
        updateObstaclePositions()
    }

    private func layoutReadyControls() {
        // Footer is laid out as four independent rows so labels never overlap:
        // instruction -> mode selector -> ranking -> utilities.
        // The bottom row is anchored above the device safe area.
        let safeBottom = view?.safeAreaInsets.bottom ?? 0
        let utilityY = max(58, safeBottom + 27)
        let rankingY = utilityY + 42
        let modeY = rankingY + 43
        let instructionY = modeY + 46

        normalModeLabel.position = CGPoint(x: size.width * 0.32, y: modeY)
        dailyModeLabel.position = CGPoint(x: size.width * 0.68, y: modeY)
        rankingSummaryLabel.position = CGPoint(x: size.width * 0.50, y: rankingY)
        missionSummaryLabel.position = CGPoint(x: size.width * 0.14, y: utilityY)
        themesSummaryLabel.position = CGPoint(x: size.width * 0.38, y: utilityY)
        statsSummaryLabel.position = CGPoint(x: size.width * 0.62, y: utilityY)
        settingsSummaryLabel.position = CGPoint(x: size.width * 0.86, y: utilityY)

        // instructionLabel lives in hudLayer rather than readyControlsLayer,
        // but it belongs visually to the same footer stack.
        instructionLabel.position = CGPoint(x: size.width * 0.50, y: instructionY)
    }

    private func rebuildReadyControlsLayer() {
        readyControlsLayer.removeAllActions()
        readyControlsLayer.removeAllChildren()

        let controls: [SKLabelNode] = [
            normalModeLabel,
            dailyModeLabel,
            rankingSummaryLabel,
            missionSummaryLabel,
            themesSummaryLabel,
            statsSummaryLabel,
            settingsSummaryLabel
        ]

        for control in controls {
            control.removeAllActions()
            control.isHidden = false
            control.alpha = 1
            control.zPosition = 0
            readyControlsLayer.addChild(control)
        }

        layoutReadyControls()
    }

    private func applyTheme() {
        backgroundColor = palette.background
        player.fillColor = palette.player
        player.strokeColor = palette.player
        playerGlow.fillColor = palette.player.withAlphaComponent(0.12)
        centerDot.fillColor = palette.accent
        comboLabel.fontColor = palette.accentSoft
        feedbackLabel.fontColor = palette.accentSoft
        updateVisualProgression()
        updateOrbitHighlight()
        refreshReadyUIIfNeeded()
    }

    // MARK: - Game states

    private func showReadyState() {
        ensureDailyState()
        activePanel = nil
        hidePanel()
        phase = .ready

        worldLayer.position = .zero
        worldLayer.alpha = 1
        clearObstacles()
        pendingSpawns.removeAll()

        titleLabel.fontSize = 46
        scoreLabel.text = ""
        bestLabel.text = bestScore > 0 ? "MELHOR  \(bestScore)" : ""
        comboLabel.text = ""
        comboLabel.alpha = 0
        feedbackLabel.alpha = 0
        gameOverMenuLabel.isHidden = true
        gameOverShareLabel.isHidden = true
        rebuildReadyControlsLayer()

        titleLabel.text = "ORBIT"
        subtitleLabel.text = gameMode == .daily ? "A mesma órbita. Três tentativas." : "Um toque. Duas órbitas."
        instructionLabel.text = dailyCanPlay || gameMode == .normal ? "TOQUE PARA COMEÇAR" : "DIÁRIO ENCERRADO POR HOJE"

        titleLabel.alpha = 1
        subtitleLabel.alpha = 1
        instructionLabel.alpha = 1
        player.alpha = 1
        playerGlow.alpha = 1

        showReadyControls(true)
        refreshReadyUI()
        applyTheme()
        pulsePlayer()
    }

    private func startGame() {
        ensureDailyState()

        if gameMode == .daily {
            guard dailyCanPlay else {
                showFeedback("3 TENTATIVAS USADAS", color: palette.accentSoft)
                return
            }
            consumeDailyAttempt()
            dailyGenerator = SeededGenerator(seed: dailySeed())
            dailyFlowGenerator = SeededGenerator(seed: dailySeed() ^ 0x464C4F575F45564E)
        }

        worldLayer.removeAllActions()
        worldLayer.position = .zero
        hudLayer.removeAllActions()
        titleLabel.removeAllActions()
        subtitleLabel.removeAllActions()
        instructionLabel.removeAllActions()
        feedbackLabel.removeAllActions()
        scoreLabel.removeAction(forKey: "scorePulse")
        comboLabel.removeAllActions()

        clearObstacles()
        pendingSpawns.removeAll()

        phase = .playing
        score = 0
        comboCount = 0
        comboMultiplier = 1
        runBestCombo = 1
        runNearMisses = 0
        runSwitches = 0
        spawnIndex = 0
        angularSpeed = 1.72
        elapsedPlayingTime = 0
        spawnTimer = 0
        nextSpawnDelay = 0.92
        switchCooldown = 0
        trailTimer = 0
        slowMotionTimer = 0
        activeFlowEvent = .none
        flowEventTimer = 0
        nextFlowEventAt = gameMode == .daily ? 14 : 12
        playerAngle = -.pi / 2
        currentRadius = outerRadius
        targetRadius = outerRadius
        lastUpdateTime = 0

        scoreLabel.text = "0"
        scoreLabel.alpha = 1
        bestLabel.text = gameMode == .daily
            ? "DIÁRIO  \(dailyBestScore)"
            : (bestScore > 0 ? "MELHOR  \(bestScore)" : "")
        comboLabel.text = ""
        comboLabel.alpha = 0
        feedbackLabel.alpha = 0
        gameOverMenuLabel.isHidden = true
        gameOverShareLabel.isHidden = true

        titleLabel.text = ""
        subtitleLabel.text = ""
        instructionLabel.text = "TOQUE PARA TROCAR"
        instructionLabel.alpha = 0.78
        showReadyControls(false)

        player.removeAllActions()
        player.setScale(1)
        player.alpha = 1
        playerGlow.removeAllActions()
        playerGlow.setScale(1)
        playerGlow.alpha = 1

        backgroundColor = palette.background
        updateVisualProgression()
        updateOrbitHighlight()
        updatePlayerPosition()
        playSound(.start)

        instructionLabel.run(
            .sequence([
                .wait(forDuration: 1.6),
                .fadeOut(withDuration: 0.35)
            ]),
            withKey: "instructionFade"
        )
    }

    private func endGame() {
        guard phase == .playing else { return }
        phase = .gameOver
        pendingSpawns.removeAll()

        let previousBest = bestScore
        let isNewBest = gameMode == .normal && score > bestScore

        if isNewBest {
            bestScore = score
            defaults.set(bestScore, forKey: StorageKey.bestScore)
        }

        recordFinishedRun()
        reportRunToGameCenter()

        playGameOverHaptic()
        playSound(.gameOver)
        shakeWorld()

        scoreLabel.text = "\(score)"
        bestLabel.text = gameMode == .daily
            ? "DIÁRIO  \(dailyBestScore)"
            : "MELHOR  \(bestScore)"
        comboLabel.alpha = 0

        if isNewBest {
            titleLabel.text = "NOVO RECORDE"
            titleLabel.fontSize = 28
            subtitleLabel.text = "Seu melhor Orbit até agora."
        } else if gameMode == .normal, previousBest > 0, score < previousBest, previousBest - score <= 5 {
            titleLabel.text = "QUASE!"
            titleLabel.fontSize = 40
            subtitleLabel.text = "Faltaram \(previousBest - score) para o recorde."
        } else if gameMode == .daily {
            titleLabel.text = dailyCanPlay ? "DIÁRIO" : "FIM DO DIÁRIO"
            titleLabel.fontSize = dailyCanPlay ? 40 : 28
            subtitleLabel.text = dailyCanPlay
                ? "Restam \(dailyAttemptsRemaining) tentativa\(dailyAttemptsRemaining == 1 ? "" : "s")."
                : "Volte amanhã para uma nova órbita."
        } else {
            titleLabel.text = "FIM"
            titleLabel.fontSize = 46
            subtitleLabel.text = "Mais uma?"
        }

        instructionLabel.removeAction(forKey: "instructionFade")
        instructionLabel.alpha = 1
        instructionLabel.text = gameMode == .daily && !dailyCanPlay
            ? "DIÁRIO ENCERRADO POR HOJE"
            : "TOQUE PARA TENTAR DE NOVO"

        gameOverMenuLabel.text = gameMode == .daily && !dailyCanPlay ? "VOLTAR" : "MENU"
        gameOverMenuLabel.isHidden = false
        gameOverMenuLabel.alpha = 1
        gameOverShareLabel.text = "COMPARTILHAR"
        gameOverShareLabel.isHidden = false
        gameOverShareLabel.alpha = 1

        titleLabel.alpha = 0
        subtitleLabel.alpha = 0
        titleLabel.run(.fadeIn(withDuration: 0.16))
        subtitleLabel.run(.sequence([
            .wait(forDuration: 0.06),
            .fadeIn(withDuration: 0.18)
        ]))

        showReadyControls(false)

        explode(at: player.position, color: palette.accent, count: 24, power: 92)
        ringBurst(at: player.position, color: palette.player)

        player.removeAllActions()
        player.run(.sequence([
            .group([
                .scale(to: 2.0, duration: 0.09),
                .fadeOut(withDuration: 0.09)
            ]),
            .wait(forDuration: 0.18),
            .run { [weak self] in
                self?.player.setScale(1)
                self?.player.alpha = 1
                self?.playerGlow.alpha = 1
            }
        ]))
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if activePanel != nil {
            handlePanelTouch(at: location)
            return
        }

        switch phase {
        case .ready:
            if handleReadyControlTouch(at: location) {
                return
            }
            playImpact(intensity: 0.68)
            startGame()

        case .playing:
            toggleOrbit()

        case .gameOver:
            playImpact(intensity: 0.55)
            titleLabel.fontSize = 46

            let shareHitRect = CGRect(
                x: gameOverShareLabel.position.x - 76,
                y: gameOverShareLabel.position.y - 28,
                width: 152,
                height: 56
            )
            let menuHitRect = CGRect(
                x: gameOverMenuLabel.position.x - 58,
                y: gameOverMenuLabel.position.y - 28,
                width: 116,
                height: 56
            )

            if shareHitRect.contains(location) {
                shareCurrentScore()
            } else if menuHitRect.contains(location) || (gameMode == .daily && !dailyCanPlay) {
                showReadyState()
            } else {
                startGame()
            }
        }
    }

    private func handleReadyControlTouch(at point: CGPoint) -> Bool {
        let modeY = normalModeLabel.position.y
        if abs(point.y - modeY) < 28 {
            if point.x < size.width / 2 {
                gameMode = .normal
            } else {
                gameMode = .daily
            }
            playSelectionHaptic()
            refreshReadyUI()
            subtitleLabel.text = gameMode == .daily ? "A mesma órbita. Três tentativas." : "Um toque. Duas órbitas."
            instructionLabel.text = dailyCanPlay || gameMode == .normal ? "TOQUE PARA COMEÇAR" : "DIÁRIO ENCERRADO POR HOJE"
            return true
        }

        let rankingY = rankingSummaryLabel.position.y
        if abs(point.y - rankingY) < 25 {
            playSelectionHaptic()
            GameCenterService.shared.showRanking()
            return true
        }

        let utilityY = missionSummaryLabel.position.y
        if abs(point.y - utilityY) < 24 {
            playSelectionHaptic()
            if point.x < size.width * 0.26 {
                openPanel(.missions)
            } else if point.x < size.width * 0.50 {
                openPanel(.themes)
            } else if point.x < size.width * 0.74 {
                openPanel(.stats)
            } else {
                openPanel(.settings)
            }
            return true
        }

        return false
    }

    private func toggleOrbit() {
        guard switchCooldown <= 0 else { return }
        switchCooldown = 0.10
        runSwitches += 1

        let goingInner = abs(targetRadius - outerRadius) < 1
        targetRadius = goingInner ? innerRadius : outerRadius

        playImpact(intensity: 0.38)
        playSound(.switchOrbit)
        burst(at: player.position, color: palette.player)

        player.removeAction(forKey: "tapPop")
        player.run(.sequence([
            .scale(to: 1.22, duration: 0.05),
            .scale(to: 1.0, duration: 0.09)
        ]), withKey: "tapPop")

        updateOrbitHighlight()
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard phase == .playing else {
            lastUpdateTime = currentTime
            return
        }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        let rawDT = min(currentTime - lastUpdateTime, 1.0 / 20.0)
        lastUpdateTime = currentTime

        elapsedPlayingTime += rawDT
        switchCooldown = max(0, switchCooldown - rawDT)
        updateFlowEvent(deltaTime: rawDT)

        let timeScale: TimeInterval = slowMotionTimer > 0 ? 0.48 : 1.0
        slowMotionTimer = max(0, slowMotionTimer - rawDT)
        let dt = rawDT * timeScale

        spawnTimer += dt
        trailTimer += rawDT

        let progressionValue = gameMode == .daily
            ? CGFloat(elapsedPlayingTime) * 0.012 + CGFloat(spawnIndex) * 0.004
            : CGFloat(elapsedPlayingTime) * 0.018 + CGFloat(score) * 0.010

        let baseAngularSpeed = min(4.15, 1.72 + progressionValue)
        angularSpeed = baseAngularSpeed * flowSpeedMultiplier
        playerAngle = normalizedAngle(playerAngle + angularSpeed * CGFloat(dt))

        let interpolation = min(1, CGFloat(rawDT) * 15)
        currentRadius += (targetRadius - currentRadius) * interpolation

        updatePendingSpawns(deltaTime: dt)

        if spawnTimer >= nextSpawnDelay * flowSpawnDelayMultiplier {
            spawnTimer = 0
            spawnPattern()
        }

        let trailInterval: TimeInterval = UIAccessibility.isReduceMotionEnabled ? 0.095 : 0.045
        if trailTimer >= trailInterval {
            trailTimer = 0
            spawnTrailDot()
        }

        updatePlayerPosition()

        if updateObstacles(deltaTime: dt) {
            endGame()
        }
    }

    private func updatePlayerPosition() {
        let point = point(onRadius: currentRadius, angle: playerAngle)
        player.position = point
        playerGlow.position = point
    }

    // MARK: - Obstacles and patterns

    private func spawnPattern() {
        spawnIndex += 1
        let roll = randomInt(0..<100)
        let ring = randomInt(0..<2)
        let tierValue = gameMode == .daily ? spawnIndex : score

        if tierValue < 5 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .standard)
            nextSpawnDelay = randomDouble(0.90...1.17)
            return
        }

        if tierValue < 12 {
            if roll < 72 {
                spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .standard)
            } else if roll < 90 {
                spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .wide)
            } else {
                spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .fast)
            }
            nextSpawnDelay = randomDouble(0.79...1.09)
            return
        }

        if roll < 42 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .standard)
            nextSpawnDelay = randomDouble(0.70...0.99)

        } else if roll < 62 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .wide)
            nextSpawnDelay = randomDouble(0.80...1.08)

        } else if roll < 78 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .fast)
            nextSpawnDelay = randomDouble(0.74...1.02)

        } else if roll < 88 && tierValue >= 18 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .drifting)
            nextSpawnDelay = randomDouble(0.80...1.07)

        } else if roll < 92 && tierValue >= 24 {
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .pulse)
            nextSpawnDelay = randomDouble(0.76...1.02)

        } else if roll < 96 && tierValue >= 30 {
            // Phase obstacles fade in quickly, rewarding early visual reading.
            spawnObstacle(ringIndex: ring, lead: randomLead(), kind: .phase)
            nextSpawnDelay = randomDouble(0.76...1.00)

        } else if roll >= 98 && tierValue >= 36 {
            // Three-step zig-zag. The generous spacing keeps it demanding but readable.
            spawnObstacle(ringIndex: ring, lead: 1.52, kind: .standard)
            pendingSpawns.append(PendingSpawn(
                remaining: 0.38,
                ringIndex: ring == 0 ? 1 : 0,
                lead: 1.42,
                kind: .fast
            ))
            pendingSpawns.append(PendingSpawn(
                remaining: 0.78,
                ringIndex: ring,
                lead: 1.34,
                kind: randomBool() ? .phase : .standard
            ))
            nextSpawnDelay = randomDouble(1.20...1.36)

        } else {
            // Two-step patterns always alternate rings and keep a minimum reaction window.
            spawnObstacle(ringIndex: ring, lead: 1.48, kind: .standard)
            pendingSpawns.append(PendingSpawn(
                remaining: tierValue > 35 ? 0.34 : 0.39,
                ringIndex: ring == 0 ? 1 : 0,
                lead: 1.38,
                kind: tierValue > 26 && randomBool() ? .fast : .standard
            ))
            nextSpawnDelay = randomDouble(1.04...1.24)
        }
    }

    private func randomLead() -> CGFloat {
        randomCGFloat(1.31...2.05)
    }

    private func updatePendingSpawns(deltaTime: TimeInterval) {
        guard !pendingSpawns.isEmpty else { return }

        for index in pendingSpawns.indices.reversed() {
            pendingSpawns[index].remaining -= deltaTime
            if pendingSpawns[index].remaining <= 0 {
                let pending = pendingSpawns.remove(at: index)
                spawnObstacle(
                    ringIndex: pending.ringIndex,
                    lead: pending.lead,
                    kind: pending.kind
                )
            }
        }
    }

    private func spawnObstacle(ringIndex: Int, lead: CGFloat, kind: ObstacleKind) {
        let ringRadius = ringIndex == 0 ? innerRadius : outerRadius
        let startAngle = normalizedAngle(playerAngle + lead)

        let tier = gameMode == .daily ? CGFloat(spawnIndex) : CGFloat(score)
        let speedGrowth = 1 + min(tier * 0.006, 0.36)
        let opposingSpeed = -randomCGFloat(0.23...0.44) * speedGrowth

        let obstacle = OrbitObstacle(
            ringIndex: ringIndex,
            kind: kind,
            angle: startAngle,
            angularVelocity: opposingSpeed,
            color: obstacleColor(for: kind)
        )

        obstacles.append(obstacle)
        worldLayer.addChild(obstacle.node)

        obstacle.node.setScale(0.35)
        obstacle.node.alpha = 0
        obstacle.node.run(.group([
            .scale(to: 1, duration: 0.14),
            .fadeIn(withDuration: 0.14)
        ]))

        if kind == .pulse && !UIAccessibility.isReduceMotionEnabled {
            obstacle.node.run(
                .repeatForever(.sequence([
                    .fadeAlpha(to: 0.42, duration: 0.22),
                    .fadeAlpha(to: 1.0, duration: 0.22)
                ])),
                withKey: "pulseObstacle"
            )
        } else if kind == .phase {
            obstacle.node.alpha = UIAccessibility.isReduceMotionEnabled ? 0.9 : 0.28
            obstacle.node.run(.fadeAlpha(to: 1.0, duration: UIAccessibility.isReduceMotionEnabled ? 0.06 : 0.42), withKey: "phaseReveal")
        }

        position(obstacle, radius: ringRadius)
    }

    private func obstacleColor(for kind: ObstacleKind) -> UIColor {
        switch kind {
        case .standard: return palette.accent
        case .wide: return palette.accentSoft
        case .fast: return palette.accent.withAlphaComponent(0.98)
        case .drifting: return palette.secondaryAccent
        case .pulse: return palette.player.withAlphaComponent(0.92)
        case .phase: return palette.secondaryAccent.withAlphaComponent(0.92)
        }
    }

    /// Returns true when a collision occurred. The round ends only after the
    /// collection traversal completes, keeping scene mutation deterministic.
    private func updateObstacles(deltaTime: TimeInterval) -> Bool {
        var toRemove: [OrbitObstacle] = []
        var didCollide = false

        for obstacle in obstacles {
            obstacle.age += deltaTime
            obstacle.angle = normalizedAngle(
                obstacle.angle + obstacle.angularVelocity() * CGFloat(deltaTime)
            )

            let radius = obstacle.ringIndex == 0 ? innerRadius : outerRadius
            position(obstacle, radius: radius)

            let delta = abs(shortestAngularDistance(from: playerAngle, to: obstacle.angle))
            let radialDistance = abs(currentRadius - radius)
            let collisionRadialThreshold: CGFloat = 19

            if delta < obstacle.collisionAngle && radialDistance < collisionRadialThreshold {
                didCollide = true
                break
            }

            let scoreWindow = obstacle.collisionAngle * 0.72
            if !obstacle.scored && delta < scoreWindow && radialDistance >= collisionRadialThreshold {
                obstacle.scored = true
                awardPass(radialDistance: radialDistance)
            }

            if obstacle.scored && obstacle.age > 0.72 {
                toRemove.append(obstacle)
            } else if obstacle.age > 6.5 {
                toRemove.append(obstacle)
            }
        }

        if !toRemove.isEmpty {
            for obstacle in toRemove {
                obstacle.node.removeAllActions()
                obstacle.node.removeFromParent()
            }
            obstacles.removeAll { $0.node.parent == nil }
        }

        return didCollide
    }

    private func awardPass(radialDistance: CGFloat) {
        comboCount += 1
        let previousMultiplier = comboMultiplier
        comboMultiplier = min(4, 1 + comboCount / 5)
        runBestCombo = max(runBestCombo, comboMultiplier)

        let isNearMiss = radialDistance < 39
        var gained = comboMultiplier

        if isNearMiss {
            gained += 1
            runNearMisses += 1
            slowMotionTimer = 0.12
            playRigidImpact(intensity: 0.55)
            playSound(.nearMiss)
            ringPulse(at: player.position)
            showFeedback("NEAR  +1", color: palette.accentSoft)
        } else {
            playSelectionHaptic()
            playSound(.point)
        }

        score += gained
        scoreLabel.text = "\(score)"
        scorePulse()

        if comboMultiplier > 1 {
            comboLabel.text = "COMBO  ×\(comboMultiplier)"
            comboLabel.alpha = 1
        }

        if comboMultiplier > previousMultiplier {
            comboPop()
            playSound(.combo)
            showFeedback("×\(comboMultiplier) COMBO", color: palette.player)
        }

        updateVisualProgression()
    }

    private func updateObstaclePositions() {
        for obstacle in obstacles {
            let radius = obstacle.ringIndex == 0 ? innerRadius : outerRadius
            position(obstacle, radius: radius)
        }
    }

    private func position(_ obstacle: OrbitObstacle, radius: CGFloat) {
        obstacle.node.position = point(onRadius: radius, angle: obstacle.angle)
        obstacle.node.zRotation = obstacle.angle + .pi / 2
    }

    private func clearObstacles() {
        obstacles.forEach {
            $0.node.removeAllActions()
            $0.node.removeFromParent()
        }
        obstacles.removeAll()

        worldLayer.children
            .filter { $0.name == "transientEffect" }
            .forEach { $0.removeFromParent() }
    }

    // MARK: - Flow events

    private var flowSpeedMultiplier: CGFloat {
        switch activeFlowEvent {
        case .none: return 1.0
        case .surge: return 1.16
        case .calm: return 0.84
        }
    }

    private var flowSpawnDelayMultiplier: TimeInterval {
        switch activeFlowEvent {
        case .none: return 1.0
        case .surge: return 0.90
        case .calm: return 1.24
        }
    }

    private func updateFlowEvent(deltaTime: TimeInterval) {
        if activeFlowEvent != .none {
            flowEventTimer = max(0, flowEventTimer - deltaTime)
            if flowEventTimer <= 0 {
                activeFlowEvent = .none
                nextFlowEventAt = elapsedPlayingTime + flowRandomDouble(9.0...13.0)
                showFeedback("FLUXO NORMAL", color: palette.player.withAlphaComponent(0.8))
            }
            return
        }

        guard elapsedPlayingTime >= nextFlowEventAt, spawnIndex >= 8 else { return }

        let event: FlowEvent = flowRandomBool() ? .surge : .calm
        activeFlowEvent = event
        flowEventTimer = event == .surge ? 3.2 : 3.6
        playSound(.event)

        switch event {
        case .surge:
            showFeedback("SURGE", color: palette.accentSoft)
            ringBurst(at: orbitCenter, color: palette.accent)
        case .calm:
            showFeedback("CALM", color: palette.player)
            ringPulse(at: player.position)
        case .none:
            break
        }
    }

    // MARK: - Ready UI

    private func showReadyControls(_ visible: Bool) {
        if visible {
            // Rebuild the footer from scratch every time Home becomes visible. This
            // makes the RANKING node independent from any state left behind by a
            // UIKit/Game Center presentation.
            rebuildReadyControlsLayer()
        } else {
            readyControlsLayer.removeAllActions()
        }

        readyControlsLayer.isHidden = !visible
        readyControlsLayer.alpha = visible ? 1 : 0
    }

    private func refreshReadyUIIfNeeded() {
        guard phase == .ready else { return }
        refreshReadyUI()
    }

    private func refreshReadyUI() {
        ensureDailyState()

        normalModeLabel.text = gameMode == .normal ? "●  NORMAL" : "NORMAL"
        dailyModeLabel.text = gameMode == .daily
            ? "●  DIÁRIO \(dailyAttemptsUsed)/3"
            : "DIÁRIO \(dailyAttemptsUsed)/3"

        normalModeLabel.fontColor = gameMode == .normal ? palette.player : UIColor(white: 1, alpha: 0.40)
        dailyModeLabel.fontColor = gameMode == .daily ? palette.player : UIColor(white: 1, alpha: 0.40)
        if !dailyCanPlay {
            dailyModeLabel.fontColor = UIColor(white: 1, alpha: 0.22)
        }

        missionSummaryLabel.text = missionSummaryText
        themesSummaryLabel.text = "TEMAS  \(unlockedThemeCount)/\(ThemeID.allCases.count)"
        rankingSummaryLabel.text = "RANKING"
        statsSummaryLabel.text = "STATS"
        settingsSummaryLabel.text = "AJUSTES"

        let utilityColor = UIColor(white: 1, alpha: 0.52)
        missionSummaryLabel.fontColor = utilityColor
        themesSummaryLabel.fontColor = utilityColor
        rankingSummaryLabel.fontColor = palette.accentSoft.withAlphaComponent(0.95)
        statsSummaryLabel.fontColor = utilityColor
        settingsSummaryLabel.fontColor = utilityColor

        if phase == .ready {
            bestLabel.text = gameMode == .daily
                ? (dailyBestScore > 0 ? "MELHOR HOJE  \(dailyBestScore)" : "")
                : (bestScore > 0 ? "MELHOR  \(bestScore)" : "")
        }
    }

    // MARK: - Panels

    private func openPanel(_ panel: PanelKind) {
        activePanel = panel
        panelLayer.removeAllChildren()
        panelLayer.isHidden = false
        themeHitRects.removeAll()
        soundSettingRect = .zero
        hapticsSettingRect = .zero

        let dim = SKShapeNode(rectOf: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.fillColor = UIColor.black.withAlphaComponent(0.72)
        dim.strokeColor = .clear
        dim.zPosition = 0
        panelLayer.addChild(dim)

        let panelHeight: CGFloat
        switch panel {
        case .themes:
            panelHeight = min(560, size.height - 120)
        case .settings:
            panelHeight = min(390, size.height - 180)
        default:
            panelHeight = min(470, size.height - 150)
        }
        let panelWidth = min(344, size.width - 38)
        let panelRect = CGRect(x: -panelWidth / 2, y: -panelHeight / 2, width: panelWidth, height: panelHeight)
        let card = SKShapeNode(
            path: CGPath(
                roundedRect: panelRect,
                cornerWidth: 26,
                cornerHeight: 26,
                transform: nil
            )
        )
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
        card.fillColor = palette.background.withAlphaComponent(0.98)
        card.strokeColor = palette.activeOrbit.withAlphaComponent(0.35)
        card.lineWidth = 1
        card.zPosition = 1
        panelLayer.addChild(card)

        switch panel {
        case .missions:
            buildMissionsPanel(center: card.position, height: panelHeight)
        case .themes:
            buildThemesPanel(center: card.position, height: panelHeight)
        case .stats:
            buildStatsPanel(center: card.position, height: panelHeight)
        case .settings:
            buildSettingsPanel(center: card.position, height: panelHeight)
        }
    }

    private func hidePanel() {
        activePanel = nil
        panelLayer.removeAllChildren()
        panelLayer.isHidden = true
        themeHitRects.removeAll()
        soundSettingRect = .zero
        hapticsSettingRect = .zero
    }

    private func handlePanelTouch(at point: CGPoint) {
        guard let activePanel else { return }

        if activePanel == .settings {
            if soundSettingRect.contains(point) {
                defaults.set(!soundEnabled, forKey: StorageKey.soundEnabled)
                if soundEnabled {
                    OrbitAudioEngine.shared.prepare()
                    playSound(.event)
                }
                openPanel(.settings)
                return
            }

            if hapticsSettingRect.contains(point) {
                if hapticsEnabled {
                    playSelectionHaptic()
                }
                defaults.set(!hapticsEnabled, forKey: StorageKey.hapticsEnabled)
                if hapticsEnabled {
                    prepareHaptics()
                    playSelectionHaptic()
                }
                openPanel(.settings)
                return
            }
        }

        if activePanel == .themes {
            for (theme, rect) in themeHitRects where rect.contains(point) {
                if isThemeUnlocked(theme) {
                    selectedThemeID = theme
                    defaults.set(theme.rawValue, forKey: StorageKey.selectedTheme)
                    playImpact(intensity: 0.38)
                    applyTheme()
                    openPanel(.themes)
                } else {
                    showPanelToast(themeUnlockDescription(theme))
                }
                return
            }
        }

        hidePanel()
        refreshReadyUI()
    }

    private func buildMissionsPanel(center: CGPoint, height: CGFloat) {
        addPanelTitle("MISSÕES DE HOJE", center: center, height: height)

        let missions = dailyMissions()
        var y = center.y + height / 2 - 105

        for mission in missions {
            let progress = missionProgress(mission)
            let complete = progress >= mission.target
            addPanelText(
                complete ? "✓  \(mission.title)" : mission.title,
                at: CGPoint(x: center.x, y: y),
                size: 14,
                color: complete ? palette.accentSoft : .white,
                weight: "AvenirNext-DemiBold"
            )
            addPanelText(
                "\(min(progress, mission.target)) / \(mission.target)",
                at: CGPoint(x: center.x, y: y - 27),
                size: 12,
                color: UIColor(white: 1, alpha: 0.46)
            )
            y -= 96
        }

        addPanelText(
            "Progresso reinicia à meia-noite",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 58),
            size: 11,
            color: UIColor(white: 1, alpha: 0.35)
        )
        addPanelText(
            "TOQUE PARA FECHAR",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 29),
            size: 10,
            color: UIColor(white: 1, alpha: 0.52),
            weight: "AvenirNext-DemiBold"
        )
    }

    private func buildThemesPanel(center: CGPoint, height: CGFloat) {
        addPanelTitle("TEMAS", center: center, height: height)

        let startY = center.y + height / 2 - 100
        let rowHeight: CGFloat = 63

        for (index, theme) in ThemeID.allCases.enumerated() {
            let y = startY - CGFloat(index) * rowHeight
            let unlocked = isThemeUnlocked(theme)
            let selected = theme == selectedThemeID

            let marker = selected ? "●" : (unlocked ? "○" : "🔒")
            addPanelText(
                "\(marker)  \(theme.displayName)",
                at: CGPoint(x: center.x - 94, y: y),
                size: 14,
                color: selected ? palette.accentSoft : (unlocked ? .white : UIColor(white: 1, alpha: 0.34)),
                weight: "AvenirNext-DemiBold",
                alignment: .left
            )

            if !unlocked {
                addPanelText(
                    themeUnlockDescription(theme),
                    at: CGPoint(x: center.x + 123, y: y),
                    size: 10,
                    color: UIColor(white: 1, alpha: 0.28),
                    alignment: .right
                )
            }

            themeHitRects.append((
                theme,
                CGRect(
                    x: center.x - 150,
                    y: y - rowHeight / 2,
                    width: 300,
                    height: rowHeight
                )
            ))
        }

        addPanelText(
            "TOQUE EM UM TEMA • FORA DA LISTA PARA FECHAR",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 28),
            size: 9,
            color: UIColor(white: 1, alpha: 0.44),
            weight: "AvenirNext-DemiBold"
        )
    }

    private func buildStatsPanel(center: CGPoint, height: CGFloat) {
        addPanelTitle("STATS", center: center, height: height)

        let entries: [(String, String)] = [
            ("MELHOR SCORE", "\(bestScore)"),
            ("PARTIDAS", "\(defaults.integer(forKey: StorageKey.totalRuns))"),
            ("PONTOS TOTAIS", "\(defaults.integer(forKey: StorageKey.totalPoints))"),
            ("NEAR MISSES", "\(defaults.integer(forKey: StorageKey.totalNearMisses))"),
            ("MAIOR COMBO", "×\(max(1, defaults.integer(forKey: StorageKey.bestCombo)))"),
            ("MAIOR TEMPO", formattedDuration(defaults.double(forKey: StorageKey.longestRun)))
        ]

        var y = center.y + height / 2 - 105
        for entry in entries {
            addPanelText(
                entry.0,
                at: CGPoint(x: center.x - 118, y: y),
                size: 11,
                color: UIColor(white: 1, alpha: 0.42),
                weight: "AvenirNext-DemiBold",
                alignment: .left
            )
            addPanelText(
                entry.1,
                at: CGPoint(x: center.x + 118, y: y),
                size: 18,
                color: .white,
                weight: "AvenirNext-DemiBold",
                alignment: .right
            )
            y -= 50
        }

        addPanelText(
            "CONQUISTAS  \(completedAchievementCount)/6  •  DIÁRIO  \(dailyBestScore) pts",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 60),
            size: 11,
            color: palette.accentSoft
        )
        addPanelText(
            "TOQUE PARA FECHAR",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 29),
            size: 10,
            color: UIColor(white: 1, alpha: 0.52),
            weight: "AvenirNext-DemiBold"
        )
    }

    private func buildSettingsPanel(center: CGPoint, height: CGFloat) {
        addPanelTitle("AJUSTES", center: center, height: height)

        let soundY = center.y + 62
        let hapticsY = center.y - 6

        addPanelText(
            "SOM",
            at: CGPoint(x: center.x - 112, y: soundY),
            size: 13,
            color: UIColor(white: 1, alpha: 0.72),
            weight: "AvenirNext-DemiBold",
            alignment: .left
        )
        addPanelText(
            soundEnabled ? "LIGADO" : "DESLIGADO",
            at: CGPoint(x: center.x + 112, y: soundY),
            size: 13,
            color: soundEnabled ? palette.accentSoft : UIColor(white: 1, alpha: 0.36),
            weight: "AvenirNext-DemiBold",
            alignment: .right
        )

        addPanelText(
            "HAPTICS",
            at: CGPoint(x: center.x - 112, y: hapticsY),
            size: 13,
            color: UIColor(white: 1, alpha: 0.72),
            weight: "AvenirNext-DemiBold",
            alignment: .left
        )
        addPanelText(
            hapticsEnabled ? "LIGADO" : "DESLIGADO",
            at: CGPoint(x: center.x + 112, y: hapticsY),
            size: 13,
            color: hapticsEnabled ? palette.accentSoft : UIColor(white: 1, alpha: 0.36),
            weight: "AvenirNext-DemiBold",
            alignment: .right
        )

        soundSettingRect = CGRect(x: center.x - 150, y: soundY - 27, width: 300, height: 54)
        hapticsSettingRect = CGRect(x: center.x - 150, y: hapticsY - 27, width: 300, height: 54)

        addPanelText(
            "Reduzir Movimento segue os Ajustes do iOS",
            at: CGPoint(x: center.x, y: center.y - 84),
            size: 10,
            color: UIColor(white: 1, alpha: 0.34)
        )
        addPanelText(
            "TOQUE EM UMA OPÇÃO • FORA PARA FECHAR",
            at: CGPoint(x: center.x, y: center.y - height / 2 + 29),
            size: 9,
            color: UIColor(white: 1, alpha: 0.48),
            weight: "AvenirNext-DemiBold"
        )
    }

    private func addPanelTitle(_ text: String, center: CGPoint, height: CGFloat) {
        addPanelText(
            text,
            at: CGPoint(x: center.x, y: center.y + height / 2 - 48),
            size: 21,
            color: .white,
            weight: "AvenirNext-Bold"
        )
    }

    private func addPanelText(
        _ text: String,
        at position: CGPoint,
        size fontSize: CGFloat,
        color: UIColor,
        weight fontName: String = "AvenirNext-Medium",
        alignment: SKLabelHorizontalAlignmentMode = .center
    ) {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .center
        label.position = position
        label.zPosition = 5
        panelLayer.addChild(label)
    }

    private func showPanelToast(_ text: String) {
        let toast = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        toast.text = text
        toast.fontSize = 11
        toast.fontColor = palette.accentSoft
        toast.horizontalAlignmentMode = .center
        toast.verticalAlignmentMode = .center
        toast.position = CGPoint(x: size.width / 2, y: size.height * 0.17)
        toast.alpha = 0
        toast.zPosition = 30
        panelLayer.addChild(toast)

        toast.run(.sequence([
            .fadeIn(withDuration: 0.08),
            .wait(forDuration: 0.7),
            .fadeOut(withDuration: 0.18),
            .removeFromParent()
        ]))
    }

    // MARK: - Game Center and sharing

    private func reportRunToGameCenter() {
        let totalRuns = defaults.integer(forKey: StorageKey.totalRuns)
        let totalNearMisses = defaults.integer(forKey: StorageKey.totalNearMisses)
        let storedBestCombo = max(1, defaults.integer(forKey: StorageKey.bestCombo))

        if gameMode == .daily {
            GameCenterService.shared.submitDailyScore(score)
        } else {
            GameCenterService.shared.submitNormalScore(score)
        }

        GameCenterService.shared.reportAchievements(
            score: max(score, bestScore),
            totalRuns: totalRuns,
            totalNearMisses: totalNearMisses,
            bestCombo: max(runBestCombo, storedBestCombo)
        )
    }

    private func shareCurrentScore() {
        let sharedBest = gameMode == .daily ? max(score, dailyBestScore) : max(score, bestScore)
        ShareScoreService.present(
            score: score,
            bestScore: sharedBest,
            modeTitle: gameMode == .daily ? "DAILY ORBIT" : "ORBIT",
            accent: palette.accent,
            background: palette.background
        )
    }

    // MARK: - Daily Orbit

    private func ensureDailyState() {
        let today = currentDayString()
        let stored = defaults.string(forKey: StorageKey.dailyDay)

        if stored != today {
            defaults.set(today, forKey: StorageKey.dailyDay)
            defaults.set(0, forKey: StorageKey.dailyAttempts)
            defaults.set(0, forKey: StorageKey.dailyBest)
            defaults.set(0, forKey: StorageKey.dailyMissionBestScore)
            defaults.set(0, forKey: StorageKey.dailyRuns)
            defaults.set(0, forKey: StorageKey.dailyNearMisses)
            defaults.set(0, forKey: StorageKey.dailyBestCombo)
            defaults.set(0.0, forKey: StorageKey.dailyLongestRun)
        }
    }

    private var dailyAttemptsUsed: Int {
        defaults.integer(forKey: StorageKey.dailyAttempts)
    }

    private var dailyAttemptsRemaining: Int {
        max(0, 3 - dailyAttemptsUsed)
    }

    private var dailyCanPlay: Bool {
        dailyAttemptsRemaining > 0
    }

    private var dailyBestScore: Int {
        defaults.integer(forKey: StorageKey.dailyBest)
    }

    private func consumeDailyAttempt() {
        defaults.set(min(3, dailyAttemptsUsed + 1), forKey: StorageKey.dailyAttempts)
    }

    private func currentDayString() -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: Date())
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func dailySeed() -> UInt64 {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: Date())
        let value = (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
        return UInt64(max(1, value)) ^ 0x4F52424954563235
    }

    // MARK: - Missions

    private func dailyMissions() -> [Mission] {
        var generator = SeededGenerator(seed: dailySeed() ^ 0x4D495353494F4E53)
        var kinds = MissionKind.allCases

        for index in stride(from: kinds.count - 1, through: 1, by: -1) {
            let swapIndex = Int(generator.unit() * Double(index + 1))
            kinds.swapAt(index, min(index, swapIndex))
        }

        return kinds.prefix(3).map { kind in
            switch kind {
            case .score:
                return Mission(kind: .score, target: [20, 25, 30][Int(generator.unit() * 3) % 3])
            case .nearMisses:
                return Mission(kind: .nearMisses, target: [2, 3, 4][Int(generator.unit() * 3) % 3])
            case .combo:
                return Mission(kind: .combo, target: [2, 3, 4][Int(generator.unit() * 3) % 3])
            case .runs:
                return Mission(kind: .runs, target: [3, 4, 5][Int(generator.unit() * 3) % 3])
            case .survive:
                return Mission(kind: .survive, target: [20, 30, 40][Int(generator.unit() * 3) % 3])
            }
        }
    }

    private func missionProgress(_ mission: Mission) -> Int {
        switch mission.kind {
        case .score:
            return defaults.integer(forKey: StorageKey.dailyMissionBestScore)
        case .nearMisses:
            return defaults.integer(forKey: StorageKey.dailyNearMisses)
        case .combo:
            return defaults.integer(forKey: StorageKey.dailyBestCombo)
        case .runs:
            return defaults.integer(forKey: StorageKey.dailyRuns)
        case .survive:
            return Int(defaults.double(forKey: StorageKey.dailyLongestRun).rounded(.down))
        }
    }

    private var completedMissionCount: Int {
        dailyMissions().filter { missionProgress($0) >= $0.target }.count
    }

    private var missionSummaryText: String {
        "MISSÕES  \(completedMissionCount)/3"
    }

    // MARK: - Stats and unlocks

    private func recordFinishedRun() {
        defaults.set(defaults.integer(forKey: StorageKey.totalRuns) + 1, forKey: StorageKey.totalRuns)
        defaults.set(defaults.integer(forKey: StorageKey.totalPoints) + score, forKey: StorageKey.totalPoints)
        defaults.set(defaults.integer(forKey: StorageKey.totalNearMisses) + runNearMisses, forKey: StorageKey.totalNearMisses)
        defaults.set(max(defaults.integer(forKey: StorageKey.bestCombo), runBestCombo), forKey: StorageKey.bestCombo)
        defaults.set(max(defaults.double(forKey: StorageKey.longestRun), elapsedPlayingTime), forKey: StorageKey.longestRun)

        defaults.set(defaults.integer(forKey: StorageKey.dailyRuns) + 1, forKey: StorageKey.dailyRuns)
        defaults.set(defaults.integer(forKey: StorageKey.dailyNearMisses) + runNearMisses, forKey: StorageKey.dailyNearMisses)
        defaults.set(max(defaults.integer(forKey: StorageKey.dailyBestCombo), runBestCombo), forKey: StorageKey.dailyBestCombo)
        defaults.set(max(defaults.double(forKey: StorageKey.dailyLongestRun), elapsedPlayingTime), forKey: StorageKey.dailyLongestRun)

        let missionBestScore = defaults.integer(forKey: StorageKey.dailyMissionBestScore)
        if score > missionBestScore {
            defaults.set(score, forKey: StorageKey.dailyMissionBestScore)
        }

        if gameMode == .daily && score > dailyBestScore {
            defaults.set(score, forKey: StorageKey.dailyBest)
        }
    }

    private var unlockedThemeCount: Int {
        ThemeID.allCases.filter(isThemeUnlocked).count
    }

    private func isThemeUnlocked(_ theme: ThemeID) -> Bool {
        switch theme {
        case .classic:
            return true
        case .neon:
            return bestScore >= 15
        case .solar:
            return bestScore >= 35
        case .ice:
            return defaults.integer(forKey: StorageKey.totalNearMisses) >= 10
        case .matrix:
            return defaults.integer(forKey: StorageKey.totalRuns) >= 15
        case .void:
            return bestScore >= 75
        }
    }

    private func themeUnlockDescription(_ theme: ThemeID) -> String {
        switch theme {
        case .classic: return "Liberado"
        case .neon: return "Score 15"
        case .solar: return "Score 35"
        case .ice: return "10 near misses"
        case .matrix: return "15 partidas"
        case .void: return "Score 75"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        let minutes = seconds / 60
        let remaining = seconds % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, remaining) : "\(remaining)s"
    }

    // MARK: - Randomness

    private func randomUnit() -> Double {
        if gameMode == .daily {
            return dailyGenerator.unit()
        }
        return Double.random(in: 0..<1)
    }

    private func randomInt(_ range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        let count = range.upperBound - range.lowerBound
        return range.lowerBound + min(count - 1, Int(randomUnit() * Double(count)))
    }

    private func randomDouble(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * randomUnit()
    }

    private func randomCGFloat(_ range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(randomUnit())
    }

    private func randomBool() -> Bool {
        randomUnit() >= 0.5
    }

    private func flowRandomUnit() -> Double {
        if gameMode == .daily {
            return dailyFlowGenerator.unit()
        }
        return Double.random(in: 0..<1)
    }

    private func flowRandomDouble(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * flowRandomUnit()
    }

    private func flowRandomBool() -> Bool {
        flowRandomUnit() >= 0.5
    }

    // MARK: - Visual progression and feedback

    private func updateVisualProgression() {
        let visualMetric = gameMode == .daily ? CGFloat(spawnIndex) * 1.45 : CGFloat(score)
        let progress = min(1, visualMetric / 65)

        backgroundColor = UIColor(
            hue: palette.backgroundHue + progress * 0.018,
            saturation: min(1, palette.backgroundSaturation + progress * 0.16),
            brightness: min(1, palette.backgroundBrightness + progress * 0.035),
            alpha: 1
        )

        innerOrbit.glowWidth = 1 + progress * 3
        outerOrbit.glowWidth = 1 + progress * 3
        centerDot.glowWidth = 5 + progress * 6
        updateOrbitHighlight()
    }

    private func updateOrbitHighlight() {
        let targetIsInner = abs(targetRadius - innerRadius) < 1
        let visualMetric = gameMode == .daily ? CGFloat(spawnIndex) : CGFloat(score)
        let intensity = min(0.14, visualMetric * 0.0015)

        let active = palette.activeOrbit.withAlphaComponent(min(0.90, 0.66 + intensity))
        let inactive = palette.orbit.withAlphaComponent(min(0.35, 0.16 + intensity * 0.45))

        innerOrbit.strokeColor = targetIsInner ? active : inactive
        outerOrbit.strokeColor = targetIsInner ? inactive : active
    }

    private func pulsePlayer() {
        player.removeAction(forKey: "readyPulse")
        playerGlow.removeAction(forKey: "readyGlow")

        player.run(.repeatForever(.sequence([
            .scale(to: 1.12, duration: 0.72),
            .scale(to: 1.0, duration: 0.72)
        ])), withKey: "readyPulse")

        playerGlow.run(.repeatForever(.sequence([
            .group([
                .scale(to: 1.28, duration: 0.72),
                .fadeAlpha(to: 0.38, duration: 0.72)
            ]),
            .group([
                .scale(to: 1.0, duration: 0.72),
                .fadeAlpha(to: 1.0, duration: 0.72)
            ])
        ])), withKey: "readyGlow")
    }

    private func scorePulse() {
        scoreLabel.removeAction(forKey: "scorePulse")
        scoreLabel.run(.sequence([
            .scale(to: 1.15, duration: 0.05),
            .scale(to: 1.0, duration: 0.10)
        ]), withKey: "scorePulse")
    }

    private func comboPop() {
        comboLabel.removeAllActions()
        comboLabel.setScale(0.72)
        comboLabel.alpha = 0
        comboLabel.run(.group([
            .scale(to: 1.0, duration: 0.16),
            .fadeIn(withDuration: 0.12)
        ]))
    }

    private func showFeedback(_ text: String, color: UIColor) {
        feedbackLabel.removeAllActions()
        feedbackLabel.text = text
        feedbackLabel.fontColor = color
        feedbackLabel.position = CGPoint(
            x: size.width / 2,
            y: orbitCenter.y + outerRadius + 42
        )
        feedbackLabel.alpha = 0
        feedbackLabel.setScale(0.82)

        feedbackLabel.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.06),
                .scale(to: 1.0, duration: 0.10)
            ]),
            .wait(forDuration: 0.28),
            .group([
                .fadeOut(withDuration: 0.18),
                .moveBy(x: 0, y: 8, duration: 0.18)
            ]),
            .run { [weak self] in
                guard let self else { return }
                self.feedbackLabel.position = CGPoint(
                    x: self.size.width / 2,
                    y: self.orbitCenter.y + self.outerRadius + 42
                )
            }
        ]))
    }

    private func spawnTrailDot() {
        guard phase == .playing else { return }

        let dot = SKShapeNode(circleOfRadius: 4.2)
        dot.name = "transientEffect"
        dot.fillColor = palette.player.withAlphaComponent(0.28)
        dot.strokeColor = .clear
        dot.position = player.position
        dot.zPosition = 7
        worldLayer.addChild(dot)

        dot.run(.sequence([
            .group([
                .fadeOut(withDuration: 0.26),
                .scale(to: 0.18, duration: 0.26)
            ]),
            .removeFromParent()
        ]))
    }

    private func burst(at position: CGPoint, color: UIColor) {
        for index in 0..<8 {
            let dot = SKShapeNode(circleOfRadius: 2.2)
            dot.name = "transientEffect"
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.position = position
            dot.zPosition = 8
            worldLayer.addChild(dot)

            let angle = CGFloat(index) / 8 * (.pi * 2)
            let distance = CGFloat.random(in: 18...34)
            let move = CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance)

            dot.run(.sequence([
                .group([
                    .move(by: move, duration: 0.20),
                    .fadeOut(withDuration: 0.20),
                    .scale(to: 0.25, duration: 0.20)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func explode(at position: CGPoint, color: UIColor, count: Int, power: CGFloat) {
        let effectiveCount = UIAccessibility.isReduceMotionEnabled ? max(4, count / 3) : count
        for _ in 0..<effectiveCount {
            let radius = CGFloat.random(in: 1.6...4.2)
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.name = "transientEffect"
            dot.fillColor = Bool.random() ? color : palette.player
            dot.strokeColor = .clear
            dot.position = position
            dot.zPosition = 120
            worldLayer.addChild(dot)

            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let distance = CGFloat.random(in: power * 0.45...power)
            let move = CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance)

            dot.run(.sequence([
                .group([
                    .move(by: move, duration: 0.38),
                    .fadeOut(withDuration: 0.38),
                    .scale(to: 0.18, duration: 0.38)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func ringPulse(at position: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: 12)
        ring.name = "transientEffect"
        ring.position = position
        ring.fillColor = .clear
        ring.strokeColor = palette.accentSoft.withAlphaComponent(0.88)
        ring.lineWidth = 2
        ring.zPosition = 7
        worldLayer.addChild(ring)

        ring.run(.sequence([
            .group([
                .scale(to: 2.8, duration: 0.24),
                .fadeOut(withDuration: 0.24)
            ]),
            .removeFromParent()
        ]))
    }

    private func ringBurst(at position: CGPoint, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 18)
        ring.name = "transientEffect"
        ring.position = position
        ring.fillColor = .clear
        ring.strokeColor = color.withAlphaComponent(0.75)
        ring.lineWidth = 3
        ring.zPosition = 110
        worldLayer.addChild(ring)

        ring.run(.sequence([
            .group([
                .scale(to: 5.5, duration: 0.34),
                .fadeOut(withDuration: 0.34)
            ]),
            .removeFromParent()
        ]))
    }

    private func shakeWorld() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        worldLayer.removeAction(forKey: "gameOverShake")
        worldLayer.position = .zero

        let shake = SKAction.sequence([
            .moveBy(x: -5, y: 2, duration: 0.035),
            .moveBy(x: 9, y: -4, duration: 0.035),
            .moveBy(x: -7, y: 4, duration: 0.035),
            .moveBy(x: 4, y: -2, duration: 0.035),
            .move(to: .zero, duration: 0.04)
        ])
        worldLayer.run(shake, withKey: "gameOverShake")
    }

    // MARK: - Preferences and achievement progress

    private var soundEnabled: Bool {
        defaults.bool(forKey: StorageKey.soundEnabled)
    }

    private var hapticsEnabled: Bool {
        defaults.bool(forKey: StorageKey.hapticsEnabled)
    }

    private var completedAchievementCount: Int {
        let totalRuns = defaults.integer(forKey: StorageKey.totalRuns)
        let totalNearMisses = defaults.integer(forKey: StorageKey.totalNearMisses)
        let storedBestCombo = max(1, defaults.integer(forKey: StorageKey.bestCombo))

        var count = 0
        if bestScore >= 10 { count += 1 }
        if bestScore >= 50 { count += 1 }
        if bestScore >= 100 { count += 1 }
        if totalNearMisses >= 10 { count += 1 }
        if storedBestCombo >= 4 { count += 1 }
        if totalRuns >= 100 { count += 1 }
        return count
    }

    private func playSound(_ cue: OrbitAudioEngine.Cue) {
        guard soundEnabled else { return }
        OrbitAudioEngine.shared.play(cue)
    }

    // MARK: - Haptics

    private func prepareHaptics() {
        guard hapticsEnabled else { return }
#if !targetEnvironment(simulator)
        impactGenerator.prepare()
        rigidImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
#endif
    }

    private func playImpact(intensity: CGFloat) {
        guard hapticsEnabled else { return }
#if !targetEnvironment(simulator)
        impactGenerator.impactOccurred(intensity: intensity)
        impactGenerator.prepare()
#endif
    }

    private func playRigidImpact(intensity: CGFloat) {
        guard hapticsEnabled else { return }
#if !targetEnvironment(simulator)
        rigidImpactGenerator.impactOccurred(intensity: intensity)
        rigidImpactGenerator.prepare()
#endif
    }

    private func playGameOverHaptic() {
        guard hapticsEnabled else { return }
#if !targetEnvironment(simulator)
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
#endif
    }

    private func playSelectionHaptic() {
        guard hapticsEnabled else { return }
#if !targetEnvironment(simulator)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
#endif
    }

    // MARK: - Geometry

    private func point(onRadius radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: orbitCenter.x + cos(angle) * radius,
            y: orbitCenter.y + sin(angle) * radius
        )
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle.truncatingRemainder(dividingBy: .pi * 2)
        if value < 0 { value += .pi * 2 }
        return value
    }

    private func shortestAngularDistance(from a: CGFloat, to b: CGFloat) -> CGFloat {
        var diff = normalizedAngle(b) - normalizedAngle(a)
        if diff > .pi { diff -= .pi * 2 }
        if diff < -.pi { diff += .pi * 2 }
        return diff
    }
}
