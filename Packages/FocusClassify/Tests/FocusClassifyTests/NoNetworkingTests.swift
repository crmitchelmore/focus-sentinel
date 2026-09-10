import Foundation
import MachO
import Testing

@testable import FocusClassify

/// The in-process half of the zero-networking guarantee (standing condition 7, F-112).
///
/// The gate proves this statically as well — `scripts/check-boundaries.sh` runs a source
/// lint, a dependency-graph assertion over `swift package describe --type json`, and an
/// `nm -u` scan of the built object. Duplicating the guarantee here is deliberate: this
/// half travels with the package, so it fires in the inner loop too, the moment someone
/// adds the import rather than the moment someone runs the gate.
@Suite("FocusClassify has no path to the network")
struct NoNetworkingTests {
    /// Modules that can move bytes off this machine, plus the Foundation networking types
    /// that are the usual accidental route in.
    private static let forbiddenSourcePatterns = [
        "import Network",
        "import CFNetwork",
        "import NetworkExtension",
        "URLSession",
        "URLRequest",
        "URLConnection",
        "NSURLSession",
        "CFStream",
        "NWConnection",
        "NWBrowser",
        "NWListener",
        "Socket("
    ]

    /// Dylibs whose presence in a load command would mean this code can open a socket.
    private static let forbiddenLibraryFragments = [
        "CFNetwork",
        "/Network.framework",
        "libnetwork",
        "NetworkExtension"
    ]

    /// `Sources/FocusClassify`, derived from this test file's own compile-time path.
    ///
    /// `#filePath` is `.../Packages/FocusClassify/Tests/FocusClassifyTests/NoNetworkingTests.swift`,
    /// so three parent directories up is the package root. This is what makes the
    /// assertion non-vacuous in both lanes: it reads the real sources rather than hoping a
    /// symbol table tells it something.
    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusClassifyTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FocusClassify (package root)
            .appending(path: "Sources/FocusClassify")
    }

    @Test("no source file in FocusClassify names a networking API")
    func sourcesNameNoNetworkingAPI() throws {
        let directory = sourcesDirectory
        #expect(
            FileManager.default.fileExists(atPath: directory.path),
            "expected FocusClassify sources at \(directory.path)"
        )

        // **Recursive from e04.** The engine's sources live in `Normalisation/`, `Heuristic/`,
        // `Snapshot/`, `Cascade/`, `Time/` and `Explanation/`, and a non-recursive listing
        // would have quietly stopped covering every one of them the moment the first
        // subdirectory appeared — a check that keeps passing while it stops looking is worse
        // than one that fails. `check-boundaries.sh` already greps this tree recursively; this
        // is the in-package half catching up with it.
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .map { directory.appending(path: $0) }
        #expect(!files.isEmpty, "found no Swift sources to scan — the check would be vacuous")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                // Skip prose: this file's own doc comments name the forbidden APIs.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }

                for pattern in Self.forbiddenSourcePatterns where line.contains(pattern) {
                    Issue.record(
                        "\(file.lastPathComponent):\(offset + 1) names '\(pattern)' — FocusClassify may never reach the network"
                    )
                }
            }
        }
    }

    @Test("the package manifest declares no remote dependency")
    func manifestDeclaresNoRemoteDependency() throws {
        let manifest = sourcesDirectory
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()  // package root
            .appending(path: "Package.swift")
        let text = try String(contentsOf: manifest, encoding: .utf8)

        // A remote dependency is written `.package(url:` or `.package(id:`. Only local
        // `.package(path:` entries are permitted, and only to siblings in this repository.
        #expect(!text.contains(".package(url:"))
        #expect(!text.contains(".package(id:"))
        #expect(text.contains(".package(path: \"../FocusCore\")"))
        #expect(text.contains(".package(path: \"../FocusRules\")"))
    }

    @Test("no loaded image named FocusClassify links a networking library")
    func loadedImagesLinkNoNetworkingLibrary() {
        for index in 0..<_dyld_image_count() {
            guard let namePointer = _dyld_get_image_name(index) else { continue }
            let imagePath = String(cString: namePointer)
            guard imagePath.contains("FocusClassify") else { continue }
            guard let header = _dyld_get_image_header(index) else { continue }

            var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<Int(header.pointee.ncmds) {
                let command = cursor.assumingMemoryBound(to: load_command.self)
                let kind = command.pointee.cmd
                if kind == LC_LOAD_DYLIB || kind == LC_LOAD_WEAK_DYLIB || kind == LC_REEXPORT_DYLIB {
                    let dylib = cursor.assumingMemoryBound(to: dylib_command.self)
                    let offset = Int(dylib.pointee.dylib.name.offset)
                    let linked = String(
                        cString: cursor.advanced(by: offset).assumingMemoryBound(to: CChar.self)
                    )
                    for fragment in Self.forbiddenLibraryFragments where linked.contains(fragment) {
                        Issue.record("\(imagePath) links \(linked) (matched '\(fragment)')")
                    }
                }
                cursor = cursor.advanced(by: Int(command.pointee.cmdsize))
            }
        }
    }
}
