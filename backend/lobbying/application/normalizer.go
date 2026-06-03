package application

import (
	"context"
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

type OrganizationAliasLookup interface {
	FindOrganizationIDsByNormalizedName(ctx context.Context, normalizedName string) ([]string, error)
	LogPendingOrganizationAlias(ctx context.Context, pending PendingOrganizationAlias) error
}

type PendingOrganizationAlias struct {
	NormalizedName           string
	ObservedName             string
	SourceTable              string
	SourceID                 string
	CandidateOrganizationIDs []string
}

type OrganizationNameCandidate struct {
	OCLOrganizationID string
	Name              string
	SourceTable       string
	SourceID          string
}

type OrganizationNameResolution struct {
	OrganizationID string
	NormalizedName string
	Ambiguous      bool
}

type NameAliasNormalizer struct {
	aliases OrganizationAliasLookup
}

func NewNameAliasNormalizer(aliases OrganizationAliasLookup) NameAliasNormalizer {
	return NameAliasNormalizer{aliases: aliases}
}

func (n NameAliasNormalizer) Resolve(ctx context.Context, candidate OrganizationNameCandidate) (OrganizationNameResolution, error) {
	normalized := NormalizeOrganizationName(candidate.Name)
	if strings.TrimSpace(candidate.OCLOrganizationID) != "" {
		return OrganizationNameResolution{
			OrganizationID: "ocl:" + strings.TrimSpace(candidate.OCLOrganizationID),
			NormalizedName: normalized,
		}, nil
	}
	if normalized == "" {
		return OrganizationNameResolution{}, fmt.Errorf("organization name is required when OCL organization ID is absent")
	}
	if n.aliases == nil {
		return OrganizationNameResolution{OrganizationID: "name:" + normalized, NormalizedName: normalized}, nil
	}

	matches, err := n.aliases.FindOrganizationIDsByNormalizedName(ctx, normalized)
	if err != nil {
		return OrganizationNameResolution{}, err
	}
	switch len(matches) {
	case 0:
		return OrganizationNameResolution{OrganizationID: "name:" + normalized, NormalizedName: normalized}, nil
	case 1:
		return OrganizationNameResolution{OrganizationID: matches[0], NormalizedName: normalized}, nil
	default:
		pending := PendingOrganizationAlias{
			NormalizedName:           normalized,
			ObservedName:             strings.TrimSpace(candidate.Name),
			SourceTable:              strings.TrimSpace(candidate.SourceTable),
			SourceID:                 strings.TrimSpace(candidate.SourceID),
			CandidateOrganizationIDs: append([]string(nil), matches...),
		}
		if err := n.aliases.LogPendingOrganizationAlias(ctx, pending); err != nil {
			return OrganizationNameResolution{}, err
		}
		return OrganizationNameResolution{
			OrganizationID: "name:" + normalized,
			NormalizedName: normalized,
			Ambiguous:      true,
		}, nil
	}
}

func NormalizeOrganizationName(value string) string {
	decomposed := norm.NFD.String(strings.ToLower(strings.TrimSpace(value)))
	parts := make([]string, 0)
	var current strings.Builder
	for _, r := range decomposed {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			current.WriteRune(r)
			continue
		}
		if current.Len() > 0 {
			parts = append(parts, current.String())
			current.Reset()
		}
	}
	if current.Len() > 0 {
		parts = append(parts, current.String())
	}
	return strings.Join(parts, " ")
}
