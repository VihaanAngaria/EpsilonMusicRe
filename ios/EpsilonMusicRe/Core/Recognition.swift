import Foundation
import AVFoundation

// MARK: - Recognition result model

struct RecognitionResult: Identifiable, Codable, Equatable {
    var trackId: String
    var title: String
    var artist: String
    var album: String?
    var coverArtUrl: String?
    var coverArtHqUrl: String?
    var genre: String?
    var releaseDate: String?
    var label: String?
    var lyrics: [String]?
    var shazamUrl: String?
    var appleMusicUrl: String?
    var spotifyUrl: String?
    var isrc: String?
    var youtubeVideoId: String?
    var recognizedAt: Double

    var id: String { trackId }
}

// MARK: - Recorder (AudioRecord parity: 44.1 kHz mono PCM16, 10 s)

@MainActor
final class MicRecorder: ObservableObject {

    @Published var level: Double = 0
    @Published var elapsed: Double = 0

    private let engine = AVAudioEngine()
    private var samples: [Int16] = []
    private var sampleRate: Double = 44100
    private var startedAt: Date?

    /// Records for `seconds`, returning raw mono Int16 samples at the actual input rate.
    func record(seconds: Double) async throws -> (samples: [Int16], sampleRate: Double) {
        samples = []
        elapsed = 0
        startedAt = Date()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100
        let totalFrames = Int(seconds * sampleRate)

        let group = DispatchGroup()
        group.enter()

        let collected = LockedBuffer()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            if let data = UnsafeMutableAudioBufferListPointer(buffer.audioBufferList).first?.mData {
                let pointer = data.assumingMemoryBound(to: Int16.self)
                let chunk = UnsafeBufferPointer(start: pointer, count: frames)
                collected.append(Array(chunk))
            }
            Task { @MainActor in
                self?.elapsed = Date().timeIntervalSince(self?.startedAt ?? Date())
                self?.level = Double(frames) / 4096.0
            }
            if collected.count >= totalFrames {
                group.leave()
            }
        }

        engine.prepare()
        try engine.start()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds + 0.5) {
                if !finished {
                    finished = true
                    group.leave()
                    continuation.resume()
                }
            }
            group.notify(queue: .global()) {
                if !finished {
                    finished = true
                    continuation.resume()
                }
            }
        }

        input.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        samples = collected.snapshot()
        elapsed = 0
        level = 0
        return (samples, sampleRate)
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Thread-safe sample accumulator.
    private final class LockedBuffer: @unchecked Sendable {
        private var data: [Int16] = []
        private let lock = NSLock()

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return data.count
        }

        func append(_ chunk: [Int16]) {
            lock.lock(); defer { lock.unlock() }
            data.append(contentsOf: chunk)
        }

        func snapshot() -> [Int16] {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }
}

// MARK: - Resampler (AudioResampler.kt parity: linear interpolation to 16 kHz)

enum AudioResampler {
    static func resampleTo16k(_ samples: [Int16], from sourceRate: Double) -> [Int16] {
        guard sourceRate > 0, sourceRate != 16000, !samples.isEmpty else { return samples }
        let ratio = sourceRate / 16000.0
        let outCount = Int(Double(samples.count) / ratio)
        var out = [Int16](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let position = Double(i) * ratio
            let index = Int(position)
            let frac = position - Double(index)
            let current = index < samples.count ? samples[index] : 0
            let next = index + 1 < samples.count ? samples[index + 1] : current
            let interpolated = Double(current) * (1 - frac) + Double(next) * frac
            out[i] = Int16(max(-32768, min(32767, interpolated)))
        }
        return out
    }
}

// MARK: - Signature generator (ShazamSignatureGenerator.kt — a 1:1 port)

enum ShazamSignatureGenerator {

    private static let sampleRate = 16000
    private static let fftSize = 2048
    private static let fftOutputSize = fftSize / 2 + 1
    private static let maxPeaks = 255
    private static let maxTimeSeconds = 12.0
    private static let ringBufSize = 256

    private static let hanning: [Double] = (0..<fftSize).map { i in
        0.5 * (1.0 - cos(2.0 * Double.pi * Double(i + 1) / 2049.0))
    }

