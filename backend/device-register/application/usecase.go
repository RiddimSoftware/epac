package application

import (
	"context"
	"errors"
	"strings"
)

var ErrTokenRequired = errors.New("token is required")

type DeviceSubscription struct {
	Token        string
	TopicIds     []string
	BillIds      []string
	Granularity  map[string]string
	MyMPMemberId *string
}

type DeviceRepository interface {
	UpsertSubscription(ctx context.Context, sub DeviceSubscription) error
}

type RegisterUseCase struct {
	repo DeviceRepository
}

func NewRegisterUseCase(repo DeviceRepository) *RegisterUseCase {
	return &RegisterUseCase{repo: repo}
}

type RegisterRequest struct {
	Token        string            `json:"token"`
	TopicIds     []string          `json:"topic_ids"`
	BillIds      []string          `json:"bill_ids"`
	Granularity  map[string]string `json:"granularity"`
	MyMPMemberId string            `json:"my_mp_member_id"`
}

func (u *RegisterUseCase) Execute(ctx context.Context, req RegisterRequest) error {
	req.Token = strings.TrimSpace(req.Token)
	if req.Token == "" {
		return ErrTokenRequired
	}
	if req.TopicIds == nil {
		req.TopicIds = []string{}
	}
	if req.BillIds == nil {
		req.BillIds = []string{}
	}
	if req.Granularity == nil {
		req.Granularity = map[string]string{}
	}

	var myMP *string
	if req.MyMPMemberId != "" {
		myMP = &req.MyMPMemberId
	}

	sub := DeviceSubscription{
		Token:        req.Token,
		TopicIds:     req.TopicIds,
		BillIds:      req.BillIds,
		Granularity:  req.Granularity,
		MyMPMemberId: myMP,
	}

	return u.repo.UpsertSubscription(ctx, sub)
}
