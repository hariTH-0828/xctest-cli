import Foundation

/// Executes xcodebuild test and returns the path to the generated .xcresult bundle.
struct TestRunner {

    struct Configuration {
        let scheme: String
        let destination: String
        let project: String?
        let workspace: String?
        let resultBundlePath: String
        let extraArgs: [String]
    }

    /// Runs `xcodebuild test` with the given configuration.
    /// Returns the path to the `.xcresult` file.
    static func runTests(config: Configuration) throws -> String {
        var args = [
            "xcodebuild", "test",
            "-scheme", config.scheme,
            "-destination", config.destination,
            "-resultBundlePath", config.resultBundlePath
        ]

        if let workspace = config.workspace {
            args += ["-workspace", workspace]
        } else if let project = config.project {
            args += ["-project", project]
        }

        args += config.extraArgs

        print("🔧 Running tests...")
        print("   Scheme: \(config.scheme)")
        print("   Destination: \(config.destination)")
        if let ws = config.workspace { print("   Workspace: \(ws)") }
        if let proj = config.project { print("   Project: \(proj)") }
        print("   Result bundle: \(config.resultBundlePath)")
        print()

        // Remove existing result bundle if present (xcodebuild fails otherwise)
        let fm = FileManager.default
        if fm.fileExists(atPath: config.resultBundlePath) {
            try fm.removeItem(atPath: config.resultBundlePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = Array(args.dropFirst()) // xcrun runs xcodebuild
        // Actually we invoke xcodebuild directly
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = Array(args.dropFirst()) // drop "xcodebuild"

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Stream output line-by-line so testers see progress
        let fileHandle = pipe.fileHandleForReading
        let data = fileHandle.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            // Print a condensed version - just test results, not the full build log
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Test Case") ||
                   trimmed.hasPrefix("Test Suite") ||
                   trimmed.contains("** TEST") ||
                   trimmed.contains("Failing tests:") ||
                   trimmed.hasPrefix("Executed") {
                    print(line)
                }
            }
        }

        process.waitUntilExit()

        let exitCode = process.terminationStatus
        // xcodebuild returns 65 when tests fail (but still produces results)
        if exitCode != 0 && exitCode != 65 {
            throw TestRunnerError.xcodebuildFailed(exitCode: exitCode)
        }

        // Verify result bundle exists
        guard fm.fileExists(atPath: config.resultBundlePath) else {
            throw TestRunnerError.resultBundleNotFound(path: config.resultBundlePath)
        }

        print()
        print("✅ Test execution complete. Result bundle: \(config.resultBundlePath)")
        return config.resultBundlePath
    }
}

enum TestRunnerError: Error, CustomStringConvertible {
    case xcodebuildFailed(exitCode: Int32)
    case resultBundleNotFound(path: String)

    var description: String {
        switch self {
        case .xcodebuildFailed(let code):
            return "xcodebuild failed with exit code \(code). Check the build log for details."
        case .resultBundleNotFound(let path):
            return "Result bundle not found at: \(path). Ensure the scheme has test targets."
        }
    }
}
