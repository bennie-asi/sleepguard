import Foundation

@main struct MonitoringStateChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        let future = now.addingTimeInterval(30)
        assert(MonitoringState(watcherRunning: nil, pausedUntil: nil, now: now) == .unavailable)
        assert(MonitoringState(watcherRunning: false, pausedUntil: nil, now: now) == .stopped)
        assert(MonitoringState(watcherRunning: true, pausedUntil: nil, now: now) == .running)
        assert(MonitoringState(watcherRunning: true, pausedUntil: future, now: now) == .paused)
        // A persisted pause must still have a recovery action when the agent is offline.
        assert(MonitoringState(watcherRunning: false, pausedUntil: future, now: now) == .paused)
        // Expiry and manual recovery return to the actual process state.
        assert(MonitoringState(watcherRunning: true, pausedUntil: now, now: now) == .running)
        assert(MonitoringState(watcherRunning: false, pausedUntil: now, now: now) == .stopped)
        assert(MonitoringState(watcherRunning: true, pausedUntil: nil, now: future) == .running)
        print("Monitoring state checks passed (pause, offline recovery and expiry)")
    }
}
