package usecase

import (
	"regexp"
	"sort"
	"strconv"
	"strings"

	"epac/bills-indexer/internal/domain"
)

// ComputeBillVersionDiff is the application policy that turns a bill's parsed
// versions into ordered version-to-version diffs. It operates purely on
// domain values (BillVersion sections in, BillDiff/BillClauseDiff out) and is
// independent of any source wire format, so it lives in the application layer
// rather than in a source adapter. Sources are responsible for fetching and
// parsing version text into domain.VersionSection; this policy is composed on
// top of that during ingestion.
//
// Versions are diffed in SortOrder sequence. A bill with fewer than two
// versions has nothing to compare, so the result is nil. When either side of a
// pair has no parsed sections (text unavailable), the diff record is still
// produced but carries no clause-level detail.
func ComputeBillVersionDiff(number string, versions []domain.BillVersion, detailURL string) []domain.BillDiff {
	if len(versions) < 2 {
		return nil
	}
	ordered := append([]domain.BillVersion(nil), versions...)
	sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].SortOrder < ordered[j].SortOrder })
	n := len(ordered)
	diffs := make([]domain.BillDiff, 0, n*(n-1)/2)
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			fromVer := ordered[i]
			toVer := ordered[j]

			// We only emit a diff artifact if:
			// 1. It is an adjacent pair (to keep compatibility and stability for existing smoke tests), OR
			// 2. Both versions have clause text (len(Sections) > 0).
			isAdjacent := (j == i + 1)
			hasTextBothSides := (len(fromVer.Sections) > 0 && len(toVer.Sections) > 0)
			if !isAdjacent && !hasTextBothSides {
				continue
			}

			diffID := stableID("diff", number, fromVer.ID, toVer.ID)

			var clauseDiffs []domain.BillClauseDiff
			if len(fromVer.Sections) > 0 && len(toVer.Sections) > 0 {
				rawDiffs := DiffClauses(fromVer.Sections, toVer.Sections)
				clauseDiffs = make([]domain.BillClauseDiff, 0, len(rawDiffs))
				for idx, rd := range rawDiffs {
					clauseID := stableID("clause", number, diffID, rd.Label)
					if rd.Label == "" {
						clauseID = stableID("clause", number, diffID, strconv.Itoa(idx))
					}
					clauseDiffs = append(clauseDiffs, domain.BillClauseDiff{
						ID:               clauseID,
						Label:            rd.Label,
						ChangeType:       rd.ChangeType,
						FromText:         rd.FromText,
						ToText:           rd.ToText,
						HansardAnchorURL: nil,
					})
				}
			}

			diffs = append(diffs, domain.BillDiff{
				ID:            diffID,
				FromVersionID: fromVer.ID,
				ToVersionID:   toVer.ID,
				SourceURL:     detailURL,
				Clauses:       clauseDiffs,
			})
		}
	}
	return diffs
}

// DiffClauses aligns two clause lists by label using a longest-common-subsequence
// pass, then classifies each clause as added, removed, modified, or unchanged.
// It depends only on the clause label and text, so it is source-agnostic.
func DiffClauses(fromClauses, toClauses []domain.VersionSection) []domain.BillClauseDiff {
	n := len(fromClauses)
	m := len(toClauses)

	dp := make([][]int, n+1)
	for i := range dp {
		dp[i] = make([]int, m+1)
	}

	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			if fromClauses[i-1].Label != "" && fromClauses[i-1].Label == toClauses[j-1].Label {
				dp[i][j] = dp[i-1][j-1] + 1
			} else {
				dp[i][j] = maxInt(dp[i-1][j], dp[i][j-1])
			}
		}
	}

	var diffs []domain.BillClauseDiff
	i, j := n, m
	for i > 0 || j > 0 {
		if i > 0 && j > 0 && fromClauses[i-1].Label != "" && fromClauses[i-1].Label == toClauses[j-1].Label {
			fc := fromClauses[i-1]
			tc := toClauses[j-1]
			changeType := "unchanged"
			if fc.Text != tc.Text {
				changeType = "modified"
			}
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      fc.Label,
				ChangeType: changeType,
				FromText:   fc.Text,
				ToText:     tc.Text,
			})
			i--
			j--
		} else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
			tc := toClauses[j-1]
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      tc.Label,
				ChangeType: "added",
				ToText:     tc.Text,
			})
			j--
		} else {
			fc := fromClauses[i-1]
			diffs = append(diffs, domain.BillClauseDiff{
				Label:      fc.Label,
				ChangeType: "removed",
				FromText:   fc.Text,
			})
			i--
		}
	}

	for k := 0; k < len(diffs)/2; k++ {
		diffs[k], diffs[len(diffs)-1-k] = diffs[len(diffs)-1-k], diffs[k]
	}

	return diffs
}

// stableID builds a deterministic, slug-safe identifier from its parts. It
// mirrors the slug rule used by the source adapters so that relocating diff ID
// generation into this layer keeps the produced identifiers byte-for-byte
// identical.
func stableID(parts ...string) string {
	filtered := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			filtered = append(filtered, part)
		}
	}
	id := strings.ToLower(strings.Join(filtered, "-"))
	id = nonSlugPattern.ReplaceAllString(id, "-")
	id = strings.Trim(id, "-")
	if id == "" {
		return "unknown"
	}
	return id
}

var nonSlugPattern = regexp.MustCompile(`[^a-z0-9]+`)

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
