import AVFoundation

final class OrbitAudioEngine {
    static let shared = OrbitAudioEngine()

    enum Cue {
        case start
        case switchOrbit
        case point
        case nearMiss
        case combo
        case gameOver
        case event
        case milestone
        case newBest
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private let format: AVAudioFormat
    private var isPrepared = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
    }

    func prepare() {
        guard !isPrepared else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            isPrepared = true
        } catch {
            // Audio is optional. Gameplay should never fail because sound could not start.
        }
    }

    func play(_ cue: Cue) {
        prepare()
        guard isPrepared, !players.isEmpty else { return }

        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count

        let spec = soundSpec(for: cue)
        guard let buffer = makeBuffer(spec) else { return }

        player.scheduleBuffer(buffer, at: nil, options: .interrupts)

        if !player.isPlaying {
            player.play()
        }
    }

    private struct SoundSpec {
        let frequency: Double
        let duration: Double
        let volume: Float
        let harmonic: Double
        let endFrequency: Double?
    }

    private func soundSpec(for cue: Cue) -> SoundSpec {
        switch cue {
        case .start:
            return SoundSpec(frequency: 520, duration: 0.085, volume: 0.16, harmonic: 0.12, endFrequency: 700)
        case .switchOrbit:
            return SoundSpec(frequency: 760, duration: 0.045, volume: 0.12, harmonic: 0.08, endFrequency: 980)
        case .point:
            return SoundSpec(frequency: 940, duration: 0.055, volume: 0.10, harmonic: 0.10, endFrequency: 1_070)
        case .nearMiss:
            return SoundSpec(frequency: 1_180, duration: 0.09, volume: 0.14, harmonic: 0.18, endFrequency: 1_480)
        case .combo:
            return SoundSpec(frequency: 1_020, duration: 0.12, volume: 0.15, harmonic: 0.22, endFrequency: 1_620)
        case .gameOver:
            return SoundSpec(frequency: 310, duration: 0.22, volume: 0.18, harmonic: 0.16, endFrequency: 120)
        case .event:
            return SoundSpec(frequency: 620, duration: 0.11, volume: 0.12, harmonic: 0.14, endFrequency: 860)
        case .milestone:
            return SoundSpec(frequency: 880, duration: 0.14, volume: 0.15, harmonic: 0.20, endFrequency: 1_320)
        case .newBest:
            return SoundSpec(frequency: 1_020, duration: 0.18, volume: 0.17, harmonic: 0.24, endFrequency: 1_720)
        }
    }

    private func makeBuffer(_ spec: SoundSpec) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(max(1, Int(spec.duration * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let total = Int(frameCount)

        for index in 0..<total {
            let progress = Double(index) / Double(max(1, total - 1))
            let frequency: Double
            if let endFrequency = spec.endFrequency {
                frequency = spec.frequency + (endFrequency - spec.frequency) * progress
            } else {
                frequency = spec.frequency
            }

            let time = Double(index) / sampleRate
            let attack = min(1.0, progress / 0.10)
            let release = min(1.0, (1.0 - progress) / 0.28)
            let envelope = max(0, min(attack, release))

            let base = sin(2.0 * .pi * frequency * time)
            let harmonic = sin(2.0 * .pi * frequency * 2.0 * time) * spec.harmonic
            samples[index] = Float((base + harmonic) * envelope) * spec.volume
        }

        return buffer
    }
}
