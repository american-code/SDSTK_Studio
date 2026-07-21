# SDSTK Studio — Plan

A universal (iPadOS + macOS) visual-programming data-science workbench, in the spirit of
[Orange Data Mining](https://orangedatamining.com), built entirely on
[SDSTK](../Downloads/SwiftSci) (Frame/Sci/Learn/Neural/Plot/Signal/Text/Optimize/TimeSeries/
Formulas/Graph). No Python, no server — a native SwiftUI app that is also the flagship
showcase of what SDSTK can do.

## 1. Core concept (Orange's model, kept)

- **Canvas**: an infinite pannable/zoomable surface. Widgets are dropped from a palette and
  wired together with links.
- **Widget** = one node. Declares typed **input ports** and **output ports** (e.g. `DataFrame`,
  `Model`, `[Double]`, `Figure`). A widget only runs once every required input is connected and
  populated.
- **Live dataflow**: changing an upstream widget's output (new file loaded, parameter tweaked)
  automatically re-runs every downstream widget that depends on it — no explicit "Run" step,
  matching Orange's feel. Long-running widgets (model training) show progress and don't block
  the canvas.
- **Workflow file**: the whole canvas (widgets, params, positions, links) is one document —
  `.sdstkflow` (JSON, `Codable`) — opened via a `DocumentGroup` so it behaves like a normal file
  on both platforms (Files app / Finder, iCloud Drive optional later).

## 2. Where this goes beyond Orange

Orange's widget set maps to numpy/pandas/scikit-learn/matplotlib plus opt-in add-ons. SDSTK
already covers that core (`Frame`/`Sci`/`Learn`/`Plot`) **and** several things Orange has no
native equivalent for, or only via a separate add-on:

| SDSTK module | Orange equivalent | Notes |
|---|---|---|
| `Frame`, `Sci`, `Learn`, `Plot` | core Orange (Data/Model/Evaluate/Visualize) | 1:1, this is the floor |
| `Neural` | — (Orange has no GPU training) | MLX-native MLP/CNN/RNN/LSTM training, real Metal GPU on iPad *and* Mac |
| `Signal` | — (no native signal-processing widgets) | FFT/STFT, filter design, peak detection, Welch PSD |
| `TimeSeries` | — (statsmodels via scripting only) | ACF/PACF, ARIMA, ETS forecasting as first-class widgets |
| `Text` | Text Mining add-on | TF-IDF/vectorization/cosine similarity, built-in not bolted-on |
| `Optimize` | — | expose curve-fitting (Levenberg-Marquardt) as a widget: fit a model form to (x,y) data |
| `Formulas` | — | a "scientific reference" widget: pick a domain equation, feed it columns as variables |
| `Graph` | Networks add-on | Dijkstra/A*/MST/topo-sort over a `DataFrame` edge list |
| Arrow/Parquet IO | Orange reads CSV natively, Parquet is clunkier | first-class File widgets for both |
| `.mlx`/`.cpu` backend toggle | — | a "Benchmark" widget that visibly runs the same op on both backends and plots the timing — literally demoing SDSTK's own engineering story |

This table **is** the widget catalog; each row becomes one or more widget categories in the
palette (Section 5).

## 3. Architecture

Follows the same pattern as `ModelBuilder`'s SwiftUI rebuild (xcodegen, single multiplatform
target, `supportedDestinations: [iOS, macOS]`) and `ModelCartography` (Swift 6 strict
concurrency). New project, generated via `project.yml`:

```
SDSTKStudio/
  project.yml
  Sources/
    App/            entry point, DocumentGroup, AppModel
    Canvas/          graph model, execution engine, link-drawing, pan/zoom
    Widgets/
      Data/          File(CSV/Arrow/Parquet), Data Table, Select Columns, Sampler, Merge, Save
      Transform/     Preprocess, Feature Constructor, Impute, Discretize
      Visualize/     Scatter, Box Plot, Distributions, Histogram, Heat Map, Line/Bar, Corr Matrix
      Model/         Linear/Logistic Regression, Trees, Forests, GBM, KMeans, PCA, Neural(MLP)
      Evaluate/      Test & Score, Confusion Matrix, ROC, Predictions
      Signal/        FFT/Spectrogram, Filter Design, Peak Finder
      Text/          Vectorizer, TF-IDF, Similarity
      TimeSeries/    Decompose, ACF/PACF, ARIMA/ETS Forecast
      Optimize/      Curve Fit
      Formulas/      Equation Evaluator
      Graph/         Shortest Path, MST, Components
    Rendering/       Swift Charts bridge + SDSTK `Plot` SVG bridge (export/print path)
    Persistence/      .sdstkflow Codable model, SwiftData workflow library (mirrors
                       ModelBuilder's SavedModel pattern for a "recent workflows" shelf)
  Resources/         assets, macOS entitlements
```

SDSTK modules are pulled in as **local SwiftPM package dependencies** (`.package(path:
"../Downloads/SwiftSci/Frame")` etc. — not vendored, not published) so Studio always builds
against the live SDSTK source tree next door.

### Execution engine

- Graph = widgets (nodes) + typed links (edges). Topological execution: a change to a node
  invalidates its output and everything reachable downstream (mark-and-sweep dirty flags, not
  full re-evaluation).
- Each widget's `run(inputs:) async throws -> Output` executes off the main actor; the canvas
  UI only observes published state (`.idle / .running / .done(Output) / .failed(Error)`).
  Widgets that wrap `Neural` training report incremental progress via an `AsyncStream`.
  Cancellation: changing a widget's params while it's running cancels the in-flight `Task`.
- Memoization: a widget doesn't re-run if neither its params nor its upstream outputs changed
  (hash params + upstream output identity) — this is what makes "live" feel instant for the
  common case (tweaking a downstream chart while upstream data is untouched).

### Widget protocol (sketch)

```swift
protocol Widget: Identifiable {
    associatedtype Params: Codable & Equatable
    associatedtype Output
    static var category: WidgetCategory { get }
    static var inputs: [PortSpec] { get }
    static var outputs: [PortSpec] { get }
    var params: Params { get set }
    func run(inputs: [AnyPort]) async throws -> Output
    associatedtype Body: View
    @ViewBuilder func inspector(params: Binding<Params>) -> Body   // parameter panel
    @ViewBuilder func preview(output: Output) -> AnyView           // node-face mini preview
}
```

A type-erased `AnyWidget` box + a registry (`WidgetCatalog`) drives the palette and
serialization (`type: "Model.LogisticRegression"` string key in the `.sdstkflow` JSON).

### Visualization strategy

Native **Swift Charts** for anything interactive on-canvas (scatter/bar/line/point-based
heatmap/box plot via custom marks) — gives real pinch-zoom/tooltip behavior on iPad for free.
SDSTK's `Plot` (headless SVG) is kept for **export/print/report** paths (Share Sheet → PDF/SVG),
not for the live on-canvas view. This is a deliberate two-renderer split, not redundancy: Swift
Charts for interaction, `Plot` for portable static output.

### Platform/RAM posture

