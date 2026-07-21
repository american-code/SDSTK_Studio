import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// Loads a photo into a `CGImage` — the "Data" source that feeds `Experts.CoreMLExpert`.
/// Follows `CSVFileWidget`'s security-scoped bookmark pattern so the picked file survives
/// document reopen, not just the session it was chosen in.
final class ImageFileWidget: StudioWidget {
    static let typeID = "Data.ImageFile"
    static let category = WidgetCategory.data
    static let displayName = "Image File"
    static let symbolName = "photo"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "image", kind: .image)]

    private struct Params: Codable {
        var bookmark: Data?
        var fileName: String?
    }
    private var params = Params()

    var fileName: String? { params.fileName }
    var summary: String { params.fileName ?? "No image selected" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func setFile(url: URL) {
        params.fileName = url.lastPathComponent
        params.bookmark = try? url.bookmarkData(options: Self.bookmarkCreationOptions)
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard let bookmark = params.bookmark else {
            throw WidgetError.message("Choose an image file")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw WidgetError.message("Couldn't access '\(url.lastPathComponent)'")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WidgetError.message("Couldn't decode '\(url.lastPathComponent)' as an image")
        }
        return .image(image)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ImageFileInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .image(let cgImage)? = output else { return AnyView(EmptyView()) }
        return AnyView(
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 80)
        )
    }

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}

private struct ImageFileInspectorView: View {
    let widget: ImageFileWidget
    let onChange: () -> Void
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("File") {
                Button(widget.fileName ?? "Choose Image…") { showImporter = true }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            widget.setFile(url: url)
            onChange()
        }
    }
}
