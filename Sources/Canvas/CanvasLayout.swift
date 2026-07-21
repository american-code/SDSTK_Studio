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
    /// Virtual size of the pannable surface.
    static let surfaceSize = CGSize(width: 2400, height: 1600)

    static func nodeHeight(inputCount: Int, outputCount: Int) -> CGFloat {
        headerHeight + CGFloat(max(inputCount, outputCount, 1)) * portRowHeight + previewHeight
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
