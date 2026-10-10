package store

import (
	"testing"
	"time"
)

func TestBlackoutPreservesUserPause(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	until := time.Now().Add(time.Hour)
	if err := db.Snooze("*", until); err != nil {
		t.Fatal(err)
	}
	before, _ := db.ResetVersion("app")
	if err := db.Hold(time.Now().Add(time.Minute), true); err != nil {
		t.Fatal(err)
	}
	during, _ := db.ResetVersion("app")
	if during == before {
		t.Fatal("in-flight actions not invalidated")
	}
	if err := db.ReleaseHold(); err != nil {
		t.Fatal(err)
	}
	actual, _ := db.SnoozedUntil("app")
	if !actual.Equal(until) {
		t.Fatal("user pause changed", actual, until)
	}
	after, _ := db.ResetVersion("app")
	if after == during {
		t.Fatal("samples not reset on restore")
	}
}
func TestBlackoutLeaseExpires(t *testing.T) {
	db, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err := db.Hold(time.Now().Add(-time.Second), true); err != nil {
		t.Fatal(err)
	}
	until, err := db.SnoozedUntil("app")
	if err != nil || time.Now().Before(until) {
		t.Fatal("stale lease pauses forever", until, err)
	}
}
