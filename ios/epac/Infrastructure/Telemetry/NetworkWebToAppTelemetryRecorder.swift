import Foundation

struct NetworkWebToAppTelemetryRecorder: WebToAppTelemetryRecording {
    func recordAppOpen(path: String, openedAt: Date) async {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "epac.riddimsoftware.com"
        components.path = "/app/telemetry/"
        components.queryItems = [
            URLQueryItem(name: "event", value: "app-open"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "ts", value: String(Int(openedAt.timeIntervalSince1970 * 1000)))
        ]

        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        _ = try? await NetworkService.shared.data(for: request)
    }
}
