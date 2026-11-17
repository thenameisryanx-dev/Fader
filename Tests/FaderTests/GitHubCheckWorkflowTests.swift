import Foundation
import Testing

/// .github/workflows/check.yml: GitHub runs ./check.sh on every push and pull request.
struct GitHubCheckWorkflowTests {
    let workflow = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".github/workflows/check.yml")

    @Test func runsCheckScriptOnEveryPushAndPullRequest() throws {
        let text = try String(contentsOf: workflow, encoding: .utf8)
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(lines.contains("push:"))
        #expect(lines.contains("pull_request:"))
        #expect(lines.contains("run: ./check.sh"))
        // check.sh fails on anything older than SDK 26 (Liquid Glass), so it needs a macOS 26+ runner.
        #expect(lines.contains("runs-on: macos-26"))
    }
}
