import FocusClassify
import FocusCore
import Foundation

/// What a cell says the model should do with it.
///
/// **Two values, and the asymmetry between them is the ruling** (R-111). A missed rescue costs
/// a question the app would have asked anyway — today's behaviour, a known-safe posture — so it
/// is bounded by a recall floor that tolerates an imperfect model. A seduction costs the app
/// going quiet about something it was told to hold, which is world knowledge overriding the
/// person's own evidence, and its budget is **zero**. A seduction is a prompt defect and the
/// remedy is the prompt, never the threshold.
public enum ModelExpectation: String, Sendable, CaseIterable, Codable, Hashable {
    /// The deterministic engine declined for want of an instrument, and a model that reads the
    /// words ought to be able to say this is the work.
    case rescue
    /// A genuine, identifiable, lexically-silent distraction against a clear priority. The
    /// deterministic engine declines and the right model answer is a decline too.
    case hold
}

/// One cell of a grid.
public struct ModelCorpusCell: Sendable, Equatable, Hashable {
    public let id: String
    /// The grid coordinate. Two cells with the same pair is a corpus defect.
    public let row: String
    public let column: String
    public let note: String
    /// The BCP-47 tag, for the multilingual grid. `nil` in the 6×6.
    public let language: String?
    public let priority: CorpusPriority
    public let evidence: CorpusEvidence
    public let dwellSeconds: Int
    public let modelExpectation: ModelExpectation

    public var dwell: Duration { .seconds(dwellSeconds) }
}

/// One grid file, with its cells and the axis names they cover.
public struct ModelCorpusFile: Sendable, Equatable {
    public let name: String
    public let note: String
    public let cells: [ModelCorpusCell]

    public var rows: [String] { orderedUnique(cells.map(\.row)) }
    public var columns: [String] { orderedUnique(cells.map(\.column)) }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    /// **Fail-closed completeness.** Every `(row, column)` pair present exactly once.
    ///
    /// A missing cell is not scored as passing; it fails. The cheapest way to make a rescue rate
    /// look good is to drop the cells that did not rescue, and a grid that could be incomplete
    /// would let that happen silently.
    public var missingCoordinates: [String] {
        let present = Set(cells.map { "\($0.row)/\($0.column)" })
        var missing: [String] = []
        for row in rows {
            for column in columns where !present.contains("\(row)/\(column)") {
                missing.append("\(row)/\(column)")
            }
        }
        return missing
    }

    public var completeness: Double {
        let expected = rows.count * columns.count
        guard expected > 0 else { return 0 }
        return Double(cells.count) / Double(expected)
    }

    /// Rows and columns that carry only one kind of expectation.
    ///
    /// **Both axes must move, and that is the ruling rather than a nicety.** A model answering
    /// from the priority alone gets a single-expectation row entirely right for entirely the
    /// wrong reason; a model answering from the subject alone does the same to a column. The
    /// cheapest way to look good is a rescue set that happens to differ from the hold set along
    /// some other axis, and this is what forbids it.
    public var axesWithoutBothExpectations: [String] {
        var offenders: [String] = []
        for row in rows {
            let kinds = Set(cells.filter { $0.row == row }.map(\.modelExpectation))
            if kinds.count < ModelExpectation.allCases.count { offenders.append("row \(row)") }
        }
        for column in columns {
            let kinds = Set(cells.filter { $0.column == column }.map(\.modelExpectation))
            if kinds.count < ModelExpectation.allCases.count {
                offenders.append("column \(column)")
            }
        }
        return offenders
    }
}

/// Both grids, loaded.
public struct ModelCorpus: Sendable, Equatable {
    public let files: [ModelCorpusFile]
    /// FNV-1a over the two files, path-prefixed, in sorted filename order.
    ///
    /// **Its own digest, deliberately separate from lane 1's.** `build-gate.sh`'s
    /// `corpus_entries` is an explicit allow-list of the deterministic corpus files, and
    /// `CorpusLoader.digest(directory:)` reads the same list. Adding `Model/` therefore moves
    /// **nothing** in lane 1 — which is load-bearing rather than incidental, and the trap it
    /// avoids is a builder "generalising" `corpus_entries` to a tree walk and breaking every
    /// committed baseline at once.
    public let digest: UInt64

    public var cells: [ModelCorpusCell] { files.flatMap(\.cells) }
    public var cellCount: Int { cells.count }
    public var rescueCount: Int { cells.filter { $0.modelExpectation == .rescue }.count }
    public var holdCount: Int { cells.filter { $0.modelExpectation == .hold }.count }

    public var digestString: String { String(format: "0x%016lx", digest) }
}

public enum ModelCorpusLoader {
    public static let directoryName = "Model"
    public static let fileNames = ["grid", "multilingual"]

    public static func load(goldenCorpusDirectory: URL) throws -> ModelCorpus {
        let directory = goldenCorpusDirectory.appendingPathComponent(directoryName)
        var files: [ModelCorpusFile] = []
        var hashed: [(String, Data)] = []
        var seen: Set<String> = []

        for name in fileNames {
            let url = directory.appendingPathComponent("\(name).json")
            guard let data = try CorpusLoader.optionalRead(url) else {
                throw CorpusDecodingError(
                    path: "\(directoryName)/\(name).json",
                    reason: "is missing — the model corpus is fail-closed, never a smaller grid"
                )
            }
            hashed.append(("\(directoryName)/\(name).json", data))

            let object = try StrictObject.parse(data: data, path: name)
            let declared = try object.string("file")
            guard declared == name else {
                throw CorpusDecodingError(
                    path: "\(name).file",
                    reason: "declares itself '\(declared)' but was loaded as '\(name)'"
                )
            }
            let note = try object.nonEmptyString("note")
            let cells = try object.objects("cells").map { try decode($0, file: name) }
            try object.finish()

            for cell in cells {
                guard seen.insert(cell.id).inserted else {
                    throw CorpusDecodingError(
                        path: name,
                        reason: "\(cell.id) is used twice — ids are unique and stable forever"
                    )
                }
            }
            files.append(ModelCorpusFile(name: name, note: note, cells: cells))
        }

        return ModelCorpus(files: files, digest: CorpusLoader.digest(over: hashed))
    }

    static func decode(_ object: StrictObject, file: String) throws -> ModelCorpusCell {
        let id = try object.nonEmptyString("id")
        let row = try object.nonEmptyString("row")
        let column = try object.nonEmptyString("column")
        let note = try object.nonEmptyString("note")
        let language = try object.optionalString("language")
        let priority = try object.object("priority")
        let intent = try priority.string("intent")
        let revision = try priority.int("revision")
        try priority.finish()
        let evidence = try object.object("evidence")
        let bundleIdentifier = try evidence.optionalString("bundleID")
        try evidence.finish()
        let dwellSeconds = try object.int("dwellSeconds")
        let rawExpectation = try object.nonEmptyString("modelExpectation")
        guard let expectation = ModelExpectation(rawValue: rawExpectation) else {
            throw CorpusDecodingError(
                path: "\(file).\(id).modelExpectation",
                reason: "'\(rawExpectation)' is neither "
                    + ModelExpectation.allCases.map(\.rawValue).joined(separator: " nor ")
            )
        }
        try object.finish()

        return ModelCorpusCell(
            id: id,
            row: row,
            column: column,
            note: note,
            language: language,
            priority: CorpusPriority(intent: intent, revision: revision),
            evidence: CorpusEvidence(
                bundleIdentifier: bundleIdentifier, origin: nil, titleTokens: []
            ),
            dwellSeconds: dwellSeconds,
            modelExpectation: expectation
        )
    }
}