    private struct FrequencyPeak {
        var fftPassNumber: Int
        var peakMagnitude: Int
        var correctedPeakFrequencyBin: Int
    }

    static func fromI16(samples: [Int16]) -> String {
        var state = GeneratorState()
        return state.process(samples)
    }

    private struct GeneratorState {
        var samplesRing = [Int](repeating: 0, count: fftSize)
        var samplesPos = 0
        var fftOutputs = [[Double]](repeating: [Double](repeating: 0, count: fftOutputSize), count: ringBufSize)
        var fftPos = 0
        var fftNumWritten = 0
        var spreadFfts = [[Double]](repeating: [Double](repeating: 0, count: fftOutputSize), count: ringBufSize)
        var spreadPos = 0
        var spreadNumWritten = 0
        var numSamples = 0
        var bandPeaks: [[FrequencyPeak]] = [[], [], [], []]
        var totalPeaks = 0

        mutating func process(_ pcm: [Int16]) -> String {
            var offset = 0
            while offset + 128 <= pcm.count {
                let elapsedSec = Double(numSamples) / Double(sampleRate)
                if elapsedSec >= maxTimeSeconds && totalPeaks >= maxPeaks { break }
                numSamples += 128
                feedSamples(pcm, start: offset, count: 128)
                doFFT()
                doPeakSpreadingAndRecognition()
                offset += 128
            }
            return encodeSignature()
        }

        private mutating func feedSamples(_ pcm: [Int16], start: Int, count: Int) {
            for k in start..<(start + count) {
                samplesRing[samplesPos] = Int(pcm[k])
                samplesPos = (samplesPos + 1) % fftSize
            }
        }

        private mutating func doFFT() {
            var windowed = [Double](repeating: 0, count: fftSize)
            for i in 0..<fftSize {
                windowed[i] = Double(samplesRing[(samplesPos + i) % fftSize]) * hanning[i]
            }
            let result = computeRFFT(windowed)
            fftOutputs[fftPos] = result
            fftPos = (fftPos + 1) % ringBufSize
            fftNumWritten += 1
        }

        private mutating func doPeakSpreadingAndRecognition() {
            doPeakSpreading()
            if spreadNumWritten >= 47 {
                doPeakRecognition()
            }
        }

        private mutating func doPeakSpreading() {
            let lastFftIdx = (fftPos - 1 + ringBufSize) % ringBufSize
            var spread = fftOutputs[lastFftIdx]

            for pos in 0..<(fftOutputSize - 2) {
                spread[pos] = max(spread[pos], spread[pos + 1], spread[pos + 2])
            }

            for pos in 0..<fftOutputSize {
                var maxVal = spread[pos]
                for offset in [-1, -3, -6] {
                    let idx = ((spreadPos + offset) % ringBufSize + ringBufSize) % ringBufSize
                    let oldVal = spreadFfts[idx][pos]
                    if oldVal > maxVal { maxVal = oldVal }
                    spreadFfts[idx][pos] = maxVal
                }
            }

            spreadFfts[spreadPos] = spread
            spreadPos = (spreadPos + 1) % ringBufSize
            spreadNumWritten += 1
        }

        private mutating func doPeakRecognition() {
            let fftMinus46 = fftOutputs[(fftPos - 46 + ringBufSize * 2) % ringBufSize]
            let spreadMinus49 = spreadFfts[(spreadPos - 49 + ringBufSize * 2) % ringBufSize]

            let otherOffsets = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249]

