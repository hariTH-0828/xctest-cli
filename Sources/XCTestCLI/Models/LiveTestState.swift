import Foundation

/// Thread-safe shared state for live test progress.
/// Updated by TestRunner as tests execute, read by WebServer endpoints.
final class LiveTestState: @unchecked Sendable {

    static let shared = LiveTestState()

    private let lock = NSLock()

    private var _phase: Phase = .idle
    private var _testCases: [LiveTestCase] = []
    private var _currentTest: String?
    private var _startTime: Date?
    private var _scheme: String = ""

    enum Phase: String, Codable {
        case idle       // Not started
        case building   // Compiling
        case testing    // Running tests
        case done       // Finished
    }

    struct LiveTestCase: Codable {
        let name: String
        let suiteName: String
        let status: TestStatus
        let duration: Double
        let failureMessage: String?
    }

    struct Snapshot: Codable {
        let phase: String
        let scheme: String
        let currentTest: String?
        let passed: Int
        let failed: Int
        let skipped: Int
        let totalCompleted: Int
        let elapsed: Double
        let testCases: [LiveTestCase]
    }

    // MARK: - Write (called by TestRunner)

    func reset(scheme: String) {
        lock.lock()
        defer { lock.unlock() }
        _phase = .idle
        _testCases = []
        _currentTest = nil
        _startTime = Date()
        _scheme = scheme
    }

    func setPhase(_ phase: Phase) {
        lock.lock()
        defer { lock.unlock() }
        _phase = phase
    }

    func testStarted(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        _phase = .testing
        _currentTest = name
    }

    func testCompleted(_ testCase: LiveTestCase) {
        lock.lock()
        defer { lock.unlock() }
        _testCases.append(testCase)
        _currentTest = nil
    }

    // MARK: - Read (called by WebServer)

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = _startTime.map { Date().timeIntervalSince($0) } ?? 0
        return Snapshot(
            phase: _phase.rawValue,
            scheme: _scheme,
            currentTest: _currentTest,
            passed: _testCases.filter { $0.status == .passed }.count,
            failed: _testCases.filter { $0.status == .failed }.count,
            skipped: _testCases.filter { $0.status == .skipped }.count,
            totalCompleted: _testCases.count,
            elapsed: elapsed,
            testCases: _testCases
        )
    }
}
