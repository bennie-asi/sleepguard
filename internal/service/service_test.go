package service

import (
	"encoding/xml"
	"io"
	"strings"
	"testing"
)

func TestPlistEscaping(t *testing.T) {
	p := Plist("/a&b/sleepguard", "/config path/c.toml", "/state<dir>")
	d := xml.NewDecoder(strings.NewReader(p))
	found := false
	for {
		tok, e := d.Token()
		if e == io.EOF {
			break
		}
		if e != nil {
			t.Fatal(e)
		}
		if v, ok := tok.(xml.CharData); ok && string(v) == "/a&b/sleepguard" {
			found = true
		}
	}
	if !found {
		t.Fatal("program path changed")
	}
}

func TestBundledServiceAssociation(t *testing.T) {
	for _, test := range []struct {
		binary     string
		associated bool
	}{
		{"/Applications/SleepGuard.app/Contents/Resources/sleepguard", true},
		{"/Users/me/My Apps/SleepGuard.app/Contents/Resources/sleepguard", true},
		{"/usr/local/bin/sleepguard", false},
		{"/tmp/Contents/Resources/sleepguard", false},
	} {
		t.Run(test.binary, func(t *testing.T) {
			p := Plist(test.binary, "/config", "/state")
			if got := strings.Contains(p, `<key>AssociatedBundleIdentifiers</key><array><string>io.sleepguard.app</string></array>`); got != test.associated {
				t.Fatalf("association = %v, want %v", got, test.associated)
			}
			if test.associated {
				if !strings.Contains(p, "<string>--run-monitor</string><string>watch</string>") || !strings.Contains(p, "/Contents/MacOS/SleepGuard</string>") {
					t.Fatal("bundled service must launch the app in Go monitor mode")
				}
			} else if !strings.Contains(p, "<string>"+escape(test.binary)+"</string><string>watch</string>") {
				t.Fatal("standalone CLI service must keep its executable")
			}
			if !strings.Contains(p, "<string>--config</string><string>/config</string><string>--state-dir</string><string>/state</string>") {
				t.Fatal("monitor configuration paths changed")
			}
		})
	}
}
