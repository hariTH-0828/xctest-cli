import Foundation

// MARK: - Test Report (output format)

struct TestReport: Codable {
    let summary: TestSummary
    let testSuites: [TestSuite]
    let generatedAt: String
}

struct TestSummary: Codable {
    let totalTests: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let duration: String
}

struct TestSuite: Codable {
    let name: String
    let testCases: [TestCase]
}

struct TestCase: Codable {
    let name: String
    let suiteName: String
    let status: TestStatus
    let duration: Double
    let failureMessage: String?
    let file: String?
    let line: Int?
}

enum TestStatus: String, Codable {
    case passed
    case failed
    case skipped
}

// MARK: - xcresulttool JSON Models (Apple's wrapped format)

/// Apple's xcresulttool wraps values in typed containers.
/// e.g. `{ "_type": { "_name": "String" }, "_value": "hello" }`

struct XCResultValue: Codable {
    let _value: String?
}

struct XCResultType: Codable {
    let _name: String?
}

struct XCResultTypedValue: Codable {
    let _type: XCResultType?
    let _value: String?
}

// Top-level: ActionsInvocationRecord
struct ActionsInvocationRecord: Codable {
    let _type: XCResultType?
    let actions: XCResultArray<ActionRecord>?
    let metrics: InvocationMetrics?
}

struct InvocationMetrics: Codable {
    let testsCount: XCResultTypedValue?
    let testsFailedCount: XCResultTypedValue?
    let testsSkippedCount: XCResultTypedValue?
}

struct ActionRecord: Codable {
    let _type: XCResultType?
    let actionResult: ActionResult?
    let testPlanName: XCResultTypedValue?
    let runDestination: RunDestination?
}

struct RunDestination: Codable {
    let displayName: XCResultTypedValue?
    let targetDeviceRecord: TargetDeviceRecord?
}

struct TargetDeviceRecord: Codable {
    let modelName: XCResultTypedValue?
    let operatingSystemVersion: XCResultTypedValue?
}

struct ActionResult: Codable {
    let _type: XCResultType?
    let testsRef: Reference?
}

struct Reference: Codable {
    let id: XCResultTypedValue?
}

// Test Plan Run Summaries
struct ActionTestPlanRunSummaries: Codable {
    let _type: XCResultType?
    let summaries: XCResultArray<ActionTestPlanRunSummary>?
}

struct ActionTestPlanRunSummary: Codable {
    let _type: XCResultType?
    let name: XCResultTypedValue?
    let testableSummaries: XCResultArray<ActionTestableSummary>?
}

struct ActionTestableSummary: Codable {
    let _type: XCResultType?
    let name: XCResultTypedValue?
    let tests: XCResultArray<ActionTestSummaryGroup>?
    let diagnosticsDirectoryName: XCResultTypedValue?
}

struct ActionTestSummaryGroup: Codable {
    let _type: XCResultType?
    let name: XCResultTypedValue?
    let duration: XCResultTypedValue?
    let subtests: XCResultArray<ActionTestItem>?
}

/// Can be either a group or a test case (leaf node).
struct ActionTestItem: Codable {
    let _type: XCResultType?
    let name: XCResultTypedValue?
    let identifier: XCResultTypedValue?
    let testStatus: XCResultTypedValue?
    let duration: XCResultTypedValue?
    let subtests: XCResultArray<ActionTestItem>?
    let summaryRef: Reference?
}

// Detailed test summary (for failures)
struct ActionTestSummary: Codable {
    let _type: XCResultType?
    let name: XCResultTypedValue?
    let testStatus: XCResultTypedValue?
    let duration: XCResultTypedValue?
    let failureSummaries: XCResultArray<ActionTestFailureSummary>?
}

struct ActionTestFailureSummary: Codable {
    let _type: XCResultType?
    let message: XCResultTypedValue?
    let fileName: XCResultTypedValue?
    let lineNumber: XCResultTypedValue?
}

// Generic array wrapper used throughout Apple's format
struct XCResultArray<T: Codable>: Codable {
    let _values: [T]?
}

// MARK: - Modern xcresulttool Models (Xcode 16+ `get test-results`)

struct ModernTestsResult: Codable {
    let testNodes: [ModernTestNode]
    let devices: [ModernDevice]?
    let testPlanConfigurations: [ModernConfiguration]?
}

struct ModernTestNode: Codable {
    let name: String
    let nodeType: String
    let nodeIdentifier: String?
    let details: String?
    let duration: String?
    let durationInSeconds: Double?
    let result: String?
    let tags: [String]?
    let children: [ModernTestNode]?
}

struct ModernDevice: Codable {
    let deviceId: String
    let deviceName: String
    let architecture: String?
    let modelName: String?
    let platform: String?
    let osVersion: String?
    let osBuildNumber: String?
}

struct ModernConfiguration: Codable {
    let configurationId: String
    let configurationName: String
}

struct ModernSummary: Codable {
    let title: String?
    let startTime: Double
    let finishTime: Double
    let result: String?
    let totalTestCount: Int
    let passedTests: Int
    let failedTests: Int
    let skippedTests: Int
    let expectedFailures: Int?
    let environmentDescription: String?
}
