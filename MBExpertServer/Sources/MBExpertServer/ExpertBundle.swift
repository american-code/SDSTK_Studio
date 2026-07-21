import Foundation

/// Reads an `.mbexpert` bundle produced by SDSTK Studio (`WorkflowDocument`'s
/// `.mbExpertBundle` export — see `Sources/Persistence/WorkflowDocument.swift` in the main app).
/// This is a standalone, additive tool: rather than depending on the app's own source tree (a
/// bigger, riskier refactor — the app isn't structured as a library today), it re-parses the
/// same on-disk JSON shape directly. `.mbexpert` is a plain directory on disk (not a zip), so no
/// archive library is needed either.
///
/// Supports the full compound topology: N `Experts.CoreMLExpert` nodes, optionally combined by
/// one `Experts.Coordinator` (its strategy and per-slot weights decoded from the same params
/// JSON the app persists). Other node types in the graph (image sources, MemStacker, charts) are
/// ignored — the server's input is the image supplied per call, not the graph's own source node.
enum ExpertBundle {
    // Mirrors of `WorkflowDocumentData`'s JSON shape — only the fields this server needs.
    struct NodeData: Codable {
        var id: UUID
        var typeID: String
        var params: Data
    }
    struct LinkData: Codable {
        var fromNode: UUID
        var fromPort: String
        var toNode: UUID
        var toPort: String
    }
    struct GraphData: Codable {
        var nodes: [NodeData] = []
        var links: [LinkData] = []
    }
    /// Subset of `CoreMLExpertWidget.Params` — the embedded model file itself is found by node
    /// ID via a directory scan, not by resolving the persisted bookmark (bookmarks are tied to
    /// the app process that created them and won't resolve here anyway).
    struct ExpertParams: Codable {
        var expertName: String?
    }
    /// Subset of `CoordinatorWidget.Params`. Strategy raw values match the app's enum.
    struct CoordinatorParams: Codable {
        var strategy: String = "Highest confidence wins"
        var weights: [Double] = []
    }

    enum LoadError: Error, CustomStringConvertible {
        case notFound(String)
        case noExpertNodes
        case multipleCoordinators(Int)
        case noEmbeddedModel(String, UUID)

        var description: String {
            switch self {
            case .notFound(let path): "Bundle not found at \(path)"
            case .noExpertNodes: "Bundle has no Experts.CoreMLExpert nodes"
            case .multipleCoordinators(let n): "Bundle has \(n) Coordinator nodes — at most one is supported"
            case .noEmbeddedModel(let name, let id): "No embedded model file for expert '\(name)' (node \(id)) — was this bundle exported with its model set?"
            }
        }
    }

    struct LoadedExpert {
        let nodeID: UUID
        let expertName: String
        /// Real on-disk URL of the extracted model — a fresh temp copy (Core ML needs a real URL
        /// to compile/load from).
        let modelURL: URL
        /// Weight this expert carries in the coordinator's vote (1.0 when no coordinator, or
        /// when the expert isn't wired into one).
        var weight: Double = 1.0
    }

    struct LoadedGraph {
        var experts: [LoadedExpert]
        /// Combination strategy raw value from the Coordinator node, `nil` when the bundle has
        /// no coordinator (single- or parallel-expert bundles).
        var coordinatorStrategy: String?
        /// A short description of the topology, for the tool descriptor.
        var topologySummary: String {
            if let coordinatorStrategy {
                "\(experts.count) expert(s) combined by a Coordinator (\(coordinatorStrategy))"
            } else if experts.count == 1 {
                "single expert '\(experts[0].expertName)'"
            } else {
                "\(experts.count) independent experts (no coordinator)"
            }
        }
    }

    static func load(bundleURL: URL) throws -> LoadedGraph {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundleURL.path) else { throw LoadError.notFound(bundleURL.path) }

        let graphData = try Data(contentsOf: bundleURL.appendingPathComponent("graph.json"))
        let graph = try JSONDecoder().decode(GraphData.self, from: graphData)

        let expertNodes = graph.nodes.filter { $0.typeID == "Experts.CoreMLExpert" }
        guard !expertNodes.isEmpty else { throw LoadError.noExpertNodes }

        let coordinatorNodes = graph.nodes.filter { $0.typeID == "Experts.Coordinator" }
        guard coordinatorNodes.count <= 1 else { throw LoadError.multipleCoordinators(coordinatorNodes.count) }
        let coordinator = coordinatorNodes.first
        let coordinatorParams = coordinator.flatMap { try? JSONDecoder().decode(CoordinatorParams.self, from: $0.params) }

        let expertsDir = bundleURL.appendingPathComponent("Experts")
        let candidates = (try? fm.contentsOfDirectory(at: expertsDir, includingPropertiesForKeys: nil)) ?? []
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("mbexpert-run-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var experts: [LoadedExpert] = []
        for node in expertNodes {
            let params = (try? JSONDecoder().decode(ExpertParams.self, from: node.params)) ?? ExpertParams()
            let name = params.expertName?.isEmpty == false ? params.expertName! : "expert-\(experts.count + 1)"
            guard let embedded = candidates.first(where: { $0.deletingPathExtension().lastPathComponent == node.id.uuidString }) else {
                throw LoadError.noEmbeddedModel(name, node.id)
            }
            let dest = stagingDir.appendingPathComponent(embedded.lastPathComponent)
            try fm.copyItem(at: embedded, to: dest)

            var expert = LoadedExpert(nodeID: node.id, expertName: name, modelURL: dest)
            // Weight comes from which coordinator slot this expert feeds: port "expertN" →
            // weights[N-1], matching `CoordinatorWidget.weight(at:)`'s index alignment.
            if let coordinator,
               let link = graph.links.first(where: { $0.fromNode == node.id && $0.toNode == coordinator.id }),
               link.toPort.hasPrefix("expert"), let slot = Int(link.toPort.dropFirst("expert".count)),
               let weights = coordinatorParams?.weights, slot - 1 < weights.count {
                expert.weight = weights[slot - 1]
            }
            experts.append(expert)
        }

        return LoadedGraph(experts: experts, coordinatorStrategy: coordinator != nil ? (coordinatorParams?.strategy ?? "Highest confidence wins") : nil)
    }
}
