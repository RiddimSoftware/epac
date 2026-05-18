package postgres

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"epac/on-this-day/internal/usecase"
)

func TestOneLineExcerpt(t *testing.T) {
	got := OneLineExcerpt("Madam Speaker,\n\nthis is   a longer statement about Parliament.", 26)
	if got != "Madam Speaker, this is a..." {
		t.Fatalf("excerpt = %q", got)
	}
}

func TestIsOptionalRankingSchemaError(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "missing members table",
			err:  errString(`ERROR: relation "members" does not exist (SQLSTATE 42P01)`),
			want: true,
		},
		{
			name: "missing related bill column",
			err:  errString(`ERROR: column s.related_bill_ids does not exist (SQLSTATE 42703)`),
			want: true,
		},
		{
			name: "unrelated query failure",
			err:  errString(`ERROR: relation "speeches" does not exist (SQLSTATE 42P01)`),
			want: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsOptionalRankingSchemaError(tc.err); got != tc.want {
				t.Fatalf("IsOptionalRankingSchemaError() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestScanSpeechItem(t *testing.T) {
	row := fakeSpeechRow{
		values: []any{
			"12345",
			2021,
			time.Date(2021, 4, 29, 0, 0, 0, 0, time.UTC),
			"Jane Example",
			"Housing",
			"Madam Speaker, housing affordability matters.",
			stringPtr("278707"),
			stringPtr("https://www.ourcommons.ca/documentviewer/en/44-1/house/sitting-1/hansard"),
		},
	}
	item, err := ScanSpeechItem(row)
	if err != nil {
		t.Fatalf("ScanSpeechItem error: %v", err)
	}
	if item.ID != "speech:12345" || item.Kind != "speech" || item.Year != 2021 {
		t.Fatalf("unexpected item identity: %+v", item)
	}
	if item.Date != "2021-04-29" || item.Title != "Housing" {
		t.Fatalf("unexpected item fields: %+v", item)
	}
	body, err := json.Marshal(usecase.OnThisDayResponse{Date: "2026-04-29", Items: []usecase.OnThisDayItem{item}})
	if err != nil {
		t.Fatalf("marshal response: %v", err)
	}
	if !strings.Contains(string(body), `"kind":"speech"`) {
		t.Fatalf("response missing speech kind: %s", body)
	}
}

type fakeSpeechRow struct {
	values []any
}

func (f fakeSpeechRow) Scan(dest ...any) error {
	for idx, value := range f.values {
		switch out := dest[idx].(type) {
		case *string:
			*out = value.(string)
		case *int:
			*out = value.(int)
		case *time.Time:
			*out = value.(time.Time)
		case **string:
			*out = value.(*string)
		}
	}
	return nil
}

func stringPtr(value string) *string {
	return &value
}

type errString string

func (e errString) Error() string {
	return string(e)
}
