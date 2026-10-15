import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **Context that arrives by URL lands on the desk only through the sheet** (F-142).
///
/// Driven through the real `PriorityHost` over a real in-memory container, because the claims
/// are about what the host stores after a person presses Replace or Add, and what it refuses to
/// show when there is nothing to add to.
@Suite("Handoff context, at the host", .serialized)
@MainActor
struct HandoffContextHostTests {
    struct Rig {
        let container: ModelContainer
        let host: PriorityHost
    }

    static func rig() throws -> Rig {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        return Rig(
            container: container,
            host: PriorityHost(
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
        )
    }

    private static func pairs(_ host: PriorityHost) -> [String] {
        (host.state.priority?.contextItems ?? []).map { "\($0.kind.rawValue):\($0.value)" }.sorted()
    }

    @Test("a start handoff attaches its context to the new priority, and only on Replace")
    func startAttachesContext() throws {
        let rig = try Self.rig()
        let host = rig.host
        let url = try #require(URL(string:
            "focus://start?task=Prep%20the%20Sodexo%20review"
                + "&context=domain:dev.azure.com&context=keyword:Sodexo"
        ))

        host.receive(url)
        #expect(host.state.priority == nil, "receiving changed the store")
        let request = try #require(host.state.pendingHandoff)

        host.acceptHandoff(request)
        #expect(host.state.priority?.intent == "Prep the Sodexo review")
        #expect(Self.pairs(host) == ["domain:https://dev.azure.com", "keyword:sodexo"])
        #expect(host.state.pendingHandoff == nil)
    }

    @Test("a context handoff with no current priority is never shown")
    func contextWithoutPriorityIsDropped() throws {
        let rig = try Self.rig()
        let host = rig.host

        host.receive(try #require(URL(string: "focus://context?add=keyword:sodexo")))
        #expect(host.state.pendingHandoff == nil)
        #expect(host.state.priority == nil)
    }

    @Test("a context handoff adds to the current priority, skipping what it already holds")
    func contextAddsToCurrent() throws {
        let rig = try Self.rig()
        let host = rig.host
        host.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: nil)
        let id = try #require(host.state.priority?.id)
        host.addContext(taskID: id, item: try #require(ContextItemDraft.keyword("acme")))

        host.receive(try #require(URL(string:
            "focus://context?add=keyword:Acme&add=domain:https%3A%2F%2Fdocs.example.com%2Fq3"
        )))
        let request = try #require(host.state.pendingHandoff)
        #expect(Self.pairs(host) == ["keyword:acme"], "receiving changed the store")

        host.acceptHandoff(request)
        #expect(host.state.priority?.id == id, "a context handoff replaced the priority")
        #expect(Self.pairs(host) == ["domain:https://docs.example.com", "keyword:acme"])
    }

    @Test("cancelling a context handoff changes nothing")
    func cancelChangesNothing() throws {
        let rig = try Self.rig()
        let host = rig.host
        host.setPriority(intent: "Write the Q3 proposal for Acme", doneWhen: nil)

        host.receive(try #require(URL(string: "focus://context?add=keyword:acme")))
        #expect(host.state.pendingHandoff != nil)
        host.cancelHandoff()
        #expect(host.state.pendingHandoff == nil)
        #expect(Self.pairs(host).isEmpty)
    }
}
