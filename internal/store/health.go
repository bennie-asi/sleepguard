package store

import (
	"database/sql"
	"encoding/json"
	"github.com/bennie-asi/sleepguard/internal/model"
)

func (s *Store) SaveWatcherHealth(h model.WatcherHealth) error {
	b, err := json.Marshal(h)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`INSERT INTO watcher_health(id,data) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data`, string(b))
	return err
}

func (s *Store) WatcherHealth() (model.WatcherHealth, error) {
	var h model.WatcherHealth
	var b string
	err := s.db.QueryRow(`SELECT data FROM watcher_health WHERE id=1`).Scan(&b)
	if err == sql.ErrNoRows {
		return h, nil
	}
	if err != nil {
		return h, err
	}
	err = json.Unmarshal([]byte(b), &h)
	return h, err
}
