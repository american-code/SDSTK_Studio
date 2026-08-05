import Foundation

/// Registry of every widget type the palette can place and the `.sdstkflow` loader can
/// reconstruct from a saved `typeID`. Register new widgets here as they're added — this is the
/// single place that needs a new line per new widget.
@MainActor
enum WidgetCatalog {
    struct Entry {
        let typeID: String
        let category: WidgetCategory
        let displayName: String
        let symbolName: String
        let make: () -> any StudioWidget
    }

    private static func entry<W: StudioWidget>(_ type: W.Type, _ make: @escaping () -> W) -> Entry {
        Entry(typeID: type.typeID, category: type.category, displayName: type.displayName,
              symbolName: type.symbolName, make: make)
    }

    static let entries: [Entry] = [
        // Data
        entry(IrisExampleWidget.self) { IrisExampleWidget() },
        entry(CSVFileWidget.self) { CSVFileWidget() },
        entry(ParquetFileWidget.self) { ParquetFileWidget() },
        entry(DataTableWidget.self) { DataTableWidget() },
        entry(SelectColumnsWidget.self) { SelectColumnsWidget() },
        entry(SamplerWidget.self) { SamplerWidget() },
        entry(ImputeWidget.self) { ImputeWidget() },
        entry(NormalizeWidget.self) { NormalizeWidget() },
        entry(FeatureConstructorWidget.self) { FeatureConstructorWidget() },
        entry(ConcatenateWidget.self) { ConcatenateWidget() },
        entry(OutlierDetectionWidget.self) { OutlierDetectionWidget() },
        entry(DataInfoWidget.self) { DataInfoWidget() },
        entry(SaveDataWidget.self) { SaveDataWidget() },
        entry(BenchmarkWidget.self) { BenchmarkWidget() },
        entry(SyntheticSignalWidget.self) { SyntheticSignalWidget() },
        entry(TextSampleWidget.self) { TextSampleWidget() },
        entry(RouteExampleWidget.self) { RouteExampleWidget() },
        entry(ImageFileWidget.self) { ImageFileWidget() },
        entry(TextPromptWidget.self) { TextPromptWidget() },
        // Visualize
        entry(ScatterPlotWidget.self) { ScatterPlotWidget() },
        entry(HistogramWidget.self) { HistogramWidget() },
        entry(BarChartWidget.self) { BarChartWidget() },
        entry(BoxPlotWidget.self) { BoxPlotWidget() },
        entry(CorrelationHeatmapWidget.self) { CorrelationHeatmapWidget() },
        entry(RankWidget.self) { RankWidget() },
        // Model
        entry(LogisticRegressionWidget.self) { LogisticRegressionWidget() },
        entry(DecisionTreeClassifierWidget.self) { DecisionTreeClassifierWidget() },
        entry(RandomForestClassifierWidget.self) { RandomForestClassifierWidget() },
        entry(LinearRegressionWidget.self) { LinearRegressionWidget() },
        entry(DecisionTreeRegressorWidget.self) { DecisionTreeRegressorWidget() },
        entry(GradientBoostingRegressorWidget.self) { GradientBoostingRegressorWidget() },
        entry(MLPRegressorWidget.self) { MLPRegressorWidget() },
        entry(MLPClassifierWidget.self) { MLPClassifierWidget() },
        // Evaluate
        entry(TestAndScoreWidget.self) { TestAndScoreWidget() },
        entry(TestAndScoreRegressorWidget.self) { TestAndScoreRegressorWidget() },
        entry(ConfusionMatrixWidget.self) { ConfusionMatrixWidget() },
        entry(ROCAUCWidget.self) { ROCAUCWidget() },
        entry(CrossValidationWidget.self) { CrossValidationWidget() },
        // Unsupervised
        entry(KMeansWidget.self) { KMeansWidget() },
        entry(PCAWidget.self) { PCAWidget() },
        // Signal
        entry(FFTWidget.self) { FFTWidget() },
        // Text
        entry(TextSimilarityWidget.self) { TextSimilarityWidget() },
        // Time Series
        entry(ACFWidget.self) { ACFWidget() },
        // Optimize
        entry(CurveFitWidget.self) { CurveFitWidget() },
        // Formulas
        entry(ProjectileMotionWidget.self) { ProjectileMotionWidget() },
        // Graph
        entry(ShortestPathWidget.self) { ShortestPathWidget() },
        // Experts
        entry(CoreMLExpertWidget.self) { CoreMLExpertWidget() },
        entry(CoreMLTabularExpertWidget.self) { CoreMLTabularExpertWidget() },
        entry(CoordinatorWidget.self) { CoordinatorWidget() },
        entry(ResearchExpertWidget.self) { ResearchExpertWidget() },
        entry(MemStackerWidget.self) { MemStackerWidget() },
    ]

    static func entry(for typeID: String) -> Entry? {
        entries.first { $0.typeID == typeID }
    }

    static func grouped(matching query: String = "") -> [(category: WidgetCategory, entries: [Entry])] {
        let filtered = query.isEmpty
            ? entries
            : entries.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        return WidgetCategory.allCases.compactMap { category in
            let matches = filtered.filter { $0.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }
}
