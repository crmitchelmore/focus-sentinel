import FocusCore
import Foundation

/// **R-75's five binding checks, as a rule rather than a habit.**
///
/// R-67 has the harness write into a staging directory the gate copies out of, because
/// `xcodebuild` does not carry an environment value into a SwiftPM test target's process — the
/// same constraint `build-gate.sh` already documents for snapshots. That mechanism is right and
/// the staleness hazard was missed: the staging path is shared between runs, and a report left
/// behind by an earlier green tree would be parsed as this run's evidence. **A gate whose
/// central number can be satisfied by a file nobody wrote today is not a gate.**
///
/// So a report is believed only when all five hold, and they are evaluated **before** any
/// metric: a stale or foreign report is not a failing number, it is no evidence at all, and
/// reporting it as a metric failure would send a reader looking in the wrong place.
///
/// Stated here in Swift so `EvaluationGateTests` asserts exactly the rule the gate stage
/// applies, rather than two descriptions of it that can drift.
public enum ReportBinding {
    public enum Check: String, Sendable, CaseIterable {
        /// B1 — the report names this run's token (R-75.2). The assertion that survives even if
        /// the pre-`unit` deletion silently no-ops: belt as well as braces, because the failure
        /// mode is *accepting stale evidence*, which is invisible when it happens.
        case runID
        /// B2 — the report is newer than the marker the gate touched immediately before `unit`
        /// (R-75.3).
        case freshness
        /// B3 — the report was produced by this engine: its stamp and policy digest equal the
        /// committed literals the unit lane asserts of the test process and both self-checks
        /// assert of the running application (R-75.4).
        case engine
        /// B4 — the report describes the corpus on disk (R-75.5).
        case corpus
        /// B5 — the bytes that were parsed are the per-run copy, not the shared staging file.
        case provenance
    }

    public struct Result: Sendable, Equatable {
        public let check: String
        public let passed: Bool
        public let detail: String
    }

    /// Everything the gate knows about the file it is holding.
    public struct Evidence: Sendable {
        public let runID: String
        public let expectedRunID: String
        public let modifiedAt: Date?
        public let markerAt: Date?
        public let stamp: String
        public let expectedStamp: String
        public let policyDigest: String
        public let expectedPolicyDigest: String
        public let corpusDigest: String
        public let expectedCorpusDigest: String
        public let parsedPath: String
        public let stagingPath: String

        public init(
            runID: String,
            expectedRunID: String,
            modifiedAt: Date?,
            markerAt: Date?,
            stamp: String,
            expectedStamp: String,
            policyDigest: String,
            expectedPolicyDigest: String,
            corpusDigest: String,
            expectedCorpusDigest: String,
            parsedPath: String,
            stagingPath: String
        ) {
            self.runID = runID
            self.expectedRunID = expectedRunID
            self.modifiedAt = modifiedAt
            self.markerAt = markerAt
            self.stamp = stamp
            self.expectedStamp = expectedStamp
            self.policyDigest = policyDigest
            self.expectedPolicyDigest = expectedPolicyDigest
            self.corpusDigest = corpusDigest
            self.expectedCorpusDigest = expectedCorpusDigest
            self.parsedPath = parsedPath
            self.stagingPath = stagingPath
        }
    }

    public static func evaluate(_ evidence: Evidence) -> [Result] {
        var results: [Result] = []

        results.append(
            Result(
                check: Check.runID.rawValue,
                passed: evidence.runID == evidence.expectedRunID,
                detail: "report '\(evidence.runID)' vs run '\(evidence.expectedRunID)'"
            )
        )

        let fresh: Bool
        if let modified = evidence.modifiedAt, let marker = evidence.markerAt {
            fresh = modified > marker
        } else {
            // No marker and no mtime is not a pass. A check that cannot be performed has not
            // been performed, and R-75 exists because an unperformed check reads like a green
            // one.
            fresh = false
        }
        results.append(
            Result(
                check: Check.freshness.rawValue,
                passed: fresh,
                detail: "modified \(evidence.modifiedAt.map(String.init(describing:)) ?? "unknown")"
                    + " vs marker \(evidence.markerAt.map(String.init(describing:)) ?? "unknown")"
            )
        )

        results.append(
            Result(
                check: Check.engine.rawValue,
                passed: evidence.stamp == evidence.expectedStamp
                    && evidence.policyDigest == evidence.expectedPolicyDigest,
                detail: "\(evidence.stamp)/\(evidence.policyDigest)"
                    + " vs \(evidence.expectedStamp)/\(evidence.expectedPolicyDigest)"
            )
        )

        results.append(
            Result(
                check: Check.corpus.rawValue,
                passed: evidence.corpusDigest == evidence.expectedCorpusDigest,
                detail: "\(evidence.corpusDigest) vs \(evidence.expectedCorpusDigest)"
            )
        )

        results.append(
            Result(
                check: Check.provenance.rawValue,
                passed: !evidence.parsedPath.isEmpty
                    && evidence.parsedPath != evidence.stagingPath,
                detail: "parsed \(evidence.parsedPath), staging \(evidence.stagingPath)"
            )
        )

        return results
    }

    public static func passes(_ evidence: Evidence) -> Bool {
        evaluate(evidence).allSatisfy(\.passed)
    }
}
