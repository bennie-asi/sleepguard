package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/control"
	"github.com/bennie-asi/sleepguard/internal/engine"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/notification"
	"github.com/bennie-asi/sleepguard/internal/platform"
	"github.com/bennie-asi/sleepguard/internal/store"
	"github.com/shirou/gopsutil/v4/process"
	"github.com/spf13/cobra"
)

func desktopConfig(path string) (config.Config, error) {
	c, e := config.Load(path)
	if errors.Is(e, os.ErrNotExist) {
		return config.Default(), nil
	}
	return c, e
}
func watcherRunning(dir string) bool {
	f, e := os.OpenFile(filepath.Join(dir, "watch.lock"), os.O_RDWR, 0600)
	if e != nil {
		return false
	}
	defer f.Close()
	if e = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); e != nil {
		return true
	}
	syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return false
}
func addDesktopCommands(root *cobra.Command, path, dir *string) {
	ui := &cobra.Command{Use: "ui", Short: "原生应用 JSON 接口"}
	ui.AddCommand(&cobra.Command{Use: "manual-action", RunE: func(cmd *cobra.Command, _ []string) error {
		var request control.Request
		decoder := json.NewDecoder(io.LimitReader(cmd.InOrStdin(), 64*1024))
		decoder.DisallowUnknownFields()
		if e := decoder.Decode(&request); e != nil {
			return fmt.Errorf("操作请求无效")
		}
		db, e := store.Open(*dir)
		if e != nil {
			return e
		}
		defer db.Close()
		ctx, cancel := context.WithTimeout(cmd.Context(), 20*time.Second)
		defer cancel()
		result, e := (control.Manual{Collect: (platform.Collector{}).Collect, Event: db.Event}).Execute(ctx, request)
		if e != nil {
			return e
		}
		return output(result)
	}})
	ui.AddCommand(&cobra.Command{Use: "blackout-hold [begin|renew|end]", Args: cobra.ExactArgs(1), RunE: func(cmd *cobra.Command, args []string) error {
		db, e := store.Open(*dir)
		if e != nil {
			return e
		}
		defer db.Close()
		switch args[0] {
		case "begin", "renew":
			return db.Hold(time.Now().Add(60*time.Second), args[0] == "begin")
		case "end":
			return db.ReleaseHold()
		default:
			return fmt.Errorf("未知黑屏控制操作")
		}
	}})
	ui.AddCommand(&cobra.Command{Use: "config", Args: cobra.NoArgs, RunE: func(cmd *cobra.Command, _ []string) error {
		c, rev, e := config.LoadWithRevision(*path)
		if errors.Is(e, os.ErrNotExist) {
			c = config.Default()
			e = nil
		}
		if e != nil {
			return e
		}
		return output(map[string]any{"config": c, "revision": rev})
	}})
	ui.AddCommand(&cobra.Command{Use: "save-config", Args: cobra.NoArgs, RunE: func(cmd *cobra.Command, _ []string) error {
		var request struct {
			Config   config.Config `json:"config"`
			Revision string        `json:"revision"`
		}
		request.Config = config.Default()
		decoder := json.NewDecoder(io.LimitReader(cmd.InOrStdin(), 1024*1024))
		decoder.DisallowUnknownFields()
		if e := decoder.Decode(&request); e != nil {
			return fmt.Errorf("配置 JSON 无效: %w", e)
		}
		if e := decoder.Decode(new(any)); e != io.EOF {
			return fmt.Errorf("只能提交一个配置对象")
		}
		if e := config.Save(*path, request.Config, request.Revision); e != nil {
			return e
		}
		c, rev, e := config.LoadWithRevision(*path)
		if e != nil {
			return e
		}
		return output(map[string]any{"config": c, "revision": rev})
	}})
	ui.AddCommand(&cobra.Command{Use: "status", RunE: func(cmd *cobra.Command, _ []string) error {
		c, e := desktopConfig(*path)
		if e != nil {
			return e
		}
		s, e := (platform.Collector{}).Collect(cmd.Context())
		if e != nil {
			return e
		}
		incidents := []model.Incident{}
		var health model.WatcherHealth
		var until time.Time
		if _, e = os.Stat(filepath.Join(*dir, "state.db")); e == nil {
			db, e := store.Open(*dir)
			if e != nil {
				return e
			}
			defer db.Close()
			health, e = db.WatcherHealth()
			if e != nil {
				return e
			}
			incidents, e = db.Active()
			if e != nil {
				return e
			}
			until, e = db.SnoozedUntil("*")
			if e != nil {
				return e
			}
		}
		running := watcherRunning(*dir)
		health.Status = health.State(running, time.Now())
		return output(map[string]any{"snapshot": s, "assessment": engine.Assess(c, s), "incidents": incidents, "paused_until": until, "watcher_running": running, "watcher_health": health, "config_path": *path, "state_dir": *dir})
	}})
	ui.AddCommand(&cobra.Command{Use: "processes", RunE: func(cmd *cobra.Command, _ []string) error {
		ctx, cancel := context.WithTimeout(cmd.Context(), 20*time.Second)
		defer cancel()
		pids, e := process.PidsWithContext(ctx)
		if e != nil {
			return e
		}
		out := []model.Process{}
		for _, pid := range pids {
			if ctx.Err() != nil {
				break
			}
			p, e := platform.InspectProcess(ctx, pid)
			if e == nil {
				out = append(out, p)
			}
		}
		return output(out)
	}})
	ui.AddCommand(&cobra.Command{Use: "resume", RunE: func(cmd *cobra.Command, _ []string) error {
		db, e := store.Open(*dir)
		if e != nil {
			return e
		}
		defer db.Close()
		if e = db.Resume("*"); e != nil {
			return e
		}
		return output(map[string]bool{"ok": true})
	}})
	var channelID string
	test := &cobra.Command{Use: "test-notification", RunE: func(cmd *cobra.Command, _ []string) error {
		c, e := desktopConfig(*path)
		if e != nil {
			return e
		}
		result, e := (notification.Dispatcher{Config: c}).Test(cmd.Context(), channelID)
		if e != nil {
			return e
		}
		db, e := store.Open(*dir)
		if e != nil {
			return e
		}
		defer db.Close()
		result.RoundID = fmt.Sprintf("test-%d", time.Now().UnixNano())
		if e = db.Delivery(time.Now(), "test", result); e != nil {
			return e
		}
		return output(result)
	}}
	test.Flags().StringVar(&channelID, "channel", "system", "要测试的渠道 ID")
	ui.AddCommand(test)
	root.AddCommand(ui)
}
