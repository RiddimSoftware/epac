import Foundation

protocol WebToAppTelemetryRecording: Sendable {
    func recordAppOpen(path: String, openedAt: Date) async
}

struct RecordWebToAppOpen: Sendable {
    let recorder: any WebToAppTelemetryRecording

    func execute(path: String) async {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        await recorder.recordAppOpen(path: trimmedPath, openedAt: Date())
    }
}

extension RecordWebToAppOpen {
    static func live() -> RecordWebToAppOpen {
        RecordWebToAppOpen(recorder: NetworkWebToAppTelemetryRecorder())
    }
}
