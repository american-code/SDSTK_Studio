import SwiftUI

/// One widget card on the canvas. Dragging the card body repositions it; dragging from an
/// output port dot starts a link (handled by the parent `CanvasView`, which owns full-graph
/// hit-testing for where the link lands).
struct NodeView: View {
    @ObservedObject var node: WidgetNode
    let state: NodeState
    var runProgress: Double? = nil   // 0…1 when widget reports fractional progress
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onOutputDragChanged: (String, CGPoint) -> Void
    let onOutputDragEnded: (String, CGPoint) -> Void

    private var widgetType: any StudioWidget.Type { node.widgetType }
    private var inputCount: Int { node.widget.dynamicInputPorts.count }
    private var outputCount: Int { node.widget.dynamicOutputPorts.count }
    private var height: CGFloat { CanvasLayout.nodeHeight(inputCount: inputCount, outputCount: outputCount) }

    private var currentOutput: PortValue? {
        if case .done(let value) = state { return value }
        return nil
    }

    var body: some View {
        ZStack {
            card
            inputDots
            outputDots
        }
        .frame(width: CanvasLayout.nodeWidth, height: height)
        .position(node.position)
        .gesture(moveGesture)
        .onTapGesture(perform: onSelect)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(widgetType.category.color)
                .frame(height: 4)
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(node.widget.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if case .failed(let message) = state {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                } else {
                    node.widget.makePreview(output: currentOutput)
                        .frame(height: CanvasLayout.previewHeight - 20)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .frame(width: CanvasLayout.nodeWidth, height: height, alignment: .top)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                              lineWidth: isSelected ? 2 : 1)
        )
        .shadow(radius: isSelected ? 4 : 1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: widgetType.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(widgetType.category.color, in: RoundedRectangle(cornerRadius: 6))
            Text(widgetType.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            statusDot
            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch state {
        case .idle:
            Circle().fill(.gray).frame(width: 8, height: 8)
        case .running:
            if let p = runProgress {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 24)
            } else {
                ProgressView().scaleEffect(0.5)
            }
        case .done:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .failed:
            Circle().fill(.red).frame(width: 8, height: 8)
        }
    }

    // Port dots are children of the same ZStack that `body` positions at `node.position` via
    // `.position(node.position)`. That outer `.position()` already places this whole assembly in
    // canvas space, so a dot's OWN `.position()` here must stay in the ZStack's *local* frame
    // (origin at its top-left, center at (nodeWidth/2, height/2)) — NOT add `node.position`
    // again. Adding it twice (an earlier, real bug) rendered every dot far from the card itself,
    // proportional to how far the node was from canvas origin (0,0) — which is exactly why
    // connecting two nodes visually failed: the user drags to where the dot is actually drawn,
    // but `CanvasView.completeLink`'s hit-test (correctly) checks the canvas-space position from
    // `CanvasView.portPosition`, which the mis-rendered dot never lined up with.
    private var inputDots: some View {
        ForEach(Array(node.widget.dynamicInputPorts.enumerated()), id: \.offset) { index, spec in
            let offset = CanvasLayout.inputPortOffset(index: index, inputCount: inputCount, outputCount: outputCount)
            PortDot(kind: spec.kind)
                .position(x: CanvasLayout.nodeWidth / 2 + offset.x, y: height / 2 + offset.y)
        }
    }

    private var outputDots: some View {
        ForEach(Array(node.widget.dynamicOutputPorts.enumerated()), id: \.offset) { index, spec in
            let offset = CanvasLayout.outputPortOffset(index: index, inputCount: inputCount, outputCount: outputCount)
            PortDot(kind: spec.kind)
                .position(x: CanvasLayout.nodeWidth / 2 + offset.x, y: height / 2 + offset.y)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                        .onChanged { value in onOutputDragChanged(spec.name, value.location) }
                        .onEnded { value in onOutputDragEnded(spec.name, value.location) }
                )
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                node.position = CGPoint(x: value.startLocation.x + value.translation.width,
                                         y: value.startLocation.y + value.translation.height)
            }
    }
}

/// A small colored dot marking one port. Color encodes `PortKind` so wiring a table into a
/// learner slot is visibly wrong before you even try it.
struct PortDot: View {
    let kind: PortKind

    var color: Color {
        switch kind {
        case .table: return .blue
        case .classifierLearner: return .purple
        case .regressorLearner: return .indigo
        case .scores: return .orange
        case .chart: return .green
        case .image: return .pink
        case .prediction: return .red
        case .text: return .yellow
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: CanvasLayout.portDotDiameter, height: CanvasLayout.portDotDiameter)
            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
    }
}
