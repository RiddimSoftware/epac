package usecase

import (
	"context"
	"regexp"
	"strconv"
	"strings"

	"epac/bills/internal/domain"
)

type BillRepository interface {
	ListBills(ctx context.Context) ([]domain.Bill, error)
	GetBillDepth(ctx context.Context, id string) (domain.Bill, error)
}

type ListBillsInput struct {
	Status     string
	Parliament string
}

type ListBills struct {
	repo BillRepository
}

func NewListBills(repo BillRepository) *ListBills {
	return &ListBills{repo: repo}
}

func (u *ListBills) Execute(ctx context.Context, input ListBillsInput) ([]domain.Bill, error) {
	bills, err := u.repo.ListBills(ctx)
	if err != nil {
		return nil, err
	}
	return filterBills(bills, input.Status, input.Parliament), nil
}

type GetBillDepth struct {
	repo BillRepository
}

func NewGetBillDepth(repo BillRepository) *GetBillDepth {
	return &GetBillDepth{repo: repo}
}

func (u *GetBillDepth) Execute(ctx context.Context, id string) (domain.Bill, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return domain.Bill{}, ErrBillNotFound
	}
	return u.repo.GetBillDepth(ctx, id)
}

var normalizeRe = regexp.MustCompile(`[^a-z0-9]+`)

func filterBills(bills []domain.Bill, statusFilter, parliamentFilter string) []domain.Bill {
	status := normalizeFilter(statusFilter)
	parliament := 0
	if parsed, err := strconv.Atoi(strings.TrimSpace(parliamentFilter)); err == nil && parsed > 0 {
		parliament = parsed
	}
	if status == "" && parliament == 0 {
		return bills
	}
	filtered := make([]domain.Bill, 0, len(bills))
	for _, bill := range bills {
		if status != "" && normalizeFilter(bill.Status) != status && normalizeFilter(bill.CurrentStage) != status {
			continue
		}
		if parliament != 0 && (bill.Parliament == nil || *bill.Parliament != parliament) {
			continue
		}
		filtered = append(filtered, bill)
	}
	return filtered
}

func normalizeFilter(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "inprogress", "in progress")
	value = strings.ReplaceAll(value, "royalassent", "royal assent")
	return normalizeRe.ReplaceAllString(value, "")
}
