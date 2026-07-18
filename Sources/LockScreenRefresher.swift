import AppKit

/// The aerial renderer plays our swapped video fine on the first lock after a
/// restart, then wedges into a black screen on later locks. Cure: restart the
/// renderer the moment the screen unlocks — and never while it is locked,
/// since killing it mid-lock blanks the running animation.
final class LockScreenRefresher {
    static let shared = LockScreenRefresher()

    private var observers: [NSObjectProtocol] = []
    private var isLocked = false

    var isCurrentlyLocked: Bool { isLocked }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()

        observers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLocked = true
        })

        observers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isLocked = false
            guard LockScreenInstaller.shared.isInstalled, !self.isLocked else { return }
            LockScreenInstaller.shared.resetRenderer()
        })
    }
}
