package runner

import (
	"context"
	"fmt"
	"log/slog"
	"syscall"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/engine"
	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/platform"
	"github.com/bennie-asi/sleepguard/internal/store"
)

type Collector interface {
	Collect(context.Context) (model.Snapshot, error)
}
type Notifier interface {
	Send(context.Context, string, string) error
}
type Runner struct {
	Config    config.Config
	Store     *store.Store
	Collector Collector
	Notifier  Notifier
	Inspect   func(context.Context, int32) (model.Process, error)
	Signal    func(int32, syscall.Signal) error
	Reload    func() (config.Config, error)
}

func (r *Runner) Tick(ctx context.Context) error {
	s, e := r.Collector.Collect(ctx)
	if e != nil {
		return e
	}
	a := engine.Assess(r.Config, s)
	active, e := r.Store.Active()
	if e != nil {
		return e
	}
	seen := map[string]bool{}
	if a.Eligible {
		for _, x := range a.Candidates {
			seen[x.Key] = true
			old, e := r.Store.Get(x.Key)
			if e != nil {
				return e
			}
			until, e := r.Store.SnoozedUntil(x.Key)
			if e != nil {
				return e
			}
			resetVersion, e := r.Store.ResetVersion(x.Key)
			if e != nil {
				return e
			}
			if old != nil && old.ResetVersion != resetVersion {
				old = nil
			}
			// A snooze invalidates accumulated warnings, including across daemon restarts.
			if old != nil && ((!until.Equal(old.SnoozedUntil) && until.After(old.FirstSeen)) || (!old.SnoozedUntil.IsZero() && !s.At.Before(old.SnoozedUntil) && old.FirstSeen.Before(old.SnoozedUntil))) {
				old = nil
			}
			i := engine.Advance(r.Config, s, x, old)
			i.SnoozedUntil = until
			i.ResetVersion = resetVersion
			if e = r.Store.Save(i); e != nil {
				return e
			}
			if old == nil || !old.Active {
				if e = r.Store.Event(s.At, i.Key, "detected", x.Label); e != nil {
					return e
				}
			}
			// UI controls may change while this tick is collecting or writing.
			latestUntil, e := r.Store.SnoozedUntil(i.Key)
			if e != nil {
				return e
			}
			latestVersion, e := r.Store.ResetVersion(i.Key)
			if e != nil {
				return e
			}
			if time.Now().Before(latestUntil) || latestVersion != i.ResetVersion {
				continue
			}
			switch engine.Decide(r.Config, i, x.Policy, s.At) {
			case engine.Notify:
				i.LastAttempt = s.At
				if e = r.Store.Save(i); e != nil {
					return e
				}
				success := false
				if dispatcher, ok := r.Notifier.(interface {
					SendAll(context.Context, string, string) []model.Delivery
				}); ok {
					for _, result := range dispatcher.SendAll(ctx, "sleepguard：持续阻止休眠", engine.Message(r.Config, s, i, x.Policy)) {
						result.RoundID = fmt.Sprintf("%s-%d", i.Key, s.At.UnixNano())
						success = success || result.Success
						if e = r.Store.Delivery(s.At, i.Key, result); e != nil {
							return e
						}
					}
				} else if r.Notifier != nil {
					err := r.Notifier.Send(ctx, "sleepguard：持续阻止休眠", engine.Message(r.Config, s, i, x.Policy))
					success = err == nil
					msg := "渠道已接收消息"
					kind := "notification_sent"
					if err != nil {
						kind = "notification_failed"
						msg = err.Error()
					}
					if e = r.Store.Event(s.At, i.Key, kind, msg); e != nil {
						return e
					}
				}
				if success {
					i.Notifications++
					i.LastSent = time.Now()
				}
				if e = r.Store.Save(i); e != nil {
					return e
				}
			case engine.Terminate:
				err := r.terminate(ctx, &i)
				i.ActionResult = "已发送结束信号；是否解除请求由后续采样确认"
				if err != nil {
					i.ActionResult = err.Error()
					if !i.ActionAttempted {
						// Leave a notification opportunity between retries. No signal was
						// attempted, so a transient preflight failure must not end the event.
						i.ActionRetryAt = s.At.Add(max(time.Minute, 2*config.Duration(r.Config.Monitor.Interval)))
					}
				}
				if e = r.Store.Save(i); e != nil {
					return e
				}
				if e = r.Store.Event(time.Now(), i.Key, "action_result", i.ActionResult); e != nil {
					return e
				}
			}
		}
	}
	for _, i := range active {
		if !seen[i.Key] {
			i.Active = false
			i.LastSeen = s.At
			if e = r.Store.Save(i); e != nil {
				return e
			}
			if e = r.Store.Event(s.At, i.Key, "reset", "已不满足持续阻止休眠条件；下次重新计数"); e != nil {
				return e
			}
		}
	}
	slog.Info("采样完成", "eligible", a.Eligible, "reason", a.Reason, "candidates", len(a.Candidates))
	return nil
}

