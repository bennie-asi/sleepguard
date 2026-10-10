// Package control performs explicit user actions independently of automatic rules.
package control

import (
	"context"
	"fmt"
	"os"
	"syscall"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
	"github.com/bennie-asi/sleepguard/internal/platform"
	"github.com/shirou/gopsutil/v4/process"
)

type Request struct {
	Key    string        `json:"key"`
	Target model.Process `json:"target"`
	Force  bool          `json:"force"`
}
type Result struct {
	Exited  bool   `json:"exited"`
	Message string `json:"message"`
}
type Manual struct {
	Collect func(context.Context) (model.Snapshot, error)
	Inspect func(context.Context, int32) (model.Process, error)
	Signal  func(int32, syscall.Signal) error
	Event   func(time.Time, string, string, string) error
	Wait    time.Duration
	Exited  func(context.Context, int32) bool
}

func (m Manual) Execute(ctx context.Context, request Request) (Result, error) {
	target := request.Target
	if target.Protected || target.PID <= 1 || target.PID == int32(os.Getpid()) || target.StartedMS <= 0 || target.Path == "" || target.UID != int32(os.Getuid()) || platform.ProtectedPath(target.Path) || target.BundleID == "io.sleepguard.app" {
		return Result{}, fmt.Errorf("此进程不允许结束")
	}
	snapshot, err := m.Collect(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("无法复核当前休眠请求")
	}
	if request.Key != target.Identity(snapshot.BootID) {
		return Result{}, fmt.Errorf("进程身份已变化，请刷新后重试")
	}
	matched := false
	for _, assertion := range snapshot.Assertions {
		if assertion.BlocksIdle() && assertion.Target != nil && !assertion.Target.Protected && assertion.Target.Identity(snapshot.BootID) == request.Key {
			matched = true
		}
	}
	if !matched {
		return Result{}, fmt.Errorf("此应用的防休眠请求已解除，请刷新状态")
	}
	inspect := m.Inspect
	if inspect == nil {
		inspect = platform.InspectProcess
	}
	current, err := inspect(ctx, target.PID)
	if err != nil || current.Protected || current.UID != target.UID || current.BundleID != target.BundleID || current.Identity(snapshot.BootID) != request.Key {
		return Result{}, fmt.Errorf("进程已退出或身份变化，操作已取消")
	}
	send := m.Signal
	if send == nil {
		send = func(pid int32, sig syscall.Signal) error {
			if sig == syscall.SIGTERM {
				return platform.RequestQuit(pid)
			}
			return syscall.Kill(int(pid), sig)
		}
	}
	kind, label, signal := "manual_quit", "请求结束", syscall.SIGTERM
	if request.Force {
		kind, label, signal = "manual_force", "强制结束", syscall.SIGKILL
	}
	if err := m.Event(time.Now(), request.Key, kind, fmt.Sprintf("%s %s · PID %d", label, target.Name, target.PID)); err != nil {
		return Result{}, err
	}
	if err := send(target.PID, signal); err != nil {
		return Result{}, fmt.Errorf("发送结束信号失败")
	}
	wait := m.Wait
	if wait <= 0 {
		wait = 3 * time.Second
	}
	deadline := time.Now().Add(wait)
	result := Result{Message: "应用尚未退出，请刷新后确认；需要时可单独选择强制结束。"}
	checkExited := m.Exited
	if checkExited == nil {
		checkExited = processExited
	}
	for {
		current, err = inspect(ctx, target.PID)
		// A dead process may remain as a zombie until its parent reaps it.
		// Permission failures alone must never be reported as a successful exit.
		exited := checkExited(ctx, target.PID)
		if (err != nil && exited) || (err == nil && (exited || current.StartedMS != target.StartedMS)) {
			result = Result{Exited: true, Message: "已确认应用退出。"}
			break
		}
		if time.Now().After(deadline) {
			break
		}
		select {
		case <-ctx.Done():
			return Result{}, ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
	if err := m.Event(time.Now(), request.Key, kind+"_result", fmt.Sprintf("%s · PID %d：%s", target.Name, target.PID, result.Message)); err != nil {
		return Result{}, err
	}
	return result, nil
}
func processExited(ctx context.Context, pid int32) bool {
	if syscall.Kill(int(pid), 0) == syscall.ESRCH {
		return true
	}
	if p, e := process.NewProcessWithContext(ctx, pid); e == nil {
		if states, e := p.StatusWithContext(ctx); e == nil {
			for _, state := range states {
				if state == process.Zombie {
					return true
				}
			}
		}
	}
	return false
}
