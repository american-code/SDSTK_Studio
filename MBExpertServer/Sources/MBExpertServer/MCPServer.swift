import Foundation

/// A minimal MCP server over stdio — hand-rolled rather than depending on an external MCP SDK,
/// since this environment can't reliably reach a remote package registry and the wire protocol
/// itself is small: newline-delimited JSON-RPC 2.0 messages on stdin/stdout, three methods
/// (`initialize`, `tools/list`, `tools/call`) plus the `notifications/initialized` notification.
///
/// Exposes one tool wrapping the whole loaded graph: every `Experts.CoreMLExpert` runs on the
/// supplied image, and — when the bundle contains a `Coordinator` — their results are combined
/// with the same strategy/weight semantics as `CoordinatorWidget.run()` in the app. Per-expert
/// results are always included alongside the combined decision, so the calling agent sees the
/// full evidence, not just the verdict.
final class MCPServer {
    private let graph: ExpertBundle.LoadedGraph
    private let toolName: String

    init(graph: ExpertBundle.LoadedGraph) {
        self.graph = graph
        // MCP tool names are conventionally snake_case identifiers; derive one from the first
        // expert's name (single-expert bundles keep their v1-compatible name) or a generic one
        // for compound bundles.
        let base = graph.experts.count == 1 ? graph.experts[0].expertName : "expert_panel"
        self.toolName = "run_" + base
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    /// Blocks reading stdin line-by-line until EOF (stdin closed) — the standard MCP stdio
    /// server lifecycle: the client owns the process and closes stdin to terminate it.
    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            handle(line: line)
        }
    }

    private func handle(line: String) {
        guard let lineData = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            writeError(id: nil, code: -32700, message: "Parse error")
            return
        }
        let id = object["id"]
        guard let method = object["method"] as? String else {
            writeError(id: id, code: -32600, message: "Invalid request: missing method")
            return
        }
        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            writeResult(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "MBExpertServer", "version": "0.2.0"],
            ])
        case "notifications/initialized", "notifications/cancelled":
            break // notifications never get a response, per JSON-RPC (no "id" means no reply expected)
        case "tools/list":
            writeResult(id: id, result: ["tools": [toolDescriptor]])
        case "tools/call":
            handleToolsCall(id: id, params: params)
        default:
            guard id != nil else { return } // unknown notification: ignore silently, don't answer what wasn't asked
            writeError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private var toolDescriptor: [String: Any] {
        [
            "name": toolName,
            "description": "Runs the SDSTK Studio expert bundle (\(graph.topologySummary)) on an image and returns per-expert predictions plus the combined decision.",
            "inputSchema": [
                "type": "object",
                "properties": ["image_path": ["type": "string", "description": "Absolute path to an image file"]],
                "required": ["image_path"],
            ],
        ]
    }

    private func handleToolsCall(id: Any?, params: [String: Any]) {
        guard let name = params["name"] as? String, name == toolName else {
            writeError(id: id, code: -32602, message: "Unknown tool: \(params["name"] as? String ?? "?")")
            return
        }
        guard let arguments = params["arguments"] as? [String: Any], let imagePath = arguments["image_path"] as? String else {
            writeError(id: id, code: -32602, message: "Missing required argument 'image_path'")
            return
        }

        // Run every expert; an individual expert's failure becomes part of the evidence
        // (`error` in its entry) rather than failing the whole call — matching how the app's
        // own null-output handling treats "one expert had nothing to say" as data.
        var expertEntries: [[String: Any]] = []
        var successes: [(result: ImageExpertRunner.Result, weight: Double)] = []
        for expert in graph.experts {
            var entry: [String: Any] = ["expert": expert.expertName, "weight": expert.weight]
            do {
                let result = try ImageExpertRunner.run(modelURL: expert.modelURL, imagePath: imagePath)
                if let label = result.label { entry["label"] = label }
                if let confidence = result.confidence { entry["confidence"] = confidence }
                if let value = result.value { entry["value"] = value }
                successes.append((result, expert.weight))
            } catch {
                entry["error"] = "\(error)"
            }
            expertEntries.append(entry)
        }

        var payload: [String: Any] = ["experts": expertEntries]
        if let decision = combine(successes) {
            payload["decision"] = decision
        }
        let allFailed = successes.isEmpty

        let payloadJSON = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        writeResult(id: id, result: [
            "content": [["type": "text", "text": payloadJSON]],
            "isError": allFailed,
        ])
    }

    /// Mirrors `CoordinatorWidget.run()`'s two strategies. With no coordinator in the bundle:
    /// a single expert's result becomes the decision directly; multiple uncoordinated experts
    /// get no combined decision (the caller sees per-expert results only).
    private func combine(_ successes: [(result: ImageExpertRunner.Result, weight: Double)]) -> [String: Any]? {
        guard !successes.isEmpty else { return nil }

        func entry(_ r: ImageExpertRunner.Result) -> [String: Any] {
            var d: [String: Any] = [:]
            if let label = r.label { d["label"] = label }
            if let confidence = r.confidence { d["confidence"] = confidence }
            if let value = r.value { d["value"] = value }
            return d
        }

        guard let strategy = graph.coordinatorStrategy else {
            return successes.count == 1 ? entry(successes[0].result) : nil
        }

        if strategy == "Weighted average (numeric value)" {
            let numeric = successes.filter { $0.result.value != nil }
            guard !numeric.isEmpty else { return nil }
            let totalWeight = numeric.reduce(0.0) { $0 + $1.weight }
            let combined = numeric.reduce(0.0) { $0 + ($1.result.value! * $1.weight) } / totalWeight
            return ["value": combined, "strategy": strategy]
        }

        // Default / "Highest confidence wins"
        let winner = successes.max { lhs, rhs in
            (lhs.result.confidence ?? 0) * lhs.weight < (rhs.result.confidence ?? 0) * rhs.weight
        }!
        var d = entry(winner.result)
        d["strategy"] = strategy
        return d
    }

    // MARK: Wire I/O

    private func writeResult(id: Any?, result: [String: Any]) {
        // `id ?? NSNull()`, not `id as Any`: a genuinely-nil id (unparseable request, or an id
        // JSON-RPC itself allows to be `null`) has to serialize as JSON `null`, not vanish or
        // trip `JSONSerialization` on a boxed `Optional<Any>.none`.
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func writeError(id: Any?, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var line = data
        line.append(0x0A) // newline — one JSON-RPC message per line, per the stdio transport
        FileHandle.standardOutput.write(line)
    }
}
