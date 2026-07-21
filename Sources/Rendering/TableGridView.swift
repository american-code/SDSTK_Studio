import SwiftUI

/// A minimal read-only spreadsheet grid — shared by any widget that previews tabular data
/// (`Data.DataTable`'s node face and inspector, primarily).
struct TableGridView: View {
    let columns: [String]
    let rows: [[String]]
    var cellWidth: CGFloat = 90

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    ForEach(columns, id: \.self) { col in
                        Text(col).font(.caption.weight(.semibold))
                            .frame(width: cellWidth, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.caption)
                                .frame(width: cellWidth, alignment: .leading)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}