            for binPos in 10..<(fftOutputSize - 8) {
                let fftVal = fftMinus46[binPos]
                if fftVal < 1.0 / 64.0 || fftVal < spreadMinus49[binPos] { continue }

                var maxNeighborSpread49 = 0.0
                for neighborOffset in [-10, -7, -4, -3, 1, 2, 5, 8] {
                    let v = spreadMinus49[binPos + neighborOffset]
                    if v > maxNeighborSpread49 { maxNeighborSpread49 = v }
                }
                if fftVal <= maxNeighborSpread49 { continue }

                var maxNeighborOther = maxNeighborSpread49
                for otherOffset in otherOffsets {
                    let spreadIdx = ((spreadPos + otherOffset) % ringBufSize + ringBufSize) % ringBufSize
                    let v = spreadFfts[spreadIdx][binPos - 1]
                    if v > maxNeighborOther { maxNeighborOther = v }
                }
                if fftVal <= maxNeighborOther { continue }

                let fftNumber = spreadNumWritten - 46

                let peakMag = log(max(1.0 / 64.0, fftVal)) * 1477.3 + 6144
                let peakMagBefore = log(max(1.0 / 64.0, fftMinus46[binPos - 1])) * 1477.3 + 6144
                let peakMagAfter = log(max(1.0 / 64.0, fftMinus46[binPos + 1])) * 1477.3 + 6144

                let peakVariation1 = peakMag * 2 - peakMagBefore - peakMagAfter
                let peakVariation2 = (peakMagAfter - peakMagBefore) * 32 / peakVariation1

                let correctedBin = Double(binPos) * 64.0 + peakVariation2
                let frequencyHz = correctedBin * (16000.0 / 2.0 / 1024.0 / 64.0)

                let band: Int
                switch frequencyHz {
                case ..<250: continue
                case ..<520: band = 0
                case ..<1450: band = 1
                case ..<3500: band = 2
                case ...5500: band = 3
                default: continue
                }

                bandPeaks[band].append(FrequencyPeak(
                    fftPassNumber: fftNumber,
                    peakMagnitude: Int(peakMag),
                    correctedPeakFrequencyBin: Int(correctedBin)))
                totalPeaks += 1
            }
        }

        // MARK: Binary encoding (encodeSignature() — exact byte layout)

