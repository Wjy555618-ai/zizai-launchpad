import XCTest

@testable import 自在启动台

@MainActor
final class ViewLayoutPolicyTests: XCTestCase {
    func testSparseSearchResultsDoNotReserveInvisibleColumns() {
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 0, spacing: 24),
            340
        )
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 2, spacing: 24),
            704
        )
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 8, spacing: 24),
            1_068
        )
    }
}
