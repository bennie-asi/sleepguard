package store

import (
	"database/sql"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
)

func TestLegacyHistoryConcurrentMigration(t *testing.T) {
	dir := t.TempDir()
	db, e := sql.Open("sqlite", filepath.Join(dir, "state.db"))
	if e != nil {
		t.Fatal(e)
	}
	_, e = db.Exec(`CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT,at INTEGER NOT NULL,incident TEXT NOT NULL,kind TEXT NOT NULL,message TEXT NOT NULL); INSERT INTO events(at,incident,kind,message) VALUES(1,'old','detected','old event')`)
	db.Close()
	if e != nil {
		t.Fatal(e)
	}
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s, e := Open(dir)
			if e != nil {
				t.Error(e)
				return
			}
			defer s.Close()
			events, e := s.History(10)
			if e != nil || len(events) != 1 || events[0].Message != "old event" || events[0].Delivery != nil {
				t.Error("lost legacy history", events, e)
			}
		}()
	}
	wg.Wait()
}
func TestResumeClearsPersistedEligibility(t *testing.T) {
	dir := t.TempDir()
	db, e := Open(dir)
	if e != nil {
		t.Fatal(e)
	}
	i := model.Incident{Key: "test", Active: true, Samples: 10, Notifications: 3, QualifiedAt: time.Now().Add(-time.Hour), LastSeen: time.Now()}
	if e = db.Save(i); e != nil {
		t.Fatal(e)
	}
	if e = db.Snooze("*", time.Now().Add(time.Hour)); e != nil {
		t.Fatal(e)
	}
	if e = db.Snooze(i.Key, time.Now().Add(time.Hour)); e != nil {
		t.Fatal(e)
	}
	if e = db.Resume("*"); e != nil {
		t.Fatal(e)
	}
	db.Close()
	db, e = Open(dir)
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	restored, e := db.Get(i.Key)
	if e != nil || restored.Active {
		t.Fatal("resume did not persist reset", restored, e)
	}
	until, e := db.SnoozedUntil(i.Key)
	if e != nil || !until.IsZero() {
		t.Fatal("resume retained snooze", until, e)
	}
	version, e := db.ResetVersion(i.Key)
	if e != nil || version == "" {
		t.Fatal("reset generation missing", version, e)
	}
	if e = db.Resume("*"); e != nil {
		t.Fatal(e)
	}
	next, e := db.ResetVersion(i.Key)
	if e != nil || next == version {
		t.Fatal("resume did not invalidate in-flight state", next, e)
	}
}
