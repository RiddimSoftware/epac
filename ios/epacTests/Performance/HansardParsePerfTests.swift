@testable import epac
import Foundation
import XCTest

final class HansardParsePerfTests: XCTestCase {
	override func setUp() {
		super.setUp()
		continueAfterFailure = false
		executionTimeAllowance = 120
	}

	func testFederalHansardXMLParseMetrics() throws {
		let xml = try Self.fixtureXML(named: "44-1-HAN291-E")
		let options = Self.measureOptions(iterations: 5)
		var parsedOrderCount = 0
		var parsedSpeechCount = 0

		measure(metrics: [XCTCPUMetric(), XCTClockMetric()], options: options) {
			startMeasuring()
			let hansard = Hansard(domain: XMLBro(xml: xml).parseXML().hansard())
			parsedOrderCount = hansard.orders.count
			parsedSpeechCount = hansard.orders
				.flatMap(\.subjects)
				.flatMap(\.speeches)
				.count
			stopMeasuring()
		}

		XCTAssertGreaterThan(parsedOrderCount, 0)
		XCTAssertGreaterThan(parsedSpeechCount, 0)
	}

	private static func fixtureXML(named name: String) throws -> String {
		let url = try XCTUnwrap(
			Bundle(for: ForThisOnly.self).url(forResource: name, withExtension: "XML"),
			"Missing bundled Hansard fixture \(name).XML"
		)
		return try String(contentsOf: url, encoding: .utf8)
	}

	private static func measureOptions(iterations: Int) -> XCTMeasureOptions {
		let options = XCTMeasureOptions.default
		options.iterationCount = iterations
		options.invocationOptions = [.manuallyStart, .manuallyStop]
		return options
	}
}
