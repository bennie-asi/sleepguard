package notification

import (
	"context"
	"errors"
	"github.com/bennie-asi/sleepguard/internal/config"
	"io"
	"net/http"
	"strings"
	"testing"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestTelegram(t *testing.T) {
	t.Setenv("SG_TEST_TOKEN", "secret-test-token")
	c := config.Default().Telegram
	c.Enabled = true
	c.ChatID = 42
	c.TokenEnv = "SG_TEST_TOKEN"
	calls := 0
	n := Telegram{Config: c, Transport: transport(func(r *http.Request) (*http.Response, error) {
		calls++
		body := `{"ok":true,"result":{"id":1,"is_bot":true,"first_name":"test","username":"testbot"}}`
		if strings.HasSuffix(r.URL.Path, "sendMessage") {
			b, _ := io.ReadAll(r.Body)
			if !strings.Contains(string(b), "%26lt%3Bapp%26gt%3B") {
				t.Fatalf("not escaped: %s", b)
			}
			body = `{"ok":true,"result":{"message_id":1,"chat":{"id":42,"type":"private"},"date":1,"text":"ok"}}`
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: make(http.Header)}, nil
	})}
	if e := n.Send(context.Background(), "test", "<app>"); e != nil {
		t.Fatal(e)
	}
	if calls != 2 {
		t.Fatalf("calls %d", calls)
	}
	n.Transport = transport(func(r *http.Request) (*http.Response, error) { return nil, errors.New(r.URL.String()) })
	if e := n.Send(context.Background(), "test", "body"); e == nil || strings.Contains(e.Error(), "secret-test-token") {
		t.Fatal("missing error or leaked token", e)
	}
}
