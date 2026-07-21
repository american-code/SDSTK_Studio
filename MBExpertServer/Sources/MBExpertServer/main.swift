import Foundation

// Usage: MBExpertServer <path-to-bundle.mbexpert>
// Loads the bundle once at startup, then serves MCP requests over stdio until stdin closes.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: MBExpertServer <path-to-bundle.mbexpert>\n".utf8))
    exit(1)
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])

do {
    let graph = try ExpertBundle.load(bundleURL: bundleURL)
    FileHandle.standardError.write(Data("MBExpertServer: loaded \(graph.topologySummary) from \(bundleURL.lastPathComponent)\n".utf8))
    MCPServer(graph: graph).run()
} catch {
    FileHandle.standardError.write(Data("MBExpertServer: failed to load bundle — \(error)\n".utf8))
    exit(1)
}
