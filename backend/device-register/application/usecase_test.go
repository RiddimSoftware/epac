package application_test

import (
	"context"
	"testing"

	"epac/device-register/application"
)

type mockRepo struct {
	upsertFunc func(ctx context.Context, sub application.DeviceSubscription) error
}

func (m *mockRepo) UpsertSubscription(ctx context.Context, sub application.DeviceSubscription) error {
	if m.upsertFunc != nil {
		return m.upsertFunc(ctx, sub)
	}
	return nil
}

func TestRegisterUseCase_Execute(t *testing.T) {
	t.Run("token is required", func(t *testing.T) {
		uc := application.NewRegisterUseCase(&mockRepo{})
		err := uc.Execute(context.Background(), application.RegisterRequest{Token: "  "})
		if err != application.ErrTokenRequired {
			t.Errorf("expected ErrTokenRequired, got %v", err)
		}
	})

	t.Run("successful registration defaults", func(t *testing.T) {
		var capturedSub application.DeviceSubscription
		repo := &mockRepo{
			upsertFunc: func(ctx context.Context, sub application.DeviceSubscription) error {
				capturedSub = sub
				return nil
			},
		}
		uc := application.NewRegisterUseCase(repo)

		err := uc.Execute(context.Background(), application.RegisterRequest{
			Token: "token123",
		})

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if capturedSub.Token != "token123" {
			t.Errorf("expected token123, got %v", capturedSub.Token)
		}
		if capturedSub.TopicIds == nil || len(capturedSub.TopicIds) != 0 {
			t.Errorf("expected empty TopicIds, got %v", capturedSub.TopicIds)
		}
		if capturedSub.BillIds == nil || len(capturedSub.BillIds) != 0 {
			t.Errorf("expected empty BillIds, got %v", capturedSub.BillIds)
		}
		if capturedSub.Granularity == nil || len(capturedSub.Granularity) != 0 {
			t.Errorf("expected empty Granularity, got %v", capturedSub.Granularity)
		}
		if capturedSub.MyMPMemberId != nil {
			t.Errorf("expected nil MyMPMemberId, got %v", capturedSub.MyMPMemberId)
		}
	})

	t.Run("successful registration all fields", func(t *testing.T) {
		var capturedSub application.DeviceSubscription
		repo := &mockRepo{
			upsertFunc: func(ctx context.Context, sub application.DeviceSubscription) error {
				capturedSub = sub
				return nil
			},
		}
		uc := application.NewRegisterUseCase(repo)

		err := uc.Execute(context.Background(), application.RegisterRequest{
			Token:        "token123",
			TopicIds:     []string{"t1"},
			BillIds:      []string{"b1"},
			Granularity:  map[string]string{"t1": "everyDebate"},
			MyMPMemberId: "123",
		})

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if capturedSub.MyMPMemberId == nil || *capturedSub.MyMPMemberId != "123" {
			t.Errorf("expected MyMPMemberId 123, got %v", capturedSub.MyMPMemberId)
		}
	})
}
