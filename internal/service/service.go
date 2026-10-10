package service

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
)

const Label = "io.sleepguard.agent"
const AppLabel = "io.sleepguard.app.agent"

func escape(s string) string { var b bytes.Buffer; xml.EscapeText(&b, []byte(s)); return b.String() }
func Plist(binary, config, state string) string {
	association := ""
	arguments := []string{binary, "watch", "--config", config, "--state-dir", state}
	resources := filepath.Dir(binary)
	contents := filepath.Dir(resources)
	if filepath.Base(resources) == "Resources" && filepath.Base(contents) == "Contents" && filepath.Ext(filepath.Dir(contents)) == ".app" {
		// Legacy LaunchAgents must identify their owning app for the Login Items UI.
		association = `<key>AssociatedBundleIdentifiers</key><array><string>io.sleepguard.app</string></array>`
		// Launch from the app's main executable so macOS resolves its name and icon.
		// This mode execs the bundled Go watcher, preserving launchd's PID and signals.
		arguments = append([]string{filepath.Join(contents, "MacOS", "SleepGuard"), "--run-monitor"}, arguments[1:]...)
	}
	args := ""
	for _, s := range arguments {
		args += "<string>" + escape(s) + "</string>"
	}
	return `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>` + Label + `</string>` + association + `<key>ProgramArguments</key><array>` + args + `</array><key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>ThrottleInterval</key><integer>30</integer><key>StandardErrorPath</key><string>` + escape(filepath.Join(state, "agent.log")) + `</string></dict></plist>`
}
func path() string {
	h, _ := os.UserHomeDir()
	return filepath.Join(h, "Library", "LaunchAgents", Label+".plist")
}
func Install(config, state string) error {
	binary, e := os.Executable()
	if e != nil {
		return e
	}
	binary, e = filepath.EvalSymlinks(binary)
	if e != nil {
		return e
	}
	config, e = filepath.Abs(config)
	if e != nil {
		return e
	}
	state, e = filepath.Abs(state)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(state, 0700); e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(path()), 0700); e != nil {
		return e
	}
	f, e := os.OpenFile(path(), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return fmt.Errorf("服务文件已存在或无法创建，请先 uninstall: %w", e)
	}
	_, e = f.WriteString(Plist(binary, config, state))
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	b, e := exec.Command("/bin/launchctl", "bootstrap", "gui/"+strconv.Itoa(os.Getuid()), path()).CombinedOutput()
	if e != nil {
		return fmt.Errorf("已写入 plist，但加载失败: %s", b)
	}
	return nil
}
func Uninstall() error {
	if _, e := os.Stat(path()); e != nil {
		return e
	}
	domain := "gui/" + strconv.Itoa(os.Getuid()) + "/" + Label
	if exec.Command("/bin/launchctl", "print", domain).Run() == nil {
		if b, e := exec.Command("/bin/launchctl", "bootout", domain).CombinedOutput(); e != nil {
			return fmt.Errorf("停止服务失败: %s", b)
		}
	}
	return os.Remove(path())
}
func Installed() bool {
	if _, e := os.Stat(path()); e == nil {
		return true
	}
	// A bundled SMAppService agent has no plist in ~/Library/LaunchAgents.
	for _, label := range []string{Label, AppLabel} {
		domain := "gui/" + strconv.Itoa(os.Getuid()) + "/" + label
		if exec.Command("/bin/launchctl", "print", domain).Run() == nil {
			return true
		}
	}
	return false
}
func Stop() error {
	for _, label := range []string{Label, AppLabel} {
		domain := "gui/" + strconv.Itoa(os.Getuid()) + "/" + label
		if exec.Command("/bin/launchctl", "print", domain).Run() != nil {
			continue
		}
		if b, e := exec.Command("/bin/launchctl", "bootout", domain).CombinedOutput(); e != nil {
			return fmt.Errorf("停止后台失败: %s", b)
		}
	}
	return nil
}

// Start refreshes the existing agent to the current bundled backend, keeping history.
func Start(cfg, state string) error {
	if !Installed() {
		return Install(cfg, state)
	}
	if e := Stop(); e != nil {
		return e
	}
	binary, e := os.Executable()
	if e != nil {
		return e
	}
	binary, e = filepath.EvalSymlinks(binary)
	if e != nil {
		return e
	}
	cfg, e = filepath.Abs(cfg)
	if e != nil {
		return e
	}
	state, e = filepath.Abs(state)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(state, 0700); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path()), ".sleepguard-agent-*.plist")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if e = f.Chmod(0600); e == nil {
		_, e = f.WriteString(Plist(binary, cfg, state))
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	if e = os.Rename(f.Name(), path()); e != nil {
		return e
	}
	if b, e := exec.Command("/bin/launchctl", "bootstrap", "gui/"+strconv.Itoa(os.Getuid()), path()).CombinedOutput(); e != nil {
		return fmt.Errorf("后台启动失败: %s", b)
	}
	return nil
}