Same lesson as `ModelBuilder`: Apple Silicon iPad can run real MLX training (unlike the earlier
rejected on-device-LLM idea, which was about model *size*, not the framework). Default dataset
size guardrails on `Neural`/large `Frame` ops on iPad (warn past N rows rather than hard-block),
Mac has no such ceiling. `Frame`'s `.cpu`/`.mlx` backend toggle is exposed as a per-workflow
setting, not hidden.

## 4. Workflow file format

`.sdstkflow` — JSON, roughly:

```json
{
  "widgets": [
    {"id": "w1", "type": "Data.CSVFile", "position": [120, 80], "params": {"path": "..."}},
    {"id": "w2", "type": "Visualize.ScatterPlot", "position": [420, 80], "params": {"x": "sepal_length", "y": "sepal_width"}}
  ],
  "links": [
    {"from": "w1", "fromPort": "table", "to": "w2", "toPort": "table"}
  ]
}
```

## 5. Phased roadmap

Each phase is independently demoable; later phases don't block earlier ones from shipping.

- **Phase 0 — Scaffolding. DONE.** `project.yml`, universal target, local package deps wired to
  SDSTK (`DataScience` + `Signal`/`Text`/`TimeSeries`/`Optimize`/`Formulas`/`Graph` added in
  Phase 7), canvas shell. Verified via a real `swift build` (macOS + iOS simulator both green —
  see the memory note on the scratch verify-package technique), not just `-typecheck`.
- **Phase 1 — Prove the loop. DONE.** `Data.CSVFile` → `Visualize.ScatterPlot` →
  `Model.LogisticRegression` → `Evaluate.TestAndScore`, live on the canvas.
- **Phase 2 — Data category. DONE (5 widgets).** `Data Table`, `Select Columns`, `Data Sampler`,
  `Impute` (drop-nulls / fill-mean), `Parquet File`. **Cut from scope:** Merge/Join, a separate
  Discretize widget, an explicit "Save Data" widget (files are exported via the document itself,
  not per-widget) — none built, not stubbed.
