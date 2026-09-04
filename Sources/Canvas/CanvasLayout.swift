import SwiftUI

/// Shared, deterministic geometry for node cards and their port dots. Port row count is fixed
/// per widget type (`inputPorts.count`/`outputPorts.count`), so a node's height — and every
/// port's offset from its center — can be computed without any runtime layout measurement.
enum CanvasLayout {
    static let nodeWidth: CGFloat = 220
    static let headerHeight: CGFloat = 36
    static let portRowHeight: CGFloat = 22
    static let previewHeight: CGFloat = 90
    static let portDotDiameter: CGFloat = 14
    /// Floor for the pannable surface, so a graph with only a handful of nodes still has room to
    /// spread out and pan.
    static let minimumSurfaceSize = CGSize(width: 2400, height: 1600)
    /// Slack kept past the farthest node's edge, so a freshly auto-placed node never lands flush
    /// against the surface boundary.
    static let surfacePadding: CGFloat = 400

    static func nodeHeight(inputCount: Int, outputCount: Int) -> CGFloat {
        headerHeight + CGFloat(max(inputCount, outputCount, 1)) * portRowHeight + previewHeight
    }

    /// Virtual size of the pannable surface — grows to fit the farthest node instead of a fixed
    /// constant, so `addNode`'s deterministic grid placement can never place a widget beyond the
    /// surface's own extent (a fixed 2400×1600 made the 25th auto-placed widget permanently
    /// unreachable — see the grid math in `CanvasView.addNode`).
    @MainActor
    static func surfaceSize(for nodes: some Collection<WidgetNode>) -> CGSize {
        guard !nodes.isEmpty else { return minimumSurfaceSize }
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for node in nodes {
            let height = nodeHeight(inputCount: node.widget.dynamicInputPorts.count,
                                     outputCount: node.widget.dynamicOutputPorts.count)
            maxX = max(maxX, node.position.x + nodeWidth / 2)
            maxY = max(maxY, node.position.y + height / 2)
        }
        return CGSize(width: max(minimumSurfaceSize.width, maxX + surfacePadding),
                       height: max(minimumSurfaceSize.height, maxY + surfacePadding))
    }

    /// Offset of input port `index` from the node's center (`node.position`).
    static func inputPortOffset(index: Int, inputCount: Int, outputCount: Int) -> CGPoint {
        let h = nodeHeight(inputCount: inputCount, outputCount: outputCount)
        return CGPoint(x: -nodeWidth / 2, y: -h / 2 + headerHeight + portRowHeight * (CGFloat(index) + 0.5))
    }

    /// Offset of output port `index` from the node's center (`node.position`).
    static func outputPortOffset(index: Int, inputCount: Int, outputCount: Int) -> CGPoint {
        let h = nodeHeight(inputCount: inputCount, outputCount: outputCount)
        return CGPoint(x: nodeWidth / 2, y: -h / 2 + headerHeight + portRowHeight * (CGFloat(index) + 0.5))
    }
}
