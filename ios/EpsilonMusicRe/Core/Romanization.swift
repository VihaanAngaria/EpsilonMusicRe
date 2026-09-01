import Foundation

/// Local lyric romanization — the iOS port of the Android app's
/// LyricsUtils.kt (1109 lines): Korean Hangul decomposition, Japanese kana,
/// Cyrillic transliteration, Devanagari and Gurmukhi maps. Fully offline.
enum Romanization {

    // MARK: Public API

    static func romanize(_ text: String) -> String {
        guard isRomanizationEnabledFor(text) else { return text }
        var out = ""
        var buffer = ""
        func flush() {
            if !buffer.isEmpty {
                out += romanizeRun(buffer)
                buffer = ""
            }
        }
        for ch in text {
            if shouldRomanize(ch) {
                buffer.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return out
    }

    static func shouldRomanize(_ ch: Character) -> Bool {
        let scalars = ch.unicodeScalars
        guard let scalar = scalars.first, scalars.count == 1 else { return false }
        return isKorean(scalar) || isKana(scalar) || isCyrillic(scalar)
            || isDevanagari(scalar) || isGurmukhi(scalar)
    }

    private static func isRomanizationEnabledFor(_ text: String) -> Bool {
        text.unicodeScalars.contains { shouldRomanize(Character($0)) }
            && UserDefaults.standard.object(forKey: "lyricsRomanizeAsMain") as? Bool != true
    }

    private static func romanizeRun(_ text: String) -> String {
        var out = ""
        for ch in text {
            let scalar = ch.unicodeScalars.first!
            if isKorean(scalar) {
                out += koreanToRomaja(ch)
            } else if isKana(scalar) {
                out += kanaToRomaji(ch)
            } else if isCyrillic(scalar) {
                out += cyrillicToRomaja(ch, previous: out.last)
            } else if isDevanagari(scalar) {
                out += devanagariToRomaja(ch)
            } else if isGurmukhi(scalar) {
                out += gurmukhiToRomaja(ch)
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // MARK: Script detection

    static func isKorean(_ s: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(Int(s.value)) || s.value == 0x3147 // ㅇ (sign Sang)
    }
    static func isKana(_ s: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(Int(s.value))
    }
    static func isCyrillic(_ s: Unicode.Scalar) -> Bool {
        (0x0400...0x04FF).contains(Int(s.value))
    }
    static func isDevanagari(_ s: Unicode.Scalar) -> Bool {
        (0x0900...0x097F).contains(Int(s.value))
    }
    static func isGurmukhi(_ s: Unicode.Scalar) -> Bool {
        (0x0A00...0x0A7F).contains(Int(s.value))
    }

    // MARK: Korean (Hangul decomposition + transliteration)

    private static let koreanLead = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp",
                                     "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    private static let koreanVowel = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o",
                                      "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu",
                                      "eu", "ui", "i"]
    private static let koreanTail = ["", "g", "kk", "ks", "n", "nj", "nh", "d", "l", "lg",
                                     "lm", "lb", "ls", "lt", "lp", "lh", "m", "b", "bs",
                                     "s", "ss", "ng", "j", "ch", "k", "t", "p", "h"]

    static func koreanToRomaja(_ ch: Character) -> String {
        guard let scalar = ch.unicodeScalars.first else { return String(ch) }
        let value = Int(scalar.value)
        guard (0xAC00...0xD7A3).contains(value) else { return String(ch) }
        let index = value - 0xAC00
        let lead = koreanLead[index / 588]
        let vowel = koreanVowel[(index % 588) / 28]
        let tail = koreanTail[index % 28]
        return lead + vowel + tail
    }

    // MARK: Japanese kana → romaji (digraph-first, sokuon doubling)

    private static let kanaMap: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "wi", "ゑ": "we", "を": "wo", "ん": "n",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "っ": "", "ー": "-", "、": ", ", "。": ". ",
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ダ": "da", "ヂ": "di", "ヅ": "du", "デ": "de", "ド": "do",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヰ": "wi", "ヱ": "we", "ヲ": "wo", "ン": "n",
        "ヴ": "vu", "ヵ": "ka", "ヶ": "ke",
    ]

    private static let kanaDigraphs: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo", "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho", "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho", "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo", "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo", "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "キャ": "kya", "キュ": "kyu", "キョ": "kyo", "シャ": "sha", "シュ": "shu", "ショ": "sho",
        "ジャ": "ja", "ジュ": "ju", "ジョ": "jo", "チャ": "cha", "チュ": "chu", "チョ": "cho",
        "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo", "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
        "ビャ": "bya", "ビュ": "byu", "ビョ": "byo", "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",
        "ミャ": "mya", "ミュ": "myu", "ミョ": "myo", "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
        "ファ": "fa", "フィ": "fi", "フェ": "fe", "フォ": "fo",
    ]

    /// Small kana that lengthen the previous consonant (っ doubling).
    private static let smallTsu = "っッ"

    static func kanaToRomaji(_ ch: Character) -> String {
        return kanaMap[String(ch)] ?? String(ch)
    }

    /// Full-string kana conversion handling digraphs and sokuon.
    static func kanaStringToRomaji(_ text: String) -> String {
        var out = ""
        var pendingDouble = false
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let two = next < text.endIndex ? String(text[index...next]) : ""
            if let digraph = kanaDigraphs[two] {
                if pendingDouble { out += doubledFirst(digraph); pendingDouble = false } else { out += digraph }
                index = text.index(after: next)
                continue
            }
            let single = String(text[index])
            if smallTsu.contains(text[index]) {
                pendingDouble = true
            } else if let mapped = kanaMap[single] {
                if pendingDouble {
                    out += doubledFirst(mapped)
                    pendingDouble = false
                } else {
                    out += mapped
                }
            } else {
                out += single
            }
            index = next
        }
        return out
    }

    private static func doubledFirst(_ syllable: String) -> String {
        guard let first = syllable.first else { return syllable }
        let doubled: Character
        switch first {
        case "a", "i", "u", "e", "o": doubled = first
        case "c": doubled = "t" // っち → tchi
        default: doubled = first
        }
        return String(doubled) + syllable
    }

    // MARK: Cyrillic (Russian-style default; Ukrainian and Serbian extras)

    private static let cyrillicMap: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
        "і": "i", "ї": "yi", "є": "ye", "ґ": "g", "ђ": "dj", "ћ": "ć",
        "љ": "lj", "њ": "nj", "џ": "dz", "ў": "u", "Ғ": "g",
        "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Е": "E", "Ё": "Yo",
        "Ж": "Zh", "З": "Z", "И": "I", "Й": "Y", "К": "K", "Л": "L", "М": "M",
        "Н": "N", "О": "O", "П": "P", "Р": "R", "С": "S", "Т": "T", "У": "U",
        "Ф": "F", "Х": "Kh", "Ц": "Ts", "Ч": "Ch", "Ш": "Sh", "Щ": "Shch",
        "Ъ": "", "Ы": "Y", "Ь": "", "Э": "E", "Ю": "Yu", "Я": "Ya",
        "І": "I", "Ї": "Yi", "Є": "Ye", "Ґ": "G", "Ђ": "Dj", "Ћ": "Ć",
        "Љ": "Lj", "Њ": "Nj", "Џ": "Dz", "Ў": "U",
    ]

