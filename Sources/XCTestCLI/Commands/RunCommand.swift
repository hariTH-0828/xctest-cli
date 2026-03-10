import ArgumentParser
import Foundation

/// `xctest-cli run` — Execute XCTest cases and generate a report.
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run XCTest cases and generate a test report."
    )

    @Argument(help: "Path to the project directory, .xcodeproj, or .xcworkspace. Defaults to the current directory.")
    var projectPath: String?

    @Option(name: .long, help: "The Xcode scheme to test. If omitted, you'll be prompted to select one.")
    var scheme: String?

    @Option(name: .long, help: "The simulator destination (e.g., 'platform=iOS Simulator,name=iPhone 16').")
    var destination: String?

    @Option(name: .long, help: "Path to the .xcworkspace file (auto-detected from project path).")
    var workspace: String?

    @Option(name: .long, help: "Path to the .xcodeproj file (auto-detected from project path).")
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

        // Resolve options interactively if not provided
        let resolved = resolveOptions()

        // Build -only-testing args from selected targets
        var extraArgs: [String] = []
        if !resolved.testTargets.isEmpty {
            for target in resolved.testTargets {
                extraArgs += ["-only-testing", target]
            }
        }

        // Step 1: Run tests
        let config = TestRunner.Configuration(
            scheme: resolved.scheme,
            destination: resolved.destination,
            project: resolved.project,
            workspace: resolved.workspace,
            resultBundlePath: resultBundlePath,
            extraArgs: extraArgs
        )

        // Start server BEFORE tests if --serve is set, so dashboard shows live progress
        var serverTask: Task<Void, Error>?
        if serve {
            let server = WebServer(reportPath: output, port: port)
            serverTask = Task {
                try await server.start()
            }
            // Give server a moment to start
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Run tests on a background thread so we don't block the Vapor event loop
        let capturedConfig = config
        let bundlePath: String = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try TestRunner.runTests(config: capturedConfig)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

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

        // Step 4: Keep server running if started
        if let task = serverTask {
            try await task.value
        }
    }

    private struct ResolvedOptions {
        let scheme: String
        let destination: String
        let project: String?
        let workspace: String?
        let testTargets: [String]  // empty = run all
    }

    /// Interactively resolve any missing options by discovering and prompting.
    private func resolveOptions() -> ResolvedOptions {
        var resolvedProject = project
        var resolvedWorkspace = workspace
        var resolvedScheme = scheme
        var resolvedDestination = destination

        // --- Step 1: Resolve project path ---
        // If the user gave a direct .xcodeproj or .xcworkspace path, use it.
        // Otherwise treat it as a directory to scan.
        if resolvedProject == nil && resolvedWorkspace == nil {
            let basePath = projectPath ?? "."
            let absPath = (basePath as NSString).standardizingPath
            let resolvedBase = absPath.hasPrefix("/") ? absPath
                : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(absPath)

            if resolvedBase.hasSuffix(".xcworkspace") {
                resolvedWorkspace = resolvedBase
                print("📦 Using workspace: \(resolvedBase)")
                print()
            } else if resolvedBase.hasSuffix(".xcodeproj") {
                resolvedProject = resolvedBase
                print("📦 Using project: \(resolvedBase)")
                print()
            } else {
                // Scan directory
                let searchDir = resolvedBase
                let projects = InteractivePrompt.discoverProjects(in: searchDir)
                if projects.isEmpty {
                    print("⚠ No .xcodeproj or .xcworkspace found in: \(searchDir)")
                    print("  Provide a path to your project directory or use --project / --workspace.")
                    print()
                } else if projects.count == 1 {
                    let p = projects[0]
                    print("📦 Found: \(p.name)")
                    switch p.kind {
                    case .workspace: resolvedWorkspace = p.path
                    case .project:   resolvedProject = p.path
                    }
                    print()
                } else {
                    print("📦 Multiple projects found in \(searchDir):\n")
                    let selected = InteractivePrompt.choose(prompt: "  Select a project:", from: projects)
                    switch selected.kind {
                    case .workspace: resolvedWorkspace = selected.path
                    case .project:   resolvedProject = selected.path
                    }
                    print()
                }
            }
        }

        // --- Step 2: Scheme ---
        if resolvedScheme == nil {
            print("🔍 Discovering schemes...")
            let schemes = InteractivePrompt.discoverSchemes(project: resolvedProject, workspace: resolvedWorkspace)
            if schemes.isEmpty {
                print("⚠ No schemes found. Use --scheme to specify one.")
                print()
            } else if schemes.count == 1 {
                resolvedScheme = schemes[0]
                print("🎯 Using scheme: \(schemes[0])")
                print()
            } else {
                print()
                resolvedScheme = InteractivePrompt.choose(prompt: "  Select a scheme:", from: schemes)
                print()
            }
        }

        // --- Step 3: Destination (Simulator) ---
        if resolvedDestination == nil {
            print("📱 Discovering simulators...")
            let simulators = InteractivePrompt.discoverSimulators()
            if simulators.isEmpty {
                print("⚠ No iOS simulators found. Using default destination.")
                resolvedDestination = "platform=iOS Simulator,name=iPhone 16"
                print()
            } else {
                print()
                let selected = InteractivePrompt.choose(prompt: "  Select a simulator:", from: simulators)
                resolvedDestination = selected.destination
                print()
            }
        }

        // --- Step 4: Test Targets (Unit / UI) ---
        var selectedTargets: [String] = []
        print("🧪 Discovering test targets...")
        let testTargets = InteractivePrompt.discoverTestTargets(
            project: resolvedProject, workspace: resolvedWorkspace
        )
        if testTargets.count > 1 {
            print()
            let selected = InteractivePrompt.chooseMultiple(
                prompt: "  Select test targets to run:",
                from: testTargets
            )
            selectedTargets = selected.map { $0.name }
            let names = selected.map { $0.description }.joined(separator: ", ")
            print()
            print("  Selected: \(names)")
            print()
        } else if testTargets.count == 1 {
            print("  Found: \(testTargets[0].description)")
            selectedTargets = [testTargets[0].name]
            print()
        } else {
            print("  No specific test targets found — will run all tests.")
            print()
        }

        // Final guard — scheme is required
        guard let finalScheme = resolvedScheme else {
            print("❌ No scheme specified. Use --scheme or run from a directory with an Xcode project.")
            Foundation.exit(1)
        }

        return ResolvedOptions(
            scheme: finalScheme,
            destination: resolvedDestination ?? "platform=iOS Simulator,name=iPhone 16",
            project: resolvedProject,
            workspace: resolvedWorkspace,
            testTargets: selectedTargets
        )
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
