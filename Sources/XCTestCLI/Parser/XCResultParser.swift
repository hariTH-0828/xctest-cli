import Foundation

/// Parses `.xcresult` bundles using `xcrun xcresulttool`.
/// Supports both the modern `get test-results` API (Xcode 16+) and the legacy `get --format json` API.
struct XCResultParser {

    let resultBundlePath: String

    /// Parse the xcresult bundle and return structured test suites.
    func parse() throws -> (suites: [TestSuite], totalDuration: Double) {
        print("📊 Parsing result bundle: \(resultBundlePath)")

        // Try modern API first, fall back to legacy
        do {
            return try parseModern()
        } catch {
            print("   Modern xcresulttool API failed, trying legacy format...")
            return try parseLegacy()
        }
    }

    // MARK: - Modern API (Xcode 16+ / xcresulttool with `get test-results`)

    private func parseModern() throws -> (suites: [TestSuite], totalDuration: Double) {
        // Get the test tree
        let testsJSON = try runXCResultTool(args: [
            "get", "test-results", "tests", "--path", resultBundlePath
        ])

        let decoder = JSONDecoder()
        let testsResult = try decoder.decode(ModernTestsResult.self, from: testsJSON)

        // Get the summary for overall stats
        let summaryJSON = try runXCResultTool(args: [
            "get", "test-results", "summary", "--path", resultBundlePath
        ])
        let summary = try decoder.decode(ModernSummary.self, from: summaryJSON)

        // Walk the test node tree to extract suites and cases
        var allSuites: [TestSuite] = []
        for node in testsResult.testNodes {
            let suites = extractSuitesFromNode(node)
            allSuites.append(contentsOf: suites)
        }

        let totalDuration = summary.finishTime - summary.startTime

        print("   Found \(allSuites.count) test suite(s)")
        let totalCases = allSuites.reduce(0) { $0 + $1.testCases.count }
        print("   Found \(totalCases) test case(s)")

        return (allSuites, totalDuration)
    }

    /// Recursively walk test nodes to find Test Suite -> Test Case structure.
    private func extractSuitesFromNode(_ node: ModernTestNode) -> [TestSuite] {
        // If this node is a "Test Suite" with children that are Test Cases, collect them
        if node.nodeType == "Test Suite" {
            var testCases: [TestCase] = []
            var childSuites: [TestSuite] = []

            for child in node.children ?? [] {
                if child.nodeType == "Test Case" {
                    testCases.append(modernNodeToTestCase(child, suiteName: node.name))
                } else {
                    // Nested suites
                    childSuites.append(contentsOf: extractSuitesFromNode(child))
                }
            }

            var result: [TestSuite] = []
            if !testCases.isEmpty {
                result.append(TestSuite(name: node.name, testCases: testCases))
            }
            result.append(contentsOf: childSuites)
            return result
        }

        // Otherwise recurse into children
        var suites: [TestSuite] = []
        for child in node.children ?? [] {
            suites.append(contentsOf: extractSuitesFromNode(child))
        }
        return suites
    }

    /// Convert a modern TestNode (Test Case) to our TestCase model.
    private func modernNodeToTestCase(_ node: ModernTestNode, suiteName: String) -> TestCase {
        let resultStr = node.result ?? "unknown"
        let status: TestStatus
        switch resultStr {
        case "Passed": status = .passed
        case "Failed": status = .failed
        case "Skipped", "Expected Failure": status = .skipped
        default: status = .failed
        }

        let duration = node.durationInSeconds ?? 0

        // Extract failure info from children
        var failureMessage: String?
        var failureFile: String?
        var failureLine: Int?

        if status == .failed, let children = node.children {
            for child in children {
                if child.nodeType == "Failure Message" {
                    failureMessage = child.name
                }
                if child.nodeType == "Source Code Reference" {
                    // Format is usually "FileName.swift:LineNumber"
                    let parts = child.name.split(separator: ":")
                    if parts.count >= 2 {
                        failureFile = String(parts[0])
                        failureLine = Int(parts[1])
                    } else {
                        failureFile = child.name
                    }
                }
            }
        }

        return TestCase(
            name: node.name,
            suiteName: suiteName,
            status: status,
            duration: duration,
            failureMessage: failureMessage,
            file: failureFile,
            line: failureLine
        )
    }

    // MARK: - Legacy API (older Xcode / `get --format json`)

