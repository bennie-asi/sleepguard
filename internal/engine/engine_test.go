package engine

import (
	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/model"
	"testing"
	"time"
)

func fixture() (config.Config, model.Snapshot) {
	c := config.Default()
	c.Telegram.Enabled = true
	c.Telegram.ChatID = 1
	c.Actions.Enabled = true
	c.Rules = []config.Rule{{BundleID: "test.app", Policy: "terminate"}}
	p := model.Process{PID: 4242, StartedMS: 100, Path: "/Applications/Test.app/Contents/MacOS/Test", Name: "Test", BundleID: "test.app"}
	s := model.Snapshot{At: time.Now(), BootID: "boot", WakeAt: time.Now().Add(-time.Hour), IdleSeconds: 3600, DisplayAsleep: true, SleepMinutes: 1, DisplayMinutes: 10, Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Holder: p, Target: &p}}}
	return c, s
}
func TestEligibility(t *testing.T) {
	c, s := fixture()
	if !Assess(c, s).Eligible {
		t.Fatal("expected eligible")
	}
	tests := []struct {
		name   string
		change func(*model.Snapshot)
	}{
		{"active", func(s *model.Snapshot) { s.IdleSeconds = 0 }},
		{"disabled", func(s *model.Snapshot) { s.SleepMinutes = 0 }},
		{"awake display", func(s *model.Snapshot) { s.DisplayAsleep = false }},
		{"just woke", func(s *model.Snapshot) { s.WakeAt = s.At }},
		{"no assertion", func(s *model.Snapshot) { s.Assertions = nil }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, v := fixture()
			tt.change(&v)
			if Assess(c, v).Eligible {
				t.Fatal("unexpected eligible")
			}
		})
	}
}
func TestEscalation(t *testing.T) {
	c, s := fixture()
	x := Assess(c, s).Candidates[0]
	i := Advance(c, s, x, nil)
	i.Samples = 3
	i.QualifiedAt = s.At
	if Decide(c, i, x.Policy, s.At) != Notify {
		t.Fatal("expected notify")
	}
	// Failed delivery does not shorten the independent processing wait.
	i.LastAttempt = s.At.Add(-time.Hour)
	i.Notifications = 0
	if Decide(c, i, x.Policy, s.At) == Terminate {
		t.Fatal("failed notification escalated")
	}
	i.LastAttempt = s.At
	if Decide(c, i, x.Policy, Deadline(c, i).Add(-time.Second)) == Terminate {
		t.Fatal("missing final grace")
	}
	if Decide(c, i, x.Policy, Deadline(c, i)) != Terminate {
		t.Fatal("expected terminate")
	}
	c.Telegram.Enabled = false
	if Decide(c, i, "process", Deadline(c, i)) != Terminate {
		t.Fatal("process-only requires a notification channel")
	}
	i.SnoozedUntil = s.At.Add(time.Hour)
	if Decide(c, i, x.Policy, s.At) != Wait {
		t.Fatal("snooze ignored")
	}
	i.SnoozedUntil = time.Time{}
	i.ActionAttempted = true
	if Decide(c, i, x.Policy, s.At) != Wait {
		t.Fatal("repeated action")
	}
}
func TestNewWakeAndGapReset(t *testing.T) {
	c, s := fixture()
	x := Assess(c, s).Candidates[0]
	i := Advance(c, s, x, nil)
	i.Notifications = 3
	s.At = s.At.Add(time.Minute)
	j := Advance(c, s, x, &i)
	if j.Notifications != 3 {
		t.Fatal("lost restart persistence")
	}
	s.WakeAt = s.At
	j = Advance(c, s, x, &i)
	if j.Notifications != 0 {
		t.Fatal("wake did not reset")
	}
	s.WakeAt = i.WakeAt
	s.At = s.At.Add(time.Hour)
	j = Advance(c, s, x, &i)
	if j.Notifications != 0 {
		t.Fatal("gap did not reset")
	}
	p := *x.Target
	p.StartedMS++
	if p.Identity(s.BootID) == x.Key {
		t.Fatal("PID reuse collision")
	}
}
func TestProtectedProcess(t *testing.T) {
	c, s := fixture()
	s.Assertions[0].Target.Protected = true
	if Assess(c, s).Candidates[0].Policy != "notify" {
		t.Fatal("protected app allowed")
	}
}
