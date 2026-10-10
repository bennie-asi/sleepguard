package notification

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"html"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/bennie-asi/sleepguard/internal/config"
	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api"
	"github.com/nikoksr/notify/service/telegram"
)

type Telegram struct {
	Config    config.Telegram
	Transport http.RoundTripper
}
type boundTransport struct {
	ctx  context.Context
	base http.RoundTripper
}

func (t boundTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return t.base.RoundTrip(r.Clone(t.ctx))
}
func (t Telegram) Send(ctx context.Context, subject, body string) error {
	if !t.Config.Enabled {
		return errors.New("Telegram 未启用")
	}
	ctx, cancel := context.WithTimeout(ctx, config.Duration(t.Config.Timeout))
	defer cancel()
	token := os.Getenv(t.Config.TokenEnv)
	if token == "" && t.Config.KeychainService != "" {
		// The app that saved the item also reads it. Never trust the generic security
		// CLI or return the token across a process boundary. The helper cannot prompt.
		binary, e := os.Executable()
		if e != nil {
			return errors.New("找不到 SleepGuard 凭据服务")
		}
		helper := filepath.Clean(filepath.Join(filepath.Dir(binary), "..", "MacOS", "SleepGuard"))
		data, _ := json.Marshal(map[string]any{"service": t.Config.KeychainService, "chatID": t.Config.ChatID, "title": subject, "body": body, "timeout": config.Duration(t.Config.Timeout).Seconds()})
		command := exec.CommandContext(ctx, helper, "--send-keychain-telegram")
		command.Stdin = bytes.NewReader(data)
		if e := command.Run(); e != nil {
			if exit, ok := e.(*exec.ExitError); ok && exit.ExitCode() == 3 {
				return errors.New("钥匙串尚未授权；请打开此渠道，重新保存 Token 或点击测试并在系统窗口选择始终允许")
			}
			return errors.New("Telegram 发送失败，请检查凭据、网络和 SleepGuard 应用位置")
		}
		return nil
	}
	if token == "" {
		return errors.New("未找到 Telegram token，请配置环境变量或登录钥匙串")
	}
	base := t.Transport
	if base == nil {
		base = http.DefaultTransport
	}
	client := &http.Client{Timeout: config.Duration(t.Config.Timeout), Transport: boundTransport{ctx, base}}
	bot, e := tgbotapi.NewBotAPIWithClient(token, client)
	if e != nil {
		return errors.New("Telegram 身份验证失败（凭据或网络错误）")
	}
	service := &telegram.Telegram{}
	service.SetClient(bot)
	service.AddReceivers(t.Config.ChatID)
	if e = service.Send(ctx, html.EscapeString(subject), html.EscapeString(body)); e != nil {
		return errors.New("Telegram 发送失败（接口拒绝或网络错误）")
	}
	return nil
}
