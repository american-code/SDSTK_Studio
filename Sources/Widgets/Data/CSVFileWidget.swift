import Foundation
import SwiftUI
import UniformTypeIdentifiers
import DataScience

/// Loads a CSV file into a `DataFrame`. Access to the picked file persists across app launches
/// via a security-scoped bookmark (required inside the macOS sandbox; a no-op safety net on
/// iOS where `fileImporter` already grants scoped access).
final class CSVFileWidget: StudioWidget {
    static let typeID = "Data.CSVFile"
    static let category = WidgetCategory.data
    static let displayName = "CSV File"
    static let symbolName = "tablecells"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {
        var bookmark: Data?
        var fileName: String?
        var hasHeader: Bool = true
    }
    private var params = Params()

    var fileName: String? { params.fileName }
    var hasHeader: Bool {
        get { params.hasHeader }
        set { params.hasHeader = newValue }
    }

    var summary: String { params.fileName ?? "No file selected" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func setFile(url: URL) {
        params.fileName = url.lastPathComponent
        params.bookmark = try? url.bookmarkData(options: Self.bookmarkCreationOptions)
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard let bookmark = params.bookmark else {
            throw WidgetError.message("Choose a CSV file")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw WidgetError.message("Couldn't access '\(url.lastPathComponent)'")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let df = try DataFrame.readCSV(path: url.path, hasHeader: params.hasHeader)
        return .table(df)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CSVFileInspectorView(widget: self, onChange: onChange))
    }

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}

private struct CSVFileInspectorView: View {
    let widget: CSVFileWidget
    let onChange: () -> Void
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("File") {
                Button(widget.fileName ?? "Choose CSV…") { showImporter = true }
                Toggle("Has header row", isOn: Binding(
                    get: { widget.hasHeader },
                    set: { widget.hasHeader = $0; onChange() }
                ))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            widget.setFile(url: url)
            onChange()
        }
    }
}
