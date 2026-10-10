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
