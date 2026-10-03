import Foundation
import Observation

@Observable
@MainActor
final class DetailRouter {
    struct Target: Identifiable {
        let id = UUID()
        let row: CatalogRow
        let index: Int
        let autoplay: Bool
    }

    var target: Target?

    func open(row: CatalogRow, index: Int, autoplay: Bool = false) {
        target = Target(row: row, index: index, autoplay: autoplay)
    }

    func close() {
        target = nil
    }
}
