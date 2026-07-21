import Foundation
import SwiftUI
import FoundationModels

/// A general-knowledge "expert" node backed by Apple's on-device Foundation Model — distinct
/// from the narrow, closed-domain Core ML experts, which only handle what they were explicitly
/// trained on. v1 is plain text generation only: `LanguageModelSession` does accept a `tools:`
/// parameter, but wiring a real web-search tool is its own scoped design problem (network access
/// from a graph node, what a search result even looks like as a `PortValue`), not a one-line
/// addition — deliberately deferred, not silently dropped.
final class ResearchExpertWidget: StudioWidget {
    static let typeID = "Experts.ResearchExpert"
    static let category = WidgetCategory.experts
    static let displayName = "Research Expert"
    static let symbolName = "text.bubble"
    static let inputPorts: [PortSpec] = [PortSpec(name: "prompt", kind: .text)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "response", kind: .text)]

    private struct Params: Codable { var instructions: String = "" }
    private var params = Params()

    var instructions: String {
        get { params.instructions }
        set { params.instructions = newValue }
    }

    var summary: String { params.instructions.isEmpty ? "No instructions" : String(params.instructions.prefix(40)) }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .text(let prompt) = inputs[0] else { throw WidgetError.message("Expected text") }
        guard !prompt.isEmpty else { throw WidgetError.message("Prompt is empty") }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw WidgetError.message("On-device model unavailable: \(reason)")
        }

        let session = LanguageModelSession(instructions: params.instructions.isEmpty ? nil : params.instructions)
        let response = try await session.respond(to: prompt)
        return .text(response.content)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ResearchExpertInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .text(let text)? = output else { return AnyView(EmptyView()) }
        return AnyView(Text(text).font(.callout).lineLimit(6).padding(.vertical, 4))
    }
}

private struct ResearchExpertInspectorView: View {
    let widget: ResearchExpertWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            Section("Instructions (optional)") {
                TextEditor(text: Binding(get: { widget.instructions }, set: { widget.instructions = $0; onChange() }))
                    .frame(minHeight: 100)
            }
        }
    }
}
