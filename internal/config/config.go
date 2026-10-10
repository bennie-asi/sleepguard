package config

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
)

type Config struct {
	Monitor       Monitor       `toml:"monitor" json:"monitor"`
	Telegram      Telegram      `toml:"telegram" json:"telegram"`
	Actions       Actions       `toml:"actions" json:"actions"`
	Rules         []Rule        `toml:"rules" json:"rules"`
	Notifications Notifications `toml:"notifications" json:"notifications"`
	Channels      []Channel     `toml:"channels" json:"channels"`
}
type Notifications struct {
	SystemEnabled bool   `toml:"system_enabled" json:"system_enabled"`
	HelperPath    string `toml:"helper_path,omitempty" json:"helper_path"`
}
type Channel struct {
	ID              string `toml:"id" json:"id"`
	Name            string `toml:"name" json:"name"`
	Type            string `toml:"type" json:"type"`
	Enabled         bool   `toml:"enabled" json:"enabled"`
	ChatID          int64  `toml:"chat_id,omitempty" json:"chat_id"`
	TokenEnv        string `toml:"token_env,omitempty" json:"token_env"`
	KeychainService string `toml:"keychain_service,omitempty" json:"keychain_service"`
	Timeout         string `toml:"timeout" json:"timeout"`
}
type Monitor struct {
	Interval           string `toml:"interval" json:"interval"`
	Grace              string `toml:"grace" json:"grace"`
	WakeGrace          string `toml:"wake_grace" json:"wake_grace"`
	ConsecutiveSamples int    `toml:"consecutive_samples" json:"consecutive_samples"`
	ReminderInterval   string `toml:"reminder_interval" json:"reminder_interval"`
	NotifyCount        int    `toml:"notify_count" json:"notify_count"`
	FinalGrace         string `toml:"final_grace" json:"final_grace"`
	RetentionDays      int    `toml:"retention_days" json:"retention_days"`
}
type Telegram struct {
	Enabled         bool   `toml:"enabled" json:"enabled"`
	ChatID          int64  `toml:"chat_id" json:"chat_id"`
	TokenEnv        string `toml:"token_env" json:"token_env"`
	KeychainService string `toml:"keychain_service" json:"keychain_service"`
	Timeout         string `toml:"timeout" json:"timeout"`
}
type Actions struct {
	Enabled      bool   `toml:"enabled" json:"enabled"`
	KillAfter    string `toml:"kill_after" json:"kill_after"`
	AllowSIGKILL bool   `toml:"allow_sigkill" json:"allow_sigkill"`
	Wait         string `toml:"wait" json:"wait"`
}
type Rule struct {
	BundleID string `toml:"bundle_id,omitempty" json:"bundle_id"`
	Path     string `toml:"path,omitempty" json:"path"`
	Policy   string `toml:"policy,omitempty" json:"policy,omitempty"`
	Name     string `toml:"name,omitempty" json:"name"`
	Notify   *bool  `toml:"notify,omitempty" json:"notify,omitempty"`
	Process  *bool  `toml:"process,omitempty" json:"process,omitempty"`
}

func Bool(value bool) *bool { return &value }
func (r Rule) Selection() (notify, process bool) {
	if r.Notify != nil || r.Process != nil {
		return r.Notify != nil && *r.Notify, r.Process != nil && *r.Process
	}
	return r.Policy != "ignore", r.Policy == "terminate"
}
func (c Config) ActiveChannels() []Channel {
	out := []Channel{}
	if c.Notifications.SystemEnabled {
		out = append(out, Channel{ID: "system", Name: "系统通知", Type: "system", Enabled: true, Timeout: "10s"})
	}
	for _, ch := range c.Channels {
		if ch.Enabled && ch.Type == "telegram" {
			out = append(out, ch)
		}
	}
	if c.Telegram.Enabled {
		out = append(out, Channel{ID: "legacy-telegram", Name: "Telegram", Type: "telegram", Enabled: true, ChatID: c.Telegram.ChatID, TokenEnv: c.Telegram.TokenEnv, KeychainService: c.Telegram.KeychainService, Timeout: c.Telegram.Timeout})
	}
	return out
}
func (c *Config) Normalize() {
	if c.Rules == nil {
		c.Rules = []Rule{}
	}
	if c.Channels == nil {
		c.Channels = []Channel{}
	}
	for idx := range c.Rules {
		r := &c.Rules[idx]
		n, p := r.Selection()
		r.Notify = Bool(n)
		r.Process = Bool(p)
		r.Policy = ""
	}
	if c.Telegram.Enabled {
		c.Channels = append(c.Channels, Channel{ID: "legacy-telegram", Name: "Telegram", Type: "telegram", Enabled: true, ChatID: c.Telegram.ChatID, TokenEnv: c.Telegram.TokenEnv, KeychainService: c.Telegram.KeychainService, Timeout: c.Telegram.Timeout})
		c.Telegram.Enabled = false
	}
}

func Default() Config {
	return Config{
		Monitor:  Monitor{"60s", "5m", "2m", 3, "10m", 3, "10m", 30},
		Telegram: Telegram{false, 0, "SLEEPGUARD_TELEGRAM_TOKEN", "sleepguard.telegram", "15s"},
		Actions:  Actions{Enabled: false, KillAfter: "15s", Wait: "30m"},
		Rules:    []Rule{}, Channels: []Channel{},
	}
}
func DefaultPath() string {
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".config", "sleepguard", "config.toml")
}
func DefaultStateDir() string {
	h, _ := os.UserHomeDir()
	return filepath.Join(h, "Library", "Application Support", "sleepguard")
}
func Duration(s string) time.Duration { d, _ := time.ParseDuration(s); return d }
func Load(path string) (Config, error) {
	c, _, e := LoadWithRevision(path)
	return c, e
}

