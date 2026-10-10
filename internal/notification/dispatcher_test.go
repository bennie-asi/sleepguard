package notification

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
)

type sendFunc func(context.Context, string, string) error

func (f sendFunc) Send(c context.Context, s, b string) error { return f(c, s, b) }
func TestIndependentConcurrentChannels(t *testing.T) {
	c := config.Default()
	c.Channels = []config.Channel{{ID: "slow", Name: "Slow", Type: "telegram", Enabled: true, Timeout: "1s"}, {ID: "good", Name: "Good", Type: "telegram", Enabled: true, Timeout: "1s"}}
	goodSent := make(chan struct{})
	release := make(chan struct{})
	d := Dispatcher{Config: c, Factory: func(ch config.Channel) Sender {
		return sendFunc(func(ctx context.Context, _, _ string) error {
			if ch.ID == "slow" {
				select {
				case <-release:
				case <-ctx.Done():
				}
				return errors.New("timeout")
			}
			close(goodSent)
			return nil
		})
	}}
	done := make(chan bool, 1)
	go func() {
		r := d.SendAll(context.Background(), "test", "body")
		done <- len(r) == 2 && !r[0].Success && r[1].Success
	}()
	select {
	case <-goodSent:
	case <-time.After(time.Second):
		t.Fatal("slow channel blocked good channel")
	}
	close(release)
	if !<-done {
		t.Fatal("results not independent")
	}
}
func TestDisabledAndFutureChannelsAreExcluded(t *testing.T) {
	c := config.Default()
	c.Channels = []config.Channel{{ID: "off", Type: "telegram", Enabled: false}, {ID: "future", Type: "webhook", Enabled: false}}
	d := Dispatcher{Config: c, Factory: func(config.Channel) Sender { t.Fatal("disabled provider invoked"); return nil }}
	if len(d.SendAll(context.Background(), "test", "body")) != 0 {
		t.Fatal("unexpected result")
	}
}