    private func parseLegacy() throws -> (suites: [TestSuite], totalDuration: Double) {
        let invocationJSON = try runXCResultTool(args: [
            "get", "--format", "json", "--path", resultBundlePath
        ])

        let decoder = JSONDecoder()
        let invocation = try decoder.decode(ActionsInvocationRecord.self, from: invocationJSON)

        guard let actions = invocation.actions?._values, !actions.isEmpty else {
            throw ParserError.noActionsFound
        }

        var allSuites: [TestSuite] = []
        var totalDuration: Double = 0

        for action in actions {
            guard let testsRefId = action.actionResult?.testsRef?.id?._value else {
                continue
            }

            let summariesJSON = try runXCResultTool(args: [
                "get", "--format", "json", "--path", resultBundlePath, "--id", testsRefId
            ])

            let summaries = try decoder.decode(ActionTestPlanRunSummaries.self, from: summariesJSON)

            guard let planSummaries = summaries.summaries?._values else { continue }

            for planSummary in planSummaries {
                guard let testableSummaries = planSummary.testableSummaries?._values else { continue }

                for testable in testableSummaries {
                    let testableName = testable.name?._value ?? "Unknown"
                    guard let testGroups = testable.tests?._values else { continue }

                    for group in testGroups {
                        let suites = try extractLegacyTestSuites(
                            from: group,
                            parentName: testableName,
                            decoder: decoder
                        )
                        allSuites.append(contentsOf: suites)
                    }
                }
            }
        }

        for suite in allSuites {
            for testCase in suite.testCases {
                totalDuration += testCase.duration
            }
        }

        print("   Found \(allSuites.count) test suite(s)")
        let totalCases = allSuites.reduce(0) { $0 + $1.testCases.count }
        print("   Found \(totalCases) test case(s)")

        return (allSuites, totalDuration)
    }

    private func extractLegacyTestSuites(
        from group: ActionTestSummaryGroup,
        parentName: String,
        decoder: JSONDecoder
    ) throws -> [TestSuite] {
        guard let subtests = group.subtests?._values else {
            return []
        }

        let suiteName = group.name?._value ?? parentName
        var testCases: [TestCase] = []
        var childSuites: [TestSuite] = []

        for item in subtests {
            let typeName = item._type?._name ?? ""

            if item.subtests?._values != nil && typeName != "ActionTestMetadata" {
                let subGroup = ActionTestSummaryGroup(
                    _type: item._type,
                    name: item.name,
                    duration: item.duration,
                    subtests: item.subtests
                )
                let extracted = try extractLegacyTestSuites(
                    from: subGroup,
                    parentName: suiteName,
                    decoder: decoder
                )
                childSuites.append(contentsOf: extracted)
            } else {
                let testCase = try parseLegacyTestItem(item, suiteName: suiteName, decoder: decoder)
                testCases.append(testCase)
            }
        }

        var suites: [TestSuite] = []
        if !testCases.isEmpty {
            suites.append(TestSuite(name: suiteName, testCases: testCases))
        }
        suites.append(contentsOf: childSuites)
        return suites
    }

    private func parseLegacyTestItem(
        _ item: ActionTestItem,
        suiteName: String,
        decoder: JSONDecoder
    ) throws -> TestCase {
        let name = item.name?._value ?? "Unknown"
        let statusString = item.testStatus?._value ?? "Unknown"
        let duration = Double(item.duration?._value ?? "0") ?? 0

        let status: TestStatus
        switch statusString.lowercased() {
        case "success": status = .passed
        case "failure": status = .failed
        case "skipped", "expected failure": status = .skipped
        default: status = .failed
        }

        var failureMessage: String?
        var failureFile: String?
        var failureLine: Int?

        if status == .failed, let summaryRefId = item.summaryRef?.id?._value {
            do {
                let detailJSON = try runXCResultTool(args: [
                    "get", "--format", "json", "--path", resultBundlePath, "--id", summaryRefId
                ])
                let detail = try decoder.decode(ActionTestSummary.self, from: detailJSON)

                if let failures = detail.failureSummaries?._values, let first = failures.first {
                    failureMessage = first.message?._value
                    failureFile = first.fileName?._value
                    if let lineStr = first.lineNumber?._value {
                        failureLine = Int(lineStr)
                    }
                }
            } catch {
                failureMessage = "Test failed (details unavailable)"
            }
        }

        return TestCase(
            name: name,
            suiteName: suiteName,
            status: status,
            duration: duration,
            failureMessage: failureMessage,
            file: failureFile,
            line: failureLine
        )
    }

    // MARK: - xcresulttool execution

    /// Execute xcresulttool and return raw JSON data.
    private func runXCResultTool(args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcresulttool"] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ParserError.xcresulttoolFailed(
                args: args,
                exitCode: process.terminationStatus
            )
        }

        guard !data.isEmpty else {
            throw ParserError.emptyOutput(args: args)
        }

        return data
    }
}

enum ParserError: Error, CustomStringConvertible {
    case noActionsFound
    case xcresulttoolFailed(args: [String], exitCode: Int32)
    case emptyOutput(args: [String])

    var description: String {
        switch self {
        case .noActionsFound:
            return "No test actions found in the result bundle."
        case .xcresulttoolFailed(let args, let code):
            return "xcresulttool failed (exit \(code)) with args: \(args.joined(separator: " "))"
        case .emptyOutput(let args):
            return "xcresulttool returned empty output for: \(args.joined(separator: " "))"
        }
    }
}
