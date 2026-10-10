package notification

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/model"
)

type Sender interface {
	Send(context.Context, string, string) error
}
type Dispatcher struct {
	Config config.Config
	// Factory permits another provider without changing the engine.
	Factory func(config.Channel) Sender
}

func (d Dispatcher) sender(ch config.Channel) Sender {
	if d.Factory != nil {
		return d.Factory(ch)
	}
	if ch.Type == "system" {
		return System{HelperPath: d.Config.Notifications.HelperPath}
	}
	return Telegram{Config: config.Telegram{Enabled: true, ChatID: ch.ChatID, TokenEnv: ch.TokenEnv, KeychainService: ch.KeychainService, Timeout: ch.Timeout}}
}
func (d Dispatcher) SendAll(ctx context.Context, subject, body string) []model.Delivery {
	channels := d.Config.ActiveChannels()
	out := make([]model.Delivery, len(channels))
	var wg sync.WaitGroup
	for idx, ch := range channels {
		wg.Add(1)
		go func(idx int, ch config.Channel) {
			defer wg.Done()
			ctx, cancel := context.WithTimeout(ctx, config.Duration(ch.Timeout))
			defer cancel()
			err := d.sender(ch).Send(ctx, subject, body)
			out[idx] = model.Delivery{ChannelID: ch.ID, ChannelName: ch.Name, Provider: ch.Type, Success: err == nil, Message: "渠道已接收消息"}
			if err != nil {
				out[idx].Message = err.Error()
			}
		}(idx, ch)
	}
	wg.Wait()
	return out
}
func (d Dispatcher) Send(ctx context.Context, subject, body string) error {
	for _, v := range d.SendAll(ctx, subject, body) {
		if v.Success {
			return nil
		}
	}
	return errors.New("没有渠道成功接收通知")
}
func (d Dispatcher) Test(ctx context.Context, id string) (model.Delivery, error) {
	for _, ch := range d.Config.ActiveChannels() {
		if ch.ID == id {
			ctx, cancel := context.WithTimeout(ctx, config.Duration(ch.Timeout))
			defer cancel()
			err := d.sender(ch).Send(ctx, "SleepGuard 测试", "此通知渠道已连接。")
			r := model.Delivery{ChannelID: ch.ID, ChannelName: ch.Name, Provider: ch.Type, Success: err == nil, Message: "渠道已接收测试通知"}
			if err != nil {
				r.Message = err.Error()
			}
			return r, nil
		}
	}
	return model.Delivery{}, errors.New("此渠道未启用或尚未接入")
}

// The signed app helper owns UNUserNotificationCenter, even when the menu app is closed.
type System struct{ HelperPath string }

func (s System) Send(ctx context.Context, subject, body string) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	helper := s.HelperPath
	if helper == "" {
		binary, e := os.Executable()
		if e != nil {
			return errors.New("找不到系统通知应用")
		}
		helper = filepath.Clean(filepath.Join(filepath.Dir(binary), "..", "MacOS", "SleepGuard"))
	}
	b, _ := json.Marshal(map[string]string{"title": subject, "body": body})
	cmd := exec.CommandContext(ctx, helper, "--deliver-notification")
	cmd.Stdin = bytes.NewReader(b)
	// The helper returns only a bounded public error; never forward credential-bearing output.
	if e := cmd.Run(); e != nil {
		return errors.New("系统通知未送达，请检查 SleepGuard 通知权限和应用位置")
	}
	return nil
}
