import XCTest
@testable import AttributionKit

final class AttributionKitTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertNotNil(AttributionKit.shared)
    }
}
