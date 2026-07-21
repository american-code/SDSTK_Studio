import Foundation
import SwiftUI
import UniformTypeIdentifiers
import DataScience

/// Loads a Parquet file into a `DataFrame` via SDSTK's hand-rolled Parquet reader (PLAIN
/// encoding, uncompressed — see SDSTK's own `ParquetIOError.unsupportedEncoding` for scope
/// limits on files written with compression/dictionary encoding). Otherwise identical in
/// structure to `CSVFileWidget`, including the security-scoped bookmark handling.
final class ParquetFileWidget: StudioWidget {
    static let typeID = "Data.ParquetFile"
    static let category = WidgetCategory.data
    static let displayName = "Parquet File"
    static let symbolName = "cylinder.split.1x2"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {
        var bookmark: Data?
        var fileName: String?
    }
    private var params = Params()

    var fileName: String? { params.fileName }
    var summary: String { params.fileName ?? "No file selected" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func setFile(url: URL) {
        params.fileName = url.lastPathComponent
        params.bookmark = try? url.bookmarkData(options: Self.bookmarkCreationOptions)
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard let bookmark = params.bookmark else {
            throw WidgetError.message("Choose a Parquet file")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw WidgetError.message("Couldn't access '\(url.lastPathComponent)'")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let df = try DataFrame.readParquet(path: url.path)
        return .table(df)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ParquetFileInspectorView(widget: self, onChange: onChange))
    }

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}

private struct ParquetFileInspectorView: View {
    let widget: ParquetFileWidget
    let onChange: () -> Void
    @State private var showImporter = false

    var body: some View {
        Form {
            Button(widget.fileName ?? "Choose Parquet…") { showImporter = true }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "parquet") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            widget.setFile(url: url)
            onChange()
        }
    }
}
