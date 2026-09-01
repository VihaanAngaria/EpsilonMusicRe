import Foundation
import AVFoundation
import MediaToolbox
import AudioToolbox
import CoreMedia

// MARK: - Biquad peaking filter (RBJ audio EQ cookbook — playback/BiquadFilter.kt parity)

struct BiquadFilter {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0
    var a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    /// Peaking EQ (PK) — A = 10^(gain/40), alpha = sin(w0)/(2Q).
    init(sampleRate: Double, frequency: Double, gainDb: Double, q: Double = 1.41) {
        let A = pow(10.0, gainDb / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cw0 = cos(w0)
        let a0 = 1.0 + alpha / A
        b0 = (1.0 + alpha * A) / a0
        b1 = (-2.0 * cw0) / a0
        b2 = (1.0 - alpha * A) / a0
        a1 = (-2.0 * cw0) / a0
        a2 = (1.0 - alpha / A) / a0
    }

    mutating func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

// MARK: - EQ profiles (EqScreen.kt preset values, verbatim)

struct EQProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var groupName: String
    /// Raw slider values -600...600 (band gain dB = raw/50 → ±12 dB).
    var bands: [Int]
    var preampDb: Double

    static let bandFrequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let presets: [EQProfile] = {
        func p(_ name: String, _ group: String, _ bands: [Int]) -> EQProfile {
            EQProfile(id: group.lowercased() + "-" + name.lowercased().replacingOccurrences(of: " ", with: "-"),
                      name: name, groupName: group, bands: bands, preampDb: 0)
        }
        var out: [EQProfile] = [
            p("Flat", "Epsilon Signature", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            p("Signature", "Epsilon Signature", [150, 100, 50, 0, -20, 0, 80, 150, 200, 150]),
            p("Acoustic", "Epsilon Signature", [150, 150, 50, 75, 100, 75, 125, 175, 150, 75]),
            p("Bass Boost", "Epsilon Signature", [500, 400, 250, 100, 0, -50, 0, 100, 200, 300]),
            p("Pure Clarity", "Epsilon Signature", [-100, -50, 0, 50, 150, 250, 300, 250, 150, 100]),
            p("Soft Bass", "Epsilon Signature", [200, 180, 140, 80, 30, 20, 60, 90, 110, 130]),
            p("Electronic", "Epsilon Signature", [350, 280, 120, -50, -150, 50, 180, 300, 400, 500]),
            p("Rock", "Epsilon Signature", [300, 220, 150, 50, -100, 120, 200, 250, 320, 380]),
            p("Pop", "Epsilon Signature", [-150, 0, 100, 180, 250, 220, 150, 80, -50, -120]),
            p("Jazz", "Epsilon Signature", [150, 100, 60, 140, 200, 180, 120, 180, 220, 200]),
            p("Voice", "Epsilon Signature", [-250, -150, 0, 200, 400, 380, 200, 120, 0, -120]),
            p("Open", "Dolby Atmos", [150, 180, 220, 180, 160, 210, 250, 280, 180, 80]),
            p("Rich", "Dolby Atmos", [100, 160, 200, 220, 280, 260, 240, 200, 150, 50]),
            p("Focused", "Dolby Atmos", [-300, -50, 130, 180, 220, 120, 140, 100, -50, -300]),
            p("Music", "Dirac Audio", [200, 140, 80, 0, 30, 80, 140, 200, 280, 350]),
            p("Movie", "Dirac Audio", [300, 250, 150, 0, 70, 120, 180, 250, 320, 400]),
            p("Game", "Dirac Audio", [150, 250, 200, 0, 80, 150, 300, 450, 400, 280]),
        ]
        out.append(contentsOf: EqualizerEngine.loadCustomProfiles())
        return out
    }()

    /// The "Epsilon Tuning" profile actually applied (CustomEqualizerAudioProcessor input).
    func asAppliedProfile() -> EQProfile {
        EQProfile(id: "echo_tuning", name: "Epsilon Tuning", groupName: "Applied",
                  bands: bands, preampDb: preampDb)
    }
}

// MARK: - Engine state

/// Shared audio DSP state read by the render thread.
final class DSPState {
    var lock = NSLock()
    var enabled = false
    var preamp: Double = 1.0
    var normalizationGain: Double = 1.0
    var skipSilenceEnabled = false
    var sampleRate: Double = 44100
    var channels: Int = 2
    var isFloat = true
    var isInterleaved = false
    var bands: [Int] = Array(repeating: 0, count: 10)
    var filters: [[BiquadFilter]] = []      // [channel][band]
    var silenceFrames: Int = 0
    var isSilent: Bool = false
}

/// The equalizer engine — a port of the Android app's custom ExoPlayer
/// `CustomEqualizerAudioProcessor` biquad chain, applied on iOS through the
/// public MTAudioProcessingTap API attached to AVPlayerItem audio mixes.
@MainActor
final class EqualizerEngine: ObservableObject {

    static let shared = EqualizerEngine()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "echo_eq_enabled"); rebuildFilters() }
    }
    /// 0 = Simple (bass/mid/treble circle), 1 = Advanced (10 bands).
    @Published var mode: Int {
        didSet { UserDefaults.standard.set(mode, forKey: "echo_eq_mode") }
    }
    /// Raw band values -600...600.
    @Published var bands: [Int] {
        didSet {
            for (i, v) in bands.enumerated() {
                UserDefaults.standard.set(v, forKey: "echo_eq_band_\(i)")
            }
            rebuildFilters()
        }
    }
    @Published var preampDb: Double {
        didSet { UserDefaults.standard.set(preampDb, forKey: "echo_eq_preamp") }
    }
    @Published var activePresetId: String? {
        didSet { UserDefaults.standard.set(activePresetId, forKey: "echo_eq_active_preset") }
    }
    @Published var customProfiles: [EQProfile] = [] {
        didSet { saveCustomProfiles() }
    }
    @Published var normalizationEnabled: Bool {
        didSet { UserDefaults.standard.set(normalizationEnabled, forKey: "audioNormalization") }
    }
    @Published var skipSilence: Bool {
        didSet { UserDefaults.standard.set(skipSilence, forKey: "skipSilence") }
    }
    @Published var crossfadeEnabled: Bool {
        didSet { UserDefaults.standard.set(crossfadeEnabled, forKey: "crossfadeEnabled") }
    }
    @Published var crossfadeDuration: Double {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }
    @Published var persistentQueue: Bool {
        didSet { UserDefaults.standard.set(persistentQueue, forKey: "persistentQueue") }
    }

    let dsp = DSPState()

    var bandGainsDb: [Double] { bands.map { Double($0) / 50.0 } }

    private init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "echo_eq_enabled") as? Bool ?? false
        mode = defaults.object(forKey: "echo_eq_mode") as? Int ?? 0
        var loaded = [Int]()
        for i in 0..<10 {
            loaded.append(defaults.object(forKey: "echo_eq_band_\(i)") as? Int ?? 0)
        }
        bands = loaded
        preampDb = defaults.object(forKey: "echo_eq_preamp") as? Double ?? 0
        activePresetId = defaults.string(forKey: "echo_eq_active_preset")
        customProfiles = Self.loadCustomProfiles()
        normalizationEnabled = defaults.object(forKey: "audioNormalization") as? Bool ?? true
        skipSilence = defaults.object(forKey: "skipSilence") as? Bool ?? false
        crossfadeEnabled = defaults.object(forKey: "crossfadeEnabled") as? Bool ?? false
        crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 5
        persistentQueue = defaults.object(forKey: "persistentQueue") as? Bool ?? true
        rebuildFilters()
    }

    // MARK: Simple-mode triangle mapping (AxionEqScreen.kt)

    /// Bass/Mids/Treble (-10...10) → 10 bands.
    func setSimpleValues(bass: Double, mids: Double, treble: Double) {
        let b = bass * 50, m = mids * 50, t = treble * 50
        bands = [
            Int(1.1 * b), Int(b), Int(0.7 * b + 0.3 * m), Int(0.2 * b + 0.8 * m),
            Int(m), Int(m), Int(0.8 * m + 0.2 * t), Int(0.3 * m + 0.7 * t),
            Int(t), Int(1.15 * t)
        ]
        activePresetId = nil
    }

    var simpleBass: Double { Double(bands[1]) / 50.0 }
    var simpleMids: Double { Double(bands[4] + bands[5]) / 100.0 }
    var simpleTreble: Double { Double(bands[8]) / 50.0 }

    func applyPreset(_ preset: EQProfile) {
        bands = preset.bands
        preampDb = preset.preampDb
        activePresetId = preset.id
    }

    func saveCustomPreset(named name: String) {
        let profile = EQProfile(id: "custom_\(Int(Date().timeIntervalSince1970))",
                                name: name, groupName: "Custom", bands: bands, preampDb: preampDb)
        customProfiles.append(profile)
        activePresetId = profile.id
    }

    func deleteCustomPreset(_ id: String) {
        customProfiles.removeAll { $0.id == id }
        if activePresetId == id { activePresetId = nil }
    }

    private static func loadCustomProfiles() -> [EQProfile] {
        guard let data = UserDefaults.standard.data(forKey: "eq_custom_profiles"),
              let profiles = try? JSONDecoder().decode([EQProfile].self, from: data) else { return [] }
        return profiles
    }

    private func saveCustomProfiles() {
        if let data = try? JSONEncoder().encode(customProfiles) {
            UserDefaults.standard.set(data, forKey: "eq_custom_profiles")
        }
    }

    // MARK: Filter rebuild (main thread; DSP reads under lock)

    nonisolated func rebuildFilters() {
        let state = dsp
        state.lock.lock()
        defer { state.lock.unlock() }
        state.enabled = enabled
        state.preamp = pow(10.0, preampDb / 20.0)
        state.bands = bands
        state.skipSilenceEnabled = skipSilence
        let sampleRate = state.sampleRate > 0 ? state.sampleRate : 44100
        let channels = max(1, state.channels)
        state.filters = (0..<channels).map { _ in
            EQProfile.bandFrequencies.enumerated().compactMap { index, freq -> BiquadFilter? in
                guard freq < sampleRate / 2.0 else { return nil }
                let gain = state.bands.indices.contains(index) ? Double(state.bands[index]) / 50.0 : 0
                if gain == 0 { return nil }
                return BiquadFilter(sampleRate: sampleRate, frequency: freq, gainDb: gain)
            }
        }
    }

    /// Sets the normalization gain from the resolved stream's loudnessDb
    /// (LoudnessEnhancer parity: gain = -loudnessDb clamped to [-15, +3] dB).
    func setLoudness(db: Double?) {
        let clamped = min(max(-(db ?? 0), -15), 3)
        dsp.lock.lock()
        dsp.normalizationGain = pow(10.0, clamped / 20.0)
        dsp.lock.unlock()
    }

    // MARK: Silence detection (SilenceDetectorAudioProcessor parity)

    var isCurrentlySilent: Bool {
        dsp.lock.lock()
        defer { dsp.lock.unlock() }
        return dsp.isSilent
    }

    // MARK: Tap creation

    /// Creates an MTAudioProcessingTap wired to the shared DSP state.
    /// Callbacks are C function pointers (no captures); state flows through
    /// clientInfo/GetStorage into the file-private functions below.
    @MainActor
    func makeTap() -> MTAudioProcessingTap? {
        let state = dsp
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(EQTapStateHolder(state)).toOpaque(),
            init: nil,
            finalize: { tap in
                if let storage = MTAudioProcessingTapGetStorage(tap) {
                    Unmanaged<EQTapStateHolder>.fromOpaque(storage).release()
                }
            },
            prepare: { tap, formatDescription, _ in
                guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
                let holder = Unmanaged<EQTapStateHolder>.fromOpaque(storage).takeUnretainedValue()
                epsTapPrepare(state: holder.state, formatDescription: formatDescription)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferList in
                guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
                let holder = Unmanaged<EQTapStateHolder>.fromOpaque(storage).takeUnretainedValue()
                epsTapProcess(state: holder.state, numberFrames: Int(numberFrames), bufferList: bufferList)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, callbacks, 0, &tap)
        guard status == noErr else { return nil }
        return tap
    }
}

