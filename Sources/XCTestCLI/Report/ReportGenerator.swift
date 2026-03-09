import Foundation

/// Generates a JSON report from parsed test results.
struct ReportGenerator {

    /// Generate a TestReport and write it to the given path.
    static func generate(
        suites: [TestSuite],
        totalDuration: Double,
        outputPath: String
    ) throws -> TestReport {
        let totalTests = suites.reduce(0) { $0 + $1.testCases.count }
        let passed = suites.reduce(0) { total, suite in
            total + suite.testCases.filter { $0.status == .passed }.count
        }
        let failed = suites.reduce(0) { total, suite in
            total + suite.testCases.filter { $0.status == .failed }.count
        }
        let skipped = suites.reduce(0) { total, suite in
            total + suite.testCases.filter { $0.status == .skipped }.count
        }

        let durationStr = formatDuration(totalDuration)

        let summary = TestSummary(
            totalTests: totalTests,
            passed: passed,
            failed: failed,
            skipped: skipped,
            duration: durationStr
        )

        let formatter = ISO8601DateFormatter()
        let report = TestReport(
            summary: summary,
            testSuites: suites,
            generatedAt: formatter.string(from: Date())
        )

        // Write JSON to file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)

        let outputURL = URL(fileURLWithPath: outputPath)
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL)

        print("📝 Report saved to: \(outputPath)")
        print("   Total: \(totalTests) | Passed: \(passed) | Failed: \(failed) | Skipped: \(skipped)")
        print("   Duration: \(durationStr)")

        return report
    }

    private static func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.2fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = seconds - Double(mins * 60)
        return String(format: "%dm%.2fs", mins, secs)
    }
}
