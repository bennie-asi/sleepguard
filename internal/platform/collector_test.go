package platform

import (
	"github.com/bennie-asi/sleepguard/internal/model"
	"testing"
	"time"
)

func TestSettings(t *testing.T) {
	text := "Battery Power:\n sleep 1\n displaysleep 2\nAC Power:\n sleep 1 (sleep prevented by app)\n displaysleep 10\n"
	s, e := ParseSettings(text, "AC Power")
	if e != nil || s.Sleep != 1 || s.Display != 10 {
		t.Fatalf("%+v %v", s, e)
	}
	if _, e = ParseSettings(text, "bogus"); e == nil {
		t.Fatal("unknown source accepted")
	}
	if _, e = ParseSettings("AC Power:\n sleep 1", "AC Power"); e == nil {
		t.Fatal("missing display accepted")
	}
}

func TestDelegationRejectsRecycledPID(t *testing.T) {
	created := time.Unix(100, 0)
	p := model.Process{PID: 42, StartedMS: 99000, Path: "/Applications/Test"}
	if !ValidDelegation(p, created) {
		t.Fatal("valid owner rejected")
	}
	p.StartedMS = 101000
	if ValidDelegation(p, created) {
		t.Fatal("recycled PID accepted")
	}
	if ValidDelegation(p, time.Time{}) {
		t.Fatal("missing metadata accepted")
	}
}

func TestGlobalSleepSwitch(t *testing.T) {
	for _, v := range []string{"0", "1"} {
		got, e := ParseSleepDisabled("System-wide power settings:\n SleepDisabled\t" + v)
		if e != nil || got != (v == "1") {
			t.Fatal(v, got, e)
		}
	}
	for _, text := range []string{
		"System-wide power settings:\nCurrently in use:\n sleep 1 (sleep prevented by app)\n displaysleep 10\n",
		"System-wide power settings:\n DestroyFVKeyOnStandby 0\n",
	} {
		if got, e := ParseSleepDisabled(text); e != nil || got {
			t.Fatalf("unset override should leave sleep enabled: %v %v", got, e)
		}
	}
	for _, text := range []string{"", "unknown", "Currently in use:\n sleep 1\n",
		"System-wide power settings:\n SleepDisabled", "System-wide power settings:\n SleepDisabled 2"} {
		if _, e := ParseSleepDisabled(text); e == nil {
			t.Fatalf("invalid system settings accepted: %q", text)
		}
	}
}
