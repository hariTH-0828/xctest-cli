import Vapor

/// Lightweight Vapor web server that serves the HTML dashboard and test report API.
struct WebServer {

    let reportPath: String
    let port: Int

    /// Start the Vapor server.
    func start() async throws {
        var env = Environment(name: "production", arguments: ["serve"])
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        app.http.server.configuration.port = port
        app.http.server.configuration.hostname = "127.0.0.1"

        // Routes
        let capturedReportPath = reportPath

        app.get { req -> Response in
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "text/html; charset=utf-8")
            return Response(status: .ok, headers: headers, body: .init(string: DashboardHTML.indexHTML))
        }

        app.get("api", "report") { req -> Response in
            let fm = FileManager.default
            guard fm.fileExists(atPath: capturedReportPath),
                  let data = fm.contents(atPath: capturedReportPath) else {
                throw Abort(.notFound, reason: "No report found at \(capturedReportPath)")
            }
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            return Response(status: .ok, headers: headers, body: .init(data: data))
        }

        app.get("health") { _ -> HTTPStatus in .ok }

        app.get("api", "live") { req -> Response in
            let snapshot = LiveTestState.shared.snapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            headers.add(name: .cacheControl, value: "no-cache")
            return Response(status: .ok, headers: headers, body: .init(data: data))
        }

        print()
        print("🌐 Dashboard server started!")
        print("   Open: http://127.0.0.1:\(port)")
        print("   Report: \(capturedReportPath)")
        print("   Press Ctrl+C to stop")
        print()

        do {
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
    }
}
