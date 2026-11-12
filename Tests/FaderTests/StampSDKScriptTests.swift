import Foundation
import Testing

/// stamp-sdk.sh: records in Fader's binary which macOS SDK it was really built with.
///
/// SwiftPM wrote "SDK 15.0" into Fader even when building with the macOS 27 SDK. macOS reads that
/// number to pick the design: an app claiming SDK 15 is kept on the old-style controls, so Fader's
/// sliders never got the Liquid Glass knob.
struct StampSDKScriptTests {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaderStampSDKTests-\(UUID().uuidString)")

    /// Runs a command and returns its exit status and output.
    func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The SDK version a binary says it was built with, e.g. "27.2".
    func recordedSDK(of binary: URL) throws -> String? {
        let output = try run("/usr/bin/xcrun", ["vtool", "-show-build", binary.path]).output
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("sdk ") }
            .map { String($0.dropFirst(4)) }
    }

    @Test func stampsTheSDKThatIsActuallyInstalled() throws {
        defer { try? FileManager.default.removeItem(at: workDir) }
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        // A tiny program that claims "built with SDK 15.0", the way SwiftPM left Fader.
        let source = workDir.appendingPathComponent("tiny.c")
        try "int main(void) { return 0; }".write(to: source, atomically: true, encoding: .utf8)
        let binary = workDir.appendingPathComponent("tiny")
        let compile = try run("/usr/bin/xcrun", [
            "clang", "-mmacosx-version-min=15.0", "-Wl,-platform_version,macos,15.0,15.0",
            "-o", binary.path, source.path,
        ])
        try #require(compile.status == 0, "\(compile.output)")
        try #require(try recordedSDK(of: binary) == "15.0")

        let stamp = try run(repoRoot.appendingPathComponent("stamp-sdk.sh").path, [binary.path])
        #expect(stamp.status == 0, "\(stamp.output)")

        let installedSDK = try run("/usr/bin/xcrun", ["--show-sdk-version"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try recordedSDK(of: binary) == installedSDK)
        // The program still runs after the change.
        #expect(try run(binary.path, []).status == 0)
    }

    @Test func failsClearlyWhenTheBinaryIsMissing() throws {
        let result = try run(repoRoot.appendingPathComponent("stamp-sdk.sh").path,
                             [workDir.appendingPathComponent("nope").path])
        #expect(result.status != 0)
        #expect(result.output.contains("not found"))
    }
}
