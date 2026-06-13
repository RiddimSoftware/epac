package apns

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"epac/push-notification-dispatcher/internal/domain"
)

const DefaultBaseURL = "https://api.push.apple.com"

type Client struct {
	baseURL    string
	httpClient *http.Client
}

func NewClient(baseURL string) *Client {
	return NewClientWithHTTPClient(baseURL, nil)
}

func NewClientWithHTTPClient(baseURL string, httpClient *http.Client) *Client {
	baseURL = strings.TrimSpace(baseURL)
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), httpClient: httpClient}
}

func (c *Client) Deliver(ctx context.Context, subscription domain.DeviceSubscription, notification domain.LiveVoteNotification) error {
	body, err := encodePayload(notification)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint(subscription.Token), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("apns returned status %d", resp.StatusCode)
	}
	return nil
}

type apnsPayload struct {
	Aps        apnsAps `json:"aps"`
	DivisionID int     `json:"division_id"`
	Parliament int     `json:"parliament"`
	Session    int     `json:"session"`
	Result     string  `json:"result"`
	Status     string  `json:"status"`
}

type apnsAps struct {
	Alert apnsAlert `json:"alert"`
}

type apnsAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

func encodePayload(notification domain.LiveVoteNotification) ([]byte, error) {
	if !notification.Valid() {
		return nil, domain.ErrInvalidPushNotificationPayload
	}

	return json.Marshal(apnsPayload{
		Aps: apnsAps{Alert: apnsAlert{
			Title: notification.Title,
			Body:  notification.Body,
		}},
		DivisionID: notification.DivisionID,
		Parliament: notification.Parliament,
		Session:    notification.Session,
		Result:     notification.Result,
		Status:     notification.Status,
	})
}

func (c *Client) endpoint(token domain.DeviceToken) string {
	if !strings.Contains(c.baseURL, "apple") {
		return c.baseURL
	}
	return fmt.Sprintf("%s/3/device/%s", c.baseURL, url.PathEscape(token.String()))
}
