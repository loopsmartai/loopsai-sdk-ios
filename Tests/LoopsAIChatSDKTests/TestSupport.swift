import Foundation

/// Thread-safe recorder for analytics events captured inside `@Sendable`
/// adapter closures (avoids mutating captured `var`s, which is a Swift 6 error).
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func record(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        names.append(name)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return names
    }

    var count: Int { all.count }
}
