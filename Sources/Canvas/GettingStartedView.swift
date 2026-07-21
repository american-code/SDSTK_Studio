import SwiftUI

/// Shown automatically on first launch (tracked via `hasSeenGettingStarted` in `CanvasView`) and
/// any time from the toolbar's "?" button. A quick orientation, not full documentation — the
/// interaction model itself (palette → canvas → wire → inspect) mirrors Orange Data Mining's own
/// visual-programming canvas, so anyone who's used Orange (or a node editor generally) already
/// knows the shape of it; this just spells it out for everyone else.
struct GettingStartedView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id = Int.random(in: Int.min...Int.max)
        let symbol: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(symbol: "square.grid.2x2", title: "Add a widget",
             body: "Tap any widget in the left palette — it drops onto the canvas. Widgets are grouped by category (Data, Visualize, Model, Evaluate, …), same as Orange's own tabs."),
        Step(symbol: "circle.fill", title: "Wire it up",
             body: "Every widget has colored dots: inputs on the left, outputs on the right. Drag from an output dot to an input dot of the same color to connect two widgets — data only flows once they're wired."),
        Step(symbol: "slider.horizontal.3", title: "Configure it",
             body: "Tap a widget to select it, then use the right-hand inspector to set its parameters (which column, how many folds, …). Results update live — no separate \"Run\" step."),
        Step(symbol: "sparkles", title: "Or just open an example",
             body: "The toolbar's Examples menu opens a fully-wired starter workflow — Classify Iris, Explore Data, or a Regression Demo — so you can see a working pipeline before building your own."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("SDSTK Studio is a visual-programming canvas for data science — build a pipeline by connecting widgets, in the spirit of Orange Data Mining.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: step.symbol)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.headline)
                                Text(step.body).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Getting Started")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}
