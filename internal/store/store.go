package store

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
	_ "modernc.org/sqlite"
)

type Store struct{ db *sql.DB }

func Open(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	// The menu app and watcher may open an old database at the same time.
	lock, e := os.OpenFile(filepath.Join(dir, "schema.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	defer lock.Close()
	if e = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); e != nil {
		return nil, e
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	path := filepath.Join(dir, "state.db")
	f, e := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	f.Close()
	db, e := sql.Open("sqlite", path)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	s := &Store{db}
	_, e = db.Exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS incidents (key TEXT PRIMARY KEY, data TEXT NOT NULL, active INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, incident TEXT NOT NULL, kind TEXT NOT NULL, message TEXT NOT NULL, delivery TEXT NOT NULL DEFAULT '{}');
CREATE TABLE IF NOT EXISTS snoozes (scope TEXT PRIMARY KEY, until_ns INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS temporary_holds (scope TEXT PRIMARY KEY, until_ns INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS control_resets (scope TEXT PRIMARY KEY, version INTEGER NOT NULL);`)
	if e != nil {
		db.Close()
		return nil, e
	}
	var exists int
	if e = db.QueryRow("SELECT COUNT(*) FROM pragma_table_info('events') WHERE name='delivery'").Scan(&exists); e != nil {
		db.Close()
		return nil, e
	}
	if exists == 0 {
		if _, e = db.Exec("ALTER TABLE events ADD COLUMN delivery TEXT NOT NULL DEFAULT '{}'"); e != nil {
			db.Close()
			return nil, e
		}
	}
	return s, nil
}
func (s *Store) Close() error { return s.db.Close() }
func (s *Store) Save(i model.Incident) error {
	b, e := json.Marshal(i)
	if e != nil {
		return e
	}
	_, e = s.db.Exec(`INSERT INTO incidents(key,data,active,updated) VALUES(?,?,?,?) ON CONFLICT(key) DO UPDATE SET data=excluded.data,active=excluded.active,updated=excluded.updated`, i.Key, string(b), i.Active, i.LastSeen.UnixNano())
	return e
}
func (s *Store) Get(key string) (*model.Incident, error) {
	var b string
	var active bool
	e := s.db.QueryRow(`SELECT data,active FROM incidents WHERE key=?`, key).Scan(&b, &active)
	if e == sql.ErrNoRows {
		return nil, nil
	}
	if e != nil {
		return nil, e
	}
	var i model.Incident
	e = json.Unmarshal([]byte(b), &i)
	i.Active = active
	return &i, e
}
func (s *Store) Active() ([]model.Incident, error) {
	r, e := s.db.Query(`SELECT data FROM incidents WHERE active=1 ORDER BY key`)
	if e != nil {
		return nil, e
	}
	defer r.Close()
	out := []model.Incident{}
	for r.Next() {
		var b string
		if e = r.Scan(&b); e != nil {
			return nil, e
		}
		var i model.Incident
		if e = json.Unmarshal([]byte(b), &i); e != nil {
			return nil, e
		}
		out = append(out, i)
	}
	return out, r.Err()
}
func (s *Store) Event(at time.Time, key, kind, msg string) error {
	_, e := s.db.Exec(`INSERT INTO events(at,incident,kind,message) VALUES(?,?,?,?)`, at.UnixNano(), key, kind, msg)
	return e
}
func (s *Store) Delivery(at time.Time, key string, result model.Delivery) error {
	data, e := json.Marshal(result)
	if e != nil {
		return e
	}
	kind := "notification_failed"
	if result.Success {
		kind = "notification_sent"
	}
	_, e = s.db.Exec(`INSERT INTO events(at,incident,kind,message,delivery) VALUES(?,?,?,?,?)`, at.UnixNano(), key, kind, result.ChannelName+"："+result.Message, string(data))
	return e
}
func (s *Store) History(limit int) ([]model.Event, error) {
	if limit < 1 || limit > 10000 {
		return nil, fmt.Errorf("limit 必须在 1..10000 之间")
	}
	r, e := s.db.Query(`SELECT e.id,e.at,e.incident,e.kind,e.message,e.delivery,COALESCE(json_extract(i.data,'$.label'),'') FROM events e LEFT JOIN incidents i ON i.key=e.incident ORDER BY e.id DESC LIMIT ?`, limit)
	if e != nil {
		return nil, e
	}
	defer r.Close()
	out := []model.Event{}
	for r.Next() {
		var v model.Event
		var at int64
		var data string
		if e = r.Scan(&v.ID, &at, &v.Incident, &v.Kind, &v.Message, &data, &v.Label); e != nil {
			return nil, e
		}
		v.At = time.Unix(0, at)
		if data != "{}" {
			if e = json.Unmarshal([]byte(data), &v.Delivery); e != nil {
				return nil, e
			}
		}
		out = append(out, v)
	}
	return out, r.Err()
}
func (s *Store) Snooze(scope string, until time.Time) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if _, e = tx.Exec(`INSERT INTO snoozes(scope,until_ns) VALUES(?,?) ON CONFLICT(scope) DO UPDATE SET until_ns=excluded.until_ns`, scope, until.UnixNano()); e != nil {
		return e
	}
	if _, e = tx.Exec(`INSERT INTO events(at,incident,kind,message) VALUES(?,?,?,?)`, time.Now().UnixNano(), scope, "paused", "已暂停至 "+until.Format(time.RFC3339)); e != nil {
		return e
	}
	return tx.Commit()
}
func (s *Store) Resume(scope string) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if scope == "*" {
		_, e = tx.Exec("DELETE FROM snoozes")
		if e == nil {
			_, e = tx.Exec("UPDATE incidents SET active=0 WHERE active=1")
		}
	} else {
		_, e = tx.Exec("DELETE FROM snoozes WHERE scope=?", scope)
		if e == nil {
			_, e = tx.Exec("UPDATE incidents SET active=0 WHERE key=?", scope)
		}
	}
	if e != nil {
		return e
	}
	if _, e = tx.Exec(`INSERT INTO control_resets(scope,version) VALUES(?,1) ON CONFLICT(scope) DO UPDATE SET version=version+1`, scope); e != nil {
		return e
	}
	if _, e = tx.Exec(`INSERT INTO events(at,incident,kind,message) VALUES(?,?,?,?)`, time.Now().UnixNano(), scope, "resumed", "已恢复通知与处理；重新累计异常"); e != nil {
		return e
	}
	return tx.Commit()
}

// A resume invalidates any sample or delivery that was already in flight.
func (s *Store) ResetVersion(scope string) (string, error) {
	rows, e := s.db.Query(`SELECT scope,version FROM control_resets WHERE scope IN (?, '*') ORDER BY scope`, scope)
	if e != nil {
		return "", e
	}
	defer rows.Close()
	var version strings.Builder
	for rows.Next() {
		var key string
		var n int64
		if e = rows.Scan(&key, &n); e != nil {
			return "", e
		}
		fmt.Fprintf(&version, "%s:%d;", key, n)
	}
	return version.String(), rows.Err()
}
func (s *Store) SnoozedUntil(scope string) (time.Time, error) {
	var n sql.NullInt64
	e := s.db.QueryRow(`SELECT MAX(until_ns) FROM (SELECT until_ns FROM snoozes WHERE scope IN (?, '*') UNION ALL SELECT until_ns FROM temporary_holds WHERE scope='blackout')`, scope).Scan(&n)
	if e != nil {
		return time.Time{}, e
	}
	if !n.Valid {
		return time.Time{}, nil
	}
	return time.Unix(0, n.Int64), nil
}

// A renewable lease stops actions during blackout without touching user snoozes.
// If the app crashes, the hold expires rather than disabling monitoring forever.
func (s *Store) Hold(until time.Time, begin bool) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if _, e = tx.Exec(`INSERT INTO temporary_holds(scope,until_ns) VALUES('blackout',?) ON CONFLICT(scope) DO UPDATE SET until_ns=excluded.until_ns`, until.UnixNano()); e != nil {
		return e
	}
	if begin {
		if _, e = tx.Exec(`INSERT INTO control_resets(scope,version) VALUES('*',1) ON CONFLICT(scope) DO UPDATE SET version=version+1`); e != nil {
			return e
		}
		if _, e = tx.Exec(`INSERT INTO events(at,incident,kind,message) VALUES(?, '*', 'blackout_started', '已开启所有显示器黑屏')`, time.Now().UnixNano()); e != nil {
			return e
		}
	}
	return tx.Commit()
}
func (s *Store) ReleaseHold() error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	for _, query := range []string{`DELETE FROM temporary_holds WHERE scope='blackout'`, `UPDATE incidents SET active=0 WHERE active=1`, `INSERT INTO control_resets(scope,version) VALUES('*',1) ON CONFLICT(scope) DO UPDATE SET version=version+1`} {
		if _, e = tx.Exec(query); e != nil {
			return e
		}
	}
	if _, e = tx.Exec(`INSERT INTO events(at,incident,kind,message) VALUES(?, '*', 'blackout_ended', '已恢复显示；保留原暂停设置，重新累计异常')`, time.Now().UnixNano()); e != nil {
		return e
	}
	return tx.Commit()
}
func (s *Store) Prune(now time.Time, days int) error {
	tx, e := s.db.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	cutoff := now.Add(-time.Duration(days) * 24 * time.Hour).UnixNano()
	for _, q := range []string{`DELETE FROM events WHERE at<?`, `DELETE FROM incidents WHERE active=0 AND updated<?`} {
		if _, e = tx.Exec(q, cutoff); e != nil {
			return e
		}
	}
	if _, e = tx.Exec(`DELETE FROM snoozes WHERE until_ns<?`, now.UnixNano()); e != nil {
		return e
	}
	return tx.Commit()
}
