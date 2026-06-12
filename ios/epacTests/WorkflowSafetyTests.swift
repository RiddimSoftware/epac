@testable import epac
import Foundation
import Testing

struct WorkflowSafetyTests {
    @Test func pullRequestWorkflowsUsePublicRunners() throws {
        for workflow in try prWorkflowFiles() {
            let source = try String(contentsOf: workflow, encoding: .utf8)
            let restrictedLabel = ["self", "hosted"].joined(separator: "-")
            #expect(
                !source.contains(restrictedLabel),
                "Workflow \(relativePath(workflow)) runs pull_request jobs on a self-hosted runner."
            )
        }
    }

    @Test func pullRequestWorkflowsDoNotDependOnInternalAutomergeBotCredentials() throws {
        let botPrefix = ["DEV", "BOT"].joined(separator: "_")
        let banned = [
            "\(botPrefix)_APP_ID",
            "\(botPrefix)_\(["PRIVATE", "KEY"].joined(separator: "_"))",
            "actions/create-github-app-token"
        ]
        for workflow in try prWorkflowFiles() {
            let source = try String(contentsOf: workflow, encoding: .utf8)
            for reference in banned {
                #expect(
                    !source.contains(reference),
                    "Workflow \(relativePath(workflow)) references internal automerge bot infrastructure (\(reference))."
                )
            }
        }
    }

    private func prWorkflowFiles() throws -> [URL] {
        try allWorkflowFiles().filter { url in
            let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return source.contains("pull_request:")
        }
    }

    private func allWorkflowFiles() throws -> [URL] {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let workflowsDir = repoRoot.appendingPathComponent(".github/workflows")
        return try FileManager.default
            .contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yml" || $0.pathExtension == "yaml" }
            .sorted { $0.path < $1.path }
    }

    private func relativePath(_ url: URL) -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDir.deletingLastPathComponent().deletingLastPathComponent().path + "/"
        return url.path.replacingOccurrences(of: root, with: "")
    }
}
