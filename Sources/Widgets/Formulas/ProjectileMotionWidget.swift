import Foundation
import SwiftUI
import DataScience
import Formulas

/// Sweeps launch angle 0–90° through SDSTK's `Mechanics.projectileRange` closed-form equation
/// and charts the result — a standalone "reference" widget (no data input) showing off the
/// `Formulas` module, one of the "beyond Orange" categories (see PLAN.md §2).
final class ProjectileMotionWidget: StudioWidget {
    static let typeID = "Formulas.ProjectileMotion"
    static let category = WidgetCategory.formulas
    static let displayName = "Projectile Range"
    static let symbolName = "figure.archery"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var speed: Double = 20 }
    private var params = Params()

    var speed: Double {
        get { params.speed }
        set { params.speed = newValue }
    }

    var summary: String { "launch speed \(String(format: "%.1f", params.speed)) m/s" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        let points = stride(from: 1.0, through: 89.0, by: 1.0).map { degrees -> ChartData.Point in
            let radians = degrees * .pi / 180
            let range = Mechanics.projectileRange(speed: params.speed, angle: radians)
            return ChartData.Point(x: degrees, y: range)
        }
        return .chart(.points(points: points, xLabel: "Launch angle (°)", yLabel: "Range (m)",
                               title: "Projectile range at \(String(format: "%.0f", params.speed)) m/s"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Slider(value: Binding(get: { self.speed }, set: { self.speed = $0; onChange() }), in: 1...100) {
                Text("Launch speed: \(String(format: "%.1f", speed)) m/s")
            }
        })
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}
