import Foundation

/// Provides interactive terminal prompts for selecting options.
enum InteractivePrompt {

    // MARK: - Generic selection

    /// Display a numbered list and let the user pick one.
    /// Returns the selected item.
    static func choose<T: CustomStringConvertible>(
        prompt: String,
        from options: [T]
    ) -> T {
        print(prompt)
        for (i, option) in options.enumerated() {
            print("  \(i + 1)) \(option)")
        }
        print()

        while true {
            print("  Enter choice (1-\(options.count)): ", terminator: "")
            guard let line = readLine()?.trimmingCharacters(in: .whitespaces),
                  let index = Int(line),
                  index >= 1, index <= options.count else {
                print("  ⚠ Invalid selection. Try again.")
                continue
            }
            return options[index - 1]
        }
    }

    /// Display a numbered list and let the user pick one or more items.
    /// Input: comma-separated numbers or ranges (e.g. "1,3" or "1-3" or "all").
    /// Returns the selected items.
    static func chooseMultiple<T: CustomStringConvertible>(
        prompt: String,
        from options: [T]
    ) -> [T] {
        print(prompt)
        for (i, option) in options.enumerated() {
            print("  \(i + 1)) \(option)")
        }
        print()

        while true {
            print("  Enter choices (e.g. 1,3 or 1-3 or 'all'): ", terminator: "")
            guard let line = readLine()?.trimmingCharacters(in: .whitespaces), !line.isEmpty else {
                print("  ⚠ Invalid selection. Try again.")
                continue
            }

            if line.lowercased() == "all" {
                return options
            }

            var indices = Set<Int>()
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var valid = true

            for part in parts {
                if part.contains("-") {
                    let rangeParts = part.split(separator: "-")
                    guard rangeParts.count == 2,
                          let start = Int(rangeParts[0]),
                          let end = Int(rangeParts[1]),
                          start >= 1, end <= options.count, start <= end else {
                        valid = false
                        break
                    }
                    for i in start...end { indices.insert(i) }
                } else if let num = Int(part), num >= 1, num <= options.count {
                    indices.insert(num)
                } else {
                    valid = false
                    break
                }
            }

            if !valid || indices.isEmpty {
                print("  ⚠ Invalid selection. Try again.")
                continue
            }

            return indices.sorted().map { options[$0 - 1] }
        }
    }

