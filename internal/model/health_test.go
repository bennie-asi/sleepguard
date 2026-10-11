package model

import (
	"testing"
	"time"
)

func TestWatcherHealthUsesWorkerCompletionNotProcessLiveness(t *testing.T) {
	now := time.Now()
	h := WatcherHealth{StartedAt: now, IntervalSeconds: 60}
	if h.State(true, now) != "starting" {
		t.Fatal("new worker reported healthy")
	}
	if h.State(true, now.Add(31*time.Second)) != "stale" {
		t.Fatal("stuck first collection hidden")
	}
	h.LastSuccess = now
	if h.State(true, now.Add(180*time.Second)) != "healthy" {
		t.Fatal("normal sampling grace rejected")
	}
	if h.State(true, now.Add(181*time.Second)) != "stale" {
		t.Fatal("live but stalled worker reported healthy")
	}
	h.LastAttempt = now.Add(181 * time.Second)
	if h.State(true, now.Add(182*time.Second)) != "stale" {
		t.Fatal("attempt without success reset health")
	}
	h.LastError = "collection failed"
	h.LastErrorAt = now.Add(time.Second)
	if h.State(true, now.Add(time.Second)) != "failed" {
		t.Fatal("worker error hidden")
	}
	if h.State(false, now) != "stopped" {
		t.Fatal("stopped worker reported running")
	}
	if (WatcherHealth{}).State(true, now) != "unknown" {
		t.Fatal("legacy worker reported healthy")
	}
}
