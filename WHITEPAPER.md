# SDSTK Studio

### A Native Swift Canvas for Data Science on Apple Silicon

---

## Executive Summary

SDSTK Studio is a universal SwiftUI application — one codebase running natively on both iPadOS
and macOS — that brings visual-programming data science to Apple platforms. Modeled on the
interaction model of [Orange Data Mining](https://orangedatamining.com), it lets a user build a
data pipeline by dragging widgets onto a canvas and wiring them together, watching results update
live as the graph changes.

What makes it possible is what it's built on: **SDSTK**, an MLX-native Swift reimplementation of
the Python data-science stack — pandas, SciPy, scikit-learn, matplotlib, and more — running
directly on Apple Silicon's unified memory and GPU, with no Python interpreter, no server, and no
translation layer in between.

The result is a single native app that is simultaneously a usable data-science tool and a working
demonstration of SDSTK's range: 40 widgets across 11 categories, several of which have no
equivalent in Orange itself.

---

## 1. The Problem: Python's Tax

The Python data-science ecosystem — NumPy, pandas, SciPy, scikit-learn — is the default toolkit
for the world's data work. It is also, by construction, a compromise: interpreted glue code, the
CPython GIL serializing execution, and a hard boundary between a fast C/Fortran core and a slow
Python layer sitting on top of it. Every array operation crosses that boundary.

On Apple Silicon, [MLX](https://github.com/ml-explore/mlx-swift) removes the boundary entirely —
a unified-memory, lazily-evaluated, GPU-accelerated array framework with autodiff built in, and no
CPU/GPU copy tax because there is no separate GPU memory to copy to. SDSTK is the ecosystem
**on top of** MLX that didn't exist yet: NumPy's role is already filled by `MLXArray` itself, so
SDSTK starts one layer up and builds pandas, SciPy, and scikit-learn's equivalents directly in
Swift.

SDSTK Studio exists to put that stack in front of a user without asking them to write any Swift —
or any code at all.

---

## 2. Foundation: SDSTK Underneath

Every widget in Studio is a thin UI layer over an already-independent SDSTK package. Nothing in
the app re-implements data-science logic; it only exposes it.

| SDSTK module | Replaces | What it gives Studio |
|---|---|---|
| **Frame** | pandas | Columnar `DataFrame`, group-by, joins, windows, nulls, CSV/Arrow/Parquet I/O — swappable `.cpu`/`.mlx` numeric backend |
| **Sci** (`LinAlg` + `Stats`) | SciPy | Linear algebra (BLAS/LAPACK via Accelerate), descriptive stats, hypothesis tests, distributions |
| **Learn** | scikit-learn | Linear/logistic regression, decision trees, ensembles, k-means, PCA, cross-validation |
| **Neural** | PyTorch (training loop) | MLX-native MLP/CNN/RNN/LSTM training with a compiled train loop *(not yet wired into Studio — see Roadmap)* |
| **Plot** | matplotlib | Headless SVG rendering — Studio's export path, not its live view |
| **Signal** | SciPy.signal | FFT/STFT, windowing, filter design, peak detection |
| **Text** | spaCy / NLTK | Tokenization, TF-IDF, cosine similarity |
| **Optimize** | SciPy.optimize | Levenberg-Marquardt curve fitting, gradient descent, Nelder-Mead |
| **TimeSeries** | statsmodels.tsa | Rolling stats, ACF/PACF, ARIMA, exponential smoothing |
| **Formulas** | — | Closed-form physics/chemistry/biology equations, with no Python equivalent as a single reference |
| **Graph** | NetworkX | Dijkstra, A*, MST, connected components |

SDSTK carries hundreds of passing tests across these packages, each independently releasable as
its own Swift package. Studio depends on them as local Swift Package Manager dependencies — a
deliberate choice that keeps the app always building against SDSTK's live source, not a frozen
copy.

---

## 3. Architecture: Canvas, Widgets, Dataflow

### The widget contract

Every widget conforms to a single `StudioWidget` protocol: a stable type identifier, a category,
declared **typed input and output ports** (`.table`, `.classifierLearner`, `.regressorLearner`,
`.scores`, `.chart`), a `run(inputs:)` function, and a SwiftUI inspector view for its parameters.
Ports are typed deliberately — a regressor can't be wired into a slot expecting a classifier, and
the mistake is caught by the type system, not a runtime check.

### Live dataflow

Studio's `ExecutionEngine` tracks the workflow as a directed graph, computes topological order via
Kahn's algorithm, and re-runs only what a change actually invalidates — a dirty-marking scheme
that propagates from an edited node to everything downstream of it. Editing a widget's parameters
doesn't require a "Run" button; the graph updates itself, the way Orange's own canvas does.

### The document format

A workflow is one `.sdstkflow` file — JSON describing every widget's type, position, and
parameters, plus the links between them — opened through SwiftUI's `DocumentGroup`, so it behaves
like any other document on either platform: Open Recent, iCloud Drive, drag-and-drop.

### A concurrency decision worth naming

SDSTK's `DataFrame` and `Figure` types wrap MLX/Metal state that isn't `Sendable`, so Studio's
graph and execution engine are deliberately pinned to the main actor. SwiftUI's
`ReferenceFileDocument`, however, declares its requirements as nonisolated and `Sendable`-
constrained — a real conflict between "this state must stay on one thread" and "this protocol
assumes it might not." The resolution: the document class conforms as `@unchecked Sendable` and
every protocol-required method wraps its body in `MainActor.assumeIsolated`, turning an
assumption the type system can't verify into a checked runtime guarantee instead of a silent race.

---

## 4. Capability Survey: 40 Widgets, 11 Categories

| Category | Widgets | Highlights |
|---|---|---|
| **Data** | 17 | CSV/Parquet import, a bundled Iris dataset, table preview, column selection, sampling, imputation, normalization, feature construction, table joins, outlier detection, schema summary, CSV export, a synthetic-signal generator, and the speed benchmark |
| **Visualize** | 6 | Scatter, histogram, bar, box plot, correlation heatmap, univariate feature ranking — all native Swift Charts, not the headless SVG renderer |
| **Model** | 6 | Logistic & linear regression, decision trees, random forests, gradient boosting |
| **Evaluate** | 3 | Cross-validated Test & Score (classifier and regressor), confusion matrix from a real held-out split |
| **Unsupervised** | 2 | k-means, PCA |
| **Signal** | 1 | FFT magnitude spectrum |
| **Text** | 1 | TF-IDF cosine-similarity heatmap |
| **Time Series** | 1 | Autocorrelation |
| **Optimize** | 1 | Levenberg-Marquardt curve fitting |
| **Formulas** | 1 | Closed-form equation sweep (currently projectile motion) |
| **Graph** | 1 | Dijkstra shortest path over a weighted edge list |

The first four categories are direct parity with Orange's own core (data/pandas, visualize/
matplotlib, model/evaluate via scikit-learn). The last six have **no native equivalent in
Orange at all** — Signal, Time Series, and Graph exist there only as separate add-ons, if at
all, and Formulas has no analogue anywhere in Orange's ecosystem. That gap is the point: Studio
isn't cloning Orange, it's using Orange's proven interaction model to show what a data-science
canvas looks like when the underlying stack has more than pandas and scikit-learn under it.

---

## 5. Performance: The Speed Story

Frame's numeric columns run on a swappable backend — `.mlx` (GPU, via `MLXArray`) or `.cpu`
(portable pure-Swift). Studio's **Backend Benchmark** widget makes that tradeoff visible rather
than theoretical: it times the identical `Column` construct-and-sum operation on both backends
over a configurable row count (up to millions of rows) and charts the result directly on the
canvas. The honest finding, consistent with SDSTK's own internal benchmarks: the GPU backend wins
decisively on compute-bound work, and is not automatically faster on memory-bound operations like
a plain sum at moderate sizes — a real result, not a marketing one.

Because Frame defaults to the `.mlx` backend, and MLX's scheduler will abort the process outright
if its Metal shader library (`mlx.metallib`) isn't present, Studio ships a build-time script that
fetches the correct prebuilt shader library automatically, and pins the entire rest of the app to
the `.cpu` backend by default — the Benchmark widget is the only code path that ever touches
`.mlx`, and it checks the shader library's presence before doing so. This was not left as a
theoretical safeguard: the exact failure mode (an immediate, clearly-logged process exit — not a
silent crash) and the exact success path were both reproduced directly during development, and
the guard was written against the observed behavior, not an assumption about it.

---

## 6. Universal by Design

Studio is a single SwiftUI codebase targeting iPadOS and macOS through `supportedDestinations` —
not two apps sharing code, one app. The same `.sdstkflow` file opens identically on either
platform; the same three-column layout (palette, canvas, inspector) adapts to a Mac window or an
iPad's larger multitasking surface without platform-specific branches in the widget layer.

---

## 7. Getting Started

Eleven bundled example workflows cover every category, reachable from the canvas toolbar's
Examples menu — each opens fully wired and ready to run:

- **Classify Iris**, **Explore Data**, **Regression Demo** — the core Data → Model → Evaluate loop
- **Unsupervised Clustering** — k-means feeding a PCA projection feeding a scatter plot
- **Signal FFT Demo**, **Time Series Autocorrelation**, **Optimize Curve Fit** — each built on a
  synthetic-signal generator designed to make the underlying structure (a frequency peak, an
  autocorrelation pattern, a recoverable curve) visibly real, not contrived
- **Text Similarity** — a small bundled corpus clustering by topic
- **Graph Shortest Path** — a nine-city distance network with genuine alternate routes
- **Formulas: Physics** — a one-click equation sweep
- **Speed Benchmark (CPU vs GPU)** — pre-configured at two million rows specifically to make the
  backend gap dramatic on first open

A first-launch onboarding sheet (also available anytime from the toolbar) walks through the four
things a new user needs: add a widget, wire it up, configure it, or just open an example.

---

## 8. What's Next

Honestly scoped, not implied as done:

- **Interactive selection propagation** — clicking or lassoing points in a chart to filter or
  highlight the same rows downstream, the single largest remaining gap against Orange's actual
  day-to-day feel. This is a new data-flow concept across the whole port system, not one more
  widget, and is deliberately being scoped as its own effort rather than bolted on.
- **A Neural (MLP) widget** — `Neural` is MLX-only with no CPU fallback and isn't yet wired as a
  Studio dependency; it needs the same shader-library guard as the Benchmark widget, plus an
  async training-progress design nothing else in the app has needed yet.
- **Broader Model coverage** — Naive Bayes, SVM, and k-nearest-neighbors don't exist in SDSTK's
  `Learn` module yet; adding Model widgets for them means extending SDSTK itself first.
- **Report generation and canvas annotations**, and **pinch-to-zoom** on the canvas (currently
  pan-only).

---

## Closing

SDSTK Studio is built on the premise that the best way to prove a data-science toolkit works is
to make something with it that a person actually wants to open. Every widget on the canvas is a
real call into real SDSTK code — there is no mocked path, no simplified demo-only version of the
math sitting behind the UI. What you connect on the canvas is what runs.
