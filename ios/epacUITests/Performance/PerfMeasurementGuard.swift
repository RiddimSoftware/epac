//
//  PerfMeasurementGuard.swift
//  epacUITests
//

import XCTest

enum PerfMeasurementGuard {
    struct Metric {
        let name: String
        let metric: any XCTMetric

        init(name: String, metric: any XCTMetric) {
            self.name = name
            self.metric = metric
        }
    }

    static func measure(
        in testCase: XCTestCase,
        metrics: [Metric],
        file: StaticString = #filePath,
        line: UInt = #line,
        block: () -> Void
    ) {
        measure(
            in: testCase,
            metrics: metrics,
            options: XCTMeasureOptions(),
            file: file,
            line: line,
            block: block
        )
    }

    static func measure(
        in testCase: XCTestCase,
        metrics: [Metric],
        options: XCTMeasureOptions,
        file: StaticString = #filePath,
        line: UInt = #line,
        block: () -> Void
    ) {
        XCTAssertFalse(
            metrics.isEmpty,
            "Performance tests must declare at least one expected metric",
            file: file,
            line: line
        )
        testCase.measure(metrics: metrics.map(\.metric), options: options, block: block)

        let expectedMetricNames = metrics.map(\.name).joined(separator: "\n")
        let attachment = XCTAttachment(string: expectedMetricNames)
        attachment.name = "Expected performance metrics"
        testCase.add(attachment)
    }
}