    /// Ask a yes/no question. Returns true for yes.
    static func confirm(_ prompt: String, default defaultValue: Bool = false) -> Bool {
        let hint = defaultValue ? "(Y/n)" : "(y/N)"
        print("\(prompt) \(hint): ", terminator: "")
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return defaultValue
        }
        if line.isEmpty { return defaultValue }
        return line == "y" || line == "yes"
    }

    // MARK: - Discover projects / workspaces

    struct ProjectInfo: CustomStringConvertible {
        enum Kind: String { case workspace, project }
        let kind: Kind
        let path: String
        let name: String

        var description: String {
            let icon = kind == .workspace ? "📂" : "📁"
            return "\(icon) \(name) (\(kind.rawValue))"
        }
    }

    /// Scan the current directory for .xcworkspace and .xcodeproj files.
    static func discoverProjects(in directory: String = ".") -> [ProjectInfo] {
        let fm = FileManager.default
        var results: [ProjectInfo] = []

        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else {
            return results
        }

        // Workspaces first (preferred)
        for item in contents.sorted() {
            if item.hasSuffix(".xcworkspace") {
                let fullPath = (directory as NSString).appendingPathComponent(item)
                results.append(ProjectInfo(kind: .workspace, path: fullPath, name: item))
            }
        }
        for item in contents.sorted() {
            if item.hasSuffix(".xcodeproj") {
                let fullPath = (directory as NSString).appendingPathComponent(item)
                results.append(ProjectInfo(kind: .project, path: fullPath, name: item))
            }
        }

        return results
    }

    // MARK: - Discover schemes

    /// List schemes from a project or workspace using `xcodebuild -list`.
    static func discoverSchemes(project: String? = nil, workspace: String? = nil) -> [String] {
        var args: [String] = ["-list"]
        if let ws = workspace {
            args += ["-workspace", ws]
        } else if let proj = project {
            args += ["-project", proj]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
        }

        // Parse the "Schemes:" section
        var schemes: [String] = []
        var inSchemes = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Schemes:") {
                inSchemes = true
                continue
            }
            if inSchemes {
                if trimmed.isEmpty { break }
                schemes.append(trimmed)
            }
        }
        return schemes
    }

    // MARK: - Discover simulators

    struct Simulator: CustomStringConvertible {
        let name: String
        let runtime: String
        let udid: String
        let state: String

        var description: String {
            let stateIcon = state == "Booted" ? "🟢" : "⚪"
            return "\(stateIcon) \(name) — \(runtime)"
        }

        var destination: String {
            "platform=iOS Simulator,name=\(name)"
        }
    }

    /// List available iOS simulators using `xcrun simctl list devices available -j`.
    static func discoverSimulators() -> [Simulator] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "available", "-j"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }

        var simulators: [Simulator] = []

        for (runtimeKey, deviceList) in devices {
            // Only iOS simulators
            guard runtimeKey.contains("iOS") || runtimeKey.contains("iphone") || runtimeKey.contains("SimRuntime.iOS") else {
                continue
            }

            // Extract readable runtime name — e.g. "com.apple.CoreSimulator.SimRuntime.iOS-18-0" → "iOS 18.0"
            let runtime = readableRuntime(from: runtimeKey)

            for device in deviceList {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String,
                      let isAvailable = device["isAvailable"] as? Bool,
                      isAvailable else { continue }
                let state = device["state"] as? String ?? "Shutdown"
                simulators.append(Simulator(name: name, runtime: runtime, udid: udid, state: state))
            }
        }

        // Sort: booted first, then by runtime (newest first), then name
        simulators.sort { a, b in
            if a.state == "Booted" && b.state != "Booted" { return true }
            if a.state != "Booted" && b.state == "Booted" { return false }
            if a.runtime != b.runtime { return a.runtime > b.runtime }
            return a.name < b.name
        }

        // Filter to only iPhone simulators for clarity
        return simulators.filter { $0.name.contains("iPhone") || $0.name.contains("iPad") }
    }

    // MARK: - Discover test targets

    struct TestTarget: CustomStringConvertible {
        let name: String
        let isUITest: Bool

        var description: String {
            let icon = isUITest ? "📱" : "🧪"
            let kind = isUITest ? "UI Tests" : "Unit Tests"
            return "\(icon) \(name) (\(kind))"
        }
    }

    /// Discover test targets from a project or workspace using `xcodebuild -list`.
    static func discoverTestTargets(project: String? = nil, workspace: String? = nil) -> [TestTarget] {
        var args: [String] = ["-list"]
        if let ws = workspace {
            args += ["-workspace", ws]
        } else if let proj = project {
            args += ["-project", proj]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
        }

        // Parse the "Targets:" section — test targets typically end in "Tests"
        var targets: [String] = []
        var inTargets = false
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Targets:") {
                inTargets = true
                continue
            }
            if inTargets {
                if trimmed.isEmpty { break }
                targets.append(trimmed)
            }
        }

        // Filter to only test targets (names containing "Test")
        return targets
            .filter { $0.lowercased().contains("test") }
            .map { name in
                let isUI = name.lowercased().contains("uitest")
                return TestTarget(name: name, isUITest: isUI)
            }
    }

    private static func readableRuntime(from key: String) -> String {
        // "com.apple.CoreSimulator.SimRuntime.iOS-18-0" → "iOS 18.0"
        if let range = key.range(of: "SimRuntime.") {
            let suffix = String(key[range.upperBound...])   // "iOS-18-0"
            // Replace first dash with space (e.g. "iOS-18-0" → "iOS 18-0"), then remaining dashes with dots
            guard let firstDash = suffix.firstIndex(of: "-") else { return suffix }
            var result = suffix
            result.replaceSubrange(firstDash...firstDash, with: " ")
            result = result.replacingOccurrences(of: "-", with: ".")
            return result
        }
        return key.components(separatedBy: ".").last ?? key
    }
}
