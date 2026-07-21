import Foundation

/// A widget that references an external model file needing to travel with the graph when
/// exported as an `.mbexpert` bundle. Conformed by every `Experts.*` widget that wraps a Core ML
/// model (`CoreMLExpert`, `CoreMLTabularExpert`) — `WorkflowDocument`'s bundle export/import
/// checks against this protocol, not concrete widget types, so a third expert shape doesn't
/// need changes there.
@MainActor
protocol ExportsEmbeddedModel: AnyObject {
    /// Copies the referenced model to a fresh temp location for embedding into an export.
    /// Returns `nil` if no model is set (an incomplete node is skipped, not a failed export).
    func stageModelFileForExport() throws -> URL?
    /// Points this widget at an already-local file (e.g. one just extracted from an `.mbexpert`
    /// bundle) without going through the sandboxed file picker.
    func rebind(toLocalFile url: URL)
}

/// Shared security-scoped-bookmark handling for widgets that reference an external model file.
/// A plain `Codable` value (not a `StudioWidget` itself) held as a property, since Swift classes
/// can't share implementation via multiple inheritance — both `CoreMLExpertWidget` and
/// `CoreMLTabularExpertWidget` hold one of these instead of duplicating the bookmark dance.
struct ModelFileBookmark: Codable {
    var bookmark: Data?
    var fileName: String?

    mutating func setFile(_ url: URL) {
        fileName = url.lastPathComponent
        bookmark = try? url.bookmarkData(options: Self.creationOptions)
    }

    /// Same mechanics as `setFile` — kept as a separate name at call sites so "user picked this
    /// via the file importer" and "the app rebound this after unpacking a bundle" read distinctly,
    /// even though the underlying bookmark call is identical either way.
    mutating func rebind(toLocalFile url: URL) {
        fileName = url.lastPathComponent
        bookmark = try? url.bookmarkData(options: Self.creationOptions)
    }

    /// Resolves the bookmark, holds the security scope open for `body`, then releases it —
    /// centralizes the start/stop pairing so a caller can't forget the `defer`.
    func withResolvedURL<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark else {
            throw WidgetError.message("Choose a Core ML model (.mlmodel / .mlpackage)")
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: Self.resolutionOptions,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw WidgetError.message("Couldn't access '\(url.lastPathComponent)'")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }

    /// Copies the resolved file (or `.mlpackage` directory) to a fresh temp location — the
    /// shared half of `ExportsEmbeddedModel.stageModelFileForExport()`. Returns `nil` if no
    /// model is set yet.
    func stageForExport() throws -> URL? {
        guard bookmark != nil else { return nil }
        return try withResolvedURL { url in
            let stagingDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("mbexpert-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let dest = stagingDir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        }
    }

    #if os(macOS)
    static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let creationOptions: URL.BookmarkCreationOptions = []
    static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif
}
