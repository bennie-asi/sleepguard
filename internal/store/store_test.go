package store

import (
	"github.com/bennie-asi/sleepguard/internal/model"
	"testing"
	"time"
)

func TestPersistenceAndConcurrentSnooze(t *testing.T) {
	dir := t.TempDir()
	a, e := Open(dir)
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	b, e := Open(dir)
	if e != nil {
		t.Fatal(e)
	}
	defer b.Close()
	i := model.Incident{Key: "abc", Active: true, Notifications: 2, LastSeen: time.Now()}
	if e = a.Save(i); e != nil {
		t.Fatal(e)
	}
	until := time.Now().Add(time.Hour)
	if e = b.Snooze("*", until); e != nil {
		t.Fatal(e)
	}
	if e = a.Save(i); e != nil {
		t.Fatal(e)
	}
	got, e := a.SnoozedUntil(i.Key)
	if e != nil || !got.Equal(until) {
		t.Fatal("save lost concurrent snooze", e)
	}
	restored, e := b.Get("abc")
	if e != nil || restored.Notifications != 2 {
		t.Fatal("lost state", e)
	}
	if e = a.Event(time.Now().Add(-48*time.Hour), "abc", "old", "old"); e != nil {
		t.Fatal(e)
	}
	if e = a.Prune(time.Now(), 1); e != nil {
		t.Fatal(e)
	}
	events, e := a.History(10)
	if e != nil || len(events) != 1 || events[0].Kind != "paused" {
		t.Fatal("prune failed", e)
	}
}
