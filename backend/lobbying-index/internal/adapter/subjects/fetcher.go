package subjects

import (
	"context"
	"fmt"
	"html"
	"io"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
)

const (
	defaultBaseURL           = "https://lobbycanada.gc.ca"
	defaultSubjectMatterPath = "/app/secure/ocl/lrs/do/regSms"
	defaultUserAgent         = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

var (
	subjectRowRE = regexp.MustCompile(`(?is)<tr>\s*<td>\s*([^<\n]+?)\s*</td>\s*<td[^>]*>\s*<a[^>]*adv_2001_subjectMatter=([^"&>\s]+)[^>]*>`) //nolint:gocritic // mirrors source-site regex for compatibility
)

type Fetcher struct {
	client      *http.Client
	baseURL     string
	userAgent   string
	englishPath string
	frenchPath  string
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(fetcher *Fetcher) {
		if client != nil {
			fetcher.client = client
		}
	}
}

func WithBaseURL(baseURL string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(baseURL) != "" {
			fetcher.baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
		}
	}
}

func WithUserAgent(userAgent string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(userAgent) != "" {
			fetcher.userAgent = strings.TrimSpace(userAgent)
		}
	}
}

func WithPaths(englishPath, frenchPath string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(englishPath) != "" {
			fetcher.englishPath = strings.TrimSpace(englishPath)
		}
		if strings.TrimSpace(frenchPath) != "" {
			fetcher.frenchPath = strings.TrimSpace(frenchPath)
		}
	}
}

func NewFetcher(opts ...Option) *Fetcher {
	fetcher := &Fetcher{
		client:      &http.Client{Timeout: 45 * time.Second},
		baseURL:     defaultBaseURL,
		userAgent:   defaultUserAgent,
		englishPath: defaultSubjectMatterPath + "?lang=eng",
		frenchPath:  defaultSubjectMatterPath + "?lang=fra",
	}
	for _, option := range opts {
		option(fetcher)
	}
	return fetcher
}

func (f *Fetcher) FetchSubjectMatters(ctx context.Context) ([]domain.OCLSubjectMatterType, error) {
	enHTML, err := f.fetch(ctx, f.baseURL+f.englishPath)
	if err != nil {
		return nil, fmt.Errorf("fetch EN subject matters: %w", err)
	}
	frHTML, err := f.fetch(ctx, f.baseURL+f.frenchPath)
	if err != nil {
		return nil, fmt.Errorf("fetch FR subject matters: %w", err)
	}

	enLabels := parseSubjectMatterRows(enHTML)
	frLabels := parseSubjectMatterRows(frHTML)

	codes := map[string]struct{}{}
	for code := range enLabels {
		codes[code] = struct{}{}
	}
	for code := range frLabels {
		codes[code] = struct{}{}
	}

	codesSlice := make([]string, 0, len(codes))
	for code := range codes {
		codesSlice = append(codesSlice, code)
	}
	sort.Strings(codesSlice)

	result := make([]domain.OCLSubjectMatterType, 0, len(codesSlice))
	for _, code := range codesSlice {
		result = append(result, domain.OCLSubjectMatterType{
			SubjectCodeObjet: code,
			SmtEnDesc:        enLabels[code],
		})
		if result[len(result)-1].SmtEnDesc == "" {
			result[len(result)-1].SmtEnDesc = frLabels[code]
		}
	}
	return result, nil
}

func (f *Fetcher) fetch(ctx context.Context, sourceURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", f.userAgent)
	req.Header.Set("Accept", "text/html")

	resp, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("expected HTTP 200 from subject matter endpoint, got %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func parseSubjectMatterRows(htmlText string) map[string]string {
	entries := map[string]string{}
	for _, match := range subjectRowRE.FindAllStringSubmatch(htmlText, -1) {
		if len(match) < 3 {
			continue
		}
		code := strings.TrimSpace(match[2])
		label := strings.TrimSpace(html.UnescapeString(match[1]))
		if label == "" || code == "" {
			continue
		}
		entries[code] = label
	}
	return entries
}
