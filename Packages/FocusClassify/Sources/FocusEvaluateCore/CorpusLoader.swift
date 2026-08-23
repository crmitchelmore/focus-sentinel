import FocusCore
import Foundation

/// One corpus file, loaded and carrying the floor it owes.
public struct CorpusFile: Sendable, Equatable {
    public let name: String
    public let note: String
    public let floor: Int
    public let cases: [CorpusCase]
}

/// The whole golden corpus: the four single-shot files, and the sequence fixtures beside them.
public struct GoldenCorpus: Sendable, Equatable {
    public let files: [CorpusFile]
    /// The replayable event streams beside the single-shot files. F-151's fixtures cannot
    /// express time; these are what does (R-69).
    public let sequences: [SequenceFixture]
    /// Committed files this directory did not hold.
    ///
    /// Recorded rather than thrown, because the corpus was committed **file by file** — the
    /// baseline and rule cases, then the heuristic ones, then the adversarial suite, then the
    /// sequences — and a loader that could not read a partial tree would make the middle of
    /// that impossible to commit. `validateComplete()` is what refuses one, and it is what the
    /// harness and the metric gate call.
    public let missingFiles: [String]
    /// FNV-1a over the concatenated bytes of every corpus file, in sorted relative-path order.
    ///
    /// R-75.5: the evaluation stage recomputes this from the working tree and refuses a report
    /// that does not match, so a report cannot certify a corpus other than the one on disk.
    public let digest: UInt64

    public var cases: [CorpusCase] { files.flatMap(\.cases) }

    /// Single-shot cases plus sequence fixtures. The committed floor of 132 is over **both**,
    /// because a corpus that could meet its total by dropping every sequence would not be able
    /// to express time at all — and time is what F-48 and F-49 are made of.
    public var caseCount: Int { cases.count + sequences.count }

    public var adversarial: [CorpusCase] { cases.filter { !$0.families.isEmpty } }

    public func file(named name: String) -> CorpusFile? {
        files.first { $0.name == name }
    }

    /// Every binding rule R-66 and R-74.3 put on the corpus **as a whole**.
    ///
    /// The per-file half matters as much as the total. The easiest way to make a false-nudge
    /// rate go to zero is to delete the case that produced one; the second easiest is to
    /// replace thirty adversarial cases with thirty baseline ones. A single total would catch
    /// the first and miss the second, which is why every floor is asserted separately.
    public func validateComplete() throws {
        guard missingFiles.isEmpty else {
            throw CorpusDecodingError(
                path: CorpusLoader.goldenCorpusDirectoryName,
                reason: "missing committed corpus file(s): \(missingFiles.joined(separator: ", "))"
            )
        }
        for file in files where file.cases.count < file.floor {
            throw CorpusDecodingError(
                path: file.name,
                reason: "holds \(file.cases.count) cases but its committed floor is \(file.floor)"
            )
        }
        guard sequences.count >= EvaluationPolicy.sequenceFloor else {
            throw CorpusDecodingError(
                path: CorpusLoader.sequencesDirectoryName,
                reason: "holds \(sequences.count) fixtures but the committed floor is "
                    + "\(EvaluationPolicy.sequenceFloor)"
            )
        }
        guard caseCount >= EvaluationPolicy.corpusFloor else {
            throw CorpusDecodingError(
                path: CorpusLoader.goldenCorpusDirectoryName,
                reason: "holds \(caseCount) cases and sequences but the committed floor is "
                    + "\(EvaluationPolicy.corpusFloor)"
            )
        }
    }
}

/// Reads the committed corpus out of a **directory**, never out of a bundle.
///
/// Two readers need the same bytes and they run in different processes: the swift-testing
/// suites, which reach the fixtures through the test bundle's `Resources/GoldenCorpus`, and the
/// `FocusEvaluate` executable, which reaches them through the working tree. Taking a directory
/// URL rather than a `Bundle` is what lets both hand this loader the same content — and it is
/// what makes the corpus digest comparable between the report the harness writes and the digest
/// the gate recomputes from the tree (R-75.5). A `.copy` resource is a byte-for-byte copy of the
/// tree, so the two digests agree by construction rather than by luck.
public enum CorpusLoader {
    public static let goldenCorpusDirectoryName = "GoldenCorpus"
    public static let sequencesDirectoryName = "sequences"