// The revision belongs to the same bytes that were decoded, including during a concurrent save.
func LoadWithRevision(path string) (Config, string, error) {
	c := Default()
	b, e := os.ReadFile(path)
	if e != nil {
		return c, "", e
	}
	d := toml.NewDecoder(strings.NewReader(string(b))).DisallowUnknownFields()
	if e = d.Decode(&c); e != nil {
		return c, "", fmt.Errorf("解析配置: %w", e)
	}
	if e = c.Validate(); e != nil {
		return c, "", e
	}
	c.Normalize()
	return c, fmt.Sprintf("%x", sha256.Sum256(b)), nil
}
func (c Config) Validate() error {
	for name, s := range map[string]string{"interval": c.Monitor.Interval, "grace": c.Monitor.Grace, "wake_grace": c.Monitor.WakeGrace, "reminder_interval": c.Monitor.ReminderInterval, "final_grace": c.Monitor.FinalGrace, "kill_after": c.Actions.KillAfter, "action_wait": c.Actions.Wait, "timeout": c.Telegram.Timeout} {
		d, e := time.ParseDuration(s)
		if e != nil || d <= 0 {
			return fmt.Errorf("%s 必须是正时间长度，例如 60s、5m", name)
		}
	}
	if Duration(c.Monitor.Interval) < time.Second {
		return fmt.Errorf("interval 不能小于 1s")
	}
	if c.Monitor.ConsecutiveSamples < 2 || c.Monitor.NotifyCount < 1 || c.Monitor.RetentionDays < 1 {
		return fmt.Errorf("consecutive_samples 至少 2，notify_count 和 retention_days 至少 1")
	}
	if c.Telegram.Enabled && (c.Telegram.ChatID == 0 || (c.Telegram.TokenEnv == "" && c.Telegram.KeychainService == "")) {
		return fmt.Errorf("启用 Telegram 需要 chat_id 和凭据来源")
	}
	channelIDs := map[string]bool{"system": true}
	if c.Telegram.Enabled {
		channelIDs["legacy-telegram"] = true
	}
	for _, ch := range c.Channels {
		if ch.ID == "" || ch.Name == "" || channelIDs[ch.ID] {
			return fmt.Errorf("通知渠道需要唯一 ID 和名称")
		}
		channelIDs[ch.ID] = true
		switch ch.Type {
		case "telegram":
			if ch.Enabled && (ch.ChatID == 0 || (ch.TokenEnv == "" && ch.KeychainService == "")) {
				return fmt.Errorf("启用 Telegram 渠道需要 Chat ID 和凭据来源")
			}
		case "webhook", "feishu", "slack", "email":
			if ch.Enabled {
				return fmt.Errorf("%s 尚未接入，不能启用", ch.Type)
			}
		default:
			return fmt.Errorf("未知渠道类型 %s", ch.Type)
		}
		if d, e := time.ParseDuration(ch.Timeout); e != nil || d <= 0 || d > time.Minute {
			return fmt.Errorf("渠道 timeout 必须在 0 到 1 分钟之间")
		}
	}
	seen := map[string]bool{}
	for _, r := range c.Rules {
		if (r.BundleID == "") == (r.Path == "") {
			return fmt.Errorf("每条规则必须且只能指定 bundle_id 或 path")
		}
		if r.Path != "" && !filepath.IsAbs(r.Path) {
			return fmt.Errorf("规则 path 必须是绝对路径")
		}
		if r.Policy != "" && (r.Notify != nil || r.Process != nil) {
			return fmt.Errorf("规则不能混用 policy 和 notify/process")
		}
		if r.Policy != "" && r.Policy != "notify" && r.Policy != "terminate" && r.Policy != "ignore" {
			return fmt.Errorf("规则 policy 必须是 notify、terminate 或 ignore")
		}
		k := r.BundleID + "|" + r.Path
		if seen[k] {
			return fmt.Errorf("存在重复应用规则")
		}
		seen[k] = true
	}
	return nil
}

const Example = `# sleepguard: 通知与处理可分别启用；自动处理默认关闭。
[monitor]
interval = "60s"
grace = "5m"
wake_grace = "2m"
consecutive_samples = 3
reminder_interval = "10m"
notify_count = 3 # 旧配置兼容字段，不再作为处理门槛
final_grace = "10m"
retention_days = 30

[notifications]
system_enabled = false # 原生应用授权后开启

[telegram]
enabled = false
chat_id = 0
# 先读取环境变量；没有则读取当前用户登录钥匙串的同名通用密码。
# LaunchAgent 不继承终端环境，常驻运行建议使用钥匙串。
token_env = "SLEEPGUARD_TELEGRAM_TOKEN"
keychain_service = "sleepguard.telegram"
timeout = "15s"

[actions]
enabled = false
kill_after = "15s"
allow_sigkill = false
wait = "30m"

[[rules]]
bundle_id = "com.netease.163music"
name = "网易云音乐"
notify = true
process = false # actions.enabled=true 且 process=true 才允许自动结束

# 添加任意数量的独立电报渠道；凭据值只保存在钥匙串或环境变量。
# [[channels]]
# id = "personal"
# name = "电报 · 个人提醒"
# type = "telegram"
# enabled = true
# chat_id = 123456789
# keychain_service = "sleepguard.telegram.personal"
# timeout = "15s"

# 其他应用默认仅通知。两项都设为 false 表示忽略，不告警、不处理。
# 指定可执行文件时使用精确绝对路径，不匹配进程名或通配符。
# [[rules]]
# path = "/Applications/Windows App.app/Contents/MacOS/Windows App"
# notify = true
# process = false
`
