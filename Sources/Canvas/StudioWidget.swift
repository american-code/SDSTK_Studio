import Foundation
import SwiftUI

/// One node type in the canvas — a widget in the Orange sense. Conforming types are reference
/// types so the graph can hold a heterogeneous `[any StudioWidget]` and the inspector panel can
/// mutate a node's params in place.
///
/// Pinned to `@MainActor`: SDSTK's `DataFrame`/`Figure` wrap MLX/Metal state that isn't
/// `Sendable`, so widget execution deliberately never crosses an actor boundary in this first
/// pass. Fine for Phase 1's data sizes; a later phase that offloads real heavy compute (e.g.
/// `Neural` training on a big dataset) should convert to Sendable-safe boundary types before
/// hopping off the main actor, not lift this constraint wholesale.
@MainActor
protocol StudioWidget: AnyObject {
    /// Stable string key used in the `.sdstkflow` file and the catalog. Never rename once shipped.
    static var typeID: String { get }
    static var category: WidgetCategory { get }
    static var displayName: String { get }
    /// SF Symbol shown on the palette entry and node face.
    static var symbolName: String { get }
    static var inputPorts: [PortSpec] { get }
    static var outputPorts: [PortSpec] { get }

    /// One-line summary of current params, shown on the node face (e.g. "iris.csv, 150 rows").
    var summary: String { get }

    func encodeParams() throws -> Data
    func applyParams(from data: Data) throws

    func run(inputs: [PortValue]) async throws -> PortValue

    /// The parameter panel shown when this node is selected. `onChange` must be called after
    /// any mutation so the engine re-marks this node (and everything downstream) dirty.
    func makeInspector(onChange: @escaping () -> Void) -> AnyView
}

extension StudioWidget {
    /// Small preview rendered on the node face itself (e.g. a mini chart). Most widgets don't
    /// need one; `Visualize` widgets override this.
    func makePreview(output: PortValue?) -> AnyView { AnyView(EmptyView()) }

    /// Instance-level ports — what the engine, canvas geometry, and link hit-testing actually
    /// consult. Defaults forward to the static per-type declarations, so a widget whose port
    /// topology depends on its params (e.g. `Experts.Coordinator`'s expert count) overrides
    /// these; every fixed-shape widget needs no change. The static declarations remain the
    /// palette's source of truth for what a *type* looks like before placement.
    var dynamicInputPorts: [PortSpec] { Self.inputPorts }
    var dynamicOutputPorts: [PortSpec] { Self.outputPorts }
}

/// A plain-message error a widget's `run` throws for user-facing conditions (missing selection,
/// no file chosen, etc.) — as opposed to a lower-level SDSTK error, which is shown via
/// `String(describing:)` as-is.
enum WidgetError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        if case .message(let m) = self { return m }
        return "Unknown error"
    }
}