func (r *Runner) guard(ctx context.Context, i model.Incident) error {
	s, e := r.Collector.Collect(ctx)
	if e != nil {
		return fmt.Errorf("处理取消：重新采集失败")
	}
	if s.BootID != i.BootID || !s.WakeAt.Equal(i.WakeAt) {
		return fmt.Errorf("处理取消：发生睡眠或重启")
	}
	if e = r.authorize(ctx, i); e != nil {
		return e
	}
	a := engine.Assess(r.Config, s)
	if !a.Eligible {
		return fmt.Errorf("处理取消：已不满足休眠超时条件")
	}
	for _, x := range a.Candidates {
		if x.Key == i.Key && engine.Processing(x.Policy) && x.Target != nil && !x.Target.Protected {
			if i.RuleVersion != "" && s.At.Before(engine.Deadline(r.Config, i)) {
				return fmt.Errorf("处理取消：等待时间尚未结束")
			}
			return nil
		}
	}
	return fmt.Errorf("处理取消：目标已退出、身份变化或请求已解除")
}

// Run again under the control lock immediately before a signal, after all
// potentially slow collection. Configuration changes during collection apply too.
func (r *Runner) authorize(ctx context.Context, i model.Incident) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if r.Reload != nil {
		current, e := r.Reload()
		if e != nil {
			return fmt.Errorf("处理取消：当前配置无效")
		}
		r.Config = current
	}
	if !r.Config.Actions.Enabled || i.Target == nil || i.Target.Protected {
		return fmt.Errorf("处理取消：目标不允许结束")
	}
	until, e := r.Store.SnoozedUntil(i.Key)
	if e != nil {
		return e
	}
	if time.Now().Before(until) {
		return fmt.Errorf("处理取消：已暂停")
	}
	version, e := r.Store.ResetVersion(i.Key)
	if e != nil {
		return e
	}
	if version != i.ResetVersion {
		return fmt.Errorf("处理取消：监控已重新恢复，需要重新累计异常")
	}
	policy := engine.Policy(r.Config, i.Target)
	if !engine.Processing(policy) || (i.RuleVersion != "" && i.RuleVersion != engine.RuleVersion(r.Config, policy)) {
		return fmt.Errorf("处理取消：规则已变化，需要重新累计异常")
	}
	return nil
}
func (r *Runner) sendGuarded(ctx context.Context, i *model.Incident, sig syscall.Signal) error {
	if e := r.guard(ctx, *i); e != nil {
		return e
	}
	return r.Store.WithControlLock(ctx, func() error {
		if e := r.authorize(ctx, *i); e != nil {
			return e
		}
		if sig == syscall.SIGKILL && !r.Config.Actions.AllowSIGKILL {
			return fmt.Errorf("处理取消：强制结束已关闭")
		}
		inspect := r.Inspect
		if inspect == nil {
			inspect = platform.InspectProcess
		}
		p, e := inspect(ctx, i.Target.PID)
		if e != nil || p.Protected || p.Identity(i.BootID) != i.Key || !engine.Processing(engine.Policy(r.Config, &p)) {
			return fmt.Errorf("处理取消：目标已退出或身份变化")
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if sig == syscall.SIGTERM {
			// Persist intent before the syscall: a crash after delivery must not
			// cause another signal on restart. Preflight errors never reach here.
			intent := *i
			intent.ActionAttempted = true
			if e = r.Store.Save(intent); e != nil {
				return e
			}
			if e = r.Store.Event(time.Now(), i.Key, "action_attempt", "复核通过，准备发送 SIGTERM"); e != nil {
				return e
			}
			i.ActionAttempted = true
		}
		send := r.Signal
		if send == nil {
			send = func(pid int32, sig syscall.Signal) error { return syscall.Kill(int(pid), sig) }
		}
		if e = send(i.Target.PID, sig); e != nil {
			return fmt.Errorf("%s 失败: %w", sig, e)
		}
		return nil
	})
}
func (r *Runner) terminate(ctx context.Context, i *model.Incident) error {
	if e := r.sendGuarded(ctx, i, syscall.SIGTERM); e != nil {
		return e
	}
	if !r.Config.Actions.AllowSIGKILL {
		return nil
	}
	timer := time.NewTimer(config.Duration(r.Config.Actions.KillAfter))
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
	}
	return r.sendGuarded(ctx, i, syscall.SIGKILL)
}
