package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/store"
)

func TestWatchHealthSurvivesFailureAndDistinguishesRestart(t *testing.T) {
	path, state := watchTestPaths(t)
	run := func(f watchCollectorFunc) error {
		root := commandWithWatchCollector(f)
		root.SetArgs([]string{"watch", "--once", "--config", path, "--state-dir", state})
		return root.ExecuteContext(context.Background())
	}
	if err := run(func(context.Context) (model.Snapshot, error) { return model.Snapshot{At: time.Now()}, nil }); err != nil {
		t.Fatal(err)
	}
	db, err := store.Open(state)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	health, err := db.WatcherHealth()
	if err != nil || health.LastSuccess.IsZero() || health.LastAttempt.IsZero() {
		t.Fatalf("successful tick not recorded: %+v %v", health, err)
	}
	lastSuccess := health.LastSuccess
	if err = run(func(context.Context) (model.Snapshot, error) {
		return model.Snapshot{}, errors.New("fixture collection failure")
	}); err == nil {
		t.Fatal("expected failed watch")
	}
	health, err = db.WatcherHealth()
	if err != nil || health.LastError != "fixture collection failure" || !health.LastSuccess.Equal(lastSuccess) {
		t.Fatalf("failed watch lost evidence: %+v %v", health, err)
	}
	if watcherRunning(state) || health.State(false, time.Now()) != "stopped" {
		t.Fatal("failed watch still reports running")
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started := make(chan struct{})
	root := commandWithWatchCollector(watchCollectorFunc(func(ctx context.Context) (model.Snapshot, error) {
		close(started)
		<-ctx.Done()
		return model.Snapshot{}, ctx.Err()
	}))
	root.SetArgs([]string{"watch", "--config", path, "--state-dir", state})
	done := make(chan error, 1)
	go func() { done <- root.ExecuteContext(ctx) }()
	awaitCollection(t, started)
	health, err = db.WatcherHealth()
	if err != nil || !watcherRunning(state) || health.State(true, time.Now()) != "starting" {
		t.Fatalf("old success/error contaminated restart health: %+v %v", health, err)
	}
	if health.LastError == "" {
		t.Fatal("restart discarded previous error evidence")
	}
	if health.State(true, health.StartedAt.Add(31*time.Second)) != "stale" {
		t.Fatal("held process lock masked hung collection")
	}
	cancel()
	awaitWatch(t, done)
	health, err = db.WatcherHealth()
	if err != nil || health.LastError != "fixture collection failure" {
		t.Fatalf("normal shutdown replaced real error: %+v %v", health, err)
	}
}
