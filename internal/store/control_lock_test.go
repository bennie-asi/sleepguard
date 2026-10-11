package store

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestControlAcknowledgementWaitsForSignalSection(t *testing.T) {
	dir := t.TempDir()
	watcher, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer watcher.Close()
	ui, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer ui.Close()
	err = watcher.WithControlLock(context.Background(), func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 40*time.Millisecond)
		defer cancel()
		err := ui.WithControlLock(ctx, func() error { t.Error("second owner entered the signal section"); return nil })
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("lock was not cancellable: %v", err)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	until := time.Now().Add(time.Hour)
	if err = ui.Snooze("*", until); err != nil {
		t.Fatal(err)
	}
	if err = watcher.WithControlLock(context.Background(), func() error {
		got, err := watcher.SnoozedUntil("*")
		if err != nil || !got.Equal(until) {
			t.Fatalf("acknowledged pause not visible: %v %v", got, err)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
