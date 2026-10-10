package control

import (
	"context"
	"errors"
	"github.com/bennie-asi/sleepguard/internal/model"
	"os"
	"syscall"
	"testing"
	"time"
)

func TestManualRevalidatesBeforeSignal(t *testing.T) {
	target := model.Process{PID: 999998, StartedMS: 1234, UID: int32(os.Getuid()), Path: "/Applications/Fixture.app/Contents/MacOS/Fixture", BundleID: "dev.fixture", Name: "Fixture"}
	snapshot := model.Snapshot{BootID: "boot", Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Target: &target}}}
	for _, scenario := range []string{"protected", "recycled", "cleared", "other-user", "unresolved", "stale-key", "inspect-failed"} {
		t.Run(scenario, func(t *testing.T) {
			request := Request{Key: target.Identity("boot"), Target: target, Force: true}
			s := snapshot
			current := target
			switch scenario {
			case "protected":
				current.Protected = true
			case "recycled":
				current.StartedMS++
			case "cleared":
				s.Assertions = nil
			case "other-user":
				current.UID++
			case "unresolved":
				s.Assertions = []model.Assertion{{Type: "PreventUserIdleSystemSleep"}}
			case "stale-key":
				request.Key = "stale"
			}
			called := false
			m := Manual{Collect: func(context.Context) (model.Snapshot, error) { return s, nil }, Inspect: func(context.Context, int32) (model.Process, error) {
				if scenario == "inspect-failed" {
					return model.Process{}, errors.New("denied")
				}
				return current, nil
			}, Signal: func(int32, syscall.Signal) error { called = true; return nil }, Event: func(time.Time, string, string, string) error { return nil }}
			if _, err := m.Execute(context.Background(), request); err == nil || called {
				t.Fatal("unsafe signal", err, called)
			}
		})
	}
}
func TestManualQuitNeverEscalates(t *testing.T) {
	target := model.Process{PID: int32(os.Getpid()) + 100000, StartedMS: 1234, UID: int32(os.Getuid()), Path: "/Applications/Fixture.app/Contents/MacOS/Fixture", Name: "Fixture"}
	s := model.Snapshot{BootID: "boot", Assertions: []model.Assertion{{Type: "PreventUserIdleSystemSleep", Target: &target}}}
	signals := []syscall.Signal{}
	m := Manual{Collect: func(context.Context) (model.Snapshot, error) { return s, nil }, Inspect: func(context.Context, int32) (model.Process, error) { return target, nil }, Signal: func(_ int32, s syscall.Signal) error { signals = append(signals, s); return nil }, Event: func(time.Time, string, string, string) error { return nil }, Wait: time.Millisecond, Exited: func(context.Context, int32) bool { return false }}
	result, err := m.Execute(context.Background(), Request{Key: target.Identity("boot"), Target: target})
	if err != nil || result.Exited || len(signals) != 1 || signals[0] != syscall.SIGTERM {
		t.Fatal(result, err, signals)
	}
}
