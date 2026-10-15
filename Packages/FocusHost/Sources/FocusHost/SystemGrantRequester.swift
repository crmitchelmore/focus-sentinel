import ApplicationServices
import CoreGraphics
import EventKit
import FocusCore
import Foundation
import os

/// **The one place in this application that may ask macOS for a grant** (focus-exdi.4).
///
/// Every request selector this repository contains lives in this file and nowhere else, and
/// `Config/grant-request-sites.txt` names it so `check-grants.sh` can prove the confinement
/// rather than take it on trust. The rule about *when* an ask is permitted is not here — it is
/// `GrantGate`, in `FocusCore`, so that it can be asserted without a Mac.
///
/// **What did not change.** The zero-grant reading is still the shipped one: with no switch on,
/// `GrantGate` never reaches this object, `requestCount` stays zero, and the capability table
/// reads exactly as it did under PD-1. What changed is that the person now has a way to say yes.
@MainActor
final class SystemGrantRequester: GrantRequesting {
    private(set) var requestCount = 0
    private let logger = Logger(subsystem: "com.chrismitchelmore.FocusSentinel", category: "grants")

    /// The prompting option's key, spelled rather than imported.
    ///
    /// `ApplicationServices` declares `kAXTrustedCheckOptionPrompt` as a global `var`, which
    /// Swift 6 refuses to let any concurrent context read. The value is a constant the system
    /// never writes, so it is written here — and this is the one place in the application that
    /// asks for the prompt at all, which is the fact `Config/grant-request-sites.txt` confines
    /// and `check-grants.sh` proves through `AXIsProcessTrustedWithOptions` beside it.
    private static let promptKey = "AXTrustedCheckOptionPrompt"

    /// **Called when an asynchronous ask is answered** (focus-cal). The calendar's ask is the
    /// one that cannot answer synchronously: EventKit returns the person's decision later, so
    /// the composition root is told then, and re-reads.
    var onGrantAnswered: (@MainActor (GrantOptIn) -> Void)?

    /// Ask the system, and answer with the state the ask left the app in.
    ///
    /// Accessibility and Screen Recording are synchronous reads that may raise the system's own
    /// consent dialog. The calendar's ask is asynchronous: this returns the state as it stands,
    /// and `onGrantAnswered` reports the answer. None is retried: a person who dismissed the
    /// dialog has answered, and asking again on the next launch would be the nagging this app
    /// exists not to do.
    func requestGrant(_ grant: GrantOptIn) -> CapabilityState {
        requestCount += 1
        logger.notice("asking for \(grant.rawValue, privacy: .public), which the person switched on")
        switch grant {
        case .accessibilityWindowContext:
            let options = [Self.promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .available : .denied
        case .screenCapture:
            return CGRequestScreenCaptureAccess() ? .available : .denied
        case .calendarEvents:
            // Full access is the only kind that can read an event's times; write-only access,
            // the narrower grant, cannot see the calendar at all.
            let current = grantState(.calendarEvents)
            guard current == .notRequested else { return current }
            Task { @MainActor [weak self] in
                let store = EKEventStore()
                _ = try? await store.requestFullAccessToEvents()
                self?.onGrantAnswered?(.calendarEvents)
            }
            return current
        }
    }

    /// Read the state without asking for anything: no prompt, no counter.
    func grantState(_ grant: GrantOptIn) -> CapabilityState {
        switch grant {
        case .accessibilityWindowContext:
            return AXIsProcessTrusted() ? .available : .denied
        case .screenCapture:
            return CGPreflightScreenCaptureAccess() ? .available : .denied
        case .calendarEvents:
            // A class method: reading the status opens no event store and prompts for nothing.
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .available
            case .notDetermined: return .notRequested
            case .restricted: return .restricted
            case .denied, .writeOnly: return .denied
            @unknown default: return .unavailable
            }
        }
    }
}
