import Foundation

/// What one element of the frontmost window is, in the only terms the search cares about.
///
/// The host maps the platform's roles onto these four, so this file — and `FocusCore` — names no
/// Accessibility symbol (`check-boundaries.sh`).
public enum SelectedItemNodeKind: Sendable, Equatable {
    /// A list, table or outline: something that can report which of its rows is selected.
    case collection
    /// A heading.
    case heading
    /// The main region of a document — where a web application draws the open item.
    case mainRegion
    /// Anything else. Walked through, never read.
    case other
}

/// One element of the frontmost window, read lazily: each property is a message to the other
/// application, so the search asks for a property only when its answer can change the outcome.
public protocol SelectedItemNode {
    var kind: SelectedItemNodeKind { get }
    var children: [Self] { get }
    /// The selected rows of a `.collection`; empty for every other kind.
    var selectedRows: [Self] { get }
    /// The element's own text: its title, its value or its description, whichever it has.
    var text: String? { get }
}

/// **Find the selected item inside a window whose title names nothing** (issue #26).
///
/// Measured on the owner's Mac on 15 October 2026: native sidebars (Mail, Finder, Outlook,
/// Pasta, Just Speak to It) report a selected row; the GitHub Copilot app's sidebar is a web
/// outline that marks no row selected, and names the open session in the first heading of its
/// main region ("Session: …"). So the search takes a selected row first and the main region's
/// first heading, in document order, second.
///
/// **Bounded twice.** Breadth-first to `maximumDepth`, at most `maximumElements` elements, and a
/// `shouldStop` the reader ties to a monotonic deadline: one application's full tree took ten
/// seconds to walk, and this runs on the main actor every judgement.
public enum SelectedItemSearch {
    /// The most elements one search reads.
    public static let maximumElements = 400
    /// How deep below the window the search goes. The Copilot app's main heading sits at eight.
    public static let maximumDepth = 14
    /// How many elements inside one selected row are searched for its text.
    public static let maximumRowElements = 16

    /// What one search came back with.
    public enum Outcome: Equatable, Sendable {
        /// The item the window names.
        case found(SelectedItem)
        /// The whole budget-sized tree was read and named nothing.
        case nothing
        /// The search stopped at its budget before it could tell. The reader treats this as a
        /// read that failed, not as an answer — so a flaky read keeps the last item for a moment
        /// rather than restarting the dwell clock.
        case exhausted
    }

    public static func search<Node: SelectedItemNode>(
        from window: Node,
        applicationName: String?,
        bundleIdentifier: String,
        shouldStop: () -> Bool
    ) -> Outcome {
        func reduce(_ text: String?) -> SelectedItem? {
            SelectedItem.normalise(
                elementText: text,
                applicationName: applicationName,
                bundleIdentifier: bundleIdentifier
            )
        }

        // Each element carries its path of child indices, so the heading kept is the first in
        // document order — what a reader sees first — even though the walk is breadth-first.
        var queue: [(node: Node, path: [Int], inMain: Bool)] = [(window, [], false)]
        var next = 0
        var heading: (item: SelectedItem, path: [Int])?
        var visited = 0

        while next < queue.count {
            if visited >= maximumElements || shouldStop() {
                return heading.map { .found($0.item) } ?? .exhausted
            }
            let (node, path, inMain) = queue[next]
            next += 1
            visited += 1

            var childrenInMain = inMain
            switch node.kind {
            case .collection:
                if let row = node.selectedRows.first, let item = rowItem(row, reduce: reduce) {
                    return .found(item)
                }
            case .heading:
                if inMain, heading.map({ path.lexicographicallyPrecedes($0.path) }) ?? true,
                   let item = reduce(node.text) {
                    heading = (item, path)
                }
            case .mainRegion:
                childrenInMain = true
            case .other:
                break
            }
            if path.count < maximumDepth {
                for (index, child) in node.children.enumerated() {
                    queue.append((child, path + [index], childrenInMain))
                }
            }
        }
        return heading.map { .found($0.item) } ?? .nothing
    }

    /// The first nameable text in a selected row: the row's own, else its cells' and their text.
    private static func rowItem<Node: SelectedItemNode>(
        _ row: Node,
        reduce: (String?) -> SelectedItem?
    ) -> SelectedItem? {
        var queue = [row]
        var next = 0
        while next < queue.count, next < maximumRowElements {
            let node = queue[next]
            next += 1
            if let item = reduce(node.text) { return item }
            queue.append(contentsOf: node.children)
        }
        return nil
    }
}
