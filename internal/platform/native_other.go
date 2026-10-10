//go:build !darwin || !cgo

package platform

import (
	"fmt"
	"syscall"
)

func RequestQuit(pid int32) error { return syscall.Kill(int(pid), syscall.SIGTERM) }

func nativeRead() (nativeSnapshot, error) {
	return nativeSnapshot{}, fmt.Errorf("原生采集需要 macOS 和 CGO_ENABLED=1 构建")
}
func bundleID(string) string { return "" }
