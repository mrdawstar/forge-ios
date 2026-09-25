import AVFoundation
import Foundation

/// Fully synthesized scene audio (spec §1.7).
///
/// Nothing here is a sample. Every cue is generated at call time from its
/// parameters, so the stone responds to how hard and how fast the hand moves:
/// the grind's gain tracks velocity and its band-pass centre tracks position,
/// both continuously smoothed.
@MainActor
final class ForgeAudio {

    static let shared = ForgeAudio()

    /// Gated by the Sounds setting.
    var isEnabled: Bool = true

    private let engine = AVAudioEngine()
    private var isConfigured = false
    private var sampleRate: Double = 44_100

    // One-shot voices, round-robined so overlapping cues never cut each other.
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private static let voiceCount = 8

    // Grind chain: noise source → band-pass + low-pass → gain → main mixer.
    private var grindSource: AVAudioSourceNode?
    private let grindEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let grindMixer = AVAudioMixerNode()
    private var grindIsRunning = false

    // Smoothed grind parameters. Both are driven from the physics loop on the
    // main thread and applied to AudioUnit parameters, which the units then
    // ramp internally — no audio-thread parameter reads required.
    private var grindGain: Double = 0
    private var grindCentre: Double = 820
    private var grindTargetGain: Double = 0
    private var grindTargetCentre: Double = 820

    private init() {}

    // MARK: - Lifecycle

    /// Safe to call repeatedly; only the first call does work.
    func prepare() {
        guard !isConfigured else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // .ambient respects the silent switch and never ducks other audio.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // A denied session is not fatal — the scene simply plays silent.
        }

        sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 44_100 }

        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }

        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: monoFormat)
            voices.append(node)
        }

        configureGrindChain(format: monoFormat)

        isConfigured = true
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard isConfigured, !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
        for voice in voices where !voice.isPlaying {
            voice.play()
        }
    }

    // MARK: - Grind (looping, parameter-driven)

    private func configureGrindChain(format: AVAudioFormat) {
        // White noise generated inline. A tiny xorshift keeps the render block
        // allocation-free and lock-free, which is mandatory on the audio thread.
        var state: UInt32 = 0x9E3779B9
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    state ^= state << 13
                    state ^= state >> 17
                    state ^= state << 5
                    // Map to −1…1
                    ptr[frame] = (Float(state) / Float(UInt32.max)) * 2 - 1
                }
            }
            return noErr
        }
        grindSource = source

        // Stone scraping stone: a narrow band that rises as the blade emerges,
        // rolled off above 3.4 kHz so it stays gritty rather than hissy.
        let band = grindEQ.bands[0]
        band.filterType = .bandPass
        band.frequency = 820
        band.bandwidth = 1.1
        band.bypass = false

        let lowPass = grindEQ.bands[1]
        lowPass.filterType = .lowPass
        lowPass.frequency = 3400
        lowPass.bypass = false

        grindEQ.globalGain = 0

        engine.attach(source)
        engine.attach(grindEQ)
        engine.attach(grindMixer)
        engine.connect(source, to: grindEQ, format: format)
        engine.connect(grindEQ, to: grindMixer, format: format)
        engine.connect(grindMixer, to: engine.mainMixerNode, format: format)

        grindMixer.outputVolume = 0
    }

    /// Called on touch-down. The loop starts at gain 0 and is only ever made
    /// audible by hand movement.
    func startGrind() {
        guard isEnabled else { return }
        prepare()
        startEngineIfNeeded()
        grindGain = 0
        grindTargetGain = 0
        grindMixer.outputVolume = 0
        grindIsRunning = true
    }

    /// Per-frame update from the physics loop.
    ///
    /// gain  = min(0.17, |vel| · 0.13)   — silent the moment the hand stops
    /// centre = 820 + pos · 1750 Hz      — pitch rises as the blade emerges
    func updateGrind(pos: Double, vel: Double) {
        guard grindIsRunning, isEnabled else { return }
        grindTargetGain = min(0.17, abs(vel) * 0.13)
        grindTargetCentre = 820 + min(max(pos, 0), 1) * 1750
        smoothGrind()
    }

    /// Release: fade out, then stop the source (spec: 0.06s time constant,
    /// source stopped after 320ms).
    func stopGrind() {
        guard grindIsRunning else { return }
        grindTargetGain = 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            // ~320ms of smoothing at display rate.
            for _ in 0..<20 {
                self.smoothGrind()
                try? await Task.sleep(for: .milliseconds(16))
            }
            self.grindMixer.outputVolume = 0
            self.grindGain = 0
            self.grindIsRunning = false
        }
    }

    private func smoothGrind() {
        // One-pole smoothing, ~0.06s time constant at 60–120 Hz update rate.
        let alpha = 0.18
        grindGain += (grindTargetGain - grindGain) * alpha
        grindCentre += (grindTargetCentre - grindCentre) * alpha
        grindMixer.outputVolume = Float(max(0, min(grindGain, 0.17)))
        grindEQ.bands[0].frequency = Float(max(60, min(grindCentre, 8000)))
    }

    // MARK: - One-shot cues

    /// Triangle body hit: frequency `f0 → f1` exponentially over 0.9·len,
    /// 12ms attack then an exponential tail to silence at `len`.
    func thump(from f0: Double, to f1: Double, gain: Double, length: Double) {
        render(length: length) { t, _ in
            let sweep = min(t / (0.9 * length), 1)
            let freq = f0 * pow(f1 / f0, sweep)
            return (freq, Self.envelope(t: t, length: length, attack: 0.012, decay: 6.9) * gain)
        } waveform: { phase in
            // Triangle, −1…1
            4 * abs(phase - 0.5) - 1
        }
    }

    /// Band-passed noise burst. `decay` shapes the amplitude as `(1−p)^decay`,
    /// the centre sweeps `f0 → f1` exponentially, Q is the band width.
    func noise(length: Double, from f0: Double, to f1: Double, q: Double, gain: Double, decay: Double) {
        guard isEnabled, isConfigured || prepareLazily() else { return }
        let frames = Int(length * sampleRate)
        guard frames > 0, let buffer = makeBuffer(frames: frames) else { return }
        guard let data = buffer.floatChannelData?[0] else { return }

        var state: UInt32 = 0x2545F491
        // Chamberlin state-variable filter — cheap, and stable while the centre
        // frequency sweeps, which a biquad with jumped coefficients is not.
        var low: Double = 0
        var band: Double = 0
        let q1 = 1.0 / max(q, 0.3)

        for i in 0..<frames {
            let p = Double(i) / Double(frames)
            let t = Double(i) / sampleRate

            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            let white = (Double(state) / Double(UInt32.max)) * 2 - 1

            let centre = f0 * pow(f1 / f0, p)
            let f = 2 * sin(.pi * min(centre, sampleRate / 3) / sampleRate)

            low += f * band
            let high = white - low - q1 * band
            band += f * high

            let amp = pow(1 - p, decay)
            _ = t
            data[i] = Float(band * amp * gain)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        play(buffer)
    }

    /// Two sines, the second delayed 70ms, ~0.9s exponential tails.
    func chime() {
        guard isEnabled, isConfigured || prepareLazily() else { return }
        let length = 0.95
        let frames = Int(length * sampleRate)
        guard frames > 0, let buffer = makeBuffer(frames: frames),
              let data = buffer.floatChannelData?[0] else { return }

        let partials: [(freq: Double, gain: Double, delay: Double)] = [
            (1318, 0.05, 0),
            (1975, 0.03, 0.07),
        ]
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for p in partials where t >= p.delay {
                let local = t - p.delay
                sample += sin(2 * .pi * p.freq * local) * exp(-local / 0.28) * p.gain
            }
            data[i] = Float(sample)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        play(buffer)
    }

    /// The blade singing after it tears free: four detuned partials with
    /// staggered attacks, the higher ones dying first.
    func ring() {
        guard isEnabled, isConfigured || prepareLazily() else { return }
        let length = 1.85
        let frames = Int(length * sampleRate)
        guard frames > 0, let buffer = makeBuffer(frames: frames),
              let data = buffer.floatChannelData?[0] else { return }

        let base: [(freq: Double, gain: Double, attack: Double, decay: Double)] = [
            (1046, 0.075, 0.006, 1.70),
            (1571, 0.042, 0.010, 1.30),
            (2350, 0.024, 0.014, 1.00),
            (3130, 0.013, 0.018, 0.78),
        ]
        // ±0.2% detune keeps the partials from phase-locking into a synth tone.
        let partials = base.map { p -> (Double, Double, Double, Double) in
            (p.freq * (1 + Double.random(in: -0.002...0.002)), p.gain, p.attack, p.decay)
        }

        for i in 0..<frames {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (freq, gain, attack, decay) in partials {
                let env: Double
                if t < attack {
                    env = t / attack
                } else {
                    env = exp(-(t - attack) / (decay / 4.6))
                }
                sample += sin(2 * .pi * freq * t) * env * gain
            }
            data[i] = Float(sample)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        play(buffer)
    }

    // MARK: - Composite cues (§1.7)

    func ritualCommitted() {
        noise(length: 0.42, from: 1900, to: 900, q: 5, gain: 0.13, decay: 3.2)
        thump(from: 190, to: 120, gain: 0.075, length: 0.4)
    }

    func catchCrack() {
        noise(length: 0.16, from: 3100, to: 1500, q: 7, gain: 0.11, decay: 5)
    }

    func slipBack() {
        noise(length: 0.30, from: 1200, to: 600, q: 4, gain: 0.10, decay: 3)
    }

    func bottomOut() {
        thump(from: 76, to: 48, gain: 0.10, length: 0.34)
    }

    /// Stone tears, a heavy thud, then the blade sings for ~1.7s.
    func breakFree() {
        noise(length: 0.7, from: 1500, to: 420, q: 2.2, gain: 0.24, decay: 1.7)
        thump(from: 120, to: 62, gain: 0.16, length: 0.7)
        ring()
    }

    func undo() {
        thump(from: 72, to: 46, gain: 0.13, length: 0.42)
    }

    // MARK: - Helpers

    @discardableResult
    private func prepareLazily() -> Bool {
        prepare()
        return isConfigured
    }

    private static func envelope(t: Double, length: Double, attack: Double, decay: Double) -> Double {
        if t < attack { return t / attack }
        let u = (t - attack) / max(length - attack, 0.0001)
        return exp(-decay * u)
    }

    private func makeBuffer(frames: Int) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    }

    private func render(
        length: Double,
        step: (_ t: Double, _ index: Int) -> (frequency: Double, amplitude: Double),
        waveform: (Double) -> Double
    ) {
        guard isEnabled, isConfigured || prepareLazily() else { return }
        let frames = Int(length * sampleRate)
        guard frames > 0, let buffer = makeBuffer(frames: frames),
              let data = buffer.floatChannelData?[0] else { return }

        var phase: Double = 0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let (freq, amp) = step(t, i)
            phase += freq / sampleRate
            if phase >= 1 { phase -= floor(phase) }
            data[i] = Float(waveform(phase) * amp)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        play(buffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard isEnabled, !voices.isEmpty else { return }
        startEngineIfNeeded()
        let voice = voices[nextVoice % voices.count]
        nextVoice += 1
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.isPlaying { voice.play() }
    }
}
