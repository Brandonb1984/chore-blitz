import AVFoundation

/// Tiny chiptune synth: square/triangle waves generated on the fly, so there
/// are no audio files. Original melody and effects.
final class GameAudio {
    static let shared = GameAudio()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let lock = NSLock()
    private var voices: [Voice] = []
    private var musicOn = false
    private var musicStep = 0
    private var samplesUntilNextStep = 0
    private let sampleRate: Double
    private var started = false

    private struct Voice {
        var freq: Double
        var phase: Double = 0
        var samplesLeft: Int
        var total: Int
        var volume: Float
        var square: Bool
    }

    private init() {
        sampleRate = 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = abl.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.lock.lock()
            for i in 0..<Int(frameCount) {
                if self.musicOn { self.tickMusic() }
                var sample: Float = 0
                for v in self.voices.indices {
                    var voice = self.voices[v]
                    guard voice.samplesLeft > 0 else { continue }
                    let env = Float(voice.samplesLeft) / Float(voice.total)
                    let wave: Float = voice.square
                        ? (voice.phase < 0.5 ? 1 : -1)
                        : Float(4 * abs(voice.phase - 0.5) - 1)
                    sample += wave * voice.volume * env
                    voice.phase += voice.freq / self.sampleRate
                    if voice.phase >= 1 { voice.phase -= 1 }
                    voice.samplesLeft -= 1
                    self.voices[v] = voice
                }
                out[i] = max(-1, min(1, sample))
            }
            self.voices.removeAll { $0.samplesLeft <= 0 }
            self.lock.unlock()
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5
    }

    private func startIfNeeded() {
        guard !started else { return }
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do { try engine.start(); started = true } catch { started = false }
    }

    private func note(_ midi: Int, _ seconds: Double, volume: Float = 0.12, square: Bool = true, delay: Double = 0) {
        let freq = 440 * pow(2, Double(midi - 69) / 12)
        let n = Int(seconds * sampleRate)
        let add = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.voices.append(Voice(freq: freq, samplesLeft: n, total: n, volume: volume, square: square))
            self.lock.unlock()
        }
        startIfNeeded()
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: add) } else { add() }
    }

    // MARK: Effects

    /// Coin "ka-ching": two quick high notes.
    func kaching() {
        note(88, 0.08)
        note(95, 0.30, delay: 0.07)
    }

    /// Gem pickup arpeggio.
    func gem() {
        for (i, m) in [76, 80, 83, 88].enumerated() { note(m, 0.09, volume: 0.09, delay: Double(i) * 0.045) }
    }

    /// Level up fanfare.
    func levelUp() {
        for (i, m) in [72, 76, 79, 84, 88, 91].enumerated() { note(m, 0.14, volume: 0.1, delay: Double(i) * 0.08) }
        note(96, 0.6, volume: 0.1, delay: 0.5)
    }

    /// One reel click while spinning.
    func tick() { note(84, 0.03, volume: 0.06) }

    /// Spin result.
    func win(big: Bool) {
        let notes = big ? [72, 76, 79, 84, 79, 84, 88, 91, 96] : [79, 84, 88]
        for (i, m) in notes.enumerated() { note(m, 0.12, volume: 0.11, delay: Double(i) * 0.09) }
    }

    // MARK: Music

    /// An original 16-step loop: bass on triangle, melody on square.
    private let melody: [Int?] = [69, nil, 72, 76, 74, nil, 72, 69, 67, nil, 69, 72, 71, 67, 64, nil,
                                  69, nil, 72, 76, 79, 77, 76, 74, 72, nil, 74, 76, 72, nil, 69, nil]
    private let bass: [Int] = [45, 45, 45, 45, 41, 41, 41, 41, 43, 43, 43, 43, 40, 40, 44, 44]

    private func tickMusic() {
        if samplesUntilNextStep > 0 { samplesUntilNextStep -= 1; return }
        let stepSeconds = 0.16
        samplesUntilNextStep = Int(stepSeconds * sampleRate)
        let n = Int(stepSeconds * sampleRate * 0.9)
        if let m = melody[musicStep % melody.count] {
            voices.append(Voice(freq: 440 * pow(2, Double(m - 69) / 12), samplesLeft: n, total: n, volume: 0.05, square: true))
        }
        if musicStep % 2 == 0 {
            let b = bass[(musicStep / 2) % bass.count]
            let bn = Int(stepSeconds * 2 * sampleRate * 0.95)
            voices.append(Voice(freq: 440 * pow(2, Double(b - 69) / 12), samplesLeft: bn, total: bn, volume: 0.09, square: false))
        }
        musicStep += 1
    }

    func setMusic(_ on: Bool) {
        if on { startIfNeeded() }
        lock.lock()
        if on && !musicOn { musicStep = 0; samplesUntilNextStep = 0 }
        musicOn = on
        lock.unlock()
    }
}
