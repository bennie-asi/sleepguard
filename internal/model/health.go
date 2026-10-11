package model

import "time"

// Written only by the watcher; UI collection must never advance these times.
type WatcherHealth struct {
	PID             int       `json:"pid"`
	StartedAt       time.Time `json:"started_at"`
	LastAttempt     time.Time `json:"last_attempt"`
	LastSuccess     time.Time `json:"last_success"`
	LastErrorAt     time.Time `json:"last_error_at"`
	LastError       string    `json:"last_error"`
	IntervalSeconds float64   `json:"interval_seconds"`
	Status          string    `json:"status"`
}

func (h WatcherHealth) State(running bool, now time.Time) string {
	if !running {
		return "stopped"
	}
	if h.StartedAt.IsZero() {
		return "unknown"
	}
	if h.LastError != "" && !h.LastErrorAt.Before(h.StartedAt) && h.LastErrorAt.After(h.LastSuccess) {
		return "failed"
	}
	if h.LastSuccess.Before(h.StartedAt) {
		if now.Sub(h.StartedAt) > 30*time.Second {
			return "stale"
		}
		return "starting"
	}
	if now.Sub(h.LastSuccess).Seconds() > max(30, 3*h.IntervalSeconds) {
		return "stale"
	}
	return "healthy"
}
