import Foundation
import SwiftUI
import DataScience

/// Times the same `Column` construct+sum on SDSTK's `.cpu` and `.mlx` backends over a synthetic
/// row count and charts the difference — turns SDSTK's own benchmark story (see
/// `[[swiftsci-project]]`: GPU wins on compute-bound work, loses on memory-bound ops like a
/// plain sum at these sizes) into a live in-app demo. Standalone (no table input) since a
/// meaningful GPU-vs-CPU gap needs a much larger row count than any bundled example dataset has.
///
/// **Safety-critical:** MLX's C++ scheduler calls `exit(-1)` — not a catchable Swift error — if
/// it can't find a compiled Metal shader library the moment anything touches the `.mlx` backend.
/// This widget is the ONLY place in the app that ever sets `FrameConfig.backend = .mlx` (every
/// other widget runs on the app-wide `.cpu` default set in `SDSTKStudioApp.init`), and it checks
/// availability first — if nothing's found, this throws a normal, recoverable `WidgetError`
/// instead of ever reaching the risky code path.
///
/// A real Xcode build (not a raw `swift build` — confirmed via mlx-swift's own README: "SwiftPM
/// (command line) cannot build the Metal shaders so the ultimate build has to be done via
/// Xcode") compiles MLX's `.metal` sources natively and bundles the result as
/// `mlx-swift_Cmlx.bundle/default.metallib` inside the app — zero network access, since the
/// shader sources ship as checked-in submodules. `metallibAvailable` checks for that bundle
/// first; the flat `mlx.metallib`-next-to-executable path is a fallback for the raw
/// `swift build` CLI harness used to verify this code (which genuinely cannot compile Metal
/// shaders at all, per that same README note).
final class BenchmarkWidget: StudioWidget {
    static let typeID = "Data.Benchmark"
    static let category = WidgetCategory.data
    static let displayName = "Backend Benchmark"
    static let symbolName = "speedometer"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var rowCount: Int = 500_000 }
    private var params = Params()
    private(set) var lastResultText = ""

    var rowCount: Int {
        get { params.rowCount }
        set { params.rowCount = newValue }
    }

    var summary: String { lastResultText.isEmpty ? "\(params.rowCount) rows, not yet run" : lastResultText }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    /// Whether MLX can find a compiled Metal shader library, checked the same way MLX's own
    /// C++ core searches (`load_default_library` in mlx-swift's `device.cpp`): first the
    /// Xcode-native resource bundle a real app build produces, then the flat
    /// `mlx.metallib`-next-to-executable convention a raw `swift build` CLI binary uses.
    static var metallibAvailable: Bool {
        // Xcode's real, no-network build path: MLX's `.metal` shaders compiled natively into
        // this fixed-name resource bundle (`SWIFTPM_BUNDLE` in mlx-swift's Package.swift).
        let bundleParents = [
            Bundle.main.bundleURL,                                             // iOS: flat layout
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"), // macOS: nested layout
        ]
        for parent in bundleParents {
            let cmlxBundleURL = parent.appendingPathComponent("mlx-swift_Cmlx.bundle")
            if let cmlxBundle = Bundle(url: cmlxBundleURL),
               cmlxBundle.url(forResource: "default", withExtension: "metallib") != nil {
                return true
            }
        }

        // Fallback: the flat "next to the executable" convention — used by the raw `swift
        // build` CLI harness, which cannot compile Metal shaders at all and instead has one
        // manually copied alongside the binary.
        guard let exeURL = Bundle.main.executableURL else { return false }
        let dir = exeURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("mlx.metallib").path)
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard Self.metallibAvailable else {
            throw WidgetError.message(
                "No compiled MLX Metal shader library found, so the GPU backend is unavailable. "
                + "A real Xcode build should produce this automatically with no network access — "
                + "try a clean build (this app was likely built via `swift build`, which cannot "
                + "compile Metal shaders at all; see PLAN.md).")
        }
        let n = max(1_000, params.rowCount)
        let values = (0..<n).map { _ in Double.random(in: 0...1) }

        FrameConfig.backend = .cpu
        let cpuStart = DispatchTime.now()
        let cpuSum = Column(values).sum() ?? 0
        let cpuMillis = millisSince(cpuStart)

        FrameConfig.backend = .mlx
        let mlxStart = DispatchTime.now()
        let mlxSum = Column(values).sum() ?? 0
        let mlxMillis = millisSince(mlxStart)
        FrameConfig.backend = .cpu // restore the app-wide safe default immediately

        lastResultText = "CPU \(String(format: "%.1f", cpuMillis))ms vs MLX \(String(format: "%.1f", mlxMillis))ms "
            + "(sums agree within \(String(format: "%.2e", abs(cpuSum - mlxSum))))"

        return .chart(.bars(categories: ["CPU", "MLX (GPU)"], values: [cpuMillis, mlxMillis],
                             xLabel: "Backend", yLabel: "Time (ms)",
                             title: "Construct + sum, \(n) rows"))
    }

    private func millisSince(_ start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(BenchmarkInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct BenchmarkInspectorView: View {
    let widget: BenchmarkWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if !BenchmarkWidget.metallibAvailable {
                Text("No compiled MLX Metal shader library found — the GPU backend is unavailable "
                     + "in this build. A real Xcode build produces one automatically.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Stepper("Rows: \(widget.rowCount)",
                    value: Binding(get: { widget.rowCount }, set: { widget.rowCount = $0; onChange() }),
                    in: 1_000...5_000_000, step: 50_000)
            if !widget.lastResultText.isEmpty {
                Text(widget.lastResultText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
