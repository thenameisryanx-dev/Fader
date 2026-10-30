import Foundation
import Testing

/// package.sh: the disk image (DMG) for sending Fader to other people.
struct PackageScriptTests {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // Each test gets its own throwaway folder, never the real build folder.
    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaderPackageTests-\(UUID().uuidString)")

    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A stand-in for the real app, so the test doesn't have to build Fader.
    func makeFakeApp() throws -> URL {
        let app = workDir.appendingPathComponent("Fader.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try "fake app".write(to: macOS.appendingPathComponent("Fader"), atomically: true, encoding: .utf8)
        return app
    }

    @Test func dmgContainsAppApplicationsShortcutAndInstructions() throws {
        defer { try? FileManager.default.removeItem(at: workDir) }
        let app = try makeFakeApp()
        let dmg = workDir.appendingPathComponent("Fader.dmg")

        let status = try run(repoRoot.appendingPathComponent("package.sh").path, [app.path, dmg.path])
        #expect(status == 0)
        try #require(FileManager.default.fileExists(atPath: dmg.path))

        // Open the disk image like a user would, but hidden from Finder.
        let mountPoint = workDir.appendingPathComponent("mounted")
        try #require(try run("/usr/bin/hdiutil",
                             ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, dmg.path]) == 0)
        defer { try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let files = FileManager.default
        let copiedApp = mountPoint.appendingPathComponent("Fader.app/Contents/MacOS/Fader")
        #expect(try String(contentsOf: copiedApp, encoding: .utf8) == "fake app")
        #expect(try files.destinationOfSymbolicLink(atPath: mountPoint.appendingPathComponent("Applications").path)
                == "/Applications")
        let instructions = try String(contentsOf: mountPoint.appendingPathComponent("How to open Fader.txt"),
                                      encoding: .utf8)
        #expect(instructions.contains("Open Anyway"))
    }

    @Test func failsClearlyWhenAppIsMissing() throws {
        defer { try? FileManager.default.removeItem(at: workDir) }
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let missingApp = workDir.appendingPathComponent("Nope.app")
        let dmg = workDir.appendingPathComponent("Fader.dmg")

        let status = try run(repoRoot.appendingPathComponent("package.sh").path, [missingApp.path, dmg.path])
        #expect(status != 0)
        #expect(!FileManager.default.fileExists(atPath: dmg.path))
    }
}
