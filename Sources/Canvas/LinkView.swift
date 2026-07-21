import SwiftUI

/// A cubic-Bezier connector between two ports, curving horizontally like Xcode/Quartz Composer
/// style node editors.
private struct LinkPath: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let controlOffset = max(abs(to.x - from.x) * 0.5, 40)
        path.move(to: from)
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + controlOffset, y: from.y),
                      control2: CGPoint(x: to.x - controlOffset, y: to.y))
        return path
    }
}

struct LinkView: View {
    let from: CGPoint
    let to: CGPoint
    var color: Color = .secondary
    var lineWidth: CGFloat = 2

    var body: some View {
        LinkPath(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
