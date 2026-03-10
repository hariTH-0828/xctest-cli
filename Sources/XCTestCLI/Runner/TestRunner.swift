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

        // Initialize live state
        let live = LiveTestState.shared
        live.reset(scheme: config.scheme)

        let tracker = ProgressTracker()
        tracker.update(phase: .preparing)

        // Track current suite and test start time for duration
        var currentSuiteName = ""
        var testStartDate = Date()

        // Buffer failure detail lines between test start → test end
        var pendingFailureLines: [String] = []
        var pendingFailureFile: String?
        var pendingFailureLine: Int?

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
                        live.setPhase(.building)
                    }
                    // Track file being compiled: "Compiling SomeFile.swift"
                    if trimmed.hasPrefix("Compiling ") {
                        let fileName = String(trimmed.dropFirst("Compiling ".count))
                        live.setCurrentFile(fileName)
                    }
                }

                // Track current test suite
                // Old: "Test Suite 'MyTests' started at 2026-03-09..."
                // New: "Test suite 'MyTests' started on 'Device'"
                let trimmedLower = trimmed.lowercased()
                if trimmedLower.hasPrefix("test suite '") && trimmedLower.contains("started") {
                    if let start = trimmed.range(of: "'"),
                       let end = trimmed.range(of: "'", range: trimmed.index(after: start.lowerBound)..<trimmed.endIndex) {
                        let suiteName = String(trimmed[start.upperBound..<end.lowerBound])
                        if !suiteName.contains(".") && suiteName != "All tests" && suiteName != "Selected tests" {
                            currentSuiteName = suiteName
                            live.setCurrentSuite(suiteName)
                        }
                    }
                }

                // Detect test started
                // Old: "Test Case '-[Module.Class method]' started."
                // New: "Test case 'Class.method()' started on 'Device'"
                if trimmedLower.hasPrefix("test case") && trimmedLower.contains("started") {
                    let testName = parseTestName(from: trimmed)
                    tracker.update(phase: .testing)
                    tracker.testStarted(testName)
                    live.setPhase(.testing)
                    live.testStarted(testName)
                    testStartDate = Date()
                    // Reset failure buffer for this test
                    pendingFailureLines = []
                    pendingFailureFile = nil
                    pendingFailureLine = nil
                }

                // Capture failure detail lines (appear between test start and test fail)
                // Old: /path/to/File.swift:42: error: -[Module.Class method] : message
                // New: may vary; also check for generic "error:" pattern with file path
                if let failure = Self.parseFailureLine(trimmed) {
                    pendingFailureLines.append(failure.message)
                    if pendingFailureFile == nil {
                        pendingFailureFile = failure.file
                        pendingFailureLine = failure.line
                    }
                }

                // Detect test passed
                if trimmedLower.hasPrefix("test case") && trimmedLower.contains("passed") {
                    let testName = parseTestName(from: trimmed)
                    let duration = parseDuration(from: trimmed) ?? Date().timeIntervalSince(testStartDate)
                    tracker.testPassed(testName)
                    live.testCompleted(LiveTestState.LiveTestCase(
                        name: testName,
                        suiteName: currentSuiteName,
                        status: .passed,
                        duration: duration,
                        failureMessage: nil,
                        file: nil,
                        line: nil
                    ))
                    pendingFailureLines = []
                    pendingFailureFile = nil
                    pendingFailureLine = nil
                }

                // Detect test failed
                if trimmedLower.hasPrefix("test case") && trimmedLower.contains("failed") {
                    let testName = parseTestName(from: trimmed)
                    let duration = parseDuration(from: trimmed) ?? Date().timeIntervalSince(testStartDate)
                    let failureMsg = pendingFailureLines.isEmpty ? nil : pendingFailureLines.joined(separator: "\n")
                    tracker.testFailed(testName)
                    live.testCompleted(LiveTestState.LiveTestCase(
                        name: testName,
                        suiteName: currentSuiteName,
                        status: .failed,
                        duration: duration,
                        failureMessage: failureMsg,
                        file: pendingFailureFile,
                        line: pendingFailureLine
                    ))
                    pendingFailureLines = []
                    pendingFailureFile = nil
                    pendingFailureLine = nil
                }

                // Print important summary lines as-is
                if trimmed.contains("** TEST SUCCEEDED **") || trimmed.contains("** TEST FAILED **") {
                    tracker.update(phase: .done)
                    tracker.finish()
                    live.setPhase(.done)
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

    /// Extract test name from xcodebuild output.
    /// Old format: `Test Case '-[MyAppTests.LoginTests testExample]' started.`
    /// New format: `Test case 'UserAppTests.testDetailEndpoint()' passed on 'Device' (0.001 seconds)`
    private static func parseTestName(from line: String) -> String {
        // Try old format first: content between '-[' and ']'
        if let start = line.range(of: "-["),
           let end = line.range(of: "]'") {
            let raw = String(line[start.upperBound..<end.lowerBound])
            let parts = raw.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let classPath = String(parts[0])
                let method = String(parts[1])
                let className = classPath.components(separatedBy: ".").last ?? classPath
                return "\(className).\(method)()"
            }
            return raw
        }

        // New format: extract content between first pair of single quotes
        // "Test case 'ClassName.methodName()' passed on 'Device' (0.123 seconds)"
        guard let firstQuote = line.firstIndex(of: "'") else { return line }
        let afterFirst = line.index(after: firstQuote)
        guard afterFirst < line.endIndex,
              let secondQuote = line[afterFirst...].firstIndex(of: "'") else { return line }
        let raw = String(line[afterFirst..<secondQuote]) // "UserAppTests.testDetailEndpoint()"

        // Already in "Class.method()" format — return as-is
        return raw
    }

    /// Extract duration from xcodebuild output like:
    /// Old: `Test Case '...' passed (0.123 seconds).`
    /// New: `Test case '...' passed on 'Device' (0.123 seconds)`
    private static func parseDuration(from line: String) -> Double? {
        // Search for " seconds)" first, then find the matching "(" before it
        guard let secEnd = line.range(of: " seconds)") else { return nil }
        let prefix = line[line.startIndex..<secEnd.lowerBound]
        guard let openParen = prefix.lastIndex(of: "(") else { return nil }
        let numberStr = line[line.index(after: openParen)..<secEnd.lowerBound]
        return Double(numberStr)
    }

    /// Parse failure detail from xcodebuild output.
    /// Old: `/path/to/TestFile.swift:42: error: -[Module.Class method] : XCTAssertEqual failed: ...`
    /// New: `/path/to/TestFile.swift:42: error: XCTAssertEqual failed: ...`
    /// Returns (filePath, lineNumber, message) or nil if not a failure line.
    private static func parseFailureLine(_ line: String) -> (file: String, line: Int, message: String)? {
        // Look for ": error: " pattern which is common to both formats
        guard let errorRange = line.range(of: ": error: ") else { return nil }

        let prefix = String(line[line.startIndex..<errorRange.lowerBound])
        // prefix is "/path/to/File.swift:42"
        guard let lastColon = prefix.lastIndex(of: ":") else { return nil }
        let filePath = String(prefix[prefix.startIndex..<lastColon])
        let lineStr = String(prefix[prefix.index(after: lastColon)...])
        guard let lineNum = Int(lineStr) else { return nil }
        // Ensure the file path looks like a real path (not a timestamp or other colon-containing string)
        guard filePath.hasSuffix(".swift") || filePath.hasSuffix(".m") || filePath.contains("/") else { return nil }

        var message = String(line[errorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Old format: strip the "-[Module.Class method] : " prefix from the message
        if message.hasPrefix("-["), let msgStart = message.range(of: "] : ") {
            message = String(message[msgStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return message.isEmpty ? nil : (filePath, lineNum, message)
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
