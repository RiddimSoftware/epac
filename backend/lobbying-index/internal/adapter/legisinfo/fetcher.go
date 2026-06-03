// Package legisinfo fetches bill metadata from the parl.ca/legisinfo JSON API.
package legisinfo

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
)

const (
	defaultBaseURL   = "https://www.parl.ca/legisinfo/en/bills/json"
	defaultUserAgent = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

// legisInfoBillJSON matches the bulk JSON response from /en/bills/json.
type legisInfoBillJSON struct {
	BillNumberFormatted               string `json:"BillNumberFormatted"`
	ParliamentNumber                  int    `json:"ParliamentNumber"`
	SessionNumber                     int    `json:"SessionNumber"`
	LongTitleEn                       string `json:"LongTitleEn"`
	BillTypeEn                        string `json:"BillTypeEn"`
	PassedHouseFirstReadingDateTime   string `json:"PassedHouseFirstReadingDateTime"`
	PassedHouseSecondReadingDateTime  string `json:"PassedHouseSecondReadingDateTime"`
	PassedHouseThirdReadingDateTime   string `json:"PassedHouseThirdReadingDateTime"`
	PassedSenateFirstReadingDateTime  string `json:"PassedSenateFirstReadingDateTime"`
	PassedSenateSecondReadingDateTime string `json:"PassedSenateSecondReadingDateTime"`
	PassedSenateThirdReadingDateTime  string `json:"PassedSenateThirdReadingDateTime"`
	ReceivedRoyalAssentDateTime       string `json:"ReceivedRoyalAssentDateTime"`
}

// Fetcher retrieves bill data from parl.ca/legisinfo.
type Fetcher struct {
	client    *http.Client
	baseURL   string
	userAgent string
}

// Option configures a Fetcher.
type Option func(*Fetcher)

func WithHTTPClient(c *http.Client) Option {
	return func(f *Fetcher) {
		if c != nil {
			f.client = c
		}
	}
}

func WithBaseURL(u string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(u) != "" {
			f.baseURL = strings.TrimSpace(u)
		}
	}
}

func WithUserAgent(ua string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(ua) != "" {
			f.userAgent = strings.TrimSpace(ua)
		}
	}
}

// NewFetcher creates a LegisInfo bill fetcher.
func NewFetcher(opts ...Option) *Fetcher {
	f := &Fetcher{
		client:    &http.Client{Timeout: 45 * time.Second},
		baseURL:   defaultBaseURL,
		userAgent: defaultUserAgent,
	}
	for _, opt := range opts {
		opt(f)
	}
	return f
}

// FetchBills retrieves all bills for the given parliament and session.
func (f *Fetcher) FetchBills(ctx context.Context, parliament, session int) ([]domain.LegisInfoBill, error) {
	url := fmt.Sprintf("%s?parlsession=%d-%d&load=yes", strings.TrimRight(f.baseURL, "?"), parliament, session)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("build legisinfo request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", f.userAgent)

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch legisinfo bills: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("legisinfo returned HTTP %d", resp.StatusCode)
	}

	var raw []legisInfoBillJSON
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("decode legisinfo response: %w", err)
	}

	bills := make([]domain.LegisInfoBill, 0, len(raw))
	for _, r := range raw {
		number := strings.TrimSpace(r.BillNumberFormatted)
		if number == "" {
			continue
		}
		bills = append(bills, domain.LegisInfoBill{
			Number:                            number,
			Parliament:                        r.ParliamentNumber,
			Session:                           r.SessionNumber,
			LongTitleEn:                       strings.TrimSpace(r.LongTitleEn),
			BillTypeEn:                        strings.TrimSpace(r.BillTypeEn),
			PassedHouseFirstReadingDateTime:   r.PassedHouseFirstReadingDateTime,
			PassedHouseSecondReadingDateTime:  r.PassedHouseSecondReadingDateTime,
			PassedHouseThirdReadingDateTime:   r.PassedHouseThirdReadingDateTime,
			PassedSenateFirstReadingDateTime:  r.PassedSenateFirstReadingDateTime,
			PassedSenateSecondReadingDateTime: r.PassedSenateSecondReadingDateTime,
			PassedSenateThirdReadingDateTime:  r.PassedSenateThirdReadingDateTime,
			ReceivedRoyalAssentDateTime:       r.ReceivedRoyalAssentDateTime,
		})
	}
	return bills, nil
}
