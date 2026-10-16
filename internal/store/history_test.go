package store

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func TestHistoryPagesKeepRoundsAndSnapshot(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	// Interleaved channel results must remain on one page, even at a boundary.
	_, err = s.db.Exec(`INSERT INTO incidents VALUES ('app','{"label":"Example"}',0,0);
INSERT INTO events(at,incident,kind,message,delivery) VALUES
(1,'app','notification_sent','ok','{"round_id":"first","success":true}'),
(2,'app','detected','detected','{}'),
(3,'app','notification_failed','failed','{"round_id":"first","success":false}'),
(4,'app','notification_sent','legacy','{"round_id":"","success":true}'),
(5,'app','notification_sent','legacy','{"round_id":"","success":true}');`)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 205; i++ {
		if err = s.Event(time.Now(), "app", "detected", fmt.Sprint(i)); err != nil {
			t.Fatal(err)
		}
	}
	ctx := context.Background()
	first, err := s.QueryHistory(ctx, HistoryQuery{Category: "all", Page: 1, PageSize: 20})
	if err != nil || first.Total != 209 || len(first.Events) != 20 || first.SnapshotID != 210 {
		t.Fatalf("first page: %+v, %v", first, err)
	}
	// A new event between page requests must neither duplicate nor hide records.
	if err = s.Event(time.Now(), "app", "paused", "new after snapshot"); err != nil {
		t.Fatal(err)
	}
	seen := map[int64]bool{}
	for page := 1; page <= 11; page++ {
		got, err := s.QueryHistory(ctx, HistoryQuery{Category: "all", Page: page, PageSize: 20, SnapshotID: first.SnapshotID})
		if err != nil || got.Total != first.Total || len(got.Events) > 21 {
			t.Fatalf("page %d: %+v, %v", page, got, err)
		}
		for _, event := range got.Events {
			if seen[event.ID] || event.ID > first.SnapshotID || event.Label != "Example" {
				t.Fatalf("duplicate, shifted snapshot or lost label: %+v", event)
			}
			seen[event.ID] = true
		}
	}
	if len(seen) != 210 {
		t.Fatalf("pagination lost records beyond the old 100-event cap: %d", len(seen))
	}
	notifications, err := s.QueryHistory(ctx, HistoryQuery{Category: "notification", Page: 3, PageSize: 1})
	if err != nil || notifications.Total != 3 || len(notifications.Events) != 2 || notifications.Events[0].ID != 3 || notifications.Events[1].ID != 1 {
		t.Fatalf("notification round split or empty round IDs merged: %+v, %v", notifications, err)
	}
	// Retention may remove old pages; the response must clamp to an existing one.
	if _, err = s.db.Exec(`DELETE FROM events WHERE id<210`); err != nil {
		t.Fatal(err)
	}
	last, err := s.QueryHistory(ctx, HistoryQuery{Category: "all", Page: 11, PageSize: 20, SnapshotID: first.SnapshotID})
	if err != nil || last.Page != 1 || last.Total != 1 || len(last.Events) != 1 || last.Events[0].ID != 210 {
		t.Fatalf("pruned page was not clamped: %+v, %v", last, err)
	}
}

func TestHistoryCategoriesAndValidation(t *testing.T) {
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	categories := map[string][]string{
		"monitor":      {"detected", "reset"},
		"notification": {"notification_sent", "notification_failed"},
		"action":       {"action_attempt", "action_result", "manual_quit", "manual_quit_result", "manual_force", "manual_force_result"},
		"control":      {"paused", "resumed", "blackout_started", "blackout_ended"},
		"other":        {"future_event"},
	}
	for _, kinds := range categories {
		for _, kind := range kinds {
			if err := s.Event(time.Now(), "", kind, "test"); err != nil {
				t.Fatal(err)
			}
		}
	}
	before, err := s.History(100)
	if err != nil {
		t.Fatal(err)
	}
	for category, kinds := range categories {
		got, err := s.QueryHistory(context.Background(), HistoryQuery{Category: category, Page: 1, PageSize: 100})
		if err != nil || got.Total != len(kinds) || len(got.Events) != len(kinds) {
			t.Fatalf("category %s: %+v, %v", category, got, err)
		}
		for i, event := range got.Events {
			if event.Kind != kinds[len(kinds)-1-i] {
				t.Fatalf("wrong category/order: %+v", got.Events)
			}
		}
	}
	for _, query := range []HistoryQuery{
		{Category: "invalid", Page: 1, PageSize: 20},
		{Category: "all", Page: 0, PageSize: 20},
		{Category: "all", Page: 1, PageSize: 0},
		{Category: "all", Page: 1, PageSize: 101},
		{Category: "all", Page: 1, PageSize: 20, SnapshotID: -1},
	} {
		if _, err := s.QueryHistory(context.Background(), query); err == nil {
			t.Fatalf("accepted invalid query: %+v", query)
		}
	}
	after, err := s.History(100)
	if err != nil || !reflect.DeepEqual(before, after) {
		t.Fatalf("browsing modified existing history: %v", err)
	}
	if _, err := s.db.Exec(`DELETE FROM events`); err != nil {
		t.Fatal(err)
	}
	empty, err := s.QueryHistory(context.Background(), HistoryQuery{Category: "all", Page: 9, PageSize: 20})
	if err != nil || empty.Page != 1 || empty.Total != 0 || empty.Events == nil || len(empty.Events) != 0 {
		t.Fatalf("empty history: %+v, %v", empty, err)
	}
}

func TestHistoryIndexesMigrateLegacyDatabase(t *testing.T) {
	dir := t.TempDir()
	db, err := sql.Open("sqlite", filepath.Join(dir, "state.db"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, incident TEXT NOT NULL, kind TEXT NOT NULL, message TEXT NOT NULL);
INSERT INTO events(at,incident,kind,message) VALUES (1,'','detected','legacy');`)
	db.Close()
	if err != nil {
		t.Fatal(err)
	}
	s, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	got, err := s.QueryHistory(context.Background(), HistoryQuery{Category: "monitor", Page: 1, PageSize: 20})
	if err != nil || got.Total != 1 || got.Events[0].Message != "legacy" {
		t.Fatalf("legacy history migration: %+v, %v", got, err)
	}
}
