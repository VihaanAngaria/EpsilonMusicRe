import Foundation

/// OpenAI-compatible chat client — the Swift port of the Android app's
/// OpenRouterService (AiSettings, AiPlaylistGenerator, AiPlaylistModifier,
/// AiRecommendationsHelper). Supports OpenRouter (default), Mistral and any
/// custom OpenAI-compatible base URL, plus DeepL for literal translation.
@MainActor
final class AIClient: ObservableObject {

    static let shared = AIClient()

    // MARK: Settings (AiSettings.kt parity)

    var provider: String {
        get { UserDefaults.standard.string(forKey: "aiProvider") ?? "OpenRouter" }
        set { UserDefaults.standard.set(newValue, forKey: "aiProvider") }
    }
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "openRouterApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openRouterApiKey") }
    }
    var baseUrl: String {
        get { UserDefaults.standard.string(forKey: "openRouterBaseUrl") ?? defaultBaseUrl }
        set { UserDefaults.standard.set(newValue, forKey: "openRouterBaseUrl") }
    }
    var model: String {
        get { UserDefaults.standard.string(forKey: "openRouterModel") ?? "google/gemini-2.5-flash-lite" }
        set { UserDefaults.standard.set(newValue, forKey: "openRouterModel") }
    }
    var deeplKey: String {
        get { UserDefaults.standard.string(forKey: "deeplApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "deeplApiKey") }
    }
    var translationMode: String {
        get { UserDefaults.standard.string(forKey: "translateMode") ?? "Literal" }
        set { UserDefaults.standard.set(newValue, forKey: "translateMode") }
    }
    var translationLanguage: String {
        get { UserDefaults.standard.string(forKey: "translateLanguage") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "translateLanguage") }
    }
    var autoTranslate: Bool {
        get { UserDefaults.standard.object(forKey: "autoTranslate") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "autoTranslate") }
    }
    var aiRecommendations: Bool {
        get { UserDefaults.standard.object(forKey: "aiRecommendations") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "aiRecommendations") }
    }

    var defaultBaseUrl: String {
        switch provider {
        case "Mistral": return "https://api.mistral.ai/v1/chat/completions"
        case "DeepL": return "https://api.deepl.com/v2/translate"
        default: return "https://openrouter.ai/api/v1/chat/completions"
        }
    }

    private init() {}

    var isConfigured: Bool {
        if provider == "DeepL" { return !deeplKey.isEmpty }
        return !apiKey.isEmpty
    }

    // MARK: Chat completion

    struct ChatMessage: Codable {
        var role: String
        var content: String
    }

    func chat(messages: [ChatMessage], maxTokens: Int = 4096) async throws -> String {
        let url = baseUrl
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.3,
            "max_tokens": maxTokens,
        ]
        guard let request = LyricsHTTP.buildRequest(url: url, method: "POST",
                                                    headers: [
                                                        "Authorization": "Bearer \(apiKey)",
                                                        "Content-Type": "application/json",
                                                        "HTTP-Referer": "https://github.com/VihaanAngaria/EpsilonMusic",
                                                        "X-Title": "epsilonmusic",
                                                    ],
                                                    body: try? JSONSerialization.data(withJSONObject: body), timeout: 60) else {
            throw AIClientError.notConfigured
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIClientError.requestFailed(message)
        }
        guard let json = JSON.parse(data),
              let content = JSON.asString(JSON.dig(json, "choices", 0, "message", "content")) else {
            throw AIClientError.badResponse
        }
        return content
    }

    enum AIClientError: LocalizedError {
        case notConfigured, badResponse, requestFailed(String), parseError

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add an AI provider key in Settings → AI lyrics translation."
            case .badResponse: return "Unexpected response from the AI provider."
            case .requestFailed(let m): return "AI provider error: \(m)"
            case .parseError: return "The AI response could not be parsed."
            }
        }
    }

    // MARK: Lyrics translation

    func translateLyrics(lines: [String]) async throws -> [String] {
        // DeepL path.
        if provider == "DeepL" {
            return try await deeplTranslate(lines: lines)
        }
        let systemPrompt = """
        You are a precise lyrics translation assistant. Your output must ALWAYS be a valid JSON array of strings. \
        CRITICAL RULES: 1. Output ONLY a JSON array: ["line1", ...]. 2. NO explanations or markdown. \
        3. Each input line maps to exactly one output line. 4. Preserve empty lines as "". \
        5. Return EXACTLY \(lines.count) items. 6. If uncertain, best approximation but maintain line count.
        """
        var userPrompt: String
        switch translationMode {
        case "Romanized":
            userPrompt = """
            Transliterate each line into ASCII-only romanized text (e.g. "आ" → "aa", "東京" → "toukyou"). \
            No diacritics. Target script: ASCII. Translate to \(translationLanguage)-suitable romanization. Input:
            \(Self.encodeLines(lines))
            """
        case "Transcribed":
            userPrompt = """
            Phonetically transcribe each line into the \(translationLanguage) writing system. Input:
            \(Self.encodeLines(lines))
            """
        default:
            userPrompt = """
            Translate each lyric line to \(translationLanguage), prioritizing singability and natural flow. Input:
            \(Self.encodeLines(lines))
            """
        }
        let content = try await chat(messages: [ChatMessage(role: "system", content: systemPrompt),
                                                ChatMessage(role: "user", content: userPrompt)],
                                     maxTokens: max(100, lines.count * 100))
        guard let parsed = Self.parseTranslationArray(content, expectedCount: lines.count) else {
            throw AIClientError.parseError
        }
        return parsed
    }

    private func deeplTranslate(lines: [String]) async throws -> [String] {
        var endpoint = "https://api.deepl.com/v2/translate"
        if deeplKey.hasSuffix(":fx") {
            endpoint = "https://api-free.deepl.com/v2/translate"
        }
        var target = translationLanguage.uppercased()
        if target == "EN" { target = "EN-US" }
        let body: [String: Any] = [
            "text": lines,
            "target_lang": target,
            "preserve_formatting": true,
        ]
        guard let request = LyricsHTTP.buildRequest(url: endpoint, method: "POST",
                                                    headers: [
                                                        "Authorization": "DeepL-Auth-Key \(deeplKey)",
                                                        "Content-Type": "application/json",
                                                    ],
                                                    body: try? JSONSerialization.data(withJSONObject: body), timeout: 60) else {
            throw AIClientError.notConfigured
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = JSON.parse(data),
              let translations = JSON.asArray(JSON.dig(json, "translations")) else {
            throw AIClientError.badResponse
        }
        return translations.compactMap { JSON.asString(JSON.dig($0, "text")) }
    }

    static func encodeLines(_ lines: [String]) -> String {
        Self.jsonString(from: lines) ?? lines.joined(separator: "\n")
    }

    static func parseTranslationArray(_ content: String, expectedCount: Int) -> [String]? {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // strip markdown fences
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String], array.count == expectedCount {
            return array
        }
        // Partial JSON array recovery (streamed-ish responses).
        if text.hasPrefix("[") {
            var recovered: [String] = []
            let regex = try? NSRegularExpression(pattern: "\"((?:[^\"\\\\]|\\\\.)*)\"")
            if let regex = regex, let matches = try? regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                for match in matches {
                    if let range = Range(match.range(at: 1), in: text) {
                        let value = String(text[range])
                            .replacingOccurrences(of: "\\\"", with: "\"")
                            .replacingOccurrences(of: "\\n", with: "\n")
                        recovered.append(value)
                    }
                }
            }
            if !recovered.isEmpty {
                while recovered.count < expectedCount { recovered.append("") }
                return Array(recovered.prefix(expectedCount))
            }
        }
        return nil
    }

    static func jsonString(from lines: [String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: lines) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: AI playlists

    struct AISong: Codable, Equatable {
        var title: String
        var artist: String
    }

    /// Create-from-prompt (AiPlaylistGenerator).
    func generatePlaylist(prompt: String, songCount: Int = 20) async throws -> (name: String, songs: [AISong]) {
        let systemPrompt = """
        You are a highly accurate and strict music historian with a deep knowledge of every genre, era, and region. \
        Output ONLY raw JSON: {"name": "<playlist name>", "songs": [{"title": "...", "artist": "..."}]} with exactly \
        \(songCount) songs matching the request.
        """
        let content = try await chat(messages: [ChatMessage(role: "system", content: systemPrompt),
                                                ChatMessage(role: "user", content: prompt)], maxTokens: 4000)
        return Self.parsePlaylist(content)
    }

    static func parsePlaylist(_ content: String) -> (name: String, songs: [AISong]) {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        guard let data = text.data(using: .utf8) else { return ("", []) }
        struct Root: Codable { var name: String?; var songs: [AISong]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return ("", []) }
        return (root.name ?? "AI Playlist", root.songs ?? [])
    }

    /// Modify-with-instruction (AiPlaylistModifier).
    struct AIModifyResult: Codable {
        var removeIds: [Int]
        var additions: [AISong]

        enum CodingKeys: String, CodingKey {
            case removeIds = "remove_ids"
            case additions
        }
    }

    func modifyPlaylist(current: [Song], instruction: String) async throws -> AIModifyResult {
        let songsArray = current.enumerated().map { index, song -> [String: String] in
            ["id": "\(index)", "title": song.title, "artist": song.artistsText]
        }
        let songsJson = (try? JSONSerialization.data(withJSONObject: songsArray))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let systemPrompt = """
        You are a playlist editor. Current playlist (JSON): \(songsJson). \
        User instruction: \(instruction). \
        Output ONLY JSON: {"remove_ids": [int...], "additions": [{"title": "...", "artist": "..."}]}
        """
        let content = try await chat(messages: [ChatMessage(role: "system", content: systemPrompt)],
                                     maxTokens: 3000)
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        if let data = text.data(using: .utf8),
           let result = try? JSONDecoder().decode(AIModifyResult.self, from: data) {
            return result
        }
        return AIModifyResult(removeIds: [], additions: [])
    }

    /// Recommendations from listening history (AiRecommendationsHelper).
    func recommend(seedSongs: [Song], count: Int = 20) async throws -> [AISong] {
        let seedText = seedSongs.prefix(40).map { "\($0.title) by \($0.artistsText)" }.joined(separator: "\n")
        let systemPrompt = """
        Based on these songs the user plays and likes, recommend \(count) similar but different songs. \
        Output ONLY a JSON array: [{"title": "...", "artist": "..."}]. Seed songs:
        \(seedText)
        """
        let content = try await chat(messages: [ChatMessage(role: "system", content: systemPrompt)], maxTokens: 3000)
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "^```[a-zA-Z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        guard let data = text.data(using: .utf8),
              let songs = try? JSONDecoder().decode([AISong].self, from: data) else {
            return []
        }
        return songs
    }
}
