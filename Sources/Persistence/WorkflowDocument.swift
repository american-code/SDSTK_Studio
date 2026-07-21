import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sdstkFlow = UTType(exportedAs: "org.sdstk.studio.sdstkflow")
    /// A `.sdstkflow` graph plus embedded copies of every `Experts.CoreMLExpert` model it
    /// references — a self-contained, portable package (directory bundle, the same mechanism
    /// `.rtfd`/`.pages` use) instead of a bookmark pointing at wherever the model file happened
    /// to live when the graph was built. Not a new binary model format — each embedded model
    /// stays a plain `.mlmodel`/`.mlpackage`; only the *bundle* is new.
    static let mbExpertBundle = UTType(exportedAs: "org.sdstk.studio.mbexpert", conformingTo: .package)
}

/// The live document: a `WorkflowGraph` (structure/layout) plus the `ExecutionEngine` that runs
/// it. `ReferenceFileDocument`'s requirements are nonisolated + `Sendable`-constrained (SwiftUI
/// needs to hand documents across its own internal queues), but `WorkflowGraph`/`ExecutionEngine`
/// are deliberately `@MainActor` (they hold non-Sendable `DataFrame`/`Figure` state — see
/// `StudioWidget.swift`). `@unchecked Sendable` bridges that gap, but a bare
/// `MainActor.assumeIsolated` is NOT enough: the system's document I/O machinery calls these
/// nonisolated requirements from a background thread in practice (confirmed by a real
/// `EXC_BREAKPOINT` crash — `assumeIsolated` traps the instant that assumption is false), so
/// every call site below is guarded with `Thread.isMainThread` and hops via `DispatchQueue.main
/// .sync` when it's wrong, instead of just asserting it was already there. This can't be
/// factored into one shared generic helper — passing `T` through a generic `rethrows` wrapper
/// makes the compiler demand `T: Sendable` for `assumeIsolated`, even though direct concrete
/// calls (as below) don't require it; confirmed with a minimal repro, not assumed.
final class WorkflowDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.sdstkFlow, .mbExpertBundle] }
    static var writableContentTypes: [UTType] { [.sdstkFlow, .mbExpertBundle] }

    let graph: WorkflowGraph
    let engine: ExecutionEngine

    init() {
        let (graph, engine): (WorkflowGraph, ExecutionEngine)
        if Thread.isMainThread {
            (graph, engine) = MainActor.assumeIsolated {
                let graph = WorkflowGraph()
                return (graph, ExecutionEngine(graph: graph))
            }
        } else {
            (graph, engine) = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let graph = WorkflowGraph()
                    return (graph, ExecutionEngine(graph: graph))
                }
            }
        }
        self.graph = graph
        self.engine = engine
    }

    init(configuration: ReadConfiguration) throws {
        let (graph, engine) = try Self.load(from: configuration.file)
        self.graph = graph
        self.engine = engine
    }

    /// Builds a graph+engine from a `.sdstkflow` (flat file) or `.mbexpert` (bundle)
    /// `FileWrapper`. Factored out of `init(configuration:)` so it's callable — and testable —
    /// without SwiftUI's own `ReadConfiguration`, which has no accessible public initializer.
    ///
    /// Deliberately NOT `@MainActor` at the signature level, even though it ends by building a
    /// `@MainActor` graph: `FileWrapper` isn't `Sendable`, so every read of `file` has to happen
    /// in this nonisolated body *before* entering `MainActor.assumeIsolated` — capturing `file`
    /// itself into the isolated closure (rather than the plain `Data`/`Bool` extracted from it)
    /// is exactly what the compiler's data-race checker correctly rejects.
    static func load(from file: FileWrapper) throws -> (WorkflowGraph, ExecutionEngine) {
        let saved: WorkflowDocumentData
        var embeddedModels: [UUID: URL] = [:]

        if file.isDirectory {
            guard let graphData = file.fileWrappers?["graph.json"]?.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            saved = try JSONDecoder().decode(WorkflowDocumentData.self, from: graphData)
            embeddedModels = extractEmbeddedModels(from: file)
        } else {
            guard let data = file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            saved = try JSONDecoder().decode(WorkflowDocumentData.self, from: data)
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                buildGraph(from: saved, embeddedModels: embeddedModels)
            }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    buildGraph(from: saved, embeddedModels: embeddedModels)
                }
            }
        }
    }

    /// Where embedded models get written out on open of an `.mbexpert` bundle — Core ML needs a
    /// real on-disk URL to compile/load from, it can't load a compiled model straight out of an
    /// in-memory `FileWrapper`. Mirrors ModelBuilder's own `ModelStore` pattern: copy into
    /// Application Support so the model persists independent of the bundle's original location.
    private static var embeddedModelsDirectory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EmbeddedExperts", isDirectory: true)
    }

    /// Extracts every child of the bundle's `Experts/` directory back to real files, keyed by
    /// the node ID encoded in each child's filename (`"<node-id>.<ext>"`, set at export time —
    /// see `fileWrapper(snapshot:configuration:)`). `FileWrapper.write` handles both a flat
    /// `.mlmodel` file and a nested `.mlpackage` directory tree uniformly.
    private static func extractEmbeddedModels(from bundle: FileWrapper) -> [UUID: URL] {
        guard let expertsWrapper = bundle.fileWrappers?["Experts"], let children = expertsWrapper.fileWrappers else {
            return [:]
        }
        let destDir = embeddedModelsDirectory
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        var result: [UUID: URL] = [:]
        for (embeddedName, child) in children {
            guard let nodeID = UUID(uuidString: (embeddedName as NSString).deletingPathExtension) else { continue }
            let destURL = destDir.appendingPathComponent(embeddedName)
            try? FileManager.default.removeItem(at: destURL) // stale copy from a previous open of this bundle
            guard (try? child.write(to: destURL, options: [], originalContentsURL: nil)) != nil else { continue }
            result[nodeID] = destURL
        }
        return result
    }

    /// Copies one of the bundled example workflows (`Resources/Examples/*.sdstkflow`) into the
    /// user's Documents directory (skipped if already there) and returns its URL — used by the
    /// "Open Example" menu (`CanvasView`'s toolbar), which then hands the URL to the OS
    /// (`NSWorkspace`/`UIApplication`) to open like any other double-clicked file. Going through
    /// a real file + the system opener, rather than constructing a `WorkflowDocument` directly
    /// in-process, is deliberate: SwiftUI's `@Environment(\.newDocument)` only supports
    /// value-type `FileDocument`, not the `ReferenceFileDocument` this class conforms to
    /// (confirmed via a real compiler error, not assumed) — going through the filesystem sidesteps
    /// that entirely and is exactly what "File > Open" does anyway.
    static func exampleFileURL(named name: String) -> URL? {
        guard let bundledURL = Bundle.main.url(forResource: name, withExtension: "sdstkflow", subdirectory: "Examples") else {
            return nil
        }
        let examplesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Examples", isDirectory: true)
        let destURL = examplesDir.appendingPathComponent("\(name).sdstkflow")
        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.createDirectory(at: examplesDir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: bundledURL, to: destURL)
        }
        return FileManager.default.fileExists(atPath: destURL.path) ? destURL : nil
    }

    @MainActor
    private static func buildGraph(from saved: WorkflowDocumentData,
                                    embeddedModels: [UUID: URL] = [:]) -> (WorkflowGraph, ExecutionEngine) {
        let graph = WorkflowGraph()
        for nodeData in saved.nodes {
            guard let entry = WidgetCatalog.entry(for: nodeData.typeID) else {
                continue // a widget type from a newer app version; skip rather than fail the whole load
            }
            let widget = entry.make()
            try? widget.applyParams(from: nodeData.params)
            if let expertWidget = widget as? ExportsEmbeddedModel, let localURL = embeddedModels[nodeData.id] {
                expertWidget.rebind(toLocalFile: localURL)
            }
            graph.addNode(WidgetNode(id: nodeData.id,
                                      position: CGPoint(x: nodeData.x, y: nodeData.y),
                                      widget: widget))
        }
        for linkData in saved.links where graph.nodes[linkData.fromNode] != nil && graph.nodes[linkData.toNode] != nil {
            graph.addLink(WidgetLink(fromNode: linkData.fromNode, fromPort: linkData.fromPort,
                                      toNode: linkData.toNode, toPort: linkData.toPort))
        }
        let engine = ExecutionEngine(graph: graph)
        for id in graph.nodes.keys { engine.markDirty(id) }
        return (graph, engine)
    }

    func snapshot(contentType: UTType) throws -> WorkflowDocumentData {
        @MainActor func build() throws -> WorkflowDocumentData {
            var data = WorkflowDocumentData()
            data.nodes = try graph.nodes.values.map { node in
                WorkflowDocumentData.NodeData(id: node.id, typeID: node.widgetType.typeID,
                                               x: node.position.x, y: node.position.y,
                                               params: try node.widget.encodeParams())
            }
            data.links = graph.links.map {
                WorkflowDocumentData.LinkData(fromNode: $0.fromNode, fromPort: $0.fromPort,
                                               toNode: $0.toNode, toPort: $0.toPort)
            }
            return data
        }
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(build)
        } else {
            return try DispatchQueue.main.sync {
                try MainActor.assumeIsolated(build)
            }
        }
    }

    func fileWrapper(snapshot: WorkflowDocumentData, configuration: WriteConfiguration) throws -> FileWrapper {
        try makeFileWrapper(from: snapshot, asBundle: configuration.contentType == .mbExpertBundle)
    }

    /// Builds the on-disk representation for a snapshot — factored out of `fileWrapper(snapshot:
    /// configuration:)` so it's callable — and testable — without SwiftUI's own
    /// `WriteConfiguration`, which has no accessible public initializer.
    func makeFileWrapper(from snapshot: WorkflowDocumentData, asBundle: Bool) throws -> FileWrapper {
        let graphData = try JSONEncoder().encode(snapshot)
        guard asBundle else {
            return FileWrapper(regularFileWithContents: graphData)
        }

        // Stage each expert's model to a temp URL while MainActor-isolated (touching `graph`);
        // `FileWrapper` itself isn't `Sendable` so it can't cross back out of `assumeIsolated`
        // directly — a `URL` can. The actual `FileWrapper`s get built below, back in this
        // (nonisolated) context, from those staged URLs.
        @MainActor func stage() throws -> [(nodeID: UUID, url: URL)] {
            var staged: [(UUID, URL)] = []
            for node in graph.nodes.values {
                guard let expertWidget = node.widget as? ExportsEmbeddedModel,
                      let stagedURL = try expertWidget.stageModelFileForExport() else { continue }
                staged.append((node.id, stagedURL))
            }
            return staged
        }
        let stagedModels: [(nodeID: UUID, url: URL)]
        if Thread.isMainThread {
            stagedModels = try MainActor.assumeIsolated(stage)
        } else {
            stagedModels = try DispatchQueue.main.sync {
                try MainActor.assumeIsolated(stage)
            }
        }

        let graphWrapper = FileWrapper(regularFileWithContents: graphData)
        graphWrapper.preferredFilename = "graph.json"
        var topChildren: [String: FileWrapper] = ["graph.json": graphWrapper]

        if !stagedModels.isEmpty {
            var expertChildren: [String: FileWrapper] = [:]
            for (nodeID, url) in stagedModels {
                let wrapper = try FileWrapper(url: url, options: [.immediate])
                let embeddedName = "\(nodeID.uuidString).\(url.pathExtension)"
                wrapper.preferredFilename = embeddedName
                expertChildren[embeddedName] = wrapper
            }
            let expertsWrapper = FileWrapper(directoryWithFileWrappers: expertChildren)
            expertsWrapper.preferredFilename = "Experts"
            topChildren["Experts"] = expertsWrapper
        }
        return FileWrapper(directoryWithFileWrappers: topChildren)
    }
}
