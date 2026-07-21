import Foundation

/// On-disk shape of a `.sdstkflow` file. Only structure + params are persisted — execution
/// output is always recomputed on open (matches Orange: workflows re-run rather than restore a
/// cached result you can't trust is still valid).
struct WorkflowDocumentData: Codable {
    struct NodeData: Codable {
        var id: UUID
        var typeID: String
        var x: Double
        var y: Double
        var params: Data
    }
    struct LinkData: Codable {
        var fromNode: UUID
        var fromPort: String
        var toNode: UUID
        var toPort: String
    }

    var nodes: [NodeData] = []
    var links: [LinkData] = []
}
