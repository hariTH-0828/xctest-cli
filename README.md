# xctest-cli

A tester-friendly CLI tool to run iOS XCTest cases and view results through a local HTML dashboard — no Xcode knowledge required.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/macOS-13+-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Xcode-16+-1575F9?logo=xcode&logoColor=white" alt="Xcode 16+">
  <img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version 1.0.0">
</p>

---

## Overview

**xctest-cli** bridges the gap between developers who write XCTest cases and QA engineers who need to run and review them. It wraps `xcodebuild test`, parses `.xcresult` bundles, and serves results on a local web dashboard.

```
iOS Project (XCTest)
        │
   xcodebuild test
        │
   .xcresult bundle
        │
   Result Parser Engine
        │
   JSON Report
        │
   Local Web Server (Vapor)
        │
   HTML Dashboard → http://localhost:8080
```

## Features

- **Run tests** from the command line with a single command
- **Parse `.xcresult` bundles** (supports both modern Xcode 16+ and legacy formats)
- **Generate structured JSON reports** with pass/fail details, durations, and failure messages
- **Serve a local HTML dashboard** with filtering, search, and auto-refresh
- **No Xcode knowledge required** — QA engineers just run one command

## Requirements

- macOS 13+
- Xcode 16+ (with `xcresulttool`)
- Swift 5.9+
- An iOS project with XCTest cases

## Installation

### Build from source

```bash
git clone https://github.com/hariTH-0828/xctest-cli.git
cd xctest-cli
swift build -c release
```

The binary will be at `.build/release/xctest-cli`. Optionally, copy it to your PATH:

```bash
cp .build/release/xctest-cli /usr/local/bin/
```

## Usage

### Interactive mode (recommended)

Just run `xctest-cli run` from your project directory — no options needed:

```bash
cd /path/to/MyApp
xctest-cli run --serve
```

The tool will automatically:
1. **Detect** `.xcworkspace` / `.xcodeproj` files in the current directory
2. **List schemes** and let you pick one
3. **List available iOS simulators** and let you choose
4. **Run tests**, generate a report, and serve the dashboard

```
╔══════════════════════════════════════╗
║         xctest-cli • Run Tests       ║
╚══════════════════════════════════════╝

📦 Found: MyApp.xcodeproj

🔍 Discovering schemes...

  Select a scheme:
  1) MyApp
  2) MyAppTests
  
  Enter choice (1-2): 1

📱 Discovering simulators...

  Select a simulator:
  1) 🟢 iPhone 17 — iOS 26.2
  2) ⚪ iPhone 17 Pro — iOS 26.2
  3) ⚪ iPhone 16 — iOS 18.0

  Enter choice (1-3): 1
```

### Explicit options (for CI / scripting)

You can skip the interactive prompts by providing options directly:

```bash
xctest-cli run \
  --scheme MyApp \
  --project /path/to/MyApp.xcodeproj \
  --destination 'platform=iOS Simulator,name=iPhone 17' \
  --serve
```

This will:
1. Execute all XCTest cases in the scheme
2. Parse the `.xcresult` bundle
3. Generate a JSON report at `reports/latest.json`
4. Start the dashboard at `http://127.0.0.1:8080`

### Using a workspace

```bash
xctest-cli run \
  --scheme MyApp \
  --workspace /path/to/MyApp.xcworkspace \
  --destination 'platform=iOS Simulator,name=iPhone 17' \
  --serve --port 3000
```

### Parse an existing `.xcresult` bundle

```bash
xctest-cli parse /path/to/TestResults.xcresult --serve
```

### Serve a previously generated report

```bash
xctest-cli serve --report reports/latest.json --port 8080 --open
```

## Commands

### `xctest-cli run`

Run XCTest cases and generate a test report.

| Option | Default | Description |
|---|---|---|
| `--scheme` | *(required)* | Xcode scheme to test |
| `--project` | — | Path to `.xcodeproj` |
| `--workspace` | — | Path to `.xcworkspace` |
| `--destination` | `platform=iOS Simulator,name=iPhone 16` | Simulator destination |
| `--result-bundle-path` | `.xctest-cli/TestResults.xcresult` | Where to store the result bundle |
| `--output` | `reports/latest.json` | JSON report output path |
| `--serve` | `false` | Start the dashboard after tests complete |
| `--port` | `8080` | Dashboard server port |

### `xctest-cli parse`

Parse an existing `.xcresult` bundle without re-running tests.

| Option | Default | Description |
|---|---|---|
| `<result-bundle>` | *(required)* | Path to the `.xcresult` bundle |
| `--output` | `reports/latest.json` | JSON report output path |
| `--serve` | `false` | Start the dashboard after parsing |
| `--port` | `8080` | Dashboard server port |

### `xctest-cli serve`

Start the local HTML dashboard to view test results.

| Option | Default | Description |
|---|---|---|
| `--report` | `reports/latest.json` | Path to the JSON report |
| `--port` | `8080` | Dashboard server port |
| `--open` | `false` | Auto-open the dashboard in the default browser |

## Dashboard

The dashboard is a single-page app served directly from the binary (no external files needed).

**Features:**
- Summary cards showing total tests, passed, failed, and skipped counts
- Visual progress bar for pass/fail ratio
- Filter buttons — All, Passed, Failed, Skipped
- Search across test names
- Collapsible test suites with individual test details
- Failure detail panel with error messages, file paths, and line numbers
- Download report as JSON
- Auto-refresh every 10 seconds

**API Endpoints:**

| Endpoint | Description |
|---|---|
| `GET /` | HTML dashboard |
| `GET /api/report` | JSON test report |
| `GET /health` | Health check (returns 200) |

## JSON Report Format

```json
{
  "generatedAt": "2026-03-09T16:28:40Z",
  "summary": {
    "totalTests": 21,
    "passed": 21,
    "failed": 0,
    "skipped": 0,
    "duration": "3m48.83s"
  },
  "testSuites": [
    {
      "name": "MyAppTests",
      "testCases": [
        {
          "name": "testLoginSuccess()",
          "suiteName": "MyAppTests",
          "status": "passed",
          "duration": 0.12
        }
      ]
    }
  ]
}
```

## Project Structure

```
Sources/XCTestCLI/
├── XCTestCLI.swift          # Entry point
├── Commands/
│   ├── RunCommand.swift      # xctest-cli run
│   ├── ServeCommand.swift    # xctest-cli serve
│   └── ParseCommand.swift    # xctest-cli parse
├── Runner/
│   └── TestRunner.swift      # xcodebuild test execution
├── Parser/
│   └── XCResultParser.swift  # .xcresult bundle parser
├── Models/
│   └── TestReport.swift      # Data models
├── Report/
│   └── ReportGenerator.swift # JSON report generation
├── Server/
│   └── WebServer.swift       # Vapor HTTP server
└── Dashboard/
    └── DashboardHTML.swift    # Embedded HTML/CSS/JS
```

## License

MIT
