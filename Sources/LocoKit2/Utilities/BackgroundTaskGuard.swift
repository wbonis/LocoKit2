import UIKit

/// Background-task assertion that buys the process up to ~30 seconds of
/// runtime so shared-container database writes can finish before iOS
/// suspends the app. Suspending mid-write on an app-group SQLite file
/// gets the process killed with 0xdead10cc — exactly what this prevents
/// for TimelineProcessor's merge transactions.
///
/// Usage from any async context:
///
///     let keeper = await BackgroundTaskGuard(name: "TimelineProcessor.process")
///     defer { keeper.finish() }
///
/// `finish()` is idempotent and also runs from the expiration handler,
/// so the assertion can never leak.
@MainActor
public final class BackgroundTaskGuard {
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    public init(name: String) {
        taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endTask()
        }
    }

    /// Callable from any context — hops to the main actor itself so call
    /// sites can use it inside a synchronous `defer`.
    public nonisolated func finish() {
        // Keep the guard alive until the main-actor hop has ended its UIKit
        // assertion. A weak capture can let `self` disappear immediately after
        // a caller's `defer` returns, leaving the assertion behind until iOS
        // eventually kills the app for an expired background task.
        Task { @MainActor [self] in
            endTask()
        }
    }

    private func endTask() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }
}
