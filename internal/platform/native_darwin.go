//go:build darwin && cgo

package platform

/*
#cgo LDFLAGS: -framework Foundation -framework AppKit -framework IOKit -framework CoreGraphics
#include <stdlib.h>
char *sg_snapshot(void);
char *sg_bundle(const char *path);
int sg_request_quit(int pid);
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"syscall"
	"unsafe"
)

func RequestQuit(pid int32) error {
	switch C.sg_request_quit(C.int(pid)) {
	case 0:
		return nil
	case 1:
		return syscall.Kill(int(pid), syscall.SIGTERM)
	default:
		return fmt.Errorf("应用拒绝退出请求")
	}
}

func nativeRead() (nativeSnapshot, error) {
	p := C.sg_snapshot()
	if p == nil {
		return nativeSnapshot{}, fmt.Errorf("IOKit 返回空数据")
	}
	defer C.free(unsafe.Pointer(p))
	var s nativeSnapshot
	if e := json.Unmarshal([]byte(C.GoString(p)), &s); e != nil {
		return s, e
	}
	if s.Error != "" {
		return s, fmt.Errorf("原生采集失败: %s", s.Error)
	}
	return s, nil
}
func bundleID(path string) string {
	p := C.CString(path)
	defer C.free(unsafe.Pointer(p))
	r := C.sg_bundle(p)
	if r == nil {
		return ""
	}
	defer C.free(unsafe.Pointer(r))
	return C.GoString(r)
}
