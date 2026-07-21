import Foundation
import SwiftUI
import DataScience

/// Joins two incoming tables on a shared key column — Orange's Merge Data widget. The first
/// widget in the app with two input ports of the same `PortKind` (both "table"), which is why
/// `CanvasView`'s drag-to-connect hit-testing had to switch from "first port in range" to
/// "nearest port in range."
final class ConcatenateWidget: StudioWidget {
    static let typeID = "Data.Concatenate"
    static let category = WidgetCategory.data
    static let displayName = "Merge Data"
    static let symbolName = "arrow.triangle.merge"
    static let inputPorts: [PortSpec] = [PortSpec(name: "left", kind: .table), PortSpec(name: "right", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    /// Mirrors `Frame.JoinKind` locally rather than retroactively conforming that cross-module
    /// enum to `Codable` — automatic Codable synthesis isn't guaranteed for a raw-value enum
    /// conformance declared outside the module that defines it, so a small local wrapper is the
    /// safe, guaranteed-correct choice, not a shortcut.
    enum HowOption: String, Codable, CaseIterable {
        case inner = "Inner", left = "Left", right = "Right", outer = "Outer"

        var joinKind: JoinKind {
            switch self {
            case .inner: return .inner
            case .left: return .left
            case .right: return .right
            case .outer: return .outer
            }
        }
    }

    private struct Params: Codable { var key: String = ""; var how: HowOption = .inner }
    private var params = Params()
    private(set) var leftColumns: [String] = []
    private(set) var rightColumns: [String] = []

    var key: String {
        get { params.key }
        set { params.key = newValue }
    }
    var how: HowOption {
        get { params.how }
        set { params.how = newValue }
    }

    var summary: String { params.key.isEmpty ? "Select a join key" : "\(params.how.rawValue) join on \(params.key)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let left) = inputs[0] else { throw WidgetError.message("Expected a left table") }
        guard case .table(let right) = inputs[1] else { throw WidgetError.message("Expected a right table") }
        leftColumns = left.columnOrder
        rightColumns = right.columnOrder
        guard !params.key.isEmpty else { throw WidgetError.message("Select a shared key column") }
        guard left.columnOrder.contains(params.key), right.columnOrder.contains(params.key) else {
            throw WidgetError.message("'\(params.key)' must exist in both tables")
        }
        return .table(left.join(right, on: params.key, how: params.how.joinKind))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ConcatenateInspectorView(widget: self, onChange: onChange))
    }
}

private struct ConcatenateInspectorView: View {
    let widget: ConcatenateWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.leftColumns.isEmpty || widget.rightColumns.isEmpty {
                Text("Connect both a left and a right table first.").foregroundStyle(.secondary)
            } else {
                let sharedColumns = widget.leftColumns.filter { widget.rightColumns.contains($0) }
                if sharedColumns.isEmpty {
                    Text("These tables have no column names in common to join on.").foregroundStyle(.secondary)
                } else {
                    Picker("Key", selection: Binding(get: { widget.key }, set: { widget.key = $0; onChange() })) {
                        ForEach(sharedColumns, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Join type", selection: Binding(get: { widget.how }, set: { widget.how = $0; onChange() })) {
                        ForEach(ConcatenateWidget.HowOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
    }
}
