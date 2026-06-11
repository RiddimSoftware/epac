package usecase

import (
	"context"
	"errors"

	"epac/push-notification-dispatcher/internal/domain"
)

var ErrInvalidPayload = errors.New("invalid push notification payload")

type DeviceSubscriptionRepository interface {
	ListDeviceSubscriptions(ctx context.Context) ([]domain.DeviceSubscription, error)
}

type PushNotificationClient interface {
	Deliver(ctx context.Context, subscription domain.DeviceSubscription, payload domain.PushNotificationPayload) error
}

type DispatchPushNotification struct {
	subscriptions DeviceSubscriptionRepository
	client        PushNotificationClient
}

func NewDispatchPushNotification(subscriptions DeviceSubscriptionRepository, client PushNotificationClient) *DispatchPushNotification {
	return &DispatchPushNotification{subscriptions: subscriptions, client: client}
}

func (u *DispatchPushNotification) Execute(ctx context.Context, payload domain.PushNotificationPayload) (domain.DispatchResult, error) {
	if !payload.Valid() {
		return domain.DispatchResult{}, ErrInvalidPayload
	}

	subscriptions, err := u.subscriptions.ListDeviceSubscriptions(ctx)
	if err != nil {
		return domain.DispatchResult{}, err
	}

	result := domain.DispatchResult{Subscriptions: len(subscriptions)}
	for _, subscription := range subscriptions {
		if err := u.client.Deliver(ctx, subscription, payload); err != nil {
			result.Failed++
			continue
		}
		result.Delivered++
	}

	return result, nil
}
