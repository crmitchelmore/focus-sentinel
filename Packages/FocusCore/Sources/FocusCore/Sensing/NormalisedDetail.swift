import Foundation

/// The only thing that may ever be written into `ActivityEvent.detail`.
///
/// ## Raw captured content is not forbidden here — it is unrepresentable
///
/// There is **no `NormalisedDetail(String)`**. The only two ways to make one are a list of
/// tokens from a closed vocabulary and a typed measurement with an integer. A window title, a
/// URL with its path and query, a document name, a file path: none of them can be turned into
/// a value of this type by any route, so none of them can reach the store through this column.
/// The lint that fails on an assignment to `.detail` catches the one route left, which is
/// somebody bypassing this type and writing to the model directly.
///
/// That is why the privacy promise is a property of the code rather than a rule people
/// remember. A hostile corpus of exactly those four things is fed through every producer in
/// the suite and asserted absent from every stored value — but the corpus test is a check on
/// the enforcement, not the enforcement itself.
public struct NormalisedDetail: Sendable, Equatable, Hashable {
    /// Exactly what goes in the column. Tokens are sorted and comma-joined; a measurement is
    /// `kind=value`. Both are deterministic, so two identical observations produce two
    /// identical rows and the debug export is diffable.
    public let storedValue: String

    /// **Private on purpose.** Making this `public` would be the `String` initialiser this
    /// type exists not to have.
    private init(storedValue: String) {
        self.storedValue = storedValue
    }

    /// A set of closed-vocabulary tokens. Duplicates collapse and order is normalised, so
    /// `[.fullScreen, .micRunning]` and `[.micRunning, .fullScreen]` are the same row.
    public static func tokens(_ tokens: [DetailToken]) -> NormalisedDetail {
        let unique = Set(tokens).sorted()
        return NormalisedDetail(storedValue: unique.map(\.rawValue).joined(separator: ","))
    }

    /// One typed measurement.
    ///
    /// An `Int`, deliberately: seconds and counts are what this records, and a `Double`'s
    /// formatting would vary by locale and by rounding in a column that has to compare equal
    /// to itself.
    public static func measurement(_ kind: MeasurementKind, _ value: Int) -> NormalisedDetail {
        NormalisedDetail(storedValue: "\(kind.rawValue)=\(value)")
    }

    /// No detail at all — which is a perfectly good answer and the commonest one.
    public static let empty = NormalisedDetail(storedValue: "")

    public var isEmpty: Bool { storedValue.isEmpty }

    /// What a stored `detail` string means when it is read back.
    public enum Inspection: Sendable, Equatable, Hashable {
        case none
        case tokens([DetailToken])
        case measurement(MeasurementKind, Int)
        /// The column holds something this build cannot interpret. It is shown as nothing and
        /// used for nothing — **inert**, never rendered verbatim, because a row written by a
        /// build that knew a token this one does not is not a licence to print its contents.
        case unreadable
    }

    /// Read a stored value back.
    ///
    /// Unknown tokens are dropped from a list that also contains known ones; a value that
    /// yields nothing recognisable at all reads back `.unreadable`. Either way nothing
    /// uninterpretable reaches a surface.
    public static func inspect(_ stored: String?) -> Inspection {
        guard let stored, !stored.isEmpty else { return .none }

        if let separator = stored.firstIndex(of: "="), stored.firstIndex(of: ",") == nil {
            let kindRaw = String(stored[stored.startIndex..<separator])
            let valueRaw = String(stored[stored.index(after: separator)...])
            guard
                let kind = MeasurementKind.allCases.first(where: { $0.rawValue == kindRaw }),
                let value = Int(valueRaw)
            else {
                return .unreadable
            }
            return .measurement(kind, value)
        }

        let parts = stored.split(separator: ",").map(String.init)
        let known = parts.compactMap { part in
            DetailToken.allCases.first { $0.rawValue == part }
        }
        guard !known.isEmpty else { return .unreadable }
        return .tokens(known.sorted())
    }
}
