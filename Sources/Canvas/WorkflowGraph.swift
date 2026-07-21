import Foundation
import SwiftUI

/// One placed instance of a `StudioWidget` on the canvas.
@MainActor
final class WidgetNode: Identifiable, ObservableObject {
    let id: UUID
    @Published var position: CGPoint
    var widget: any StudioWidget

    init(id: UUID = UUID(), position: CGPoint, widget: any StudioWidget) {
        self.id = id
        self.position = position
        self.widget = widget
    }

    var widgetType: any StudioWidget.Type { type(of: widget) }
}

/// A typed connection from one node's output port to another node's input port.
struct WidgetLink: Identifiable, Equatable {
    let id = UUID()
    var fromNode: UUID
    var fromPort: String
    var toNode: UUID
    var toPort: String

    static func == (l: WidgetLink, r: WidgetLink) -> Bool {
        l.fromNode == r.fromNode && l.fromPort == r.fromPort &&
        l.toNode == r.toNode && l.toPort == r.toPort
    }
}

/// The workflow graph: nodes + links. Pure structure/layout — execution state lives in
/// `ExecutionEngine`, kept separate so undo/redo of layout (future work) doesn't entangle with
/// re-running widgets.
@MainActor
final class WorkflowGraph: ObservableObject {
    @Published var nodes: [UUID: WidgetNode] = [:]
    @Published var links: [WidgetLink] = []

    enum GraphError: Error, CustomStringConvertible {
        case noSuchNode
        case inputNotConnected(String)
        case upstreamNotReady(String)

        var description: String {
            switch self {
            case .noSuchNode: return "node not found"
            case .inputNotConnected(let port): return "input '\(port)' is not connected"
            case .upstreamNotReady(let port): return "input '\(port)' isn't ready yet"
            }
        }
    }

    func addNode(_ node: WidgetNode) {
        nodes[node.id] = node
    }

    func removeNode(_ id: UUID) {
        nodes.removeValue(forKey: id)
        links.removeAll { $0.fromNode == id || $0.toNode == id }
    }

    func addLink(_ link: WidgetLink) {
        // A given input port accepts exactly one incoming link.
        links.removeAll { $0.toNode == link.toNode && $0.toPort == link.toPort }
        links.append(link)
    }

    func removeLink(_ id: UUID) {
        links.removeAll { $0.id == id }
    }

    func downstream(of id: UUID) -> [UUID] {
        Array(Set(links.filter { $0.fromNode == id }.map { $0.toNode }))
    }

    /// Kahn's algorithm. Nodes involved in a cycle (shouldn't happen — the UI prevents creating
    /// one) are simply omitted from the order rather than crashing.
    func topologicalOrder() -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        for n in nodes.keys { inDegree[n] = 0 }
        for l in links where nodes[l.toNode] != nil && nodes[l.fromNode] != nil {
            inDegree[l.toNode, default: 0] += 1
        }
        var queue = nodes.keys.filter { inDegree[$0] == 0 }
        var order: [UUID] = []
        while !queue.isEmpty {
            let n = queue.removeFirst()
            order.append(n)
            for d in downstream(of: n) {
                inDegree[d]! -= 1
                if inDegree[d] == 0 { queue.append(d) }
            }
        }
        return order
    }

    /// Collect this node's input `PortValue`s, in the order its widget type declares them,
    /// reading finished upstream outputs from `states`.
    func gatherInputs(for id: UUID, states: [UUID: NodeState]) throws -> [PortValue] {
        guard let node = nodes[id] else { throw GraphError.noSuchNode }
        var result: [PortValue] = []
        for spec in node.widget.dynamicInputPorts {
            guard let link = links.first(where: { $0.toNode == id && $0.toPort == spec.name }) else {
                throw GraphError.inputNotConnected(spec.name)
            }
            guard case .done(let value)? = states[link.fromNode] else {
                throw GraphError.upstreamNotReady(spec.name)
            }
            // A multi-output upstream wraps its results per port; pick the one this link
            // actually comes from. Single-output upstreams pass through unchanged.
            if case .outputs(let byPort) = value {
                guard let portValue = byPort[link.fromPort] else {
                    throw GraphError.upstreamNotReady(spec.name)
                }
                result.append(portValue)
            } else {
                result.append(value)
            }
        }
        return result
    }
}

/// A node's execution status, as tracked by `ExecutionEngine`.
enum NodeState {
    case idle
    case running
    case done(PortValue)
    case failed(String)
}