    /// Load and decode strictly.
    ///
    /// - Throws: `CorpusDecodingError` naming the file, the JSON path and the reason. A file
    ///   that is present but malformed is a red gate, never a smaller corpus.
    public static func load(directory: URL) throws -> GoldenCorpus {
        var files: [CorpusFile] = []
        var missing: [String] = []
        var hashed: [(String, Data)] = []

        for budget in EvaluationPolicy.budgets {
            let name = "\(budget.file).json"
            let url = directory.appendingPathComponent(name)
            guard let data = try optionalRead(url) else {
                missing.append(name)
                continue
            }
            hashed.append((name, data))

            let object = try StrictObject.parse(data: data, path: budget.file)
            let declaredName = try object.string("file")
            guard declaredName == budget.file else {
                throw CorpusDecodingError(
                    path: "\(budget.file).file",
                    reason: "declares itself '\(declaredName)' but was loaded as '\(budget.file)'"
                )
            }
            let note = try object.nonEmptyString("note")
            let cases = try object.objects("cases").map {
                try CorpusCase.decode($0, file: budget.file)
            }
            try object.finish()

            files.append(
                CorpusFile(name: budget.file, note: note, floor: budget.floor, cases: cases)
            )
        }

        var sequences: [SequenceFixture] = []
        for (name, data) in try sequenceFiles(in: directory) {
            hashed.append((name, data))
            sequences.append(
                try SequenceFixture.decode(try StrictObject.parse(data: data, path: name))
            )
        }

        let corpus = GoldenCorpus(
            files: files,
            sequences: sequences,
            missingFiles: missing,
            digest: digest(over: hashed)
        )
        try validateIdentity(corpus)
        return corpus
    }

    /// Every sequence fixture, in sorted filename order so two loads agree.
    static func sequenceFiles(in directory: URL) throws -> [(String, Data)] {
        let sequenceDirectory = directory.appendingPathComponent(sequencesDirectoryName)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sequenceDirectory, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var loaded: [(String, Data)] = []
        for url in contents.filter({ $0.pathExtension == "json" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try optionalRead(url) else { continue }
            loaded.append(("\(sequencesDirectoryName)/\(url.lastPathComponent)", data))
        }
        return loaded
    }

    /// The digest, in the one canonical order.
    ///
    /// Sorted by relative path so that two runs on two trees hash the same bytes in the same
    /// order, and the path itself is hashed alongside its bytes so that renaming a file changes
    /// the digest. FNV-1a and never `Hasher`, for the reason P-118 found the hard way:
    /// `Hasher` is seeded per process and returned two different values for identical data.
    static func digest(over entries: [(String, Data)]) -> UInt64 {
        var accumulated = Data()
        for (path, data) in entries.sorted(by: { $0.0 < $1.0 }) {
            accumulated.append(contentsOf: Array(path.utf8))
            accumulated.append(data)
        }
        return FNV1a.hash(accumulated)
    }

    /// Recompute the digest alone, without decoding — what a gate stage does when it wants to
    /// know whether the report in front of it describes the tree in front of it.
    public static func digest(directory: URL) throws -> UInt64 {
        var hashed: [(String, Data)] = []
        for budget in EvaluationPolicy.budgets {
            let name = "\(budget.file).json"
            if let data = try optionalRead(directory.appendingPathComponent(name)) {
                hashed.append((name, data))
            }
        }
        for (name, data) in try sequenceFiles(in: directory) {
            hashed.append((name, data))
        }
        return digest(over: hashed)
    }

    static func optionalRead(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw CorpusDecodingError(
                path: url.lastPathComponent,
                reason: "is unreadable at \(url.path) — \(error)"
            )
        }
    }

    /// The properties every loaded case owes whatever else is present: a stable unique id, and
    /// a family name somebody declared.
    static func validateIdentity(_ corpus: GoldenCorpus) throws {
        var seen: Set<String> = []
        for testCase in corpus.cases {
            guard seen.insert(testCase.id).inserted else {
                throw CorpusDecodingError(
                    path: testCase.file,
                    reason: "\(testCase.id) is used twice — ids are unique and stable forever"
                )
            }
        }
        for sequence in corpus.sequences {
            guard seen.insert(sequence.id).inserted else {
                throw CorpusDecodingError(
                    path: sequencesDirectoryName,
                    reason: "\(sequence.id) is used twice — ids are unique and stable forever"
                )
            }
        }

        // A family name nobody declared is a family that meets no floor and is asserted by
        // nothing, which is worse than an absent one because it looks like coverage.
        let declared = Set(EvaluationPolicy.families.map(\.name))
        for testCase in corpus.cases {
            for family in testCase.families where !declared.contains(family) {
                throw CorpusDecodingError(
                    path: "\(testCase.file).\(testCase.id).families",
                    reason: "'\(family)' is not one of the eleven declared families"
                )
            }
        }
    }
}
