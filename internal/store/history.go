package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/bennie-asi/sleepguard/internal/model"
)

// Keep notification rounds together, including rounds with mixed channel results.
// Empty round IDs belong to individual events, as in older history databases.
const historyGroup = `CASE WHEN COALESCE(json_extract(delivery,'$.round_id'),'')<>'' THEN 'round:'||json_extract(delivery,'$.round_id') ELSE 'event:'||id END`
const historyCategory = `CASE
WHEN kind IN ('detected','reset') THEN 'monitor'
WHEN kind IN ('notification_sent','notification_failed') THEN 'notification'
WHEN kind IN ('action_attempt','action_result','manual_quit','manual_quit_result','manual_force','manual_force_result') THEN 'action'
WHEN kind IN ('paused','resumed','blackout_started','blackout_ended') THEN 'control'
ELSE 'other' END`

type HistoryQuery struct {
	Category   string
	Page       int
	PageSize   int
	SnapshotID int64
}

type HistoryPage struct {
	Events     []model.Event `json:"events"`
	Page       int           `json:"page"`
	PageSize   int           `json:"page_size"`
	Total      int           `json:"total"`
	SnapshotID int64         `json:"snapshot_id"`
}

// QueryHistory counts and pages display groups in one read snapshot. Only the
// requested page is decoded and joined with incident labels. A retained maximum
// ID keeps new events from shifting pages while the user browses older records.
func (s *Store) QueryHistory(ctx context.Context, query HistoryQuery) (HistoryPage, error) {
	page := HistoryPage{Events: []model.Event{}, Page: query.Page, PageSize: query.PageSize, SnapshotID: query.SnapshotID}
	if query.Page < 1 || query.PageSize < 1 || query.PageSize > 100 || query.SnapshotID < 0 {
		return page, fmt.Errorf("page 必须大于 0，page-size 必须在 1..100 之间，snapshot-id 不能为负数")
	}
	switch query.Category {
	case "all", "monitor", "notification", "action", "control", "other":
	default:
		return page, fmt.Errorf("未知事件分类：%s", query.Category)
	}
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return page, err
	}
	defer tx.Rollback()
	if page.SnapshotID == 0 {
		if err = tx.QueryRowContext(ctx, `SELECT COALESCE(MAX(id),0) FROM events`).Scan(&page.SnapshotID); err != nil {
			return page, err
		}
	}
	where, args := `id<=?`, []any{page.SnapshotID}
	if query.Category != "all" {
		where += ` AND (` + historyCategory + `)=?`
		args = append(args, query.Category)
	}
	if err = tx.QueryRowContext(ctx, `SELECT COUNT(DISTINCT (`+historyGroup+`)) FROM events WHERE `+where, args...).Scan(&page.Total); err != nil {
		return page, err
	}
	lastPage := max(1, (page.Total+page.PageSize-1)/page.PageSize)
	page.Page = min(page.Page, lastPage)
	args = append(args, page.PageSize, (page.Page-1)*page.PageSize, page.SnapshotID)
	rows, err := tx.QueryContext(ctx, `WITH selected AS (
SELECT (`+historyGroup+`) AS group_key, MAX(id) AS latest_id FROM events WHERE `+where+`
GROUP BY group_key ORDER BY latest_id DESC LIMIT ? OFFSET ?
)
SELECT e.id,e.at,e.incident,e.kind,e.message,e.delivery,COALESCE(json_extract(i.data,'$.label'),'')
FROM events e JOIN selected ON (`+historyGroup+`)=selected.group_key
LEFT JOIN incidents i ON i.key=e.incident
WHERE e.id<=? ORDER BY selected.latest_id DESC,e.id DESC`, args...)
	if err != nil {
		return page, err
	}
	page.Events, err = scanHistory(rows)
	rows.Close()
	if err != nil {
		return page, err
	}
	return page, tx.Commit()
}

func scanHistory(rows *sql.Rows) ([]model.Event, error) {
	out := []model.Event{}
	for rows.Next() {
		var event model.Event
		var at int64
		var delivery string
		if err := rows.Scan(&event.ID, &at, &event.Incident, &event.Kind, &event.Message, &delivery, &event.Label); err != nil {
			return nil, err
		}
		event.At = time.Unix(0, at)
		if delivery != "{}" {
			if err := json.Unmarshal([]byte(delivery), &event.Delivery); err != nil {
				return nil, err
			}
		}
		out = append(out, event)
	}
	return out, rows.Err()
}
