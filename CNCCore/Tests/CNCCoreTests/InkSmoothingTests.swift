import XCTest
@testable import CNCCore

final class InkSmoothingTests: XCTestCase {
    func testResamplesDenseNoisyPressure() {
        var samples: [InkDocument.Sample] = []
        for i in 0..<40 {
            let x = Double(i) * 0.1
            let p = i % 2 == 0 ? 0.8 : 0.82
            samples.append(.init(x: x, y: 0, pressure: p))
        }
        let out = InkSmoothing.prepare(samples)
        XCTAssertLessThan(out.count, samples.count)
        XCTAssertEqual(out.first?.x ?? -1, samples.first?.x ?? -2, accuracy: 0.001)
        XCTAssertEqual(out.last?.x ?? -1, samples.last?.x ?? -2, accuracy: 0.001)
    }
}
