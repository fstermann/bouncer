import Observation

/// Runs `body` now and again on every change to the `@Observable` properties it reads.
///
/// `withObservationTracking` is one-shot; this re-arms it. Cancel via the returned
/// handle when the observer outlives its subject.
@MainActor
public final class ObservationLoop {
    private var isCancelled = false

    public init(_ body: @MainActor @escaping () -> Void) {
        arm(body)
    }

    private func arm(_ body: @MainActor @escaping () -> Void) {
        withObservationTracking {
            body()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isCancelled else { return }
                self.arm(body)
            }
        }
    }

    public func cancel() {
        isCancelled = true
    }
}
