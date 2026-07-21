import SwiftUI
import DataScience

@main
struct SDSTKStudioApp: App {
    init() {
        // Frame defaults to the `.mlx` (GPU) backend, which requires `mlx.metallib` to be
        // present next to the running binary — MLX's C++ scheduler aborts the whole process
        // (`exit(-1)`, not a catchable Swift error) if it's missing. The build phase in
        // project.yml auto-fetches that file, but rather than have every ordinary widget
        // depend on that succeeding, default the app to the portable `.cpu` backend at launch
        // and let `Data.Benchmark` (the one widget that actually wants to demo `.mlx`) flip to
        // it deliberately and briefly, behind its own metallib-presence check.
        FrameConfig.backend = .cpu
    }

    var body: some Scene {
        DocumentGroup(newDocument: { WorkflowDocument() }) { file in
            CanvasView(document: file.document)
        }
    }
}
