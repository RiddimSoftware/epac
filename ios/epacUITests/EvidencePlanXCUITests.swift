import XCTest
import Evidence

final class EvidencePlanXCUITests: XCTestCase {
    func testRunEvidencePlan() throws {
        let app = XCUIApplication()
        
        // Auto-dismiss the "Open in epac?" system handoff dialog.
        // Prototyping with simctl showed that universal-link openURL steps trigger an
        // "Open in epac?" handoff dialog that contaminates subsequent screenshots.
        // By using XCTest here, we can automatically dismiss it.
        addUIInterruptionMonitor(withDescription: "Universal link handoff") { alert in
            let openButton = alert.buttons["Open"]
            if openButton.exists {
                openButton.tap()
                return true
            }
            return false
        }
        
        try EvidencePlanRunner.runFromEnvironment(on: app)
    }
}
