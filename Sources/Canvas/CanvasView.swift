import SwiftUI

/// The document's editor: a 3-column layout (palette · canvas · inspector) that adapts between
/// iPad and Mac for free via `NavigationSplitView`. Panning is native `ScrollView` scrolling —
/// no custom pan/zoom state (zoom is deferred; see `PLAN.md` roadmap, this is Phase 1).
struct CanvasView: View {
    let document: WorkflowDocument
    @ObservedObject private var graph: WorkflowGraph
    @ObservedObject private var engine: ExecutionEngine
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL

    @State private var selectedNodeID: UUID?
    @State private var pendingLink: PendingLink?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showHelp = false
    @AppStorage("hasSeenGettingStarted") private var hasSeenGettingStarted = false

    /// (display name, bundled filename without extension) — keep in sync with the actual files
    /// under `Resources/Examples/`.
    static let examples: [(name: String, file: String)] = [
        ("Classify Iris", "01-Classify-Iris"),
        ("Explore Data", "02-Explore-Data"),
        ("Regression Demo", "03-Regression-Demo"),
        ("Unsupervised Clustering", "04-Unsupervised-Clustering"),
        ("Signal FFT Demo", "05-Signal-FFT-Demo"),
        ("Time Series Autocorrelation", "06-TimeSeries-Autocorrelation"),
        ("Optimize Curve Fit", "07-Optimize-CurveFit"),
        ("Text Similarity", "08-Text-Similarity"),
        ("Graph Shortest Path", "09-Graph-ShortestPath"),
        ("Formulas: Physics", "10-Formulas-Physics"),
        ("Speed Benchmark (CPU vs GPU)", "11-Speed-Benchmark"),
    ]

    private struct PendingLink {
        var from: CGPoint
        var to: CGPoint
    }

