import AppKit
import Foundation

@MainActor
protocol ApplicationRemovalFeedbackPlaying: AnyObject {
    func playSuccessfulRemoval()
}

@MainActor
final class BundledApplicationRemovalFeedbackPlayer: ApplicationRemovalFeedbackPlaying {
    private let sound: NSSound?

    init(bundle: Bundle = .main) {
        sound = bundle.url(forResource: "ApplicationRemoved", withExtension: "wav")
            .flatMap { NSSound(contentsOf: $0, byReference: true) }
    }

    func playSuccessfulRemoval() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] == nil,
            environment["ZIZAI_UI_TESTING"] != "1",
            let sound
        else { return }

        sound.stop()
        sound.volume = 0.72
        sound.play()
    }
}

@MainActor
extension ApplicationRemovalCoordinator {
    var isRemovingAppID: String? {
        switch removalFlow {
        case .recycling(let app), .completing(let app):
            return app.id
        default:
            return nil
        }
    }

    var completingAppID: String? {
        guard case .completing(let app) = removalFlow else { return nil }
        return app.id
    }

    func beginSuccessfulRemovalFeedback(for app: AppInfo) {
        removalCompletionTask?.cancel()
        removalFlow = .completing(app)
        removalFeedbackPlayer.playSuccessfulRemoval()

        let duration = successfulRemovalFeedbackDuration
        removalCompletionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled,
                let self,
                self.completingAppID == app.id
            else { return }

            self.onRemovalCompleted(app)
            self.removalFlow = .idle
            self.removalCompletionTask = nil
        }
    }
}