        private mutating func encodeSignature() -> String {
            var contents = [UInt8]()

            for bandId in 0...3 {
                let peaks = bandPeaks[bandId]
                if peaks.isEmpty { continue }

                var peakBuf: [UInt8] = []
                var prevFftPassNumber = 0

                for peak in peaks {
                    let diff = peak.fftPassNumber - prevFftPassNumber
                    if diff >= 255 {
                        peakBuf.append(0xFF)
                        appendLittleEndian32(&peakBuf, peak.fftPassNumber)
                        prevFftPassNumber = peak.fftPassNumber
                    }
                    peakBuf.append(UInt8(peak.fftPassNumber - prevFftPassNumber))
                    appendLittleEndian16(&peakBuf, peak.peakMagnitude)
                    appendLittleEndian16(&peakBuf, peak.correctedPeakFrequencyBin)
                    prevFftPassNumber = peak.fftPassNumber
                }

                appendLittleEndian32(&contents, 0x60030040 + bandId)
                appendLittleEndian32(&contents, peakBuf.count)
                contents.append(contentsOf: peakBuf)

                let padBytes = (4 - peakBuf.count % 4) % 4
                for _ in 0..<padBytes { contents.append(0) }
            }

            let sizeMinusHeader = contents.count + 8
            let samplesAndOffset = Int(Double(numSamples) + Double(sampleRate) * 0.24)

            var header = [UInt8]()
            appendLittleEndian32(&header, 0xcafe2580)
            appendLittleEndian32(&header, 0) // CRC placeholder
            appendLittleEndian32(&header, sizeMinusHeader)
            appendLittleEndian32(&header, 0x94119c00)
            appendLittleEndian32(&header, 0)
            appendLittleEndian32(&header, 0)
            appendLittleEndian32(&header, 0)
            appendLittleEndian32(&header, 3 << 27)
            appendLittleEndian32(&header, 0)
            appendLittleEndian32(&header, 0)
            appendLittleEndian32(&header, samplesAndOffset)
            appendLittleEndian32(&header, (15 << 19) + 0x40000)

            var full = header
            appendLittleEndian32(&full, 0x40000000)
            appendLittleEndian32(&full, contents.count + 8)
            full.append(contentsOf: contents)

            // CRC32 over bytes[8...]
            let crc = crc32(Array(full[8...]))
            full[4] = UInt8(crc & 0xFF)
            full[5] = UInt8((crc >> 8) & 0xFF)
            full[6] = UInt8((crc >> 16) & 0xFF)
            full[7] = UInt8((crc >> 24) & 0xFF)

            let base64 = Data(full).base64EncodedString()
            return "data:audio/vnd.shazam.sig;base64,\(base64)"
        }
    }

    // MARK: RFFT (computeRfft — iterative radix-2, magnitude squared)

    static func computeRFFT(_ windowed: [Double]) -> [Double] {
        let n = windowed.count
        var re = windowed
        var im = [Double](repeating: 0, count: n)

        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }

        var len = 2
        while len <= n {
            let halfLen = len >> 1
            let ang = -Double.pi / Double(halfLen)
            let wBaseRe = cos(ang)
            let wBaseIm = sin(ang)
            var i = 0
            while i < n {
                var wRe = 1.0
                var wIm = 0.0
                for k in 0..<halfLen {
                    let u = i + k
                    let v = u + halfLen
                    let evenRe = re[u]
                    let evenIm = im[u]
                    let oddRe = re[v] * wRe - im[v] * wIm
                    let oddIm = re[v] * wIm + im[v] * wRe
                    re[u] = evenRe + oddRe
                    im[u] = evenIm + oddIm
                    re[v] = evenRe - oddRe
                    im[v] = evenIm - oddIm
                    let newWRe = wRe * wBaseRe - wIm * wBaseIm
                    wIm = wRe * wBaseIm + wIm * wBaseRe
                    wRe = newWRe
                }
                i += len
            }
            len <<= 1
        }

        let scaleFactor = 1.0 / Double(1 << 17)
        let minVal = 1e-10
        var out = [Double](repeating: 0, count: fftOutputSize)
        for idx in 0..<fftOutputSize {
            let mag = (re[idx] * re[idx] + im[idx] * im[idx]) * scaleFactor
            out[idx] = mag < minVal ? minVal : mag
        }
        return out
    }

    static func appendLittleEndian16(_ out: inout [UInt8], _ value: Int) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
    }

    static func appendLittleEndian32(_ out: inout [UInt8], _ value: Int) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8((value >> 24) & 0xFF))
    }

    /// CRC-32 (IEEE 802.3, zlib-compatible).
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var table: [UInt32] = []
        if table.isEmpty {
            for i in 0..<256 {
                var c = UInt32(i)
                for _ in 0..<8 {
                    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
                }
                table.append(c)
            }
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Recognizer (Shazam HTTP client + persistence)

@MainActor
final class RecognitionManager: ObservableObject {

    static let shared = RecognitionManager()

    enum Status: Equatable {
        case ready
        case listening(elapsed: Double)
        case processing
        case success(RecognitionResult)
        case noMatch(String)
        case error(String)
    }

    @Published var status: Status = .ready
    @Published var history: [RecognitionResult] = [] {
        didSet { saveHistory() }
    }

    private let recorder = MicRecorder()

    private static var historyFile: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("recognition-history.json")
    }

    private init() {
        loadHistory()
    }

    func recognize() async {
        status = .listening(elapsed: 0)
        do {
            let (raw, rate) = try await recorder.record(seconds: 10)
            status = .processing
            let resampled = AudioResampler.resampleTo16k(raw, from: rate)
            guard !resampled.isEmpty else {
                status = .error("No audio captured")
                return
            }
            let signature = ShazamSignatureGenerator.fromI16(samples: resampled)
            let sampleDurationMs = Int64(resampled.count) * 1000 / 16000
            let result = try await ShazamClient.recognize(signature: signature, sampleDurationMs: sampleDurationMs)
            if let result = result {
                status = .success(result)
                if !history.contains(where: { $0.trackId == result.trackId }) {
                    history.insert(result, at: 0)
                    if history.count > 100 { history.removeLast() }
                }
            } else {
                status = .noMatch("No matches found. Try again with clearer audio.")
            }
        } catch {
            let message = error.localizedDescription
            if message.contains("No match") {
                status = .noMatch("No matches found. Try again with clearer audio.")
            } else {
                status = .error(message)
            }
        }
    }

    func reset() {
        status = .ready
    }

    func clearHistory() {
        history = []
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: Self.historyFile, options: .atomic)
        }
    }

    private func loadHistory() {
        if let data = try? Data(contentsOf: Self.historyFile),
           let loaded = try? JSONDecoder().decode([RecognitionResult].self, from: data) {
            history = loaded
        }
    }
}

