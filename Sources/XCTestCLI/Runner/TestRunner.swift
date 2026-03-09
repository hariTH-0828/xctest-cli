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

    // MARK: - Live progress tracker

    private class ProgressTracker {
        var passed = 0
        var failed = 0
        var currentTest: String?
        var phase: Phase = .preparing
        private let startTime = Date()
        private let isTerminal = isatty(STDOUT_FILENO) != 0

        enum Phase: String {
            case preparing = "Preparing"
            case building  = "Building"
            case testing   = "Testing"
            case done      = "Done"
        }

        func update(phase: Phase) {
            self.phase = phase
            render()
        }

        func testStarted(_ name: String) {
            currentTest = name
            render()
        }

        func testPassed(_ name: String) {
            passed += 1
            currentTest = nil
            printResult("  ✅ \(name)")
        }

        func testFailed(_ name: String) {
            failed += 1
            currentTest = nil
            printResult("  ❌ \(name)")
        }

        private func render() {
            guard isTerminal else { return }
            let elapsed = formatElapsed(Date().timeIntervalSince(startTime))
            let total = passed + failed
            let status: String
            switch phase {
            case .preparing:
                status = "⏳ Preparing...  [\(elapsed)]"
            case .building:
                status = "🔨 Building...  [\(elapsed)]"
            case .testing:
                if let test = currentTest {
                    let shortName = test.components(separatedBy: ".").last ?? test
                    status = "🧪 Running: \(shortName)  |  ✅ \(passed)  ❌ \(failed)  📊 \(total)  [\(elapsed)]"
                } else {
                    status = "🧪 Testing...  |  ✅ \(passed)  ❌ \(failed)  📊 \(total)  [\(elapsed)]"
                }
            case .done:
                status = "🏁 Done  |  ✅ \(passed)  ❌ \(failed)  📊 \(total)  [\(elapsed)]"
            }
            // Overwrite the progress line (carriage return + clear line)
            print("\r\u{1B}[K\(status)", terminator: "")
            fflush(stdout)
        }

        /// Print a result line, clearing the progress line first.
        private func printResult(_ text: String) {
            if isTerminal {
                print("\r\u{1B}[K\(text)")
            } else {
                print(text)
            }
            // Re-render progress bar after the result
            render()
        }

        func finish() {
            if isTerminal {
                // Clear the progress line and print final status
                print("\r\u{1B}[K", terminator: "")
            }
        }

        private func formatElapsed(_ interval: TimeInterval) -> String {
            let mins = Int(interval) / 60
            let secs = Int(interval) % 60
            return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        }
    }

    // MARK: - Run tests

    /// Runs `xcodebuild test` with the given configuration.
    /// Returns the path to the `.xcresult` file.
    static func runTests(config: Configuration) throws -> String {
        var args = [
            "test",
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
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let tracker = ProgressTracker()
        tracker.update(phase: .preparing)

        // Stream output line-by-line for real-time progress
        let fileHandle = pipe.fileHandleForReading
        var buffer = Data()

        while true {
            let chunk = fileHandle.availableData
            if chunk.isEmpty { break } // EOF
            buffer.append(chunk)

            // Process complete lines
            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Detect build phase
                if trimmed.contains("Compiling") || trimmed.contains("Linking") || trimmed.hasPrefix("CompileC")
                    || trimmed.hasPrefix("Ld ") || trimmed.hasPrefix("Build target") {
                    if tracker.phase == .preparing {
                        tracker.update(phase: .building)
                    }
                }

                // Detect test started
                if trimmed.hasPrefix("Test Case '-[") && trimmed.contains("began") {
                    // "Test Case '-[MyTests testExample]' started."
                    let testName = parseTestName(from: trimmed)
                    tracker.update(phase: .testing)
                    tracker.testStarted(testName)
                }

                // Detect test passed
                if trimmed.hasPrefix("Test Case '-[") && trimmed.contains("passed") {
                    let testName = parseTestName(from: trimmed)
                    tracker.testPassed(testName)
                }

                // Detect test failed
                if trimmed.hasPrefix("Test Case '-[") && trimmed.contains("failed") {
                    let testName = parseTestName(from: trimmed)
                    tracker.testFailed(testName)
                }

                // Print important summary lines as-is
                if trimmed.contains("** TEST SUCCEEDED **") || trimmed.contains("** TEST FAILED **") {
                    tracker.update(phase: .done)
                    tracker.finish()
                    print(trimmed)
                }
                if trimmed.hasPrefix("Failing tests:") || (trimmed.hasPrefix("\t") && tracker.phase == .done) {
                    print(line)
                }
            }
        }

        // Process any remaining data
        if !buffer.isEmpty, let remaining = String(data: buffer, encoding: .utf8) {
            let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.contains("** TEST") {
                    tracker.finish()
                    print(trimmed)
                }
            }
        }

        tracker.finish()
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

    /// Extract test name from xcodebuild output like:
    /// `Test Case '-[MyAppTests.LoginTests testExample]' started.`
    private static func parseTestName(from line: String) -> String {
        // Extract content between '-[' and ']'
        guard let start = line.range(of: "-["),
              let end = line.range(of: "]'") else {
            return line
        }
        let raw = String(line[start.upperBound..<end.lowerBound]) // "MyAppTests.LoginTests testExample"
        // Convert "Module.Class method" → "Class.method"
        let parts = raw.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            let classPath = String(parts[0])
            let method = String(parts[1])
            let className = classPath.components(separatedBy: ".").last ?? classPath
            return "\(className).\(method)()"
        }
        return raw
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
