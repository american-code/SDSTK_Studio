import Foundation
import SwiftUI
import DataScience

/// A small bundled corpus — 15 short sentences across three topics — so `Text.Similarity` has
/// something meaningful to cluster by topic without asking the user to type or import text
/// first. No input, like `Data.IrisExample`.
final class TextSampleWidget: StudioWidget {
    static let typeID = "Data.TextSample"
    static let category = WidgetCategory.data
    static let displayName = "Text Sample"
    static let symbolName = "text.quote"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {}
    private var params = Params()

    var summary: String { "15 sentences · 3 topics" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    private static let documents: [(topic: String, text: String)] = [
        ("tech", "The new processor doubles battery life while running twice as fast."),
        ("tech", "Developers are adopting the updated framework for its faster build times."),
        ("tech", "The startup raised funding to expand its cloud computing platform."),
        ("tech", "Engineers optimized the database to handle millions of queries per second."),
        ("tech", "The company unveiled a smaller chip with significantly lower power draw."),
        ("sports", "The team clinched the championship after a dramatic overtime victory."),
        ("sports", "She broke the national record in the two hundred meter sprint."),
        ("sports", "The coach praised the defense for holding the opponent scoreless."),
        ("sports", "Fans filled the stadium to watch the rivalry match this weekend."),
        ("sports", "The rookie pitcher threw a shutout in his first professional start."),
        ("cooking", "Simmer the tomatoes slowly to develop a rich, sweet sauce."),
        ("cooking", "Whisk the eggs and sugar until the mixture turns pale and fluffy."),
        ("cooking", "Searing the steak first locks in the juices before it roasts."),
        ("cooking", "Let the dough rest overnight for a deeper sourdough flavor."),
        ("cooking", "A splash of vinegar brightens the soup right before serving."),
    ]

    func run(inputs: [PortValue]) async throws -> PortValue {
        .table(DataFrame(["topic": Column(Self.documents.map(\.topic)),
                           "text": Column(Self.documents.map(\.text))]))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Text("15 short sentences across tech/sports/cooking topics — wire straight into Text Similarity.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding())
    }
}
