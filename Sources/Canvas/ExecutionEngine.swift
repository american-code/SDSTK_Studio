import Foundation

/// Drives live dataflow: a change to any node's params (or the links around it) marks that node
/// and everything reachable downstream dirty, then re-runs dirty nodes in topological order.
/// Memoization is implicit — a node not marked dirty keeps its last `.done` state and is skipped.
@MainActor
final class ExecutionEngine: ObservableObject {
    @Published private(set) var states: [UUID: NodeState] = [:]
    let graph: WorkflowGraph
    private var dirty: Set<UUID> = []
    private var runID = 0

    init(graph: WorkflowGraph) {
        self.graph = graph
    }

    func state(for id: UUID) -> NodeState {
        states[id] ?? .idle
    }

    /// Call after adding/removing a node or link, or editing a node's params.
    func markDirty(_ id: UUID) {
        var toVisit = [id]
        var seen = Set<UUID>()
        while let n = toVisit.popLast() {
            guard seen.insert(n).inserted else { continue }
            dirty.insert(n)
            states[n] = .idle
            toVisit.append(contentsOf: graph.downstream(of: n))
        }
        scheduleRun()
    }

    func removeNode(_ id: UUID) {
        states.removeValue(forKey: id)
        dirty.remove(id)
    }

    private func scheduleRun() {
        runID += 1
        let thisRun = runID
        Task { [weak self] in
            await self?.runDirty(generation: thisRun)
        }
    }

    /// Runs every currently-dirty node in topological order. If a newer run was scheduled while
    /// this one was mid-flight (params changed again before the previous pass finished), bail —
    /// the newer `scheduleRun` will pick up the latest dirty set instead of racing it.
    private func runDirty(generation: Int) async {
        for id in graph.topologicalOrder() {
            guard generation == runID else { return }
            guard dirty.contains(id) else { continue }
            await run(id)
        }
    }

    private func run(_ id: UUID) async {
        guard let node = graph.nodes[id] else { dirty.remove(id); return }
        states[id] = .running
        do {
            let inputs = try graph.gatherInputs(for: id, states: states)
            let output = try await node.widget.run(inputs: inputs)
            states[id] = .done(output)
        } catch {
            states[id] = .failed("\(error)")
        }
        dirty.remove(id)
    }
}
