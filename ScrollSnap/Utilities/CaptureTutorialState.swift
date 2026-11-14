import Foundation

struct CaptureTutorialState {
    static let pendingKey = "CaptureTutorialPending"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPending: Bool {
        defaults.bool(forKey: Self.pendingKey)
    }

    func recordLaunch(isExistingUser: Bool) {
        // Decide once, before launch tracking or the permission request writes new state.
        guard defaults.object(forKey: Self.pendingKey) == nil else { return }
        defaults.set(!isExistingUser, forKey: Self.pendingKey)
    }

    func dismiss() {
        defaults.set(false, forKey: Self.pendingKey)
    }

    #if DEBUG
    func prepareForFirstUseTest() {
        defaults.set(true, forKey: Self.pendingKey)
    }
    #endif
}