// MARK: - Shazam HTTP client (Shazam.kt performRecognition parity)

enum ShazamClient {

    private static let userAgents = [
        "Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)",
        "Dalvik/1.6.0 (Linux; U; Android 4.4.2; SM-T210 Build/KOT49H)",
        "Dalvik/2.1.0 (Linux; U; Android 5.1.1; SM-P905V Build/LMY47X)",
        "Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)",
        "Dalvik/2.1.0 (Linux; U; Android 5.0; SM-G900F Build/LRX21T)",
    ]

    private static let timezones = [
        "Europe/Paris", "Europe/London", "America/New_York",
        "America/Los_Angeles", "Asia/Tokyo", "Asia/Dubai",
    ]

    static func recognize(signature: String, sampleDurationMs: Int64) async throws -> RecognitionResult? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid1 = UUID().uuidString.uppercased()
        let uuid2 = UUID().uuidString.lowercased()

        let body: [String: Any] = [
            "geolocation": [
                "altitude": Double.random(in: 100...500),
                "latitude": Double.random(in: -90...90),
                "longitude": Double.random(in: -180...180),
            ],
            "signature": [
                "samplems": sampleDurationMs,
                "timestamp": timestamp,
                "uri": signature,
            ],
            "timestamp": timestamp,
            "timezone": timezones.randomElement() ?? "Europe/Paris",
        ]

