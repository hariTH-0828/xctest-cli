import ArgumentParser

@main
struct XCTestCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xctest-cli",
        abstract: "A tester-friendly tool to run iOS XCTest cases and view results in a local dashboard.",
        version: "1.0.0",
        subcommands: [RunCommand.self, ServeCommand.self, ParseCommand.self],
        defaultSubcommand: nil
    )
}
