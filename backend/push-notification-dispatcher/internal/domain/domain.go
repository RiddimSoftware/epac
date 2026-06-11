package domain

import (
	"bytes"
	"encoding/json"
	"errors"
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

	return PushNotificationPayload{
		DivisionID:  fields.DivisionID,
		Parliament:  fields.Parliament,
		Session:     fields.Session,
		Result:      fields.Result,
		Status:      fields.Status,
		rawDocument: append(json.RawMessage(nil), compacted.Bytes()...),
	}, nil
}

func (p PushNotificationPayload) Valid() bool {
	return len(p.rawDocument) > 0
}

func (p PushNotificationPayload) JSON() ([]byte, error) {
	if !p.Valid() {
		return nil, ErrInvalidPushNotificationPayload
	}
	return append([]byte(nil), p.rawDocument...), nil
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
