package config

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"github.com/pelletier/go-toml/v2"
)

func Revision(path string) (string, error) {
	b, e := os.ReadFile(path)
	if os.IsNotExist(e) {
		return "", nil
	}
	if e != nil {
		return "", e
	}
	return fmt.Sprintf("%x", sha256.Sum256(b)), nil
}

// Save uses a revision check and atomic rename; credentials are never in Config.
func Save(path string, c Config, expected string) error {
	if e := c.Validate(); e != nil {
		return e
	}
	c.Normalize()
	dir := filepath.Dir(path)
	if e := os.MkdirAll(dir, 0700); e != nil {
		return e
	}
	lock, e := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return e
	}
	defer lock.Close()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); e != nil {
		return e
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	revision, e := Revision(path)
	if e != nil {
		return e
	}
	if revision != expected {
		return fmt.Errorf("配置已被其他操作修改，请刷新后重试")
	}
	b, e := toml.Marshal(c)
	if e != nil {
		return e
	}
	f, e := os.CreateTemp(dir, ".sleepguard-*.toml")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	if e = f.Chmod(0600); e == nil {
		_, e = f.Write(b)
	}
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	if prior, e := os.ReadFile(path); e == nil {
		if e = os.WriteFile(path+".previous", prior, 0600); e != nil {
			return e
		}
	}
	return os.Rename(f.Name(), path)
}
