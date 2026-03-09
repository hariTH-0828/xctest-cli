import ArgumentParser
import Foundation

/// `xctest-cli run` — Execute XCTest cases and generate a report.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run XCTest cases and generate a test report."
    )

    @Option(name: .long, help: "The Xcode scheme to test.")
    var scheme: String

    @Option(name: .long, help: "The simulator destination (e.g., 'platform=iOS Simulator,name=iPhone 16').")
    var destination: String = "platform=iOS Simulator,name=iPhone 16"

    @Option(name: .long, help: "Path to the .xcworkspace file.")
    var workspace: String?

    @Option(name: .long, help: "Path to the .xcodeproj file.")
    var project: String?

    @Option(name: .long, help: "Path to store the .xcresult bundle.")
    var resultBundlePath: String = ".xctest-cli/TestResults.xcresult"

    @Option(name: .long, help: "Path to write the JSON report.")
    var output: String = "reports/latest.json"

    @Flag(name: .long, help: "Start the dashboard server after running tests.")
    var serve: Bool = false

    @Option(name: .long, help: "Port for the dashboard server (used with --serve).")
    var port: Int = 8080

    func run() async throws {
        print("╔══════════════════════════════════════╗")
        print("║         xctest-cli • Run Tests       ║")
        print("╚══════════════════════════════════════╝")
        print()

        // Step 1: Run tests
        let config = TestRunner.Configuration(
            scheme: scheme,
            destination: destination,
            project: project,
            workspace: workspace,
            resultBundlePath: resultBundlePath,
            extraArgs: []
        )

        let bundlePath = try TestRunner.runTests(config: config)

        // Step 2: Parse results
        let parser = XCResultParser(resultBundlePath: bundlePath)
        let (suites, totalDuration) = try parser.parse()

        // Step 3: Generate report
        let report = try ReportGenerator.generate(
            suites: suites,
            totalDuration: totalDuration,
            outputPath: output
        )

        print()
        printSummary(report)

        // Step 4: Optionally start server
        if serve {
            let server = WebServer(reportPath: output, port: port)
            try await server.start()
        }
    }

    private func printSummary(_ report: TestReport) {
        let s = report.summary
        let totalStr = "\(s.totalTests)".padding(toLength: 26, withPad: " ", startingAt: 0)
        let passedStr = "\(s.passed)".padding(toLength: 26, withPad: " ", startingAt: 0)
        let failedStr = "\(s.failed)".padding(toLength: 26, withPad: " ", startingAt: 0)
        let skippedStr = "\(s.skipped)".padding(toLength: 26, withPad: " ", startingAt: 0)
        let durationStr = s.duration.padding(toLength: 25, withPad: " ", startingAt: 0)
        print("╔══════════════════════════════════════╗")
        print("║            Test Summary              ║")
        print("╠══════════════════════════════════════╣")
        print("║  Total:   \(totalStr)║")
        print("║  Passed:  \(passedStr)║")
        print("║  Failed:  \(failedStr)║")
        print("║  Skipped: \(skippedStr)║")
        print("║  Duration: \(durationStr)║")
        print("╚══════════════════════════════════════╝")

        // Print failures
        let failures = report.testSuites.flatMap { $0.testCases.filter { $0.status == .failed } }
        if !failures.isEmpty {
            print()
            print("❌ Failed Tests:")
            for tc in failures {
                print("   • \(tc.suiteName).\(tc.name)")
                if let msg = tc.failureMessage {
                    print("     \(msg)")
                }
                if let file = tc.file, let line = tc.line {
                    print("     at \(file):\(line)")
                }
            }
        }
    }
}
