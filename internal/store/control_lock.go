package store

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// Serialize acknowledged UI controls with the final authorization and signal.
// Each caller opens its own descriptor, including callers in the same process.
// Collection and the SIGKILL waiting period must remain outside this lock.
func (s *Store) WithControlLock(ctx context.Context, action func() error) error {
	f, err := os.OpenFile(filepath.Join(s.dir, "control.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	for {
		if err = ctx.Err(); err != nil {
			return err
		}
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EAGAIN) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(10 * time.Millisecond):
		}
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	if err = ctx.Err(); err != nil {
		return err
	}
	return action()
}
