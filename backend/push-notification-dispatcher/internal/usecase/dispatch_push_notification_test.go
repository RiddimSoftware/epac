package usecase

import (
	"context"
	"errors"
	"testing"

	"epac/push-notification-dispatcher/internal/domain"
)

type fakeSubscriptionRepository struct {
	called        bool
	subscriptions []domain.DeviceSubscription
	err           error
}

func (r *fakeSubscriptionRepository) ListDeviceSubscriptions(context.Context) ([]domain.DeviceSubscription, error) {
	r.called = true
	return r.subscriptions, r.err
}

type fakePushClient struct {
	delivered []domain.DeviceSubscription
	failToken string
}

func (c *fakePushClient) Deliver(_ context.Context, subscription domain.DeviceSubscription, _ domain.PushNotificationPayload) error {
	c.delivered = append(c.delivered, subscription)
	if subscription.Token.String() == c.failToken {
		return errors.New("apns rejected request")
	}
	return nil
}

func TestDispatchRejectsInvalidPayloadBeforeSubscriptionLookup(t *testing.T) {
	repo := &fakeSubscriptionRepository{}
	client := &fakePushClient{}
	dispatcher := NewDispatchPushNotification(repo, client)

	_, err := dispatcher.Execute(context.Background(), domain.PushNotificationPayload{})
	if !errors.Is(err, ErrInvalidPayload) {
		t.Fatalf("Execute error = %v, want %v", err, ErrInvalidPayload)
	}
	if repo.called {
		t.Fatal("repo should not be called for invalid payload")
	}
	if len(client.delivered) != 0 {
		t.Fatalf("client delivered %d notifications, want 0", len(client.delivered))
	}
}

func TestDispatchWithZeroSubscriptionsDoesNotCallClient(t *testing.T) {
	client := &fakePushClient{}
	dispatcher := NewDispatchPushNotification(&fakeSubscriptionRepository{}, client)

	result, err := dispatcher.Execute(context.Background(), validPayload(t))
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result != (domain.DispatchResult{}) {
		t.Fatalf("result = %#v, want zero result", result)
	}
	if len(client.delivered) != 0 {
		t.Fatalf("client delivered %d notifications, want 0", len(client.delivered))
	}
}

func TestDispatchDeliversToMultipleSubscriptions(t *testing.T) {
	client := &fakePushClient{}
	dispatcher := NewDispatchPushNotification(&fakeSubscriptionRepository{
		subscriptions: []domain.DeviceSubscription{
			domain.NewDeviceSubscription("token-a", "member-1", []string{"housing"}, nil),
			domain.NewDeviceSubscription("token-b", "", nil, []string{"C-1"}),
		},
	}, client)

	result, err := dispatcher.Execute(context.Background(), validPayload(t))
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result != (domain.DispatchResult{Subscriptions: 2, Delivered: 2}) {
		t.Fatalf("result = %#v, want 2 subscriptions delivered", result)
	}
	if len(client.delivered) != 2 {
		t.Fatalf("client delivered %d notifications, want 2", len(client.delivered))
	}
}

func TestDispatchCountsDeliveryFailuresAndContinues(t *testing.T) {
	client := &fakePushClient{failToken: "token-b"}
	dispatcher := NewDispatchPushNotification(&fakeSubscriptionRepository{
		subscriptions: []domain.DeviceSubscription{
			domain.NewDeviceSubscription("token-a", "", nil, nil),
			domain.NewDeviceSubscription("token-b", "", nil, nil),
			domain.NewDeviceSubscription("token-c", "", nil, nil),
		},
	}, client)

	result, err := dispatcher.Execute(context.Background(), validPayload(t))
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result != (domain.DispatchResult{Subscriptions: 3, Delivered: 2, Failed: 1}) {
		t.Fatalf("result = %#v, want 2 delivered and 1 failed", result)
	}
	if len(client.delivered) != 3 {
		t.Fatalf("client attempted %d notifications, want 3", len(client.delivered))
	}
}

func TestDispatchReturnsSubscriptionLookupError(t *testing.T) {
	want := errors.New("query failed")
	dispatcher := NewDispatchPushNotification(&fakeSubscriptionRepository{err: want}, &fakePushClient{})

	if _, err := dispatcher.Execute(context.Background(), validPayload(t)); !errors.Is(err, want) {
		t.Fatalf("Execute error = %v, want %v", err, want)
	}
}

func validPayload(t *testing.T) domain.PushNotificationPayload {
	t.Helper()
	payload, err := domain.ParsePushNotificationPayload([]byte(`{
		"division_id": 42,
		"parliament": 45,
		"session": 1,
		"result": "carried",
		"status": "concluded"
	}`))
	if err != nil {
		t.Fatalf("ParsePushNotificationPayload: %v", err)
	}
	return payload
}
