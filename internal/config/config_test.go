package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExampleAndActionGate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if e := os.WriteFile(path, []byte(Example), 0600); e != nil {
		t.Fatal(e)
	}
	c, e := Load(path)
	if e != nil {
		t.Fatal(e)
	}
	if c.Actions.Enabled || c.Telegram.Enabled {
		t.Fatal("unsafe defaults")
	}
	c.Actions.Enabled = true
	if c.Validate() != nil {
		t.Fatal("process-only configuration rejected")
	}
	if e = os.WriteFile(path, []byte("[monitor]\nintervall = '1s'"), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e = Load(path); e == nil {
		t.Fatal("unknown key accepted")
	}
}

func TestLogRetentionDefaultsAndRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte("[monitor]\nretention_days = 60\n"), 0600); err != nil {
		t.Fatal(err)
	}
	c, revision, err := LoadWithRevision(path)
	if err != nil {
		t.Fatal(err)
	}
	if c.Monitor.LogRetentionDays != 7 || c.Monitor.LogRetentionCount != 10 || c.Monitor.RetentionDays != 60 {
		t.Fatalf("old config lost defaults: %+v", c.Monitor)
	}
	c.Monitor.LogRetentionDays, c.Monitor.LogRetentionCount = 14, 3
	if err := Save(path, c, revision); err != nil {
		t.Fatal(err)
	}
	got, err := Load(path)
	if err != nil || got.Monitor != c.Monitor {
		t.Fatalf("retention failed round trip: %+v %v", got.Monitor, err)
	}
	for _, pair := range [][2]int{{0, 1}, {-1, 1}, {366, 1}, {1, 0}, {1, -1}, {1, 101}} {
		c.Monitor.LogRetentionDays, c.Monitor.LogRetentionCount = pair[0], pair[1]
		if c.Validate() == nil {
			t.Fatalf("invalid log retention accepted: %v", pair)
		}
	}
}
