import ArgumentParser
import Foundation

/// `xctest-cli serve` — Start the local dashboard server.
struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the local HTML dashboard to view test results."
    )

    @Option(name: .long, help: "Path to the JSON report file.")
    var report: String = "reports/latest.json"

    @Option(name: .long, help: "Port to serve the dashboard on.")
    var port: Int = 8080

    @Flag(name: .long, help: "Open the dashboard in the default browser.")
    var open: Bool = false

    func run() async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: report) else {
            print("❌ No report found at: \(report)")
            print("   Run 'xctest-cli run' first to generate a report.")
            throw ExitCode.failure
        }

        print("╔══════════════════════════════════════╗")
        print("║      xctest-cli • Dashboard          ║")
        print("╚══════════════════════════════════════╝")

        if open {
            // Slight delay so server starts before browser opens
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["http://127.0.0.1:\(port)"]
                try? process.run()
            }
        }

        let server = WebServer(reportPath: report, port: port)
        try await server.start()
    }
}
