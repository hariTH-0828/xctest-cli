import ArgumentParser
import Foundation

/// `xctest-cli parse` — Parse an existing .xcresult bundle without running tests.
struct ParseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parse",
        abstract: "Parse an existing .xcresult bundle and generate a report."
    )

    @Argument(help: "Path to the .xcresult bundle.")
    var resultBundle: String

    @Option(name: .long, help: "Path to write the JSON report.")
    var output: String = "reports/latest.json"

    @Flag(name: .long, help: "Start the dashboard server after parsing.")
    var serve: Bool = false

    @Option(name: .long, help: "Port for the dashboard server (used with --serve).")
    var port: Int = 8080

    func run() async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: resultBundle) else {
            print("❌ Result bundle not found: \(resultBundle)")
            throw ExitCode.failure
        }

        print("╔══════════════════════════════════════╗")
        print("║     xctest-cli • Parse Results       ║")
        print("╚══════════════════════════════════════╝")
        print()

        let parser = XCResultParser(resultBundlePath: resultBundle)
        let (suites, totalDuration) = try parser.parse()

        let _ = try ReportGenerator.generate(
            suites: suites,
            totalDuration: totalDuration,
            outputPath: output
        )

        if serve {
            let server = WebServer(reportPath: output, port: port)
            try await server.start()
        }
    }
}
