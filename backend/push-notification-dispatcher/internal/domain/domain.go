package domain

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

var ErrInvalidPushNotificationPayload = errors.New("invalid push notification payload")

type PushNotificationPayload struct {
	DivisionID  int    `json:"division_id,omitempty"`
	Parliament  int    `json:"parliament,omitempty"`
	Session     int    `json:"session,omitempty"`
	Result      string `json:"result,omitempty"`
	Status      string `json:"status,omitempty"`
	rawDocument json.RawMessage
}

func ParsePushNotificationPayload(raw []byte) (PushNotificationPayload, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return PushNotificationPayload{}, ErrInvalidPushNotificationPayload
	}

	var fields struct {
		DivisionID int    `json:"division_id"`
		Parliament int    `json:"parliament"`
		Session    int    `json:"session"`
		Result     string `json:"result"`
		Status     string `json:"status"`
	}
	if err := json.Unmarshal(trimmed, &fields); err != nil {
		return PushNotificationPayload{}, ErrInvalidPushNotificationPayload
	}

	var compacted bytes.Buffer
	if err := json.Compact(&compacted, trimmed); err != nil {
		return PushNotificationPayload{}, ErrInvalidPushNotificationPayload
	}

	payload := PushNotificationPayload{
		DivisionID:  fields.DivisionID,
		Parliament:  fields.Parliament,
		Session:     fields.Session,
		Result:      strings.TrimSpace(fields.Result),
		Status:      strings.TrimSpace(fields.Status),
		rawDocument: append(json.RawMessage(nil), compacted.Bytes()...),
	}
	if !payload.Valid() {
		return PushNotificationPayload{}, ErrInvalidPushNotificationPayload
	}

	return payload, nil
}

func (p PushNotificationPayload) Valid() bool {
	return len(p.rawDocument) > 0 && p.hasRequiredFields()
}

func (p PushNotificationPayload) JSON() ([]byte, error) {
	if !p.Valid() {
		return nil, ErrInvalidPushNotificationPayload
	}
	return append([]byte(nil), p.rawDocument...), nil
}

func (p PushNotificationPayload) hasRequiredFields() bool {
	return p.DivisionID > 0 &&
		p.Parliament > 0 &&
		p.Session > 0 &&
		strings.TrimSpace(p.Result) != "" &&
		strings.TrimSpace(p.Status) != ""
}

type LiveVoteNotification struct {
	Title      string
	Body       string
	DivisionID int
	Parliament int
	Session    int
	Result     string
	Status     string
}

func NewLiveVoteNotification(payload PushNotificationPayload) (LiveVoteNotification, error) {
	if !payload.Valid() {
		return LiveVoteNotification{}, ErrInvalidPushNotificationPayload
	}

	notification := LiveVoteNotification{
		Title:      "Vote status updated",
		Body:       fmt.Sprintf("Division %d status: %s.", payload.DivisionID, payload.Status),
		DivisionID: payload.DivisionID,
		Parliament: payload.Parliament,
		Session:    payload.Session,
		Result:     payload.Result,
		Status:     payload.Status,
	}
	if strings.EqualFold(payload.Status, "concluded") {
		notification.Title = "Vote result posted"
		notification.Body = fmt.Sprintf("Division %d result: %s.", payload.DivisionID, payload.Result)
	}

	return notification, nil
}

func (n LiveVoteNotification) Valid() bool {
	return strings.TrimSpace(n.Title) != "" &&
		strings.TrimSpace(n.Body) != "" &&
		n.DivisionID > 0 &&
		n.Parliament > 0 &&
		n.Session > 0 &&
		strings.TrimSpace(n.Result) != "" &&
		strings.TrimSpace(n.Status) != ""
}

type DeviceToken string

func NewDeviceToken(value string) DeviceToken {
	return DeviceToken(strings.TrimSpace(value))
}

func (t DeviceToken) String() string {
	return string(t)
}

type DeviceSubscription struct {
	Token        DeviceToken
	MyMPMemberID string
	TopicIDs     []string
	BillIDs      []string
}

func NewDeviceSubscription(token, myMPMemberID string, topicIDs, billIDs []string) DeviceSubscription {
	return DeviceSubscription{
		Token:        NewDeviceToken(token),
		MyMPMemberID: strings.TrimSpace(myMPMemberID),
		TopicIDs:     copyStrings(topicIDs),
		BillIDs:      copyStrings(billIDs),
	}
}

type DispatchResult struct {
	Subscriptions int
	Delivered     int
	Failed        int
}

func copyStrings(values []string) []string {
	if len(values) == 0 {
		return nil
	}
	out := make([]string, len(values))
	copy(out, values)
	return out
}