    init(document: WorkflowDocument) {
        self.document = document
        self._graph = ObservedObject(wrappedValue: document.graph)
        self._engine = ObservedObject(wrappedValue: document.engine)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PaletteView(onAdd: addNode)
                .navigationTitle("Widgets")
        } content: {
            canvasSurface
                .navigationTitle("Canvas")
                .toolbar {
                    ToolbarItem {
                        Menu {
                            ForEach(Self.examples, id: \.file) { example in
                                Button(example.name) {
                                    if let url = WorkflowDocument.exampleFileURL(named: example.file) {
                                        openURL(url)
                                    }
                                }
                            }
                        } label: {
                            Label("Examples", systemImage: "sparkles")
                        }
                    }
                    ToolbarItem {
                        Button {
                            showHelp = true
                        } label: {
                            Label("Getting Started", systemImage: "questionmark.circle")
                        }
                    }
                }
        } detail: {
            if let id = selectedNodeID, let node = graph.nodes[id] {
                InspectorPanel(node: node, state: engine.state(for: id), onChange: { [weak engine = engine] in engine?.markDirty(id) })
                    .navigationTitle(node.widgetType.displayName)
            } else {
                ContentUnavailableView("Select a Widget", systemImage: "square.dashed",
                                        description: Text("Add one from the palette, then tap it to edit its parameters here."))
            }
        }
        .sheet(isPresented: $showHelp) {
            GettingStartedView()
        }
        .onAppear {
            if !hasSeenGettingStarted {
                hasSeenGettingStarted = true
                showHelp = true
            }
        }
    }

    private var canvasSurface: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                CanvasGridBackground()
                    .frame(width: CanvasLayout.surfaceSize.width, height: CanvasLayout.surfaceSize.height)

                ForEach(graph.links) { link in
                    if let from = portPosition(nodeID: link.fromNode, portName: link.fromPort, isOutput: true),
                       let to = portPosition(nodeID: link.toNode, portName: link.toPort, isOutput: false) {
                        LinkView(from: from, to: to)
                            .onTapGesture { graph.removeLink(link.id); engine.markDirty(link.toNode) }
                    }
                }

                if let pending = pendingLink {
                    LinkView(from: pending.from, to: pending.to, color: .accentColor)
                }

                ForEach(Array(graph.nodes.values)) { node in
                    NodeView(
                        node: node,
                        state: engine.state(for: node.id),
                        runProgress: engine.progress[node.id],
                        isSelected: node.id == selectedNodeID,
                        onSelect: { selectedNodeID = node.id },
                        onDelete: { deleteNode(node.id) },
                        onOutputDragChanged: { port, point in
                            let start = portPosition(nodeID: node.id, portName: port, isOutput: true) ?? point
                            pendingLink = PendingLink(from: start, to: point)
                        },
                        onOutputDragEnded: { port, point in
                            completeLink(from: node.id, port: port, at: point)
                            pendingLink = nil
                        }
                    )
                }
            }
            .coordinateSpace(name: "canvas")
        }
        .background(Color.gray.opacity(0.08))
        .onTapGesture { selectedNodeID = nil }
    }

    // MARK: - Node/link mutation

    private func addNode(_ entry: WidgetCatalog.Entry) {
        let column = graph.nodes.count % 4
        let row = graph.nodes.count / 4
        let position = CGPoint(x: 160 + CGFloat(column) * 280, y: 140 + CGFloat(row) * 260)
        let node = WidgetNode(position: position, widget: entry.make())
        performInsert(node: node, links: [], actionName: "Add \(entry.displayName)")
    }

    private func deleteNode(_ id: UUID) {
        performDelete(id: id, actionName: "Delete Widget")
    }

    /// `performInsert`/`performDelete` each register the other as the next undo step, so
    /// toggling undo/redo any number of times keeps working — not just a single undo level.
    private func performInsert(node: WidgetNode, links: [WidgetLink], actionName: String) {
        graph.addNode(node)
        for link in links { graph.addLink(link) }
        selectedNodeID = node.id
        engine.markDirty(node.id)
        for link in links { engine.markDirty(link.toNode) }
        undoManager?.registerUndo(withTarget: graph) { [self] _ in
            performDelete(id: node.id, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func performDelete(id: UUID, actionName: String) {
        guard let node = graph.nodes[id] else { return }
        let removedLinks = graph.links.filter { $0.fromNode == id || $0.toNode == id }
        graph.removeNode(id)
        engine.removeNode(id)
        if selectedNodeID == id { selectedNodeID = nil }
        undoManager?.registerUndo(withTarget: graph) { [self] _ in
            performInsert(node: node, links: removedLinks, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private func completeLink(from fromNode: UUID, port fromPort: String, at point: CGPoint) {
        guard let fromWidget = graph.nodes[fromNode]?.widget,
              let fromSpec = fromWidget.dynamicOutputPorts.first(where: { $0.name == fromPort }) else { return }
        let hitRadius: CGFloat = 26
        // Nearest match within range, not first-in-declaration-order — a widget can have two
        // input ports of the same kind (e.g. `Data.Concatenate`'s "left"/"right"), and those
        // sit close enough together that "first" would sometimes pick the wrong one.
        var best: (nodeID: UUID, portName: String, distance: CGFloat)?
        for node in graph.nodes.values where node.id != fromNode {
            for spec in node.widget.dynamicInputPorts where spec.kind == fromSpec.kind {
                guard let pos = portPosition(nodeID: node.id, portName: spec.name, isOutput: false) else { continue }
                let distance = hypot(pos.x - point.x, pos.y - point.y)
                guard distance <= hitRadius else { continue }
                if best == nil || distance < best!.distance {
                    best = (node.id, spec.name, distance)
                }
            }
        }
        if let best {
            graph.addLink(WidgetLink(fromNode: fromNode, fromPort: fromPort, toNode: best.nodeID, toPort: best.portName))
            engine.markDirty(best.nodeID)
        }
    }

    private func portPosition(nodeID: UUID, portName: String, isOutput: Bool) -> CGPoint? {
        guard let node = graph.nodes[nodeID] else { return nil }
        let inputs = node.widget.dynamicInputPorts
        let outputs = node.widget.dynamicOutputPorts
        let ports = isOutput ? outputs : inputs
        guard let index = ports.firstIndex(where: { $0.name == portName }) else { return nil }
        let offset = isOutput
            ? CanvasLayout.outputPortOffset(index: index, inputCount: inputs.count, outputCount: outputs.count)
            : CanvasLayout.inputPortOffset(index: index, inputCount: inputs.count, outputCount: outputs.count)
        return CGPoint(x: node.position.x + offset.x, y: node.position.y + offset.y)
    }
}
