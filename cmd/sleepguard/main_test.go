package main

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/store"
)

type watchCollectorFunc func(context.Context) (model.Snapshot, error)

func (f watchCollectorFunc) Collect(ctx context.Context) (model.Snapshot, error) { return f(ctx) }

func watchTestPaths(t *testing.T) (string, string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	cfg := config.Default()
	cfg.Monitor.Interval = "1h"
	if e := config.Save(path, cfg, ""); e != nil {
		t.Fatal(e)
	}
	return path, filepath.Join(dir, "state")
}

func awaitWatch(t *testing.T, done <-chan error) {
	t.Helper()
	select {
	case e := <-done:
		if e != nil {
			t.Fatalf("watch did not shut down cleanly: %v", e)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("watch did not exit after its owner stopped")
	}
}

func awaitCollection(t *testing.T, started <-chan struct{}) {
	t.Helper()
	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatal("watch never started collecting")
	}
}

func TestWatchParentPipeCloseCancelsCollectionAndPreservesState(t *testing.T) {
	path, state := watchTestPaths(t)
	db, e := store.Open(state)
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	now := time.Now().UTC()
	if e = db.Save(model.Incident{Key: "existing", Active: true, FirstSeen: now.Add(-time.Hour), LastSeen: now, Notifications: 2}); e != nil {
		t.Fatal(e)
	}
	if e = db.Event(now, "existing", "test", "preserved history"); e != nil {
		t.Fatal(e)
	}
	if e = db.Snooze("*", now.Add(time.Hour)); e != nil {
		t.Fatal(e)
	}
	before, _ := db.Get("existing")
	history, _ := db.History(10)
	pausedUntil, _ := db.SnoozedUntil("*")
	configBytes, _ := os.ReadFile(path)

	reader, writer, e := os.Pipe()
	if e != nil {
		t.Fatal(e)
	}
	defer reader.Close()
	defer writer.Close()
	started := make(chan struct{})
	root := commandWithWatchCollector(watchCollectorFunc(func(ctx context.Context) (model.Snapshot, error) {
		close(started)
		<-ctx.Done()
		return model.Snapshot{}, ctx.Err()
	}))
	root.SetIn(reader)
	root.SetArgs([]string{"watch", "--exit-on-stdin-close", "--config", path, "--state-dir", state})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- root.ExecuteContext(ctx) }()
	awaitCollection(t, started)
	if !watcherRunning(state) {
		t.Fatal("watcher did not hold its state lock")
	}
	if _, e = writer.Write([]byte("parent still alive")); e != nil {
		t.Fatal(e)
	}
	select {
	case e = <-done:
		t.Fatalf("watch exited before the pipe closed: %v", e)
	default:
	}
	if e = writer.Close(); e != nil {
		t.Fatal(e)
	}
	awaitWatch(t, done)
	if watcherRunning(state) {
		t.Fatal("watcher kept its state lock after EOF")
	}
	after, e := db.Get("existing")
	if e != nil || !reflect.DeepEqual(after, before) {
		t.Fatalf("shutdown changed collected incident state: %+v, %v", after, e)
	}
	gotHistory, e := db.History(10)
	if e != nil || !reflect.DeepEqual(gotHistory, history) {
		t.Fatalf("shutdown changed event history: %+v, %v", gotHistory, e)
	}
	gotPausedUntil, e := db.SnoozedUntil("*")
	if e != nil || !gotPausedUntil.Equal(pausedUntil) {
		t.Fatalf("shutdown changed pause state: %v, %v", gotPausedUntil, e)
	}
	if got, e := os.ReadFile(path); e != nil || string(got) != string(configBytes) {
		t.Fatalf("shutdown changed configuration: %v", e)
	}
}

func TestWatchParentPipeCloseInterruptsSampleInterval(t *testing.T) {
	path, state := watchTestPaths(t)
	reader, writer, e := os.Pipe()
	if e != nil {
		t.Fatal(e)
	}
	defer reader.Close()
	defer writer.Close()
	started := make(chan struct{}, 1)
	root := commandWithWatchCollector(watchCollectorFunc(func(context.Context) (model.Snapshot, error) {
		started <- struct{}{}
		return model.Snapshot{At: time.Now()}, nil
	}))
	root.SetIn(reader)
	root.SetArgs([]string{"watch", "--exit-on-stdin-close", "--config", path, "--state-dir", state})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- root.ExecuteContext(ctx) }()
	awaitCollection(t, started)
	if e = writer.Close(); e != nil {
		t.Fatal(e)
	}
	awaitWatch(t, done)
	if watcherRunning(state) {
		t.Fatal("watcher kept its state lock after EOF")
	}
}

type unexpectedWatchInput struct{}

func (unexpectedWatchInput) Read([]byte) (int, error) {
	panic("default CLI watch must not read standard input")
}

func TestDefaultWatchDoesNotReadStdin(t *testing.T) {
	path, state := watchTestPaths(t)
	started := make(chan struct{})
	root := commandWithWatchCollector(watchCollectorFunc(func(ctx context.Context) (model.Snapshot, error) {
		close(started)
		<-ctx.Done()
		return model.Snapshot{}, ctx.Err()
	}))
	root.SetIn(unexpectedWatchInput{})
	root.SetArgs([]string{"watch", "--config", path, "--state-dir", state})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- root.ExecuteContext(ctx) }()
	awaitCollection(t, started)
	cancel()
	awaitWatch(t, done)
	if watcherRunning(state) {
		t.Fatal("watcher kept its state lock after cancellation")
	}
}
