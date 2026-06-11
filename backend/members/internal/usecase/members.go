package usecase

import (
	"context"
	"strings"

	"epac/members/internal/domain"
)

type MemberRepository interface {
	ListMembers(ctx context.Context) ([]domain.Member, error)
	GetMemberProfile(ctx context.Context, id string) (domain.Member, error)
}

type ListMembersInput struct {
	Province string
	Party    string
}

type ListMembers struct {
	repo MemberRepository
}

func NewListMembers(repo MemberRepository) *ListMembers {
	return &ListMembers{repo: repo}
}

func (u *ListMembers) Execute(ctx context.Context, input ListMembersInput) ([]domain.Member, error) {
	members, err := u.repo.ListMembers(ctx)
	if err != nil {
		return nil, err
	}
	return filterMembers(members, strings.TrimSpace(input.Province), strings.TrimSpace(input.Party)), nil
}

type GetMemberProfile struct {
	repo MemberRepository
}

func NewGetMemberProfile(repo MemberRepository) *GetMemberProfile {
	return &GetMemberProfile{repo: repo}
}

func (u *GetMemberProfile) Execute(ctx context.Context, id string) (domain.Member, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return domain.Member{}, ErrMemberNotFound
	}
	return u.repo.GetMemberProfile(ctx, id)
}

func filterMembers(members []domain.Member, province, party string) []domain.Member {
	if province == "" && party == "" {
		return members
	}
	filtered := make([]domain.Member, 0, len(members))
	for _, member := range members {
		if province != "" && !provinceMatches(member.Province, province) {
			continue
		}
		if party != "" && !strings.EqualFold(member.Party, party) {
			continue
		}
		filtered = append(filtered, member)
	}
	return filtered
}

func provinceMatches(memberProvince, filter string) bool {
	if strings.EqualFold(memberProvince, filter) {
		return true
	}
	return strings.EqualFold(memberProvince, provinceCode(filter))
}

func provinceCode(name string) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "alberta":
		return "AB"
	case "british columbia":
		return "BC"
	case "manitoba":
		return "MB"
	case "new brunswick":
		return "NB"
	case "newfoundland and labrador":
		return "NL"
	case "northwest territories":
		return "NT"
	case "nova scotia":
		return "NS"
	case "nunavut":
		return "NU"
	case "ontario":
		return "ON"
	case "prince edward island":
		return "PE"
	case "quebec":
		return "QC"
	case "saskatchewan":
		return "SK"
	case "yukon":
		return "YT"
	default:
		return strings.TrimSpace(name)
	}
}
