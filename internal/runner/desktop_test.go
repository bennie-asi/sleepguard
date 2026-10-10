package runner

import (
	"context"
	"syscall"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/engine"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/store"
)

type multiNotifier struct {
	results    []model.Delivery
	duringSend func()
}

func (n *multiNotifier) Send(context.Context, string, string) error {
	panic("must dispatch all channels")
}
func (n *multiNotifier) SendAll(context.Context, string, string) []model.Delivery {
	if n.duringSend != nil {
		n.duringSend()
	}
	return n.results
}
func desktopFixture(t *testing.T) (config.Config, *store.Store, *collector, model.Process) {
	t.Helper()
	db, e := store.Open(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { db.Close() })
	c := config.Default()
	c.Monitor.ConsecutiveSamples = 2
	c.Monitor.Interval = "1m"
	p := model.Process{PID: 99999, StartedMS: 10, Name: "Test", Path: "/Applications/Test.app/Contents/MacOS/Test", BundleID: "test.app"}
	now := time.Now()
	co := &collector{s: model.Snapshot{At: now, BootID: "b", WakeAt: now.Add(-time.Hour), IdleSeconds: 3600, DisplayAsleep: true, SleepMinutes: 1, DisplayMinutes: 10, Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Holder: p, Target: &p}}}}
	return c, db, co, p
}
func TestMultiChannelRoundAndResumeDuringSend(t *testing.T) {
	c, db, co, p := desktopFixture(t)
	c.Notifications.SystemEnabled = true
	n := &multiNotifier{results: []model.Delivery{{ChannelID: "a", ChannelName: "A", Success: true}, {ChannelID: "b", ChannelName: "B", Success: true}, {ChannelID: "c", ChannelName: "C", Success: false, Message: "failed"}}}
	r := Runner{Config: c, Store: db, Collector: co, Notifier: n}
	for range 2 {
		co.s.At = co.s.At.Add(time.Minute)
		if e := r.Tick(context.Background()); e != nil {
			t.Fatal(e)
		}
	}
	i, e := db.Get(p.Identity("b"))
	if e != nil || i.Notifications != 1 {
		t.Fatalf("each channel counted a warning: %+v %v", i, e)
	}
	history, e := db.History(10)
	if e != nil || len(history) != 4 {
		t.Fatal(history, e)
	}
	if history[0].Delivery.RoundID == "" || history[0].Delivery.RoundID != history[1].Delivery.RoundID || history[1].Delivery.RoundID != history[2].Delivery.RoundID {
		t.Fatal("missing round grouping")
	}
	n.duringSend = func() {
		if e := db.Resume("*"); e != nil {
			t.Fatal(e)
		}
	}
	// The delivery completes after resume and writes its stale sample back.
	co.s.At = co.s.At.Add(time.Minute)
	r.Config.Monitor.ReminderInterval = "1s"
	if e = r.Tick(context.Background()); e != nil {
		t.Fatal(e)
	}
	n.duringSend = nil
	co.s.At = co.s.At.Add(time.Minute)
	if e = r.Tick(context.Background()); e != nil {
		t.Fatal(e)
	}
	i, e = db.Get(i.Key)
	if e != nil || i.Samples != 1 || i.Notifications != 0 || !i.QualifiedAt.IsZero() {
		t.Fatalf("resume retained an in-flight countdown: %+v %v", i, e)
	}
}
func TestProcessingWithoutNotificationsAndConfigRevocation(t *testing.T) {
	c, db, co, p := desktopFixture(t)
	c.Actions.Enabled = true
	c.Actions.Wait = "1m"
	c.Monitor.FinalGrace = "1m"
	c.Rules = []config.Rule{{BundleID: p.BundleID, Notify: config.Bool(false), Process: config.Bool(true)}}
	signals := 0
	r := Runner{Config: c, Store: db, Collector: co, Inspect: func(context.Context, int32) (model.Process, error) { return p, nil }, Signal: func(pid int32, sig syscall.Signal) error {
		signals++
		if pid != p.PID || sig != syscall.SIGTERM {
			t.Fatal("unexpected signal")
		}
		return nil
	}}
	for sample := 0; sample < 4; sample++ {
		co.s.At = co.s.At.Add(time.Minute)
		if e := r.Tick(context.Background()); e != nil {
			t.Fatal(e)
		}
		if sample < 3 && signals != 0 {
			t.Fatal("ended before both waiting periods")
		}
	}
	if signals != 1 {
		t.Fatal("process-only rule depended on notifications")
	}
	i, _ := db.Get(p.Identity("b"))
	if i.Notifications != 0 || !i.ActionAttempted {
		t.Fatal("wrong process-only state", i)
	}
	r.Reload = func() (config.Config, error) { current := c; current.Actions.Enabled = false; return current, nil }
	if e := r.terminate(context.Background(), *i); e == nil || signals != 1 {
		t.Fatal("disabled action sent a signal")
	}
	r.Reload = func() (config.Config, error) { current := c; current.Actions.Wait = "1h"; return current, nil }
	if e := r.terminate(context.Background(), *i); e == nil || signals != 1 {
		t.Fatal("changed countdown sent a signal")
	}
	r.Reload = func() (config.Config, error) { return c, nil }
	if e := db.Resume("*"); e != nil {
		t.Fatal(e)
	}
	if e := r.terminate(context.Background(), *i); e == nil || signals != 1 {
		t.Fatal("resume retained old action eligibility")
	}
	if engine.Decide(c, *i, "process", co.s.At) != engine.Wait {
		t.Fatal("attempted action was repeated")
	}
}
