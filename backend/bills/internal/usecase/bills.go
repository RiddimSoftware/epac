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
	GetBillCommitteeStage(ctx context.Context, id string) (*domain.BillCommitteeStage, error)
	GetBillVersionDiff(ctx context.Context, id, fromVersionID, toVersionID string) (*domain.BillVersionDiff, error)
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

type GetBillCommitteeStage struct {
	repo BillRepository
}

func NewGetBillCommitteeStage(repo BillRepository) *GetBillCommitteeStage {
	return &GetBillCommitteeStage{repo: repo}
}

func (u *GetBillCommitteeStage) Execute(ctx context.Context, id string) (*domain.BillCommitteeStage, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return nil, ErrBillNotFound
	}
	return u.repo.GetBillCommitteeStage(ctx, id)
}

type LoadBillVersionDiffInput struct {
	BillID        string
	FromVersionID string
	ToVersionID   string
}

type LoadBillVersionDiff struct {
	repo BillRepository
}

func NewLoadBillVersionDiff(repo BillRepository) *LoadBillVersionDiff {
	return &LoadBillVersionDiff{repo: repo}
}

func (u *LoadBillVersionDiff) Execute(ctx context.Context, input LoadBillVersionDiffInput) (*domain.BillVersionDiff, error) {
	billID := strings.TrimSpace(input.BillID)
	if billID == "" {
		return nil, ErrBillNotFound
	}
	fromVersionID := strings.TrimSpace(input.FromVersionID)
	if fromVersionID == "" {
		return nil, ErrDiffMissingFrom
	}
	toVersionID := strings.TrimSpace(input.ToVersionID)
	if toVersionID == "" {
		return nil, ErrDiffMissingTo
	}

	if fromVersionID == toVersionID {
		return nil, nil
	}

	diff, err := u.repo.GetBillVersionDiff(ctx, billID, fromVersionID, toVersionID)
	if err != nil || diff == nil {
		return diff, err
	}
	if len(diff.Clauses) == 0 {
		return nil, nil
	}

	// Check if all clauses are unchanged. If they are, return the diff but with
	// an empty clauses slice so the client receives HTTP 200 with an empty clauses array.
	allUnchanged := true
	for _, c := range diff.Clauses {
		if c.ChangeType != "unchanged" {
			allUnchanged = false
			break
		}
	}
	if allUnchanged {
		diff.Clauses = []domain.BillClauseDiff{}
	}

	return diff, nil
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
