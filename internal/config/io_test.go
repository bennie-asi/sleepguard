package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAtomicRevisionAndRuleMigration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	c := Default()
	c.Rules = []Rule{{BundleID: "test.app", Notify: Bool(false), Process: Bool(false)}, {Path: "/Applications/Test", Notify: Bool(false), Process: Bool(true)}}
	c.Actions.Enabled = true
	if e := Save(path, c, ""); e != nil {
		t.Fatal(e)
	}
	loaded, e := Load(path)
	if e != nil {
		t.Fatal(e)
	}
	n, p := loaded.Rules[0].Selection()
	if n || p {
		t.Fatal("ignore lost in round trip")
	}
	n, p = loaded.Rules[1].Selection()
	if n || !p {
		t.Fatal("process-only lost in round trip")
	}
	if e = Save(path, c, ""); e == nil {
		t.Fatal("stale revision overwrote config")
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("config permissions")
	}
	rev, _ := Revision(path)
	if e = Save(path, c, rev); e != nil {
		t.Fatal(e)
	}
}
func TestLegacyConfigMigration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "legacy.toml")
	os.WriteFile(path, []byte("[telegram]\nenabled=true\nchat_id=1\n[[rules]]\nbundle_id='test.app'\npolicy='terminate'\n"), 0600)
	c, e := Load(path)
	if e != nil {
		t.Fatal(e)
	}
	if c.Telegram.Enabled || len(c.Channels) != 1 || c.Channels[0].KeychainService != "sleepguard.telegram" {
		t.Fatal("legacy channel lost")
	}
	n, p := c.Rules[0].Selection()
	if !n || !p || c.Rules[0].Policy != "" {
		t.Fatal("legacy rule lost")
	}
}