- **Phase 3 — Visualize category. DONE (5 widgets incl. Phase 1's Scatter Plot).** Histogram,
  Bar Chart, Box Plot, Correlation Heatmap — all native Swift Charts marks (`RectangleMark`
  heatmap, `RuleMark`+`RectangleMark` box plot). `ChartData` became an enum (`points`/`bars`/
  `heatmap`/`box`) to carry all four shapes through one port kind.
- **Phase 4 — Model category. DONE (5 widgets).** Logistic Regression (Phase 1), Decision Tree
  Classifier, Random Forest Classifier, Linear Regression, Decision Tree Regressor.
  `LearnerSpec` split into `ClassifierSpec`/`RegressorSpec` with distinct port kinds so a
  regressor can't be wired into a classifier's evaluate slot by mistake. **Cut from scope:**
  Gradient Boosting widget (the `Learn` API exists, just no widget yet), Neural/MLP widget
  (deferred — needs the same `mlx.metallib` bundling prerequisite as Phase 9), a generic
  Pipeline-chaining widget.
- **Phase 5 — Evaluate category. DONE (2 widgets).** `Test & Score` (classifier, Phase 1) +
  `Test & Score (Regressor)` (R² scoring). **Cut from scope:** Confusion Matrix, ROC Analysis,
  a standalone Predictions table — Test & Score's cross-validated summary covers the "does this
  model work" question; per-row prediction inspection is future work.
- **Phase 6 — Unsupervised. DONE (2 widgets).** `k-Means` (fits + labels inline, no separate
  evaluate step — matches Orange's own widget, since clustering has no ground truth to defer
  to), `PCA` (appends PC1..PCn columns, keeps originals so you can still facet by them).
  **Cut from scope:** a standalone Distance Matrix widget, hierarchical clustering (not present
  in `Learn` — confirmed by reading `Clustering.swift`, not assumed).
- **Phase 7 — Beyond-Orange showcase. DONE (6 widgets, one per module).** `Signal` → FFT
  magnitude spectrum; `Text` → TF-IDF cosine-similarity heatmap (30-row cap for heatmap
  readability, logged not silent); `TimeSeries` → autocorrelation bar chart; `Optimize` → Levenberg-
  Marquardt curve fit (linear/quadratic/exponential forms) with R² in the summary; `Formulas` →
  projectile-range-vs-angle sweep (no data input, pure equation demo); `Graph` → Dijkstra shortest
  path over a from/to/weight edge-list table (display-only, zero output ports — first widget to
  use the new `PortValue.none` sink case).
- **Phase 8 — Polish. DONE (4 of 5 items).** Palette search (`.searchable`), full undo/redo for
  add/delete-node (mutually-recursive `performInsert`/`performDelete` so toggling works any
  number of times, not just one level), a bundled real 150-row Iris dataset as a zero-config
  `Data.IrisExample` widget (own instead of retrofitting `CSVFileWidget` for bundled-resource
  access), SVG export via `ShareLink` bridging `ChartData` → SDSTK's `Plot.Figure` → temp file
  (only for `.points`/`.bars` shapes — `Figure` has no heatmap/box mark, so those chart types
  correctly have no export button rather than a fake one). **Not built:** a SwiftData "recent
  workflows" shelf (`DocumentGroup`'s own Open Recent covers the common case; a full library
  mirroring `ModelBuilder`'s `SavedModel` pattern was judged not worth the added surface yet).
- **Phase 9 — Stretch. DONE.** `Data.Benchmark`: times `Column` construct+sum on `.cpu` vs
  `.mlx` over a synthetic row count (default 500K — large enough for a real gap, unlike any
  bundled example dataset), charted as a bar comparison. Ships with an **automatic
  `mlx.metallib` installer**: `Scripts/fetch-mlx-metallib.sh`, wired in as a `postbuildScripts`
  entry in `project.yml`, fetches the version-matched prebuilt shader library from the
  `mlx-metal` PyPI wheel (version pinned to the *bundled MLX core* version from mlx-swift's
  `version.h`, 0.31.1 — NOT the outer mlx-swift package tag, which can differ) and copies it
  next to the built binary automatically on every Xcode build. Non-fatal if network/python
  aren't available at build time — degrades to the widget showing a clear in-app message
  instead of ever touching the GPU path.

  **Found and fixed a real app-wide bug while scoping this:** `Frame` defaults to the `.mlx`
  backend (not `.cpu`), and MLX's C++ scheduler hard-exits the process — not a catchable Swift
  error — the moment anything touches it without `mlx.metallib` present. That meant *every* one
  of the other 26 widgets was silently exposed to a crash-on-first-use risk before this pass,
  since none of them ever set a backend explicitly. Fixed by setting `FrameConfig.backend =
  .cpu` in `SDSTKStudioApp.init()` — now `Data.Benchmark` is the *only* code path in the app
  that ever touches `.mlx`, and it does so guarded by an explicit `mlx.metallib`-presence check
  (`Bundle.main.executableURL`'s directory — MLX's own search location) before ever setting the
  backend, so a failed/skipped auto-fetch degrades gracefully instead of crashing.

  **This is empirically verified, not just reasoned about:** built a disposable throwaway
  SwiftPM executable in the scratchpad that mirrors the exact backend-switching code, and ran it
  for real (not just compiled) — confirmed (a) touching `.mlx` without `mlx.metallib` present
  exits with code 255 and a clear MLX-printed error, never a silent crash; (b) fetching
  `mlx.metallib` via the identical mechanism the build script uses and placing it next to the
  binary makes the exact same code path succeed with the correct computed result; (c) the
  `.cpu`-only path never touches MLX at all regardless. This is the strongest verification any
  phase of this app has gotten so far, because it's the only one where actually *running* the
  built binary (not just compiling it) was possible and safe to do in this VM.

## 6. Explicit non-goals (v1)

- No Python-script widget (Orange has one; out of scope — the point is an all-Swift stack).
- No multi-user/collaborative editing.
- No add-on marketplace/plugin loading — the "add-ons" are just more built-in widget
  categories, since SDSTK is one codebase we control.
- No distributed/out-of-core data (SDSTK's `Frame` is in-memory, same ceiling Orange itself has).

## 7. Verification approach

`xcodebuild` is broken in this VM (see `[[modelbuilder-rebuild-architecture]]`,
`[[model-cartography-project]]` memories) — every phase gets verified here via
`swiftc -typecheck` per-platform SDK plus a headless CLI harness exercising the execution engine
and each new widget's `run()` against SDSTK APIs directly (no UI). Real `.app` builds, on-device
behavior, and actual UI/interaction testing happen in the user's own Xcode — call that out
explicitly rather than claiming a build "works" from typecheck alone.

## 8. Open questions for the user (before Phase 0 starts)

1. ~~Should the very first Phase 1 demo target a bundled sample dataset...~~ **Resolved:**
   `Data.IrisExampleWidget` (Phase 8) bundles the real Iris dataset.
2. ~~Icon/branding direction...~~ **Resolved (2026-07-17):** user chose a distinct identity over
   reusing SDSTK's own grid-mark palette — see §9 below.
3. Confirm local-package-dependency approach (pointing at `../Downloads/SwiftSci/<Module>`) is
   acceptable, vs. vendoring copies into this repo for independence from that other project.
   **Still open.**

## 9. App icon

Node-graph mark, deliberately distinct from SDSTK's own orange→magenta grid logo (chosen over
reusing that palette or an Orange-Data-Mining-citrus homage) — signals "the app," not "the
library." Four orb-style nodes in the exact `PortDot` colors used on the live canvas
(`Sources/Canvas/NodeView.swift`: systemBlue/systemGreen/systemPurple/systemOrange) connected in
a loop by the same bezier-curve language `LinkView` draws, on a dark indigo/slate gradient.
Two renders from one shared design (`Resources/AppIconSource/icon-{ios,macos}.svg`, source of
truth — edit these, not the PNGs):
- **iOS** (`icon-ios-1024.png`): full-bleed 1024×1024, no alpha (App Store requires none), no
  rounding baked in — the OS applies its own squircle mask.
- **macOS** (`icon-macos-1024.png`): Big Sur-style rounded square inset ~100px into the 1024
  canvas (`rx="182"`), drop shadow, transparent surround — macOS does NOT auto-mask, so the
  shape must already be baked into the artwork.

Rasterized via `rsvg-convert` (available in this environment; regenerate with the same tool if
the source SVGs change: `rsvg-convert -w 1024 -h 1024 <svg> -o <png>`). Both confirmed legible
at small sizes (checked down to 64×64) before finalizing — the four-color 2×2 arrangement holds
up even when the connecting curves nearly disappear.

## 10. Parity pass — closing gaps against real Orange usage

After Phase 9, asked "what's still missing for parity" and then asked to close the gaps,
ordered most-useful-to-most-complex. **9 widgets added, 37 total now** (54 Swift files):

- **Data (+7):** `Normalize` (wraps `Learn`'s already-existing `StandardScaler`/`MinMaxScaler` —
  built for `Learn.Pipeline`, had no widget yet), `Data Info` (schema/dtype/null/mean-std
  summary), `Save Data` (writes CSV to a temp file, offered via `ShareLink` — Save to Files,
  AirDrop, etc., no custom file-picker plumbing needed), `Feature Constructor` (new column via
  `columnA <op> (columnB | constant)` — deliberately scoped to `Column`'s existing `+-*/`
  overloads, not a new formula-expression parser), `Merge Data` / `Data.Concatenate` (two-table
  join on a shared key via `Frame.join(on:how:)`), `Outlier Detection` (z-score flagging, appends
  an `IsOutlier` column rather than dropping rows).
- **Visualize (+2):** `Rank` (|Pearson correlation| of every other numeric column against a
  chosen target, sorted descending), reusing `Correlation Heatmap`'s existing pattern.
- **Model (+1):** `Gradient Boosting (Regressor)` — `Learn.GradientBoostingRegressor` already
  existed (SDSTK's own benchmarks used it) but had no canvas widget; added a `.gradientBoosting`
  case to `RegressorSpec`.
- **Evaluate (+1):** `Confusion Matrix` — first widget to actually fit-and-predict on a
  real held-out split rather than just reporting `crossValScore`'s aggregate; shuffles/splits
  manually (`Learn`'s public `trainTestSplit` is Regressor-only, so this reuses the
  `SeededGenerator` RNG already written for `Data.Sampler`) and renders `Metrics.confusionMatrix`
  as a heatmap.

**A real cross-module Codable gotcha, caught before it shipped:** `Data.Concatenate`'s join-type
picker first tried `extension JoinKind: Codable, CaseIterable {}` — retroactively conforming
`Frame`'s `JoinKind` enum from the *Studio* module. Reasoned through it rather than assuming:
Swift's automatic Codable synthesis isn't guaranteed for a conformance declared outside the
defining module, even for a plain `String`-raw-value enum. Fixed with a small local
`ConcatenateWidget.HowOption` mirror enum instead, mapped to `JoinKind` only at the `run()` call
site — the safe, guaranteed-correct pattern for any future case of "I want to add Codable to a
type from a dependency."

**Also fixed while adding the first two-input-port widget:** `CanvasView.completeLink`'s
drag-to-connect hit-test picked the *first* input port within range, in declaration order — fine
when every widget had at most one port per `PortKind`, but `Data.Concatenate`'s "left"/"right"
ports (22pt apart, 26pt hit radius) could get the wrong one near the boundary. Changed to pick
the *nearest* match within range instead — a real latent bug, not hypothetical, since nothing
before this had two same-kind input ports to expose it.

**Explicitly deferred, with reasons (not silently dropped):**
- **Interactive selection propagation** (click/lasso a Scatter Plot → filter downstream) — the
  single biggest remaining gap, but it's a new data-flow *concept* across the whole port system
  (a selection mask riding alongside `.table`, new chart-interaction gestures, every consuming
  widget needing to know what to do with it), not "one more widget." Deserves its own dedicated
  design pass, not a bolt-on at the end of this one.
- **Neural (MLP) widget** — Neural isn't wired as a project dependency yet, and unlike the other
  "beyond Orange" modules it's MLX-only with no CPU fallback, so it inherits the same
  `mlx.metallib` guard-before-touch requirement as `Data.Benchmark`, plus needs an async
  progress-reporting design for training that nothing else in the app has needed yet.
- **Naive Bayes / SVM / k-Nearest Neighbors** — none exist in `Learn` at all currently; adding
  them means changing SDSTK itself, a different project, not something to do silently as a side
  effect of a Studio feature request.
- **Hierarchical Clustering / DBSCAN** — same reason: not in `Learn.Clustering` (confirmed by
  reading the file, not assumed).
- **ROC Analysis, Lift/Calibration curves, a per-row Predictions table** — `Confusion Matrix`
  covers the highest-value gap in Evaluate; these are further additions to the same category,
  not attempted this pass.
- **Report/canvas annotations, pinch-zoom** — unchanged from earlier phases' deferrals.

Verified the same way as every other phase: the scratch `verify-sdstkstudio` package, real
`swift build` for both macOS and iOS simulator, zero errors on both after these 9 widgets.

## 11. First real-user feedback pass — examples, onboarding, visual polish

After the user's first actual launch: the file-open prompt on launch was expected `DocumentGroup`
behavior (confirmed, not a bug — same as Pages/Keynote), but "not easy to understand, need
examples" and "Orange is visually appealing" were real, valid gaps. Addressed:

- **3 bundled example workflows** (`Resources/Examples/01-Classify-Iris.sdstkflow`,
  `02-Explore-Data.sdstkflow`, `03-Regression-Demo.sdstkflow`) — fully wired, pre-configured
  pipelines using the bundled Iris data, opened via a new **Examples toolbar menu** in
  `CanvasView`. Generated with a throwaway Swift script (not hand-written JSON — `params` fields
  are base64-encoded inside the outer JSON per `Data`'s default `JSONEncoder` strategy, too
  fragile to author by hand) and round-trip-verified against the app's own real
  `WorkflowDocumentData` type before use, not just assumed correct.
- **A real API dead-end found and fixed:** first tried `@Environment(\.newDocument)` to open
  each example as an in-memory `WorkflowDocument` directly — `NewDocumentAction.callAsFunction`
  requires `D: FileDocument` (confirmed via compiler error), and `WorkflowDocument` is a
  `ReferenceFileDocument` (reference type, deliberately — see the Phase 1 concurrency section).
  **Fixed** by going through a real file instead: `WorkflowDocument.exampleFileURL(named:)`
  copies the bundled example into the user's Documents/Examples folder (once), then
  `@Environment(\.openURL)` hands it to the OS — which routes back into our own app since we're
  the registered handler for `.sdstkFlow`, i.e. exactly what "File > Open" already does. Simpler
  and more correct than the in-process approach would have been anyway.
- **`GettingStartedView`** — a 4-step "add a widget / wire it up / configure it / or open an
  example" sheet, shown automatically on first launch (`@AppStorage("hasSeenGettingStarted")`)
  and anytime via a toolbar "?" button.
- **Category color-coding**: `WidgetCategory.color` (one accent per category — gold/pink/green/
  orange/purple/teal/indigo/mint/brown/cyan/blue), applied to each node's icon badge, a colored
  top accent stripe on the card, and the palette's section headers — directly answering "Orange
  is visually appealing," since color-coded categories are a big part of why Orange's canvas
  reads at a glance instead of being a wall of identical boxes.
- **`CanvasGridBackground`** — a subtle dot-grid behind the nodes (drawn via SwiftUI `Canvas`,
  `.allowsHitTesting(false)`) so the surface reads as an actual workspace.

**Icon still not resolved as of this pass** — regenerated as the full classic macOS multi-size
set (16 through 1024, 7 distinct pixel sizes) since the single-1024-image shortcut (confirmed
reliable for iOS) was suspect for being new/untested for Mac in this exact Xcode version, but the
user reported it was STILL blank after that fix too. Root cause genuinely unconfirmed — could be
Xcode/macOS icon-cache staleness (very common for freshly-built dev apps, often needs a
relaunch/logout to clear) or something this environment truly can't reproduce. **Don't assume
resolved** — next report from the user is the only way to know.

Verified via the same scratch-package technique: real `swift build` for macOS + iOS simulator,
zero errors both, after the examples/onboarding/color additions (icon changes don't touch Swift
compilation so weren't re-verified this way — there's nothing for `swift build` to check there).

## 12. Connecting nodes was actually broken — root cause + fix

User reported dragging CSV File → Data Table wouldn't connect. **Real bug, found by reading
`NodeView.swift`, not gesture-tuning guesswork:** the port dots' own `.position(x: node.position.x
+ offset.x, ...)` was nested *inside* the same `ZStack` that `body` already moves into canvas
space via `.position(node.position)` — double-applying `node.position`, so every dot rendered at
roughly `2×node.position + offset` (worse the farther a node sits from canvas origin — i.e.
every real node). `CanvasView.completeLink`'s hit-test, meanwhile, correctly checks
`node.position + offset` with no doubling — so the user was always dragging to/from wherever the
*mis-rendered* dot sat, which could never coincide with what the hit-test was actually checking.
Both ends of every drag were affected identically, so no connection could ever succeed — not an
edge case. **Fixed:** dots now position at `(nodeWidth/2 + offset.x, height/2 + offset.y)` —
anchored to the ZStack's own local center, letting the one outer `.position()` do the only
canvas-space translation. Now matches `CanvasView.portPosition`'s formula exactly. Verified via
`swift build` (can't runtime-test drag gestures from this VM) — **not yet confirmed by the user.**

## 13. Demo flow per component — showing off speed and breadth

Asked for "a demo flow for each component, to show the speed and ability of SDSTK." Before this,
only Data/Visualize/Model/Evaluate had a demo (all via Iris) — Unsupervised, Signal, Text,
TimeSeries, Optimize, Formulas, and Graph had none, and nothing demonstrated raw *speed*
specifically. Closed every gap:

**3 new bundled data-source widgets**, each purpose-built for a demo that had no suitable
existing data:
- `Data.SyntheticSignal` — generates sine/quadratic/exponential (x,y) data, up to 1M rows,
  configurable noise. Feeds Signal, TimeSeries, *and* Optimize demos from one widget (not three
  bespoke generators) — a sine wave has both a clean FFT peak and clear autocorrelation
  structure, so it does double duty.
- `Data.TextSample` — 15 bundled short sentences across tech/sports/cooking topics (with a
  `topic` label column) so `Text.Similarity`'s heatmap groups by recognizable topic rather than
  bare row indices.
- `Data.RouteExample` — 9 US cities, 15 routes (miles), built with genuinely multiple paths
  between distant pairs so `Graph.ShortestPath` has a real choice to make, not one obvious route.

**8 new example workflows** (bringing the total to 11, one per category plus the speed story):
`Unsupervised Clustering` (Iris → KMeans → PCA → Scatter, chaining two unsupervised techniques),
`Signal FFT Demo`, `Time Series Autocorrelation`, `Optimize Curve Fit` (recovers the true
quadratic from noisy synthetic data), `Text Similarity`, `Graph Shortest Path` (San Francisco →
New York), `Formulas: Physics` (the existing projectile-range widget, just needed a one-click
entry), and **`Speed Benchmark (CPU vs GPU)`** — `Data.Benchmark` pre-configured to 2,000,000
rows specifically to make the `.cpu`/`.mlx` timing gap dramatic on open, directly answering the
"show the speed" half of the ask.

Generated and round-trip-verified the same way as the first 3 examples (throwaway Swift script,
then decoded with the app's own real `WorkflowDocumentData` type before trusting them). Verified
via the scratch-package technique: `swift build`, macOS + iOS simulator, zero errors both.

## 14. Experts category — compound orchestration (Core ML Expert, Coordinator, `.mbexpert`)

After a long design conversation (in `ModelBuilder`'s session, not this one) about building a
compound "mixture of experts"-style system — independently-trained narrow Core ML models wired
into an orchestration graph, coordinated by a combiner node, eventually exposed to external LLM
agents as an MCP tool — the conclusion was that this belongs here, not in `ModelBuilder`:
`ModelBuilder` stays a single-model-at-a-time trainer/tester, and this app already has exactly
the node/port/link/execution-engine primitives the orchestration idea needs. `ModelBuilder`
produces the individual experts (`.mlpackage`/`.mlmodel` files); Studio composes them.

**2 new widgets, 1 new category, 1 new document format:**

- **`Experts.CoreMLExpert`** — loads an externally-trained Core ML model (e.g. exported from
  ModelBuilder's Library) via the same security-scoped-bookmark file-picker pattern as every
  other `Data.*File` widget. Input port `.image`, output port `.prediction`. Runs inference via
  `Vision`'s `VNCoreMLRequest` (handles image resizing/pixel-buffer prep automatically, and
  handles both classifier-shaped `[VNClassificationObservation]` and regressor-shaped
  `[VNCoreMLFeatureValueObservation]` output). Compiling a raw `.mlmodel`/`.mlpackage`
  (`MLModel.compileModel(at:)`) is a real, sometimes-slow blocking call, and — like every
  `StudioWidget` — `run()` executes on the main actor (see `StudioWidget.swift`'s concurrency
  note); the compiled `VNCoreMLModel` is cached after first load so only a freshly-picked model
  pays that cost, not every re-run.
- **`Experts.Coordinator`** — combines exactly two upstream `.prediction` inputs (`expertA`/
  `expertB`, expert A's weight fixed at 1.0, B adjustable) via either "highest confidence wins"
  or "weighted average" (numeric-value experts only; a classifier-shaped expert with no `value`
  is skipped, not coerced). Echoes the original Jacobs & Jordan (1991) mixture-of-experts gating
  network — a combiner over independent experts' outputs — not the routing-inside-one-network
  kind of MoE transformer LLMs use.
- **`Data.ImageFile`** — new Data-category source (`CGImage` via `ImageIO`, same bookmark
  pattern) since nothing existing carried an image onto the canvas.
- **`PortKind`/`PortValue`**: `.image(CGImage)` and `.prediction(ExpertPrediction)` — the latter
  a small struct (`label`/`confidence`/`value`/`sourceName`) scoped to exactly what
  ModelBuilder's two working trainers produce (image classifier, tabular regressor), not a
  speculative generic schema.
- **`.mbexpert` document format** — a directory bundle (same mechanism `.rtfd`/`.pages` use,
  registered as a second `UTType` alongside `.sdstkflow`, `conformingTo: .package`) containing
  `graph.json` (the existing `WorkflowDocumentData` JSON) plus an `Experts/` folder with a copy
  of every `CoreMLExpert` node's model file, keyed by node ID
  (`"<node-id>.<ext>"`). Not a new binary model format — every embedded model stays a plain
  `.mlmodel`/`.mlpackage`; only the bundle is new. Solves the actual problem with the bookmark-
  only approach: a `.sdstkflow` graph referencing a Core ML Expert is only as portable as the
  security-scoped bookmark to wherever the model file happened to live, which breaks if the
  graph moves to another machine or the source file moves/deletes. On open, embedded models are
  copied out to Application Support (mirrors `ModelBuilder`'s own `ModelStore` pattern — Core ML
  needs a real on-disk URL to compile/load from, it can't load straight out of an in-memory
  `FileWrapper`) and each `CoreMLExpertWidget` rebinds to its own local copy.

**Explicitly deferred, with reasons:**
- **More than 2 experts into one Coordinator, or making an expert input optional** —
  `WorkflowGraph.gatherInputs` requires every declared input port to be linked before a widget
  can run at all; there's no concept of an optional port. Supporting either needs an
  engine-level change to that contract, not just another `PortSpec` entry — a distinct design
  problem, same category as the already-deferred "interactive selection propagation."
- **A `.table`-in variant of `CoreMLExpert`** for tabular regressors (ModelBuilder's other
  working trainer) — the image-in case covers the immediate demo; a table-in port kind is a
  natural follow-up, not attempted this pass.
- **Research-expert (LLM + search tool) node, mem-stacker/bucket-of-unknowns (active-learning
  driven expert growth), MCP server wrapper exposing a loaded graph as a callable tool** — each
  is its own design problem (a network-calling non-deterministic node inside a deterministic
  memoized engine; continual-learning/novelty-detection territory with real failure modes if
  fully autonomous; a separate server process, not a SwiftUI-app feature) — tracked, not started.

**Verified three ways**, escalating from typecheck to actually running the new logic (same
standard as Phase 9's MLX-backend investigation, the most rigorous prior verification this app
had gotten):
1. Real `swift build` via the scratch-package technique — caught one genuine integration bug
   (`NodeView.swift`'s `PortDot.color` switch wasn't exhaustive for the two new port kinds).
2. A throwaway executable target (not just a library) in the same scratch package, actually
   *running* `CoordinatorWidget.run()` against synthetic `ExpertPrediction` inputs — confirmed
   highest-confidence-wins, weight-adjustable tie-breaking, weighted-average arithmetic, and
   that a classifier-shaped expert is correctly skipped (not crashed on) in the weighted-average
   path.
3. A real `.mbexpert` export→reopen round trip against the actual `WorkflowDocument` code (not
   a hand-rolled reimplementation) — required a small refactor first: `init(configuration:)` and
   `fileWrapper(snapshot:configuration:)`'s bodies moved into `WorkflowDocument.load(from:)` /
   `makeFileWrapper(from:asBundle:)`, callable without SwiftUI's `ReadConfiguration`/
   `WriteConfiguration` (both framework-constructed only, no public initializer — confirmed via
   a real compiler error, not assumed). This run caught a second genuine bug: capturing the
   non-`Sendable` `FileWrapper` itself into the `MainActor.assumeIsolated` closure (rather than
   extracting its `Sendable`-safe `Data`/`Bool` contents first) tripped Swift's data-race
   checker — a real bug, not a false positive, fixed by restructuring `load(from:)` to read
   everything it needs from `file` *before* crossing onto the main actor.

iOS-simulator cross-compilation of the scratch package (raw `swift build -Xswiftc -sdk/-target`)
hit a pre-existing sysroot/UIKit resolution problem in this environment unrelated to these
changes (every file failed identically, including untouched ones) — consistent with `xcodebuild`
already being broken here. Not fought further: `CoreML`/`Vision`/`ImageIO` are identical APIs on
both platforms, and nothing new is platform-conditional beyond the existing bookmark pattern
already used elsewhere. Real device/simulator behavior still needs the user's own Xcode, per
this file's standing verification caveat.

**Addendum — `Experts.CoreMLTabularExpert` (the `.table`-in expert deferred above):**

- New widget, table-in / `.prediction`-out, for ModelBuilder's other working trainer (Create ML
  tabular regression). Takes one row (`rowIndex`, user-selectable) from the incoming table as one
  instance's feature values — bulk dataset evaluation is a different job `Evaluate.TestAndScore`
  already covers. Feature columns are auto-matched to the loaded model's declared input names
  (`MLModelDescription.inputDescriptionsByName`) rather than a manual mapping UI, since Create ML
  training preserves the original CSV column names through to the model's input schema; a column
  the model expects but the table doesn't have throws a specific named error rather than guessing.
- **Real refactor, not scope creep:** with a second widget now needing the identical bookmark
  dance and export/rebind contract, extracted `ModelFileBookmark` (a plain `Codable` value —
  `setFile`/`rebind`/`withResolvedURL`/`stageForExport`) and an `ExportsEmbeddedModel` protocol
  into `Sources/Widgets/Experts/ExpertSupport.swift`. Retrofitted `CoreMLExpertWidget` onto both
  rather than leaving one widget on the old inline implementation and one on the new shared one.
  `WorkflowDocument`'s `.mbexpert` export/import now check `as? ExportsEmbeddedModel`, not the
  concrete `CoreMLExpertWidget` type — a third expert shape won't need changes there either.
- **A real, SDK-specific concurrency bug found and fixed, not a hypothetical:** on macOS in this
  SDK (confirmed by reading `CoreML.swiftmodule`'s actual `.swiftinterface`, not assumed),
  `MLModel.prediction` only exists as the `async` overload — the synchronous
  `prediction(fromFeatures:options:)` is explicitly `@available(macOS, unavailable)`. Since the
  loaded `MLModel` lives in `@MainActor`-isolated widget state (non-`Sendable`), awaiting that
  nonisolated async call tripped Swift's sending-risk data-race check even though nothing else
  ever holds a reference to it concurrently. Fixed with `nonisolated(unsafe) let` on that one
  local binding — the sanctioned escape hatch for a non-`Sendable` framework type used safely in
  a single-owner pattern the compiler can't itself prove.
- Verified the same three ways as the rest of this phase: real `swift build` (caught the async/
  Sendable issue above), the same functional-check executable re-run clean after the
  `CoreMLExpertWidget` refactor (confirming the retrofit changed no observable behavior), zero
  errors on a full from-scratch rebuild.

**Addendum — `Experts.ResearchExpert` (scoped-down v1 of the deferred "research-expert" node):**

Picked as the "next easiest" of the three fully-deferred items (research-expert, mem-stacker,
MCP wrapper) by scoping it down hard: plain on-device text generation only, no search/tool-use —
that half is real, separate work (network access from a graph node; what a search result even
*is* as a `PortValue`) kept explicitly deferred rather than half-built.

- **`Data.TextPrompt`** — a bare multi-line text source (`TextEditor` in the inspector, no input
  ports, outputs the new `.text(String)` port kind). Nothing existing carried a plain string onto
  the canvas — `Data.TextSample`/`Text.Similarity` work over `.table` (many rows), not one string.
- **`Experts.ResearchExpert`** — wraps Apple's on-device Foundation Model
  (`FoundationModels.LanguageModelSession`, macOS/iOS 26+ — exactly this project's deployment
  target). `.text`-in (the prompt) / `.text`-out (the response), an optional instructions field.
  Checks `SystemLanguageModel.default.availability` before running and throws a clear,
  specific error rather than assuming the model is present (Apple Intelligence isn't guaranteed
  enabled on every device).
- **`PortKind`/`PortValue.text(String)`** — the third payload type after `.image`/`.prediction`,
  generically useful for any future text-in/text-out node, not just this one.
- **Real API confirmed by reading the actual `.swiftinterface`, not guessed:**
  `LanguageModelSession(model:tools:instructions:)`, `session.respond(to: String) async throws ->
  Response<String>` (`response.content`), `SystemLanguageModel.Availability` (`.available` /
  `.unavailable(UnavailableReason)`). `respond` is `nonisolated(nonsending)` — stays on the
  caller's actor rather than hopping off — so, unlike the tabular expert's `MLModel.prediction`,
  calling it from this `@MainActor`-isolated widget needed no `nonisolated(unsafe)` workaround;
  confirmed by it actually compiling clean, not assumed from the attribute name alone.
- **Verified by actually running it, and it actually worked:** this VM turned out to have Apple
  Intelligence enabled, so the functional-check executable's `checkResearchExpert()` exercised
  genuine on-device generation end-to-end through the real widget code (prompt "Say hello in
  exactly one word." → real model response), not just the unavailable-model error path it was
  written to also handle gracefully if the model weren't present.

**Explicitly still deferred:** live web search / tool-calling for this node (a distinct, scoped
piece of work — `LanguageModelSession`'s `tools:` parameter is the real hook, once there's a
design for what a search tool's result looks like as a port value), the mem-stacker/
bucket-of-unknowns node — unchanged from the phase above. The MCP server wrapper is done; see
below.

## 15. `MBExpertServer` — MCP wrapper exposing an `.mbexpert` bundle as a callable tool

A new, separate top-level package — `MBExpertServer/` (own `Package.swift`, no dependency on
`SDSTKStudio`'s own sources or targets). Deliberate: making the app's Canvas/Widgets code
reusable by a second consumer would mean restructuring it into a shared library target, a bigger,
riskier change to code that already ships, for a feature that's additive. A standalone process
that re-parses the (self-designed, already-documented) `.mbexpert` JSON shape directly is the
lower-risk shape for a v1 — some duplicated inference logic against a from-scratch reimplemented
graph reader, in exchange for zero touch to the existing app.

**What it does:** loads an `.mbexpert` bundle given on the command line, and — v1 scope,
deliberately narrow — requires it to contain exactly one `Experts.CoreMLExpert` node (no
coordinator, no chain; multi-node graphs are the natural next step once this shape is proven).
Serves MCP (Model Context Protocol) requests over stdio until stdin closes: `initialize` →
`tools/list` (one tool, name derived from the expert's name in Studio) → `tools/call` (takes
`image_path`, runs the same Vision/Core ML inference `CoreMLExpertWidget` does, returns the
prediction as JSON text content).

**Hand-rolled JSON-RPC, not an SDK dependency** — this environment can't reliably reach a remote
package registry, and the wire protocol itself is small enough not to need one: newline-delimited
JSON-RPC 2.0 objects on stdin/stdout, three methods plus one notification. Built on
`JSONSerialization`'s loosely-typed `[String: Any]` rather than `Codable`, since JSON-RPC's `id`
can legitimately be a number, string, or `null` — a dynamic shape `Codable`'s static typing fights
more than it helps for a hand-rolled layer this small.

**Verified by actually spawning the built binary and piping real JSON-RPC lines at it** (not
just compiling): generated a genuine `.mbexpert` bundle via the app's own real export code (the
scratch functional-check package, writing the resulting `FileWrapper` to a real path instead of
just inspecting it in-memory), then ran the compiled `MBExpertServer` against it with real stdin
input, reading real stdout. Confirmed: a correct `initialize`/`tools/list` handshake; a
missing-image-file error surfaces as a clean MCP tool error (`isError: true`), not a crash; an
unknown tool name, a missing required argument, and an unknown method all return correct
JSON-RPC error objects; malformed input (not valid JSON at all) returns a `-32700 Parse error`
with `id: null`, per spec, without taking down the process. Also ran `tools/call` against a real
decodable image and the bundle's (deliberately dummy, non-model) embedded file — got a real Core
ML parse error surfaced cleanly through the same error path, confirming the failure mode that
*will* happen with a real trained model works exactly like the ones already tested. **Not
verified:** actual inference against a genuine trained Core ML model — none was available in this
environment; the inference code itself is the same logic already reasoned through and compiled
for `CoreMLExpertWidget`, just not exercised end-to-end with real weights here.

**Explicitly deferred:** multi-node graphs (coordinator + multiple experts as one tool, or one
tool per expert), the tabular expert case, and connecting this to an actual MCP client (Cline,
Claude Desktop) for a real interactive test — this phase proves the protocol and bundle-loading
plumbing work, not that a specific external client is happy with it yet.

## 16. `Experts.MemStacker` — the last deferred item, now built

The active-learning-driven expert-growth node from the original design conversation, scoped down
to a single trigger→review→promote loop (per that conversation's own conclusion: no autonomous
graph rewriting, a human stays in the loop for labeling — but **auto-train, not auto-add-to-
canvas**, once a label crosses its threshold, per explicit direction).

**Trigger logic — refined against real technique, not just "low confidence":**
- **Margin, not raw confidence, is the primary signal** — Chow's rule (1970) is the classical
  reference for a confidence-threshold reject option; margin sampling (top-1 minus runner-up
  confidence — standard in active-learning uncertainty sampling, e.g. Settles' 2009 survey) is
  the stronger uncertainty signal in practice, since a model can be genuinely confident and still
  wrong, but a thin margin over the runner-up reliably flags an ambiguous case. `ExpertPrediction`
  gained a `runnerUpConfidence: Double?` field (populated from `VNClassificationObservation`'s
  second-ranked result) and an `isEmpty` computed property for the null/error case.
- **A real semantic change to both Core ML expert widgets, not additive-only:**
  `CoreMLExpertWidget`/`CoreMLTabularExpertWidget`'s "model produced no usable output" case used
  to `throw`. It now returns a sentinel empty `ExpertPrediction` instead. Reasoning: the current
  engine (`WorkflowGraph.gatherInputs`) requires every upstream node to reach `.done` before a
  downstream node runs at all — a thrown error leaves the node `.failed` and `MemStacker`
  downstream never runs, so it could never see (and route) the null case the design explicitly
  asked for. Genuine failures (bad model file, undecodable image, compile error) still throw and
  correctly halt the graph — only "ran successfully, produced nothing usable" changed from
  exception to data.

**Storage layout** (Application Support, mirroring `ModelStore`'s own "copy into app-owned
storage, independent of source" pattern): `MemStacker/<node-id>/{Unknown, Staging/<label>,
TrainedExperts}/`. `<node-id>` is a `UUID` generated once at first creation and persisted in the
widget's own `Params` — not a fresh `UUID()` per instantiation, which would silently give a
reopened saved workflow a *different* (empty) storage folder every time and quietly lose all
prior review progress.

**The workflow, exactly as specified:** low confidence / thin margin / null output → filed into
`Unknown/` as a PNG. A human reviews one at a time in the node's inspector (image preview, label
field, "Label & File" / "Skip") — moved into `Staging/<label>/`, created if it doesn't exist yet.
**Auto-train, not human-gated:** once a label's folder reaches `promotionCount` (default 20)
*and* at least one other label is also staged (`FullyConnectedNetworkClassifier` needs ≥2 classes
to mean anything — so the retrain always runs over the *whole* staging root, not just the label
that just crossed the threshold), a background `Task` retrains automatically. Reuses
`CoreMLExpertWidget`'s already-established `onChange` callback convention to notify the
inspector when a detached background task (training) finishes — nothing in this app needed that
before (`PLAN.md`'s own Neural/MLP deferral flagged exactly this gap), solved narrowly for this
one case rather than building a general async-progress system speculatively.

**`OnDeviceExpertTrainer`** — a new, small, standalone reimplementation of ModelBuilder's own
`OnDeviceTrainer` (`ImageFeaturePrint` + `FullyConnectedNetworkClassifier` via
`CreateMLComponents`, confirmed against the real `.swiftinterface` before writing a line, not
assumed from memory). Not shared code: ModelBuilder and SDSTK Studio are separate Xcode projects
with no package relationship, so duplicating this one already-proven, well-understood piece of
logic is the lower-risk choice — same reasoning as `MBExpertServer`'s standalone `ImageExpertRunner`.

**Verified for real, end to end, not mocked:** a functional-check run that (1) confirms
`shouldFlagAsUnknown` against all four cases — confident (pass), low confidence (flag), thin
margin despite decent raw confidence (flag — the entire reason margin was added), and the
null/error sentinel (flag); (2) drives the *actual* full loop: two synthetic images flagged
unknown, labeled "red", two more labeled "blue" (`promotionCount = 2` for a fast test, not the
default 20 — the training call itself is unmodified), confirms no training fires after only one
label is staged, confirms it does fire once a second label crosses the threshold, and polls
(bounded, not indefinite) for the background `Task` to finish. **Result: a genuine 2-class Core
ML image classifier was actually trained via `CreateMLComponents` and written to disk as a real
`.mlmodel` file** — confirmed by listing the file on disk directly, not just trusting the
in-process return value, then cleaned up (this ran against the real `Application Support`
directory, a real side effect of running the check, not a sandboxed test fixture). 50% training
accuracy is expected and unremarkable — two solid-color synthetic images per class carry
essentially no learnable signal; the point was proving the pipeline runs end-to-end without
mocking any step, not producing a useful model.

**Explicitly out of scope, and why:** auto-adding a newly-trained expert as a new node on the
canvas — training completes on whatever cadence labeling happens to hit the threshold, fully
asynchronously relative to the graph's own synchronous per-node dirty/run cycle, and mutating
the graph structure itself from a background completion is a materially different (and riskier)
kind of side effect than anything the engine does today. Using a freshly-trained model still
means dragging a new `Experts.CoreMLExpert` node and pointing its existing file picker at the
output path — manual, but a deliberate, honest scope boundary, not an oversight.

## 17. Critique-response pass — closing all four flagged gaps

An external review flagged four "future work" items as the real gaps between the framing and
what shipped. All four closed in one pass, each with runtime verification, not just compilation:

**(1) Coordinator fixed 2-expert arity → dynamic N (2–8).** The constraint traced to
`StudioWidget.inputPorts` being `static` (per-type, not per-node). Fix: new
`dynamicInputPorts`/`dynamicOutputPorts` protocol members whose default implementations forward
to the static declarations — all ~45 fixed-shape widgets needed zero changes — and the seven
call sites that consult ports (`WorkflowGraph.gatherInputs`, `NodeView` dots/height,
`CanvasView` link-completion + hit-testing) now read the *instance*. `CanvasLayout` was already
fully count-parameterized, so geometry needed nothing. Coordinator overrides with
`expertCount`-generated ports (`expert1…expertN`, renamed from `expertA/expertB` — safe, nothing
shipped) and per-slot weights (trailing weights survive a shrink so re-growing restores them).
Dangling links after a shrink are benign by construction: link rendering already
`if let`-guards on `portPosition`, `gatherInputs` only iterates current ports, and the link
springs back if the count grows again — documented behavior, not an accident. Verified: 3-arity
vote through real combine logic (third expert wins at weight parity).

**(2) MBExpertServer single-expert → full compound graphs.** `ExpertBundle` now parses nodes
*and links*, loads N experts, decodes the Coordinator's persisted strategy + per-slot weights
(slot mapping: link into port `expertN` → `weights[N-1]`, mirroring
`CoordinatorWidget.weight(at:)`). `tools/call` runs every expert; per-expert failures become
`error` entries in the evidence rather than failing the call; the combined `decision` mirrors
both app strategies. Verified two ways: (a) a compound bundle (2 experts + weighted
Coordinator) generated by the app's own export code, served over real JSON-RPC — weights 1.0/0.5
came through the link mapping correctly; (b) **the Phase-15 "never ran real weights" caveat is
now closed** — a model genuinely trained by MemStacker's auto-train loop, hand-bundled and
served, classified a real red staging sample as `"red"` via MCP `tools/call`.

**(3) Interactive selection propagation.** The engine gained per-port outputs with a deliberately
minimal contract: a new `PortValue.outputs([String: PortValue])` case that `gatherInputs`
unwraps per-link by `fromPort` — downstream widgets never see the wrapper, and single-output
widgets are untouched (no `run()` signature change, no per-widget migration). `ScatterPlot` is
the proof widget (Orange's "Selected Data" pattern): a second `selected` `.table` output, a
drag-marquee selection chart in the inspector (screen→data conversion via `ChartProxy.value(atX:)`
against `plotFrame`), and the selection persisted in params as a **data-coordinate rect** — not
row indices (Orange's choice), so re-sampled/re-filtered upstream data re-selects by region
instead of silently pointing at the wrong rows. No selection → empty table (closest honest
match to Orange's "sends nothing" in a must-produce-a-value engine). Verified through the REAL
graph: 4 of 10 rows flowed `ScatterPlot.selected → DataInfo` via actual `gatherInputs`, all
columns preserved (not just the plotted two), and clearing the selection yields 0 rows. The
drag gesture itself is UI code this VM can't runtime-test — that specific slice still needs a
human in Xcode; the *dataflow* doesn't.

**(4) Neural (MLP) widget.** `Neural` wired as the eighth local package dependency.
`Model.MLPRegressor`: table in → configurable hidden layers/epochs/learning-rate → MLX-compiled
training via `Neural.train` (Adam + MSE) → per-epoch loss curve out as a chart. Deliberately
self-contained train-and-report rather than forced into the `RegressorSpec`/Test & Score path —
`Neural`'s MLX training loop can't ride `Learn`'s `crossValScore`, and pretending otherwise
would be abstraction for its own sake. Same `metallibAvailable` guard-before-touch as
`Data.Benchmark` (MLX hard-exits, not throws, without `mlx.metallib`), with the guard's failure
surfaced in both `run()` and the inspector. **Verified with REAL GPU training**, not a skip:
borrowed the version-matched `mlx.metallib` from SwiftSci's own Benchmarks build, placed it next
to the check binary, and trained y=2x+1 through the actual widget — loss 120.78 → 0.20 over 30
epochs, one chart point per epoch.

Also caught during this pass: the functional-check executable itself needed
`FrameConfig.backend = .cpu` at startup — the first check to construct a `DataFrame` directly
hit the exact MLX hard-exit Phase 9 documented, because the check binary never runs
`SDSTKStudioApp.init()` where the app sets that guard. The same class of bug the app fixed,
rediscovered live in the harness that verifies it.

Still honestly open after this pass: MBExpertServer still assumes at most one Coordinator and
ignores non-expert nodes; and none of this has been exercised against a real external MCP
client (Cline/Claude Desktop) yet.

## 18. Closing the three remaining gaps from §17

**Selection propagation on Histogram, Bar Chart, Box Plot.** Same `.outputs` mechanism as
Scatter Plot, generalized to the two selection shapes that actually apply: Histogram selects by
*bin index* (edges are fully determined by data min/max + bin count, so indices stay meaningful
run to run; a `selectionBinCount` guard clears the selection — rather than silently misapplying
it — if the bin count changes since it was made) with a tap-to-toggle bar chart; Bar Chart and
Box Plot select by *category name* (stable under reordering, unlike index) via the same tap
interaction, factored into a shared `CategoryTapChart`. `InspectorPanel`'s SVG-export button
(previously a bare `case .done(.chart(let data)) = state` match) now checks a `chartOutput`
computed property that also unwraps `.outputs["chart"]` — the direct match would have silently
stopped offering SVG export the moment any chart widget went multi-output. **A real backward-
compatibility bug caught and fixed, not hypothetical:** the new selection fields were initially
non-optional with defaults, which is irrelevant to `Codable` decoding — a missing JSON key still
throws `keyNotFound` regardless of a Swift-side default, and `buildGraph`'s `try? applyParams`
swallows that failure, silently resetting the *entire* node (column choice included) on any
saved workflow predating this change, including the bundled examples. Fixed by making the new
fields `Optional` (`nil` decodes cleanly from an absent key). Verified explicitly: fed each
widget's pre-selection JSON shape (no selection keys at all) through `applyParams` and confirmed
the pre-existing config survives — this is the kind of break that's invisible until someone
opens an old file, so it got a dedicated check rather than trusting the "should be fine" reasoning.

**MLP classifier.** `Model.MLPClassifier` alongside the regressor: target column's distinct
values sorted into dense integer class indices (deterministic across runs), output layer sized
to class count, `Neural.Loss.crossEntropy`. Verified with real MLX training on two linearly
separable synthetic blobs — asserting not just "loss decreased" but **≥90% training accuracy**,
since separable data makes anything lower a signal the label-encoding or loss wiring is wrong,
not unlucky initialization. Got 100%.

**Live gesture verification — actually done, not deferred again.** Built a minimal windowed
harness in the scratch package: a real `NSWindow` hosting `ScatterPlotWidget.makeInspector()` —
the *actual* inspector view the app ships, not a mock — writing its live selection state to a
status file on every `onChange`. The bare Swift executable wasn't visible to the sandboxed
permission system as an "application" (`request_access` couldn't resolve it by name); wrapping
it in a minimal `.app` bundle (an `Info.plist` + the same binary) fixed that, which is itself a
real, useful finding about this class of test harness, not a throwaway workaround. Requested
and was granted control of the running app, screenshotted it, and drove one real
`left_click_drag` across the live chart. Confirmed via the status file: the drag committed a
genuine data-space selection rect (`xMin≈3.17, xMax≈11.17, yMin≈0.84, yMax≈13.49`) and correctly
selected 4 rows — then clicked the real "Clear" button and confirmed the count dropped back to
0. This is the actual screen→data coordinate path (`ChartProxy.value(atX:)` against
`plotFrame`) exercised by a real OS-level drag, the one slice of this whole effort that couldn't
be verified from a script — now it has been.

All eighteen tracked tasks from the original critique-response pass are closed. What's left
unverified is only what was always out of this VM's reach: a real external MCP client
(Cline/Claude Desktop) actually calling `MBExpertServer`, and multi-Coordinator / non-expert-node
bundles.
