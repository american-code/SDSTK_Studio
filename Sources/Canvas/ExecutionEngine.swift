import Foundation

/// Per-node progress reporting: the engine sets this before each widget run, and
/// widgets may call it from their run(inputs:) implementation (which runs on @MainActor).
/// All access is on the main actor so the unsafely-nonisolated static is safe in practice.
enum EngineLocals {
    nonisolated(unsafe) static var reportProgress: ((Double) -> Void)?
}

/// Drives live dataflow: a change to any node's params (or the links around it) marks that node
/// and everything reachable downstream dirty, then re-runs dirty nodes in topological order.
/// Memoization is implicit — a node not marked dirty keeps its last `.done` state and is skipped.
@MainActor
final class ExecutionEngine: ObservableObject {
    @Published private(set) var states: [UUID: NodeState] = [:]
    /// Fractional progress (0…1) for nodes currently in .running state. Cleared on completion.
    @Published private(set) var progress: [UUID: Double] = [:]
    let graph: WorkflowGraph
    private var dirty: Set<UUID> = []
    private var runID = 0
    private var currentTask: Task<Void, Never>?

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
        progress.removeValue(forKey: id)
        dirty.remove(id)
    }

    private func scheduleRun() {
        runID += 1
        let thisRun = runID
        currentTask?.cancel()
        currentTask = Task { [weak self] in
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
        progress[id] = 0
        do {
            let inputs = try graph.gatherInputs(for: id, states: states)
            EngineLocals.reportProgress = { [weak self] fraction in
                self?.progress[id] = max(0, min(1, fraction))
            }
            defer { EngineLocals.reportProgress = nil }
            let output = try await node.widget.run(inputs: inputs)
            states[id] = .done(output)
        } catch is CancellationError {
            states[id] = .idle
        } catch {
            states[id] = .failed("\(error)")
        }
        progress.removeValue(forKey: id)
        dirty.remove(id)
    }
}
