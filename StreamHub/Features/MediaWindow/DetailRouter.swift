import Foundation
import Observation

@Observable
@MainActor
final class DetailRouter {
    struct Target: Identifiable {
        let id = UUID()
        let row: CatalogRow
        let index: Int
    }

    var target: Target?

    func open(row: CatalogRow, index: Int) {
        target = Target(row: row, index: index)
    }

    func close() {
        target = nil
    }
}
