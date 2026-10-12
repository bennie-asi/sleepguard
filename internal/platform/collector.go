package platform

import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/shirou/gopsutil/v4/process"
)

type nativeAssertion struct {
	PID        int32          `json:"pid"`
	Properties map[string]any `json:"properties"`
}
type nativeSnapshot struct {
	Error         string            `json:"error"`
	BootID        string            `json:"boot_id"`
	WakeUnix      float64           `json:"wake_unix"`
	IdleSeconds   float64           `json:"idle_seconds"`
	DisplayAsleep bool              `json:"display_asleep"`
	PowerSource   string            `json:"power_source"`
	Assertions    []nativeAssertion `json:"assertions"`
}
type Collector struct{}

func (Collector) Collect(ctx context.Context) (model.Snapshot, error) {
	n, e := nativeRead()
	if e != nil {
		return model.Snapshot{}, e
	}
	s := model.Snapshot{At: time.Now(), BootID: n.BootID, WakeAt: time.Unix(0, int64(n.WakeUnix*1e9)), IdleSeconds: n.IdleSeconds, DisplayAsleep: n.DisplayAsleep, PowerSource: n.PowerSource, Assertions: []model.Assertion{}}
	if math.IsNaN(n.IdleSeconds) || math.IsInf(n.IdleSeconds, 0) || n.IdleSeconds < 0 {
		return s, fmt.Errorf("空闲时长无效")
	}
	tctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	b, e := exec.CommandContext(tctx, "/usr/bin/pmset", "-g", "custom").Output()
	if e != nil {
		return s, fmt.Errorf("读取电源设置失败: %w", e)
	}
	settings, e := ParseSettings(string(b), n.PowerSource)
	if e != nil {
		return s, e
	}
	assertionsText, assertionErr := exec.CommandContext(tctx, "/usr/bin/pmset", "-g", "assertions").Output()
	if assertionErr == nil {
		if idx := strings.Index(string(assertionsText), "Kernel Assertions:"); idx >= 0 {
			s.KernelAssertions = strings.TrimSpace(string(assertionsText)[idx:])
		}
	} else {
		s.Diagnostics = append(s.Diagnostics, "内核请求诊断暂不可读")
	}
	s.SleepMinutes = settings.Sleep
	s.DisplayMinutes = settings.Display
	globalText, err := exec.CommandContext(tctx, "/usr/bin/pmset", "-g").Output()
	if err != nil {
		return s, fmt.Errorf("读取全局休眠开关失败")
	}
	disabled, err := ParseSleepDisabled(string(globalText))
	if err != nil {
		return s, err
	}
	s.SleepDisabled = settings.Disabled || disabled
	cache := map[int32]model.Process{}
	resolve := func(pid int32) model.Process {
		if p, ok := cache[pid]; ok {
			return p
		}
		p, err := InspectProcess(ctx, pid)
		if err != nil {
			p = model.Process{PID: pid, Name: fmt.Sprintf("PID %d", pid), Protected: true}
			s.Diagnostics = append(s.Diagnostics, fmt.Sprintf("PID %d 身份不可读，仅报告", pid))
		}
		cache[pid] = p
		return p
	}
	for _, row := range n.Assertions {
		p := row.Properties
		if num(p["AssertLevel"]) == 0 {
			continue
		}
		holder := resolve(row.PID)
		a := model.Assertion{ID: fmt.Sprintf("%x", int64(num(p["AssertionId"]))), Type: str(p["AssertType"]), Name: str(p["AssertName"]), Holder: holder, Attribution: "unresolved"}
		if a.ID == "0" {
			a.ID = fmt.Sprintf("%x", int64(num(p["AssertionID"])))
		}
		if seconds := num(p["AssertStartWhen"]); seconds > 0 {
			a.Created = time.Unix(0, int64(seconds*1e9))
		}
		if rs, ok := p["ResourcesUsed"].([]any); ok {
			for _, r := range rs {
				a.Resources = append(a.Resources, str(r))
			}
		}
		// Only a verified system broker may delegate ownership. Assertion names are not authority.
		if IsBroker(holder.Path) {
			pid := int32(num(p["AssertionOnBehalfOfPID"]))
			if pid > 1 {
				target := resolve(pid)
				if ValidDelegation(target, a.Created) {
					a.Target = &target
					a.Attribution = "system-broker-pid"
				}
			}
		} else if holder.StartedMS > 0 && holder.Path != "" {
			target := holder
			a.Target = &target
			a.Attribution = "direct"
		}
		s.Assertions = append(s.Assertions, a)
	}
	sort.Slice(s.Assertions, func(i, j int) bool {
		if s.Assertions[i].Holder.PID == s.Assertions[j].Holder.PID {
			return s.Assertions[i].ID < s.Assertions[j].ID
		}
		return s.Assertions[i].Holder.PID < s.Assertions[j].Holder.PID
	})
	return s, nil
}
func num(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
}
func str(v any) string {
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

func IsBroker(path string) bool {
	return path == "/usr/sbin/coreaudiod" || path == "/usr/libexec/runningboardd" || path == "/System/Library/CoreServices/RunningBoard.app/Contents/MacOS/runningboardd"
}

func InspectProcess(ctx context.Context, pid int32) (model.Process, error) {
	p, e := process.NewProcessWithContext(ctx, pid)
	if e != nil {
		return model.Process{}, e
	}
	path, e := p.ExeWithContext(ctx)
	if e != nil {
		return model.Process{}, e
	}
	start, e := p.CreateTimeWithContext(ctx)
	if e != nil {
		return model.Process{}, e
	}
	uids, e := p.UidsWithContext(ctx)
	if e != nil || len(uids) == 0 {
		return model.Process{}, fmt.Errorf("无法读取进程用户")
	}
	real, e := filepath.EvalSymlinks(path)
	if e != nil {
		return model.Process{}, e
	}
	path = real
	out := model.Process{PID: pid, StartedMS: start, UID: int32(uids[0]), Path: path, Name: filepath.Base(path)}
	if idx := strings.Index(path, ".app/"); idx >= 0 {
		out.BundleID = bundleID(path[:idx+4])
	}
	out.Protected = uids[0] == 0 || pid <= 1 || pid == int32(os.Getpid()) || uids[0] != uint32(os.Getuid()) || ProtectedPath(path)
	out.Protected = out.Protected || out.BundleID == "io.sleepguard.app"
	return out, nil
}
func ProtectedPath(path string) bool {
	for _, prefix := range []string{"/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"} {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return path == ""
}

type Settings struct {
	Sleep    int
	Display  int
	Disabled bool
}

func ParseSettings(text, source string) (Settings, error) {
	if source != "AC Power" && source != "Battery Power" && source != "UPS Power" {
		return Settings{}, fmt.Errorf("未知电源来源 %q", source)
	}
	section := ""
	settings := Settings{}
	foundSleep, foundDisplay := false, false
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasSuffix(line, ":") {
			section = strings.TrimSuffix(line, ":")
			continue
		}
		if section != source {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		switch fields[0] {
		case "sleep", "displaysleep", "disablesleep":
			v, e := strconv.Atoi(fields[1])
			if e != nil || v < 0 {
				return settings, fmt.Errorf("无效电源设置 %s", fields[0])
			}
			switch fields[0] {
			case "sleep":
				settings.Sleep = v
				foundSleep = true
			case "displaysleep":
				settings.Display = v
				foundDisplay = true
			case "disablesleep":
				settings.Disabled = v != 0
			}
		}
	}
	if !foundSleep || !foundDisplay {
		return settings, fmt.Errorf("缺少 %s 的休眠时间配置", source)
	}
	return settings, nil
}

// Missing or older assertion metadata cannot authorize terminating a recycled PID.
func ValidDelegation(p model.Process, created time.Time) bool {
	return p.StartedMS > 0 && p.Path != "" && !created.IsZero() && p.StartedMS <= created.UnixMilli()
}

func ParseSleepDisabled(text string) (bool, error) {
	hasSystemSettings := false
	for _, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) == "System-wide power settings:" {
			hasSystemSettings = true
		}
		fields := strings.Fields(line)
		if len(fields) > 0 && strings.EqualFold(fields[0], "SleepDisabled") {
			if len(fields) != 2 {
				return false, fmt.Errorf("全局休眠开关值无效")
			}
			switch fields[1] {
			case "0":
				return false, nil
			case "1":
				return true, nil
			default:
				return false, fmt.Errorf("全局休眠开关值无效")
			}
		}
	}
	// pmset prints this optional override only when the system settings contain
	// it. A successfully read dictionary without the key leaves sleep enabled.
	if hasSystemSettings {
		return false, nil
	}
	return false, fmt.Errorf("无法确定全局休眠开关")
}