    static func cyrillicToRomaja(_ ch: Character, previous: Character?) -> String {
        // Russian "е" → "ye" word-initially.
        if ch == "е" || ch == "Е" {
            if previous == nil || previous == " " || previous == "-" || previous == "(" {
                return ch == "е" ? "ye" : "Ye"
            }
        }
        return cyrillicMap[ch] ?? String(ch)
    }

    // MARK: Devanagari (Hindi)

    private static let devanagariMap: [Character: String] = [
        "अ": "a", "आ": "aa", "इ": "i", "ई": "ii", "उ": "u", "ऊ": "uu",
        "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऋ": "ri",
        "क": "ka", "ख": "kha", "ग": "ga", "घ": "gha", "ङ": "nga",
        "च": "cha", "छ": "chha", "ज": "ja", "झ": "jha", "ञ": "nya",
        "ट": "ta", "ठ": "tha", "ड": "da", "ढ": "dha", "ण": "na",
        "त": "ta", "थ": "tha", "द": "da", "ध": "dha", "न": "na",
        "प": "pa", "फ": "pha", "ब": "ba", "भ": "bha", "म": "ma",
        "य": "ya", "र": "ra", "ल": "la", "व": "va", "श": "sha",
        "ष": "sha", "स": "sa", "ह": "ha", "ळ": "la", "क्ष": "ksha", "ज्ञ": "gya",
        "ा": "aa", "ि": "i", "ी": "ii", "ु": "u", "ू": "uu", "े": "e",
        "ै": "ai", "ो": "o", "ौ": "au", "ृ": "ri", "ं": "n", "ँ": "n",
        "्": "", "़": "", "।": ".", "म्": "m",
    ]

    static func devanagariToRomaja(_ ch: Character) -> String {
        devanagariMap[ch] ?? String(ch)
    }

    // MARK: Gurmukhi (Punjabi)

    private static let gurmukhiMap: [Character: String] = [
        "ਅ": "a", "ਆ": "aa", "ਇ": "i", "ਈ": "ii", "ਉ": "u", "ਊ": "uu",
        "ਏ": "e", "ਐ": "ai", "ਓ": "o", "ਔ": "au",
        "ਕ": "ka", "ਖ": "kha", "ਗ": "ga", "ਘ": "gha", "ਙ": "nga",
        "ਚ": "cha", "ਛ": "chha", "ਜ": "ja", "ਝ": "jha", "ਞ": "nya",
        "ਟ": "ta", "ਠ": "tha", "ਡ": "da", "ਢ": "dha", "ਣ": "na",
        "ਤ": "ta", "ਥ": "tha", "ਦ": "da", "ਧ": "dha", "ਨ": "na",
        "ਪ": "pa", "ਫ": "pha", "ਬ": "ba", "ਭ": "bha", "ਮ": "ma",
        "ਯ": "ya", "ਰ": "ra", "ਲ": "la", "ਵ": "va", "ਸ਼": "sha",
        "ਸ": "sa", "ਹ": "ha", "ਲ਼": "la",
        "ਾ": "aa", "ਿ": "i", "ੀ": "ii", "ੁ": "u", "ੂ": "uu", "ੇ": "e",
        "ੈ": "ai", "ੋ": "o", "ੌ": "au", "ੰ": "n", "ਂ": "n", "੍": "",
        "਼": "", "ੱ": "", "ਃ": "h",
    ]

    static func gurmukhiToRomaja(_ ch: Character) -> String {
        // U+0A71 ਱ tippi/adhak doubles the next consonant — handled loosely.
        if ch.unicodeScalars.first?.value == 0x0A71 { return "" }
        return gurmukhiMap[ch] ?? String(ch)
    }
}
