import Foundation
import Testing

/// "Open Fader.command": the double-click launcher that rebuilds Fader and opens it.
/// Running it for real would quit your running Fader, so these tests only check that Finder
/// can run it; what it does is a manual check in TESTING.md.
struct LauncherScriptTests {
    let launcher = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Open Fader.command")

    @Test func isExecutableSoFinderCanRunIt() {
        #expect(FileManager.default.isExecutableFile(atPath: launcher.path))
    }

    @Test func hasNoSyntaxErrors() throws {
        try #require(FileManager.default.fileExists(atPath: launcher.path))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", launcher.path]  // -n: read the script without running it
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
