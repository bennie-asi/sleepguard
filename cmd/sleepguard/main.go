package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/engine"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/notification"
	"github.com/bennie-asi/sleepguard/internal/platform"
	"github.com/bennie-asi/sleepguard/internal/runner"
	"github.com/bennie-asi/sleepguard/internal/store"
	"github.com/spf13/cobra"
)

var appVersion = "development"
var appBuild = "0"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if e := command().ExecuteContext(ctx); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
}
func output(v any) error { e := json.NewEncoder(os.Stdout); e.SetIndent("", "  "); return e.Encode(v) }
func command() *cobra.Command {
	return commandWithWatchCollector(platform.Collector{})
}
func commandWithWatchCollector(collector runner.Collector) *cobra.Command {
	var cfgPath, state string
	root := &cobra.Command{Use: "sleepguard", Short: "检查 macOS 防休眠请求，通知并按规则处理", SilenceUsage: true, SilenceErrors: true}
	versionCmd := &cobra.Command{Use: "version", Short: "显示版本和构建号", RunE: func(cmd *cobra.Command, _ []string) error {
		if jsonVersion, _ := cmd.Flags().GetBool("json"); jsonVersion {
			return output(map[string]string{"version": appVersion, "build": appBuild})
		}
		fmt.Printf("SleepGuard %s (%s)\n", appVersion, appBuild)
		return nil
	}}
	versionCmd.Flags().Bool("json", false, "输出 JSON")
	root.AddCommand(versionCmd)
	root.PersistentFlags().StringVar(&cfgPath, "config", config.DefaultPath(), "TOML 配置路径")
	root.PersistentFlags().StringVar(&state, "state-dir", config.DefaultStateDir(), "事件数据库目录")
	load := func(required bool) (config.Config, error) {
		c, e := config.Load(cfgPath)
		if !required && !root.PersistentFlags().Changed("config") && errors.Is(e, os.ErrNotExist) {
			return config.Default(), nil
		}
		return c, e
	}
	var jsonStatus bool
	status := &cobra.Command{Use: "status", Short: "实时查看请求和休眠判断（只读）", RunE: func(cmd *cobra.Command, _ []string) error {
		c, e := load(false)
		if e != nil {
			return e
		}
		s, e := (platform.Collector{}).Collect(cmd.Context())
		if e != nil {
			return e
		}
		a := engine.Assess(c, s)
		if jsonStatus {
			return output(map[string]any{"snapshot": s, "assessment": a})
		}
		fmt.Printf("%s\n电源 %s，空闲 %s；sleep=%dm / displaysleep=%dm\n", a.Reason, s.PowerSource, time.Duration(s.IdleSeconds*float64(time.Second)).Round(time.Second), s.SleepMinutes, s.DisplayMinutes)
		for _, x := range s.Assertions {
			target := "未确定"
			if x.Target != nil {
				target = fmt.Sprintf("%s (%d)", x.Target.Name, x.Target.PID)
			}
			fmt.Printf("%s | %s | 持有者 %s (%d) → %s\n", x.Type, x.Name, x.Holder.Name, x.Holder.PID, target)
		}
		if s.KernelAssertions != "" {
			fmt.Println(s.KernelAssertions)
		}
		for _, d := range s.Diagnostics {
			fmt.Println("诊断：", d)
		}
		return nil
	}}
	status.Flags().BoolVar(&jsonStatus, "json", false, "输出 JSON")
	root.AddCommand(status)
	configCmd := &cobra.Command{Use: "config", Short: "配置管理"}
	configCmd.AddCommand(&cobra.Command{Use: "example", RunE: func(*cobra.Command, []string) error { fmt.Print(config.Example); return nil }}, &cobra.Command{Use: "validate", RunE: func(*cobra.Command, []string) error {
		_, e := load(true)
		if e == nil {
			fmt.Println("配置有效")
		}
		return e
	}})
	root.AddCommand(configCmd)
	var once, dry, exitOnStdinClose bool
	watch := &cobra.Command{Use: "watch", Short: "持续检测；默认不发送通知、不结束进程", RunE: func(cmd *cobra.Command, _ []string) (result error) {
		c, e := load(false)
		if e != nil {
			return e
		}
		ctx, cancel := context.WithCancel(cmd.Context())
		defer cancel()
		if exitOnStdinClose {
			// The desktop app owns the pipe's write end. EOF also covers its crash,
			// so the monitor cannot outlive the app without a persistent login agent.
			stdin := cmd.InOrStdin()
			if closer, ok := stdin.(io.Closer); ok {
				defer closer.Close()
			}
			go func() {
				_, _ = io.Copy(io.Discard, stdin)
				cancel()
			}()
		}
		var db *store.Store
		health := model.WatcherHealth{PID: os.Getpid(), StartedAt: time.Now(), IntervalSeconds: config.Duration(c.Monitor.Interval).Seconds()}
		var lock *os.File
		if !dry {
			if e = os.MkdirAll(state, 0700); e != nil {
				return e
			}
			lock, e = os.OpenFile(filepath.Join(state, "watch.lock"), os.O_CREATE|os.O_RDWR, 0600)
			if e != nil {
				return e
			}
			defer lock.Close()
			if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
				return fmt.Errorf("已有 watcher 使用此状态目录")
			}
			db, e = store.Open(state)
			if e != nil {
				return e
			}
			defer db.Close()
			previousHealth, err := db.WatcherHealth()
			if err != nil {
				return err
			}
			health.LastSuccess = previousHealth.LastSuccess
			health.LastError, health.LastErrorAt = previousHealth.LastError, previousHealth.LastErrorAt
			defer func() {
				if result != nil && ctx.Err() == nil {
					health.LastError = result.Error()
					health.LastErrorAt = time.Now()
					if err := db.SaveWatcherHealth(health); err != nil {
						result = errors.Join(result, err)
					}
				}
			}()
			if e = db.SaveWatcherHealth(health); e != nil {
				return e
			}
			if e = db.Prune(time.Now(), c.Monitor.RetentionDays); e != nil {
				return e
			}
		}
		r := runner.Runner{Config: c, Store: db, Collector: collector, Notifier: notification.Dispatcher{Config: c}, Reload: func() (config.Config, error) { return load(false) }}
		lastPrune := time.Now()
		ticker := time.NewTicker(config.Duration(c.Monitor.Interval))
		defer ticker.Stop()
		for {
			if ctx.Err() != nil {
				return nil
			}
			current, err := load(false)
			if err != nil {
				return err
			}
			if current.Monitor.Interval != c.Monitor.Interval {
				ticker.Reset(config.Duration(current.Monitor.Interval))
			}
			c = current
			r.Config = c
			r.Notifier = notification.Dispatcher{Config: c}
			if !dry && time.Since(lastPrune) >= 24*time.Hour {
				if e = db.Prune(time.Now(), c.Monitor.RetentionDays); e != nil {
					return e
				}
				lastPrune = time.Now()
			}
			if dry {
				s, err := collector.Collect(ctx)
				if err != nil {
					if ctx.Err() != nil {
						return nil
					}
					return err
				}
				if e = output(engine.Assess(c, s)); e != nil {
					return e
				}
			} else {
				health.LastAttempt = time.Now()
				health.IntervalSeconds = config.Duration(c.Monitor.Interval).Seconds()
				if e = db.SaveWatcherHealth(health); e != nil {
					return e
				}
				if e = r.Tick(ctx); e != nil {
					if ctx.Err() != nil {
						return nil
					}
					return e
				}
				health.LastSuccess = time.Now()
				if e = db.SaveWatcherHealth(health); e != nil {
					return e
				}
			}
			if once {
				return nil
			}
			select {
			case <-ctx.Done():
				return nil
			case <-ticker.C:
			}
		}
	}}
	watch.Flags().BoolVar(&once, "once", false, "仅采样一次")
	watch.Flags().BoolVar(&dry, "dry-run", false, "只输出判断，不写状态、不发消息、不处理进程")
	watch.Flags().BoolVar(&exitOnStdinClose, "exit-on-stdin-close", false, "标准输入关闭时退出，供桌面应用管理后台生命周期")
	root.AddCommand(watch)
	var limit int
	history := &cobra.Command{Use: "history", Short: "查看事件历史 JSON", RunE: func(*cobra.Command, []string) error {
		db, e := store.Open(state)
		if e != nil {
			return e
		}
		defer db.Close()
		v, e := db.History(limit)
		if e != nil {
			return e
		}
		return output(v)
	}}
	history.Flags().IntVar(&limit, "limit", 50, "记录数量")
	root.AddCommand(history)
	var duration string
	snooze := &cobra.Command{Use: "snooze [incident-id|all]", Args: cobra.ExactArgs(1), Short: "暂停指定事件或全部事件的通知与处理", RunE: func(_ *cobra.Command, args []string) error {
		d, e := time.ParseDuration(duration)
		if e != nil || d <= 0 {
			return fmt.Errorf("--for 必须是正时间长度")
		}
		key := args[0]
		if key == "all" {
			key = "*"
		}
		db, e := store.Open(state)
		if e != nil {
			return e
		}
		defer db.Close()
		if key != "*" {
			i, e := db.Get(key)
			if e != nil {
				return e
			}
			if i == nil {
				return fmt.Errorf("事件不存在")
			}
		}
		until := time.Now().Add(d)
		if e = db.Snooze(key, until); e != nil {
			return e
		}
		fmt.Println("已暂停至", until.Format(time.RFC3339))
		return nil
	}}
	snooze.Flags().StringVar(&duration, "for", "1h", "暂停时长")
	root.AddCommand(snooze)
	notify := &cobra.Command{Use: "notify"}
	var notifyChannel string
	notifyTest := &cobra.Command{Use: "test", Short: "实际向指定渠道发送测试消息，默认第一个已启用的 Telegram", RunE: func(cmd *cobra.Command, _ []string) error {
		c, e := load(true)
		if e != nil {
			return e
		}
		id := notifyChannel
		if id == "" {
			for _, ch := range c.ActiveChannels() {
				if ch.Type == "telegram" {
					id = ch.ID
					break
				}
			}
		}
		if id == "" {
			return fmt.Errorf("没有启用的 Telegram 渠道，请配置渠道或通过 --channel 指定")
		}
		result, e := (notification.Dispatcher{Config: c}).Test(cmd.Context(), id)
		if e != nil {
			return e
		}
		if !result.Success {
			return errors.New(result.Message)
		}
		fmt.Println(result.ChannelName + " 已接收测试消息")
		return nil
	}}
	notifyTest.Flags().StringVar(&notifyChannel, "channel", "", "要测试的渠道 ID")
	notify.AddCommand(notifyTest)
	root.AddCommand(notify)
	addDesktopCommands(root, &cfgPath, &state)
	return root
}
