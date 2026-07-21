import Foundation
import SwiftUI
import DataScience

/// A small bundled city-distance network (9 US cities, 15 routes) with genuinely multiple paths
/// between any distant pair — so `Graph.ShortestPath` has something real to choose between
/// rather than a single obvious route. No input, like `Data.IrisExample`.
final class RouteExampleWidget: StudioWidget {
    static let typeID = "Data.RouteExample"
    static let category = WidgetCategory.data
    static let displayName = "Route Example"
    static let symbolName = "map"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {}
    private var params = Params()

    var summary: String { "9 cities · 15 routes" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    /// Approximate driving miles — good enough for a demo, not a routing service.
    private static let routes: [(from: String, to: String, miles: Double)] = [
        ("San Francisco", "Los Angeles", 380),
        ("San Francisco", "Las Vegas", 570),
        ("Los Angeles", "Las Vegas", 270),
        ("Los Angeles", "Phoenix", 370),
        ("Las Vegas", "Phoenix", 300),
        ("Las Vegas", "Denver", 750),
        ("Phoenix", "Denver", 830),
        ("Phoenix", "Dallas", 1020),
        ("Denver", "Chicago", 1000),
        ("Denver", "Dallas", 780),
        ("Dallas", "Chicago", 930),
        ("Dallas", "Atlanta", 780),
        ("Chicago", "New York", 790),
        ("Atlanta", "New York", 880),
        ("Chicago", "Atlanta", 720),
    ]

    func run(inputs: [PortValue]) async throws -> PortValue {
        // Undirected in spirit — the routes list has one row per pair, so add both directions
        // since Graph.ShortestPath builds a directed Graph<String> internally.
        let both = Self.routes + Self.routes.map { (from: $0.to, to: $0.from, miles: $0.miles) }
        return .table(DataFrame(["from": Column(both.map(\.from)),
                                   "to": Column(both.map(\.to)),
                                   "miles": Column(both.map(\.miles))]))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Text("9 US cities, 15 routes with real alternate paths — wire into Shortest Path and try San Francisco → New York.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding())
    }
}