private final class EQTapStateHolder {
    let state: DSPState
    init(_ state: DSPState) { self.state = state }
}

/// Render-thread prepare: capture stream format from CMFormatDescription.
private func epsTapPrepare(state: DSPState, formatDescription: CMFormatDescription) {
    state.lock.lock()
    defer { state.lock.unlock() }
    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
        state.sampleRate = asbd.pointee.mSampleRate
        state.channels = Int(asbd.pointee.mChannelsPerFrame)
        state.isFloat = asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        state.isInterleaved = asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    }
    state.silenceFrames = 0
    state.isSilent = false
}

/// The DSP workhorse — EQ cascade + preamp + normalization + silence flag.
private func epsTapProcess(state: DSPState, numberFrames: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
    state.lock.lock()
    defer { state.lock.unlock() }

    let list = bufferList.pointee
    let bufferCount = Int(list.mNumberBuffers)
    let channels = max(1, state.channels)
    let useFilters = state.enabled && !state.filters.isEmpty
    let totalGain = (state.enabled ? state.preamp : 1.0)
        * (state.normalizationEnabled ? state.normalizationGain : 1.0)
    let detectSilence = state.skipSilenceEnabled
    var peak: Double = 0

    if state.isInterleaved {
        // Interleaved: one buffer with channels interleaved per frame.
        guard bufferCount > 0 else { return }
        let buffer = list.mBuffers[0]
        let frameCount = min(numberFrames, Int(buffer.mDataByteCount) / (MemoryLayout<Float>.size * channels))
        if state.isFloat {
            let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let idx = frame * channels + channel
                    var sample = Double(ptr[idx])
                    peak = max(peak, abs(sample))
                    if useFilters, channel < state.filters.count {
                        for bi in state.filters[channel].indices {
                            sample = state.filters[channel][bi].process(sample)
                        }
                    }
                    sample *= totalGain
                    ptr[idx] = Float(max(-1, min(1, sample)))
                }
            }
        } else {
            let ptr = buffer.mData!.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let idx = frame * channels + channel
                    var sample = Double(ptr[idx]) / 32768.0
                    peak = max(peak, abs(sample))
                    if useFilters, channel < state.filters.count {
                        for bi in state.filters[channel].indices {
                            sample = state.filters[channel][bi].process(sample)
                        }
                    }
                    sample *= totalGain
                    ptr[idx] = Int16(max(-32768, min(32767, sample * 32768.0)))
                }
            }
        }
    } else {
        // Non-interleaved: one buffer per channel.
        for bufferIndex in 0..<min(bufferCount, channels) {
            let buffer = list.mBuffers[bufferIndex]
            let frameCount = min(numberFrames, Int(buffer.mDataByteCount) / MemoryLayout<Float>.size)
            if state.isFloat {
                let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<frameCount {
                    var sample = Double(ptr[frame])
                    peak = max(peak, abs(sample))
                    if useFilters, bufferIndex < state.filters.count {
                        for bi in state.filters[bufferIndex].indices {
                            sample = state.filters[bufferIndex][bi].process(sample)
                        }
                    }
                    sample *= totalGain
                    ptr[frame] = Float(max(-1, min(1, sample)))
                }
            } else {
                let ptr = buffer.mData!.assumingMemoryBound(to: Int16.self)
                for frame in 0..<frameCount {
                    var sample = Double(ptr[frame]) / 32768.0
                    peak = max(peak, abs(sample))
                    if useFilters, bufferIndex < state.filters.count {
                        for bi in state.filters[bufferIndex].indices {
                            sample = state.filters[bufferIndex][bi].process(sample)
                        }
                    }
                    sample *= totalGain
                    ptr[frame] = Int16(max(-32768, min(32767, sample * 32768.0)))
                }
            }
        }
    }

    // Silence detection: |sample| < 256 (int16 scale ≈ 0.0078) for > 2 s.
    if detectSilence {
        if peak < 256.0 / 32768.0 {
            state.silenceFrames += numberFrames
            state.isSilent = state.silenceFrames > Int(2.0 * state.sampleRate)
        } else {
            state.silenceFrames = 0
            state.isSilent = false
        }
    } else {
        state.isSilent = false
    }
}

// MARK: - AVPlayerItem integration

extension AVPlayerItem {
    /// Attaches the shared DSP tap (EQ + normalization + silence detection).
    @MainActor
    static func withDSP(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        let engine = EqualizerEngine.shared
        guard engine.enabled || engine.normalizationEnabled || engine.skipSilence else { return item }
        guard let tap = engine.makeTap() else { return item }
        let mix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters(trackID: 0)
        params.audioTapProcessor = tap
        mix.inputParameters = [params]
        item.audioMix = mix
        return item
    }
}
