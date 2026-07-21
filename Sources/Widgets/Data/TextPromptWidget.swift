import Foundation
import SwiftUI

/// A plain multi-line text source — no file, no upstream data, just what the user typed in the
/// inspector. Feeds `Experts.ResearchExpert`'s `prompt` port; nothing existing carried a bare
/// string onto the canvas (`Data.TextSample`/`Text.Similarity` work over `.table`, many rows).
final class TextPromptWidget: StudioWidget {
    static let typeID = "Data.TextPrompt"
    static let category = WidgetCategory.data
    static let displayName = "Text Prompt"
    static let symbolName = "text.cursor"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "text", kind: .text)]

    private struct Params: Codable { var text: String = "" }
    private var params = Params()

    var text: String {
        get { params.text }
        set { params.text = newValue }
    }

    var summary: String { params.text.isEmpty ? "Empty" : String(params.text.prefix(40)) }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard !params.text.isEmpty else { throw WidgetError.message("Enter some text") }
        return .text(params.text)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(TextPromptInspectorView(widget: self, onChange: onChange))
    }
}

private struct TextPromptInspectorView: View {
    let widget: TextPromptWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            TextEditor(text: Binding(get: { widget.text }, set: { widget.text = $0; onChange() }))
                .frame(minHeight: 120)
        }
    }
}
