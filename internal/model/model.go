package model

import (
	"crypto/sha256"
	"fmt"
	"time"
)

type Process struct {
	PID       int32  `json:"pid"`
	StartedMS int64  `json:"started_ms"`
	UID       int32  `json:"uid"`
	Name      string `json:"name"`
	Path      string `json:"path"`
	BundleID  string `json:"bundle_id,omitempty"`
	Protected bool   `json:"protected"`
}

// Identity includes boot and start time: a recycled PID is never the old target.
func (p Process) Identity(boot string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(fmt.Sprintf("%s|%d|%d|%s", boot, p.PID, p.StartedMS, p.Path))))[:24]
}

type Assertion struct {
	ID          string    `json:"id"`
	Type        string    `json:"type"`
	Name        string    `json:"name"`
	Holder      Process   `json:"holder"`
	Target      *Process  `json:"target,omitempty"`
	Attribution string    `json:"attribution"`
	Resources   []string  `json:"resources,omitempty"`
	Created     time.Time `json:"created,omitempty"`
}

func (a Assertion) BlocksIdle() bool {
	switch a.Type {
	case "PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "PreventSystemSleep", "NoIdleSleepAssertion", "NoDisplaySleepAssertion":
		return true
	}
	return false
}

type Snapshot struct {
	At               time.Time   `json:"at"`
	BootID           string      `json:"boot_id"`
	WakeAt           time.Time   `json:"wake_at"`
	IdleSeconds      float64     `json:"idle_seconds"`
	DisplayAsleep    bool        `json:"display_asleep"`
	PowerSource      string      `json:"power_source"`
	SleepMinutes     int         `json:"sleep_minutes"`
	DisplayMinutes   int         `json:"display_minutes"`
	SleepDisabled    bool        `json:"sleep_disabled"`
	Assertions       []Assertion `json:"assertions"`
	Diagnostics      []string    `json:"diagnostics,omitempty"`
	KernelAssertions string      `json:"kernel_assertions,omitempty"`
}

type Candidate struct {
	Key        string      `json:"key"`
	Label      string      `json:"label"`
	Target     *Process    `json:"target,omitempty"`
	Assertions []Assertion `json:"assertions"`
	Policy     string      `json:"policy"`
}

type Assessment struct {
	Eligible         bool        `json:"eligible"`
	Reason           string      `json:"reason"`
	ThresholdSeconds float64     `json:"threshold_seconds"`
	Candidates       []Candidate `json:"candidates"`
}

type Incident struct {
	QualifiedAt     time.Time `json:"qualified_at"`
	RuleVersion     string    `json:"rule_version"`
	ResetVersion    string    `json:"reset_version"`
	Key             string    `json:"key"`
	BootID          string    `json:"boot_id"`
	WakeAt          time.Time `json:"wake_at"`
	Label           string    `json:"label"`
	Target          *Process  `json:"target,omitempty"`
	FirstSeen       time.Time `json:"first_seen"`
	LastSeen        time.Time `json:"last_seen"`
	Samples         int       `json:"samples"`
	Notifications   int       `json:"notifications"`
	LastAttempt     time.Time `json:"last_attempt"`
	LastSent        time.Time `json:"last_sent"`
	SnoozedUntil    time.Time `json:"snoozed_until"`
	ActionAttempted bool      `json:"action_attempted"`
	ActionRetryAt   time.Time `json:"action_retry_at"`
	ActionResult    string    `json:"action_result,omitempty"`
	Active          bool      `json:"active"`
}

type Event struct {
	ID       int64     `json:"id"`
	At       time.Time `json:"at"`
	Incident string    `json:"incident"`
	Label    string    `json:"label,omitempty"`
	Kind     string    `json:"kind"`
	Message  string    `json:"message"`
	Delivery *Delivery `json:"delivery,omitempty"`
}

type Delivery struct {
	ChannelID   string `json:"channel_id"`
	ChannelName string `json:"channel_name"`
	Provider    string `json:"provider"`
	RoundID     string `json:"round_id"`
	Success     bool   `json:"success"`
	Message     string `json:"message"`
}
