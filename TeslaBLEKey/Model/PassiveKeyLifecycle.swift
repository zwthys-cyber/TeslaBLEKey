/// Process-local coordinator for the restorable Phone Key connection.
/// Generation tokens prevent stale async work from publishing state after a
/// newer connection or selected vehicle has taken ownership.
struct PassiveKeyLifecycle: Equatable {
    enum State: Equatable {
        case disabled, idle, waitingForVehicle, connecting
        case establishingSession, listening, interrupted, restoring, failed
    }

    private(set) var state: State
    private(set) var generation: UInt64 = 0
    private(set) var activeOperation: UInt64?

    init(enabled: Bool) { state = enabled ? .idle : .disabled }

    mutating func setEnabled(_ enabled: Bool) {
        invalidate(nextState: enabled ? .idle : .disabled)
    }

    mutating func beginConnection() -> UInt64 {
        generation &+= 1
        activeOperation = generation
        state = .connecting
        return generation
    }

    @discardableResult
    mutating func interrupt() -> UInt64 {
        generation &+= 1
        activeOperation = nil
        state = .interrupted
        return generation
    }

    mutating func beginRecovery(for expectedGeneration: UInt64) -> Bool {
        guard expectedGeneration == generation, activeOperation == nil,
              state != .disabled, state != .listening else { return false }
        activeOperation = expectedGeneration
        state = .restoring
        return true
    }

    mutating func markEstablishingSession(for token: UInt64) -> Bool {
        guard owns(token) else { return false }
        state = .establishingSession
        return true
    }

    mutating func markListening(for token: UInt64) -> Bool {
        guard owns(token) else { return false }
        state = .listening
        activeOperation = nil
        return true
    }

    mutating func markWaiting(for token: UInt64) -> Bool {
        guard owns(token) else { return false }
        state = .waitingForVehicle
        activeOperation = nil
        return true
    }

    func owns(_ token: UInt64) -> Bool {
        token == generation && activeOperation == token
    }

    mutating func invalidate(nextState: State = .idle) {
        generation &+= 1
        activeOperation = nil
        state = nextState
    }
}