        let url = "https://amp.shazam.com/discovery/v5/en/US/android/-/tag/\(uuid1)/\(uuid2)"
            + "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&video=v3"
        guard let request = LyricsHTTP.buildRequest(url: url, method: "POST",
                                                    headers: [
                                                        "User-Agent": userAgents.randomElement() ?? "Dalvik/2.1.0",
                                                        "Content-Language": "en_US",
                                                        "Content-Type": "application/json",
                                                    ],
                                                    body: try? JSONSerialization.data(withJSONObject: body), timeout: 30) else {
            throw RecognitionError.badRequest
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RecognitionError.badResponse }
        switch http.statusCode {
        case 200..<300:
            break
        case 404:
            return nil
        case 429:
            throw RecognitionError.rateLimited
        case 500...599:
            throw RecognitionError.serviceUnavailable
        default:
            throw RecognitionError.requestFailed("Recognition failed (error \(http.statusCode))")
        }
        guard let json = JSON.parse(data) else { throw RecognitionError.badResponse }
        return parseResult(json, recognizedAt: Date().timeIntervalSince1970)
    }

    enum RecognitionError: LocalizedError {
        case badRequest, badResponse, rateLimited, serviceUnavailable, requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .badRequest: return "Recognition request could not be built"
            case .badResponse: return "Unexpected response from Shazam"
            case .rateLimited: return "Too many requests — wait a moment and try again"
            case .serviceUnavailable: return "Shazam service temporarily unavailable"
            case .requestFailed(let m): return m
            }
        }
    }

    // MARK: Response parsing (toRecognitionResult parity)

    static func parseResult(_ json: Any, recognizedAt: Double) -> RecognitionResult? {
        guard let root = json as? [String: Any], let track = JSON.asDict(root["track"]) else { return nil }
        let trackId = JSON.asString(track["key"])?.description ?? UUID().uuidString
        let title = JSON.asString(track["title"]) ?? ""
        let artist = JSON.asString(track["subtitle"]) ?? ""
        guard !title.isEmpty else { return nil }

        var coverArt: String?
        var coverArtHq: String?
        if let images = JSON.asDict(track["images"]) {
            coverArt = JSON.asString(images["coverart"])
            coverArtHq = JSON.asString(images["coverarthq"]) ?? coverArt
        }
        var genre: String?
        if let genres = JSON.asDict(track["genres"]) {
            genre = JSON.asString(genres["primary"])
        }
        let isrc = JSON.asString(track["isrc"])
        let shazamUrl = JSON.asString(track["url"])

        var appleMusicUrl: String?
        var spotifyUrl: String?
        var youtubeVideoId: String?
        if let hub = JSON.asDict(track["hub"]) {
            if let options = JSON.asArray(hub["options"]) {
                for rawOption in options {
                    guard let option = rawOption as? [String: Any] else { continue }
                    let provider = JSON.asString(option["providername"]) ?? ""
                    let uri = JSON.asString(option["uri"]) ?? ""
                    if provider.lowercased().contains("apple") {
                        appleMusicUrl = JSON.asString(JSON.dig(option, "actions", 0, "uri")) ?? uri
                    } else if provider.lowercased().contains("spotify") {
                        spotifyUrl = uri
                    } else if provider.lowercased().contains("youtube") {
                        youtubeVideoId = Self.extractVideoId(from: uri)
                    }
                }
            }
            // YouTube video actions (type contains "video").
            if youtubeVideoId == nil, let options = JSON.asArray(hub["options"]) {
                for rawOption in options {
                    guard let option = rawOption as? [String: Any] else { continue }
                    let type = JSON.asString(option["type"]) ?? ""
                    if type.lowercased().contains("video") {
                        if let actions = JSON.asArray(option["actions"]), let rawAction = actions.first,
                           let action = rawAction as? [String: Any] {
                            let uri = JSON.asString(action["uri"]) ?? ""
                            youtubeVideoId = Self.extractVideoId(from: uri)
                        }
                    }
                }
            }
        }

        var album: String?
        var releaseDate: String?
        var label: String?
        var lyrics: [String]?
        if let sections = JSON.asArray(track["sections"]) {
            for rawSection in sections {
                guard let section = rawSection as? [String: Any] else { continue }
                let type = JSON.asString(section["type"]) ?? ""
                if type == "SONG", let metadata = JSON.asArray(section["metadata"]) {
                    for rawMeta in metadata {
                        guard let meta = rawMeta as? [String: Any] else { continue }
                        let metaTitle = JSON.asString(meta["title"]) ?? ""
                        let metaText = JSON.asString(meta["text"]) ?? ""
                        if metaTitle == "Album" { album = metaText }
                        if metaTitle == "Released" { releaseDate = metaText }
                        if metaTitle == "Label" { label = metaText }
                    }
                }
                if type == "LYRICS" {
                    lyrics = JSON.asArray(section["text"])?.compactMap { JSON.asString($0) }
                }
            }
        }

        return RecognitionResult(
            trackId: trackId, title: title, artist: artist, album: album,
            coverArtUrl: coverArt, coverArtHqUrl: coverArtHq, genre: genre,
            releaseDate: releaseDate, label: label, lyrics: lyrics,
            shazamUrl: shazamUrl, appleMusicUrl: appleMusicUrl, spotifyUrl: spotifyUrl,
            isrc: isrc, youtubeVideoId: youtubeVideoId, recognizedAt: recognizedAt)
    }

    static func extractVideoId(from uri: String) -> String? {
        guard !uri.isEmpty else { return nil }
        if let range = uri.range(of: "v=") {
            let tail = String(uri[range.upperBound...])
            let id = tail.prefix(11)
            if id.count == 11 { return String(id) }
        }
        if uri.contains("youtu.be/") {
            let tail = uri.components(separatedBy: "youtu.be/").last ?? ""
            let id = tail.prefix(11)
            if id.count == 11 { return String(id) }
        }
        if uri.hasSuffix(".mp4") || uri.count == 11 { return uri }
        return nil
    }

    /// Finds the song on YouTube Music and plays it (Android RecognitionScreen flow).
    static func playOnYouTubeMusic(_ result: RecognitionResult) async throws -> Song? {
        if let videoId = result.youtubeVideoId {
            return Song(videoId: videoId, title: result.title,
                        artists: [result.artist], album: result.album,
                        duration: nil, thumbnail: result.coverArtHqUrl,
                        isLocal: false, localKey: nil, isDemo: false)
        }
        let query = "\(result.artist) \(result.title)"
        let search = try await InnerTube.shared.search(query: query, filter: .songs)
        return search.songs.first
    }
}
