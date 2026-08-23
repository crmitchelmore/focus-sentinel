import Foundation

/// What went wrong, and exactly where.
///
/// A corpus that fails to load with *"The data couldn't be read because it isn't in the correct
/// format"* is a corpus nobody can fix. Every error here names the file, the JSON path and the
/// reason, because the person reading it is looking at 132 objects and needs to be told which
/// one.
public struct CorpusDecodingError: Error, CustomStringConvertible, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }

    public var description: String { "\(path): \(reason)" }
}

/// A JSON object read **strictly**: an unknown key, a missing key or a value of the wrong type
/// fails the load rather than defaulting (R-66 rule 5, Appendix A.5).
///
/// ## Why this is hand-written rather than `Codable`
///
/// `Codable` ignores keys it does not know. That is the right default for a wire format and
/// exactly the wrong one for a golden corpus: a case with `"dwellSecods": 240` would decode
/// with a dwell of zero, pass for the wrong reason, and stop testing the thing it was written
/// for — silently, for ever. So every accessor here *consumes* its key and `finish()` fails on
/// whatever is left over. A misspelling is a red gate, which is what "strictly decoded" has to
/// mean if it is to mean anything.
///
/// A class rather than a struct because consumption is mutation and every accessor would
/// otherwise have to be `mutating`, which reads badly at forty call sites.
public final class StrictObject {
    public let path: String
    private let raw: [String: Any]
    private var consumed: Set<String> = []

    public init(path: String, raw: [String: Any]) {
        self.path = path
        self.raw = raw
    }

    /// Parse a whole file. `JSONSerialization` rather than `JSONDecoder`, because the key
    /// audit needs the untyped tree.
    public static func parse(data: Data, path: String) throws -> StrictObject {
        let any: Any
        do {
            any = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CorpusDecodingError(path: path, reason: "not valid JSON: \(error)")
        }
        guard let object = any as? [String: Any] else {
            throw CorpusDecodingError(path: path, reason: "the top level is not an object")
        }
        return StrictObject(path: path, raw: object)
    }

    // MARK: - Reading

    private func take(_ key: String) -> Any? {
        consumed.insert(key)
        let value = raw[key]
        if value is NSNull { return nil }
        return value
    }

    private func fail(_ key: String, _ reason: String) -> CorpusDecodingError {
        CorpusDecodingError(path: "\(path).\(key)", reason: reason)
    }

    public func string(_ key: String) throws -> String {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard let text = value as? String else { throw fail(key, "is not a string") }
        return text
    }

    public func nonEmptyString(_ key: String) throws -> String {
        let text = try string(key)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw fail(key, "is empty, and every case must be able to explain itself")
        }
        return text
    }

    public func optionalString(_ key: String) throws -> String? {
        guard let value = take(key) else { return nil }
        guard let text = value as? String else { throw fail(key, "is not a string") }
        return text
    }

    /// `true` when this is JSON's `true`/`false` rather than a number.
    ///
    /// `value is Bool` cannot answer that question: `JSONSerialization` returns every scalar as
    /// an `NSNumber`, and an `NSNumber` holding `1` bridges to `Bool` happily — so a naive
    /// `!(value is Bool)` guard rejects `"revision": 1` as "not a number". The type identifier
    /// is the only thing that distinguishes the two, because on this platform JSON's booleans
    /// really are `CFBoolean` instances.
    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    public func int(_ key: String) throws -> Int {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard let number = value as? NSNumber, !Self.isBoolean(value) else {
            throw fail(key, "is not a number")
        }
        return number.intValue
    }

    public func optionalInt(_ key: String) throws -> Int? {
        guard let value = take(key) else { return nil }
        guard let number = value as? NSNumber, !Self.isBoolean(value) else {
            throw fail(key, "is not a number")
        }
        return number.intValue
    }

    public func bool(_ key: String) throws -> Bool {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard Self.isBoolean(value), let flag = value as? Bool else {
            throw fail(key, "is not a boolean")
        }
        return flag
    }

    public func optionalBool(_ key: String, default fallback: Bool) throws -> Bool {
        guard let value = take(key) else { return fallback }
        guard Self.isBoolean(value), let flag = value as? Bool else {
            throw fail(key, "is not a boolean")
        }
        return flag
    }

    public func strings(_ key: String) throws -> [String] {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard let array = value as? [Any] else { throw fail(key, "is not an array") }
        return try array.enumerated().map { index, element in
            guard let text = element as? String else {
                throw CorpusDecodingError(
                    path: "\(path).\(key)[\(index)]", reason: "is not a string"
                )
            }
            return text
        }
    }

    public func optionalStrings(_ key: String) throws -> [String] {
        guard raw[key] != nil, !(raw[key] is NSNull) else {
            consumed.insert(key)
            return []
        }
        return try strings(key)
    }

    public func object(_ key: String) throws -> StrictObject {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard let nested = value as? [String: Any] else { throw fail(key, "is not an object") }
        return StrictObject(path: "\(path).\(key)", raw: nested)
    }

    public func optionalObject(_ key: String) throws -> StrictObject? {
        guard let value = take(key) else { return nil }
        guard let nested = value as? [String: Any] else { throw fail(key, "is not an object") }
        return StrictObject(path: "\(path).\(key)", raw: nested)
    }

    public func objects(_ key: String) throws -> [StrictObject] {
        guard let value = take(key) else { throw fail(key, "is required") }
        guard let array = value as? [Any] else { throw fail(key, "is not an array") }
        return try array.enumerated().map { index, element in
            guard let nested = element as? [String: Any] else {
                throw CorpusDecodingError(
                    path: "\(path).\(key)[\(index)]", reason: "is not an object"
                )
            }
            return StrictObject(path: "\(path).\(key)[\(index)]", raw: nested)
        }
    }

    public func optionalObjects(_ key: String) throws -> [StrictObject] {
        guard raw[key] != nil, !(raw[key] is NSNull) else {
            consumed.insert(key)
            return []
        }
        return try objects(key)
    }

    /// One value out of a closed vocabulary, named by the type it decodes into.
    ///
    /// Written as a lookup over `allCases` rather than through `init(rawValue:)` so the failure
    /// message can list what was permitted — the difference between *"unparseable verdict"* and
    /// *"'irrelevant' is not one of relevant, unrelated, uncertain"*.
    public func enumeration<T: RawRepresentable & CaseIterable>(
        _ key: String,
        _ type: T.Type
    ) throws -> T where T.RawValue == String {
        let raw = try string(key)
        guard let value = T.allCases.first(where: { $0.rawValue == raw }) else {
            throw fail(key, "'\(raw)' is not one of \(T.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return value
    }

    public func optionalEnumeration<T: RawRepresentable & CaseIterable>(
        _ key: String,
        _ type: T.Type
    ) throws -> T? where T.RawValue == String {
        guard let raw = try optionalString(key) else { return nil }
        guard let value = T.allCases.first(where: { $0.rawValue == raw }) else {
            throw fail(key, "'\(raw)' is not one of \(T.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return value
    }

    // MARK: - The audit

    /// Fail on every key nobody read.
    ///
    /// This is the assertion that makes the schema total. Without it the corpus accepts fields
    /// it does not implement, and a case can promise a behaviour nothing exercises.
    public func finish() throws {
        let unread = Set(raw.keys).subtracting(consumed).sorted()
        guard unread.isEmpty else {
            throw CorpusDecodingError(
                path: path,
                reason: "unknown key(s) \(unread.joined(separator: ", ")) — "
                    + "the corpus schema is closed, so a misspelling is a red gate rather than a default"
            )
        }
    }
}
