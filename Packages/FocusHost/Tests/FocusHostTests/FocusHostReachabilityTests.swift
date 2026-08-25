import Testing

@testable import FocusHost

/// The bundle exists, and that is the point of it.
@Suite("The composition layer is reachable from a test bundle")
struct FocusHostReachabilityTests {
    @Test("a test target can import the composition layer")
    func canImportTheHost() {
        #expect(Bool(true))
    }
}
