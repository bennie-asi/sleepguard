package engine

import (
	"fmt"
	"sort"
	"time"

	"github.com/bennie-asi/sleepguard/internal/config"
	"github.com/bennie-asi/sleepguard/internal/model"
)

func Policy(c config.Config, p *model.Process) string {
	if p == nil {
		return "notify"
	}
	for _, r := range c.Rules {
		if (r.BundleID != "" && r.BundleID == p.BundleID) || (r.Path != "" && r.Path == p.Path) {
			n, process := r.Selection()
			if p.Protected {
				process = false
			}
			if process {
				if n {
					return "terminate"
				}
				return "process"
			}
			if n {
				return "notify"
			}
			return "ignore"
		}
	}
	return "notify"
}

// Assess describes an expectation, not a reimplementation of powerd's scheduler.
func Assess(c config.Config, s model.Snapshot) model.Assessment {
	a := model.Assessment{Candidates: []model.Candidate{}}
	threshold := time.Duration(max(s.SleepMinutes, s.DisplayMinutes))*time.Minute + config.Duration(c.Monitor.Grace)
	a.ThresholdSeconds = threshold.Seconds()
	groups := map[string]*model.Candidate{}
	displayBlocker := false
	for _, x := range s.Assertions {
		if !x.BlocksIdle() {
			continue
		}
		if x.Type == "PreventUserIdleDisplaySleep" || x.Type == "NoDisplaySleepAssertion" {
			displayBlocker = true
		}
		if x.Holder.Name == "powerd" && x.Name == "Powerd - Prevent sleep while display is on" {
			continue
		}
		policy := Policy(c, x.Target)
		if policy == "ignore" {
			continue
		}
		key := x.Holder.Identity(s.BootID) + "-unresolved"
		label := x.Holder.Name + " (责任应用未确定)"
		if x.Target != nil {
			key = x.Target.Identity(s.BootID)
			label = x.Target.Name
		}
		g, ok := groups[key]
		if !ok {
			g = &model.Candidate{Key: key, Label: label, Target: x.Target, Policy: policy}
			groups[key] = g
		}
		g.Assertions = append(g.Assertions, x)
	}
	for _, g := range groups {
		a.Candidates = append(a.Candidates, *g)
	}
	sort.Slice(a.Candidates, func(i, j int) bool { return a.Candidates[i].Key < a.Candidates[j].Key })
	switch {
	case s.SleepDisabled || s.SleepMinutes <= 0:
		a.Reason = "当前配置禁用自动系统休眠"
	case s.DisplayMinutes <= 0:
		a.Reason = "当前配置不自动熄屏，保守地不推定休眠超时"
	case s.At.Sub(s.WakeAt) < config.Duration(c.Monitor.WakeGrace):
		a.Reason = "刚唤醒，等待宽限期"
	case s.IdleSeconds < threshold.Seconds():
		a.Reason = "尚未超过配置时间与宽限期"
	case !s.DisplayAsleep && !displayBlocker:
		a.Reason = "显示器仍亮着且无明确阻止熄屏请求，继续观察"
	case len(a.Candidates) == 0:
		a.Reason = "未发现需要告警的应用防休眠请求；硬件/内核原因仅供诊断"
	default:
		a.Eligible = true
		a.Reason = "超过预期空闲时间，仍有应用防休眠请求"
	}
	return a
}

func Advance(c config.Config, s model.Snapshot, x model.Candidate, old *model.Incident) model.Incident {
	gap := 3 * config.Duration(c.Monitor.Interval)
	version := RuleVersion(c, x.Policy)
	fresh := old == nil || !old.Active || old.RuleVersion != version || old.BootID != s.BootID || !old.WakeAt.Equal(s.WakeAt) || s.At.Sub(old.LastSeen) > gap || s.At.Before(old.LastSeen)
	var i model.Incident
	if fresh {
		i = model.Incident{Key: x.Key, BootID: s.BootID, WakeAt: s.WakeAt, FirstSeen: s.At, Active: true}
	} else {
		i = *old
	}
	i.Label = x.Label
	i.Target = x.Target
	i.LastSeen = s.At
	i.Samples++
	i.RuleVersion = version
	if i.Samples >= c.Monitor.ConsecutiveSamples && i.QualifiedAt.IsZero() {
		i.QualifiedAt = s.At
	}
	return i
}

type Decision string

const (
	Wait      Decision = "wait"
	Notify    Decision = "notify"
	Terminate Decision = "terminate"
)

func Decide(c config.Config, i model.Incident, policy string, now time.Time) Decision {
	if !i.Active || i.Samples < c.Monitor.ConsecutiveSamples || now.Before(i.SnoozedUntil) || i.ActionAttempted {
		return Wait
	}
	if c.Actions.Enabled && Processing(policy) && i.Target != nil && !i.Target.Protected && !i.QualifiedAt.IsZero() && !now.Before(Deadline(c, i)) && !now.Before(i.ActionRetryAt) {
		return Terminate
	}
	if (policy == "notify" || policy == "terminate") && len(c.ActiveChannels()) > 0 && (i.LastAttempt.IsZero() || now.Sub(i.LastAttempt) >= config.Duration(c.Monitor.ReminderInterval)) {
		return Notify
	}
	return Wait
}
func Processing(policy string) bool { return policy == "terminate" || policy == "process" }
func RuleVersion(c config.Config, policy string) string {
	return fmt.Sprintf("%s|%t|%d|%s|%s|%s|%s", policy, c.Actions.Enabled, c.Monitor.ConsecutiveSamples, c.Monitor.Grace, c.Monitor.WakeGrace, c.Actions.Wait, c.Monitor.FinalGrace)
}
func Deadline(c config.Config, i model.Incident) time.Time {
	return i.QualifiedAt.Add(config.Duration(c.Actions.Wait) + config.Duration(c.Monitor.FinalGrace))
}

func Message(c config.Config, s model.Snapshot, i model.Incident, policy string) string {
	target := "归属不明确，仅通知"
	if i.Target != nil {
		target = fmt.Sprintf("%s (PID %d)", i.Target.Name, i.Target.PID)
	}
	action := "本事件只通知，不自动结束进程"
	if c.Actions.Enabled && Processing(policy) {
		action = fmt.Sprintf("处理等待 %s，再等待 %s 并复核后请求退出；通知结果不改变倒计时", c.Actions.Wait, c.Monitor.FinalGrace)
	}
	return fmt.Sprintf("应用：%s\n空闲：%s\n电源：%s；配置 sleep=%dm / displaysleep=%dm\n持续检测：%s\n本次通知：%d\n%s\n暂停处理：sleepguard snooze %s --for 1h", target, time.Duration(s.IdleSeconds*float64(time.Second)).Round(time.Second), s.PowerSource, s.SleepMinutes, s.DisplayMinutes, s.At.Sub(i.FirstSeen).Round(time.Second), i.Notifications+1, action, i.Key)
}
