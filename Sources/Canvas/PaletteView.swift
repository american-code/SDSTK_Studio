import SwiftUI

/// Sidebar list of every registered widget type, grouped by category — the palette Orange
/// itself keeps down the left edge. Filterable by name once the catalog grows past a glance.
struct PaletteView: View {
    let onAdd: (WidgetCatalog.Entry) -> Void
    @State private var query = ""

    var body: some View {
        List {
            ForEach(WidgetCatalog.grouped(matching: query), id: \.category) { group in
                Section {
                    ForEach(group.entries, id: \.typeID) { entry in
                        Button {
                            onAdd(entry)
                        } label: {
                            Label {
                                Text(entry.displayName)
                            } icon: {
                                Image(systemName: entry.symbolName)
                                    .foregroundStyle(group.category.color)
                            }
                        }
                    }
                } header: {
                    Text(group.category.rawValue)
                        .foregroundStyle(group.category.color)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, prompt: "Search widgets")
    }
}
