package runner

import (
	"context"
	"errors"
	"syscall"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/engine"
	"github.com/bennie-asi/sleepguard/internal/model"
)

type collectorFunc func(context.Context) (model.Snapshot, error)

func (f collectorFunc) Collect(ctx context.Context) (model.Snapshot, error) { return f(ctx) }

func TestControlsDuringRecollectionCancelSignals(t *testing.T) {
	for _, signal := range []syscall.Signal{syscall.SIGTERM, syscall.SIGKILL} {
		for _, operation := range []string{"pause", "resume", "blackout", "release", "config", "cancel"} {
			t.Run(signal.String()+"/"+operation, func(t *testing.T) {
				c, db, co, p := desktopFixture(t)
				c.Actions.Enabled = true
				c.Actions.AllowSIGKILL = true
				c.Actions.KillAfter = "1ms"
				c.Rules = []config.Rule{{BundleID: p.BundleID, Process: config.Bool(true)}}
				x := engine.Assess(c, co.s).Candidates[0]
				i := engine.Advance(c, co.s, x, nil)
				i.Samples = 2
				i.QualifiedAt = co.s.At.Add(-time.Hour)
				ctx, cancel := context.WithCancel(context.Background())
				defer cancel()
				signals, collects := 0, 0
				r := Runner{Config: c, Store: db, Reload: func() (config.Config, error) { return c, nil },
					Inspect: func(context.Context, int32) (model.Process, error) { return p, nil },
					Signal:  func(int32, syscall.Signal) error { signals++; return nil },
					Collector: collectorFunc(func(context.Context) (model.Snapshot, error) {
						collects++
						if signal == syscall.SIGKILL && collects == 1 {
							return co.s, nil
						}
						var err error
						switch operation {
						case "pause":
							err = db.Snooze("*", time.Now().Add(time.Hour))
						case "resume":
							err = db.Resume("*")
						case "blackout":
							err = db.Hold(time.Now().Add(time.Minute), true)
						case "release":
							err = db.ReleaseHold()
						case "config":
							c.Actions.Enabled = false
						case "cancel":
							cancel()
						}
						if err != nil {
							t.Fatal(err)
						}
						return co.s, nil
					}),
				}
				err := r.terminate(ctx, &i)
				want := 0
				if signal == syscall.SIGKILL {
					want = 1
				}
				if err == nil || signals != want || i.ActionAttempted != (want == 1) {
					t.Fatalf("control acknowledged but obsolete action continued: err=%v signals=%d attempted=%v", err, signals, i.ActionAttempted)
				}
			})
		}
	}
}

func TestPreflightFailureRetriesAndKeepsNotifications(t *testing.T) {
	c, db, co, p := desktopFixture(t)
	c.Actions.Enabled = true
	c.Notifications.SystemEnabled = true
	c.Rules = []config.Rule{{BundleID: p.BundleID, Notify: config.Bool(true), Process: config.Bool(true)}}
	x := engine.Assess(c, co.s).Candidates[0]
	i := engine.Advance(c, co.s, x, nil)
	i.Samples = 2
	i.QualifiedAt = co.s.At.Add(-time.Hour)
	if err := db.Save(i); err != nil {
		t.Fatal(err)
	}
	collects, signals := 0, 0
	n := &notifier{}
	r := Runner{Config: c, Store: db, Notifier: n,
		Inspect: func(context.Context, int32) (model.Process, error) { return p, nil },
		Signal:  func(int32, syscall.Signal) error { signals++; return nil },
		Collector: collectorFunc(func(context.Context) (model.Snapshot, error) {
			collects++
			if collects == 2 {
				return model.Snapshot{}, errors.New("temporary probe failure")
			}
			return co.s, nil
		}),
	}
	if err := r.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	saved, err := db.Get(i.Key)
	if err != nil || saved.ActionAttempted || saved.ActionRetryAt.IsZero() {
		t.Fatalf("preflight failure ended event: %+v %v", saved, err)
	}
	// A new Runner must honor the persisted retry deadline too.
	restarted := r
	co.s.At = co.s.At.Add(time.Minute)
	if err = restarted.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	if n.calls != 1 || signals != 0 {
		t.Fatalf("retry wait suppressed notification or sent early: notify=%d signals=%d", n.calls, signals)
	}
	for range 3 {
		co.s.At = co.s.At.Add(time.Minute)
		if err = restarted.Tick(context.Background()); err != nil {
			t.Fatal(err)
		}
	}
	if signals != 1 {
		t.Fatalf("expected one successful action after retry; got %d", signals)
	}
}

func TestFailureAfterSIGTERMNeverRepeatsSignal(t *testing.T) {
	c, db, co, p := desktopFixture(t)
	c.Actions.Enabled = true
	c.Actions.AllowSIGKILL = true
	c.Actions.KillAfter = "1ms"
	c.Rules = []config.Rule{{BundleID: p.BundleID, Process: config.Bool(true)}}
	i := engine.Advance(c, co.s, engine.Assess(c, co.s).Candidates[0], nil)
	i.Samples = 2
	i.QualifiedAt = co.s.At.Add(-time.Hour)
	if err := db.Save(i); err != nil {
		t.Fatal(err)
	}
	collects, signals := 0, 0
	r := Runner{Config: c, Store: db,
		Inspect: func(context.Context, int32) (model.Process, error) { return p, nil },
		Signal:  func(int32, syscall.Signal) error { signals++; return nil },
		Collector: collectorFunc(func(context.Context) (model.Snapshot, error) {
			collects++
			if collects == 3 {
				return model.Snapshot{}, errors.New("probe failed before SIGKILL")
			}
			return co.s, nil
		}),
	}
	for range 4 {
		if err := r.Tick(context.Background()); err != nil {
			t.Fatal(err)
		}
		co.s.At = co.s.At.Add(time.Minute)
	}
	if signals != 1 {
		t.Fatalf("repeated an already attempted signal: %d", signals)
	}
}
