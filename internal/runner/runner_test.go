package runner

import (
	"context"
	"errors"
	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/store"
	"syscall"
	"testing"
	"time"
)

type collector struct {
	s   model.Snapshot
	err error
}

func (c *collector) Collect(context.Context) (model.Snapshot, error) { return c.s, c.err }

type notifier struct {
	calls int
	err   error
}

func (n *notifier) Send(context.Context, string, string) error { n.calls++; return n.err }
func TestNotificationFailureAndSnooze(t *testing.T) {
	db, e := store.Open(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	c := config.Default()
	c.Telegram.Enabled = true
	c.Telegram.ChatID = 1
	c.Monitor.ConsecutiveSamples = 2
	c.Monitor.ReminderInterval = "1s"
	p := model.Process{PID: 99999, StartedMS: 1, Path: "/Applications/Test.app/Contents/MacOS/Test", Name: "Test"}
	co := &collector{s: model.Snapshot{At: time.Now(), BootID: "b", WakeAt: time.Now().Add(-time.Hour), IdleSeconds: 3600, DisplayAsleep: true, SleepMinutes: 1, DisplayMinutes: 10, Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Holder: p, Target: &p}}}}
	no := &notifier{err: errors.New("mock failure")}
	r := Runner{Config: c, Store: db, Collector: co, Notifier: no}
	tick := func() {
		t.Helper()
		co.s.At = co.s.At.Add(time.Minute)
		if e = r.Tick(context.Background()); e != nil {
			t.Fatal(e)
		}
	}
	tick()
	tick()
	tick()
	i, e := db.Get(p.Identity("b"))
	if e != nil || i.Notifications != 0 || no.calls != 2 {
		t.Fatalf("failure counted %+v %v calls=%d", i, e, no.calls)
	}
	no.err = nil
	tick()
	i, _ = db.Get(p.Identity("b"))
	if i.Notifications != 1 {
		t.Fatal("success not counted")
	}
	if e = db.Snooze(i.Key, co.s.At.Add(time.Hour)); e != nil {
		t.Fatal(e)
	}
	tick()
	tick()
	if no.calls != 3 {
		t.Fatal("sent during snooze")
	}
	co.s.IdleSeconds = 0
	tick()
	i, _ = db.Get(i.Key)
	if i.Active {
		t.Fatal("user input did not reset")
	}
	co.err = errors.New("probe failure")
	if r.Tick(context.Background()) == nil {
		t.Fatal("collection failure ignored")
	}
}
func TestGuardRejectsProtectedAndChangedWake(t *testing.T) {
	db, e := store.Open(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	c := config.Default()
	c.Actions.Enabled = true
	r := Runner{Config: c, Store: db, Collector: &collector{s: model.Snapshot{BootID: "new"}}}
	i := model.Incident{Key: "x", BootID: "old", Target: &model.Process{PID: 99999}}
	if e = r.guard(context.Background(), i); e == nil {
		t.Fatal("new boot accepted")
	}
	i.Target.Protected = true
	if e = r.terminate(context.Background(), &i); e == nil {
		t.Fatal("protected process accepted")
	}
}

func TestSignalRevalidatesIdentityAndWake(t *testing.T) {
	db, e := store.Open(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	c := config.Default()
	c.Actions.Enabled = true
	c.Rules = []config.Rule{{BundleID: "test", Policy: "terminate"}}
	p := model.Process{PID: 99999, StartedMS: 10, Path: "/Applications/Test", BundleID: "test"}
	now := time.Now()
	s := model.Snapshot{At: now, BootID: "b", WakeAt: now.Add(-time.Hour), IdleSeconds: 3600, DisplayAsleep: true, SleepMinutes: 1, DisplayMinutes: 10, Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Holder: p, Target: &p}}}
	co := &collector{s: s}
	signals := 0
	observed := p
	r := Runner{Config: c, Store: db, Collector: co, Inspect: func(context.Context, int32) (model.Process, error) { return observed, nil }, Signal: func(pid int32, sig syscall.Signal) error {
		signals++
		if pid != p.PID || sig != syscall.SIGTERM {
			t.Fatal("unexpected signal")
		}
		return nil
	}}
	i := model.Incident{Key: p.Identity("b"), BootID: "b", WakeAt: s.WakeAt, Target: &p}
	if e = r.terminate(context.Background(), &i); e != nil || signals != 1 {
		t.Fatal("valid action rejected", e)
	}
	observed.StartedMS++
	if e = r.terminate(context.Background(), &i); e == nil || signals != 1 {
		t.Fatal("PID reuse accepted", e)
	}
	observed = p
	co.s.IdleSeconds = 0
	if e = r.terminate(context.Background(), &i); e == nil || signals != 1 {
		t.Fatal("user activity ignored", e)
	}
}
