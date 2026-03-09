# iOS XCTest Visual Test Runner

### Implementation Plan

## 1. Objective

Build a **tester-friendly tool** that allows QA engineers to execute existing **iOS XCTest unit tests** and view the results through a **local HTML dashboard**.

Developers will continue writing unit tests in XCTest.
Testers will use this tool only to **run tests and view results** without opening Xcode.

The tool should:

* Execute XCTest cases using CLI
* Parse the test result bundle (`.xcresult`)
* Convert results into structured data
* Display results in a **local web interface**
* Provide readable failure details

---

# 2. Target Users

### Developers

Responsibilities:

* Write XCTest cases
* Maintain test coverage

### QA / Testers

Responsibilities:

* Run tests
* Verify pass/fail status
* Review detailed failures

Testers should **not need Xcode knowledge**.

---

# 3. System Architecture

```
iOS Project
(Unit Tests - XCTest)
        │
        │
   xcodebuild test
        │
        │
  Test Result Bundle
     (.xcresult)
        │
        │
   Result Parser Engine
        │
        │
     JSON Report
        │
        │
   Local Web Server
        │
        │
   HTML Dashboard
 http://localhost:PORT
```

---

# 4. Technology Stack

## CLI Layer

Recommended language:

**Swift**

Reasons:

* Native macOS support
* Easy integration with Xcode tools
* Direct access to Apple utilities

Libraries:

* Swift ArgumentParser
* Foundation
* Vapor (optional web server)

Alternative:

* Node.js + Express

---

# 5. Core Components

## 5.1 Test Runner

Responsible for executing XCTest from command line.

Example command:

```bash
xcodebuild test \
-scheme MyApp \
-destination 'platform=iOS Simulator,name=iPhone 15'
```

Output generated:

```
DerivedData/Logs/Test/*.xcresult
```

This `.xcresult` file contains all test information.

---

# 5.2 Result Extraction

Apple provides a tool to read `.xcresult` bundles.

Command:

```bash
xcrun xcresulttool get --format json --path Test.xcresult
```

This converts the result bundle into **JSON format**.

Example:

```json
{
  "testsCount": 25,
  "testsPassedCount": 23,
  "testsFailedCount": 2,
  "failures": [
    {
      "testName": "LoginTests.testInvalidPassword",
      "message": "XCTAssertEqual failed"
    }
  ]
}
```

---

# 5.3 Result Parser

The parser converts raw JSON into structured data.

### Data Model

```
TestSuite
 ├── name
 ├── testCases[]
```

Test case structure:

```
TestCase
 ├── name
 ├── status (pass/fail)
 ├── duration
 ├── errorMessage
 ├── file
 └── line
```

---

# 5.4 Report Generator

Convert parsed results into a **clean JSON report**.

Example:

```json
{
 "totalTests": 120,
 "passed": 115,
 "failed": 5,
 "duration": "2m15s",
 "tests": [
   {
     "name": "LoginTests.testValidLogin",
     "status": "passed",
     "duration": "0.12s"
   },
   {
     "name": "LoginTests.testInvalidPassword",
     "status": "failed",
     "message": "Expected true but got false"
   }
 ]
}
```

Store output in:

```
reports/latest.json
```

---

# 5.5 Local Web Server

Start a lightweight server.

Example:

```
http://localhost:8080
```

Responsibilities:

* Serve HTML dashboard
* Load test report JSON
* Display results visually

Possible tools:

Swift:

* Vapor

Node alternative:

* Express

---

# 6. HTML Dashboard

## 6.1 Summary Section

Display overall test metrics.

Example:

```
Total Tests: 120
Passed: 115
Failed: 5
Execution Time: 2m15s
```

Visual indicators:

* Green → Passed
* Red → Failed

---

## 6.2 Test Case Table

| Test Case                      | Status | Duration |
| ------------------------------ | ------ | -------- |
| LoginTests.testValidLogin      | PASS   | 0.12s    |
| LoginTests.testInvalidPassword | FAIL   | 0.15s    |

---

## 6.3 Failure Detail Panel

When a failure is selected:

```
Test Name:
LoginTests.testInvalidPassword

Failure:
XCTAssertEqual failed

Expected: true
Actual: false

File:
LoginTests.swift

Line:
45
```

---

# 7. CLI Commands

Suggested CLI interface.

### Run Tests

```
tester run
```

Runs XCTest and generates report.

---

### Serve Report

```
tester serve
```

Starts local dashboard server.

---

### Combined Command

```
tester run --serve
```

Runs tests and automatically opens dashboard.

---

# 8. Project Structure

```
ios-test-dashboard
│
├── cli
│   └── run-tests.swift
│
├── parser
│   └── xcresult-parser.swift
│
├── report
│   └── report-generator.swift
│
├── server
│   └── web-server.swift
│
├── ui
│   ├── index.html
│   ├── dashboard.js
│   └── style.css
│
└── reports
    └── latest.json
```

---

# 9. Implementation Phases

## Phase 1 — Test Execution

Features:

* Run XCTest via `xcodebuild`
* Generate `.xcresult`
* Extract JSON data

Goal:
Produce a **basic JSON report**.

---

## Phase 2 — Result Parsing

Features:

* Parse test suites
* Parse individual test cases
* Capture failures

Goal:
Generate structured report file.

---

## Phase 3 — HTML Dashboard

Features:

* Test summary view
* Test table
* Failure detail view

Goal:
Visualize test results via browser.

---

## Phase 4 — Usability Improvements

Features:

* Auto refresh results
* Filter failed tests
* Search test cases
* Download report

---

# 10. Advanced Features (Future)

### Live Test Monitoring

Show test progress while running.

---

### Historical Reports

```
Run #1
Run #2
Run #3
```

Compare results across runs.

---

# 11. Expected Outcome

After implementation, testers will be able to:

1. Run tests with a simple command

```
tester run
```

2. Open browser

```
http://localhost:8080
```

3. View test results clearly without using Xcode.

---

# 12. Already Existing Tools

Look at these for inspiration:

* fastlane scan
* xcpretty
* Allure Report
* Danger

# 13. Key Benefits

* QA teams can validate unit tests independently
* Faster debugging of failed tests
* Clear visual reporting
* No dependency on Xcode UI
* Can integrate with CI systems

---

# End of Implementation Plan
