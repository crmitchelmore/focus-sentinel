import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Standing priorities arrive through the sheet and are picked like history** (F-142, F-15).
///
/// Driven through the real `PriorityHost` over an in-memory container: receiving shows, Set
/// stores, the current priority is never moved by the set, and picking a slot is "work on this
/// again" with its context pack.
@Suite("Standing priorities, at the host", .serialized)
@MainActor
struct StandingPrioritiesHostTests {
    /// Held for the suite's lifetime: a host outliving its container traps on the first fetch.
    static var containers: [ModelContainer] = []

    static func host() throws -> PriorityHost {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        containers.append(container)
        return PriorityHost(
            context: container.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            environment: PriorityHost.Environment(
                status: .paused,
                storeOpened: true,
                isObservingActivity: false
            )
        )
    }

    static let url = URL(string:
        "focus://priorities?primary=Qualify%20Boulanger&primaryDoneWhen=bid%20decision%20made"
            + "&primaryContext=keyword:Boulanger&primaryContext=domain:dev.azure.com"
            + "&secondary1=Fellowship%20dogfooding&secondary2=Links%20pages%20loop"
    )!

    @Test("receiving shows the set and stores nothing, even with no current priority")
    func receiveShowsOnly() throws {
        let host = try Self.host()
        host.receive(Self.url)
        let request = try #require(host.state.pendingHandoff)
        #expect(request.verb == .priorities)
        #expect(request.standing.map(\.task) == [
            "Qualify Boulanger", "Fellowship dogfooding", "Links pages loop"
        ])
        #expect(host.state.standing.isEmpty, "receiving changed the store")
    }

    @Test("Set stores the shortlist in order without moving the current priority")
    func setStoresWithoutActivating() throws {
        let host = try Self.host()
        host.setPriority(intent: "Prep the Sodexo review", doneWhen: nil)
        let current = try #require(host.state.priority?.id)

        host.receive(Self.url)
        host.acceptHandoff(try #require(host.state.pendingHandoff))

        #expect(host.state.priority?.id == current, "setting priorities moved the pointer")
        #expect(host.state.standing.map(\.slot) == [0, 1, 2])
        #expect(host.state.standing.map(\.row.intent) == [
            "Qualify Boulanger", "Fellowship dogfooding", "Links pages loop"
        ])
        #expect(host.state.standing.first?.row.doneWhen == "bid decision made")
        #expect(host.state.standing.first?.row.contextItemCount == 2)
        #expect(host.state.pendingHandoff == nil)
    }

    @Test("sending the same set again reuses the tasks and does not double their context")
    func resendIsIdempotent() throws {
        let host = try Self.host()
        host.receive(Self.url)
        host.acceptHandoff(try #require(host.state.pendingHandoff))
        let first = host.state.standing.map(\.id)

        host.receive(Self.url)
        host.acceptHandoff(try #require(host.state.pendingHandoff))
        #expect(host.state.standing.map(\.id) == first)
        #expect(host.state.standing.first?.row.contextItemCount == 2)
    }

    @Test("picking a slot makes it current, with its context")
    func pickActivates() throws {
        let host = try Self.host()
        host.receive(Self.url)
        host.acceptHandoff(try #require(host.state.pendingHandoff))
        let main = try #require(host.state.standing.first)

        host.activate(taskID: main.id)
        #expect(host.state.priority?.id == main.id)
        #expect(host.state.priority?.contextItems.count == 2)
        #expect(host.state.standing.first?.row.isActive == true)
    }

    @Test("cancelling changes nothing")
    func cancelChangesNothing() throws {
        let host = try Self.host()
        host.receive(Self.url)
        host.cancelHandoff()
        #expect(host.state.pendingHandoff == nil)
        #expect(host.state.standing.isEmpty)
    }
}
