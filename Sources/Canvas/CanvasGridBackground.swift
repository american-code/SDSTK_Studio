import SwiftUI

/// A subtle dot-grid behind the canvas nodes — cheap visual polish that makes the surface read
/// as an actual workspace (matches the dotted-grid feel of Orange's own canvas) instead of a
/// flat, featureless rectangle.
struct CanvasGridBackground: View {
    private let spacing: CGFloat = 24
    private let dotRadius: CGFloat = 1.1

    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(.secondary.opacity(0.18))
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: color)
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
