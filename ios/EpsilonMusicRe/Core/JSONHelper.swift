import Foundation

/// Lightweight dynamic JSON navigation helpers for parsing InnerTube responses.
/// InnerTube responses are huge and shape-shifting; navigating them dynamically
/// (like the Kotlin client does with kotlinx.serialization + default values)
/// keeps the Swift port compact and resilient.
enum JSON {

    static func asDict(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func asArray(_ any: Any?) -> [Any]? {
        any as? [Any]
    }

    static func asString(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    static func asDouble(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func asInt(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Dig through nested dictionaries/arrays: keys are `String` for dicts, `Int` for arrays.
    /// Returns nil as soon as a step fails — never crashes.
    static func dig(_ any: Any?, _ keys: [Any]) -> Any? {
        var current = any
        for key in keys {
            if let k = key as? String {
                guard let dict = current as? [String: Any], let next = dict[k] else { return nil }
                current = next
            } else if let k = key as? Int {
                guard let arr = current as? [Any], k >= 0, k < arr.count else { return nil }
                current = arr[k]
            } else {
                return nil
            }
        }
        return current
    }

    static func dig(_ any: Any?, _ keys: Any...) -> Any? {
        dig(any, keys)
    }

    /// Parses a JSON Data payload to a Foundation object tree.
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
