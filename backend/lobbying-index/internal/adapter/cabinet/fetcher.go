package cabinet

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
	"golang.org/x/net/html"
)

const (
	defaultCabinetURL        = "https://www.pm.gc.ca/en/cabinet"
	defaultMandateLettersURL = "https://www.pm.gc.ca/en/mandate-letters"
	defaultUserAgent         = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
	defaultTopicConfidence   = 0.85
)

var mandateLetterHrefPattern = regexp.MustCompile(`href="([^"]*/mandate-letters/\d{4}/\d{2}/\d{2}/[^"]+)"`)

type Fetcher struct {
	client            *http.Client
	cabinetURL        string
	mandateLettersURL string
	userAgent         string
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(fetcher *Fetcher) {
		if client != nil {
			fetcher.client = client
		}
	}
}

func WithCabinetURL(url string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(url) != "" {
			fetcher.cabinetURL = strings.TrimSpace(url)
		}
	}
}

func WithMandateLettersURL(url string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(url) != "" {
			fetcher.mandateLettersURL = strings.TrimSpace(url)
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

func NewFetcher(opts ...Option) *Fetcher {
	fetcher := &Fetcher{
		client:            &http.Client{Timeout: 45 * time.Second},
		cabinetURL:        defaultCabinetURL,
		mandateLettersURL: defaultMandateLettersURL,
		userAgent:         defaultUserAgent,
	}
	for _, opt := range opts {
		opt(fetcher)
	}
	return fetcher
}

func (f *Fetcher) FetchCabinet(ctx context.Context) (domain.CabinetSnapshot, error) {
	cabinetHTML, err := f.fetch(ctx, f.cabinetURL)
	if err != nil {
		return domain.CabinetSnapshot{}, fmt.Errorf("fetch cabinet page: %w", err)
	}
	periods, err := parseCabinetHTML(cabinetHTML, f.cabinetURL)
	if err != nil {
		return domain.CabinetSnapshot{}, err
	}
	if len(periods) == 0 {
		return domain.CabinetSnapshot{}, fmt.Errorf("parsed zero cabinet ministers from %s", f.cabinetURL)
	}

	mandateIndexHTML, err := f.fetch(ctx, f.mandateLettersURL)
	if err != nil {
		return domain.CabinetSnapshot{}, fmt.Errorf("fetch mandate letters page: %w", err)
	}
	mandateURL, hasLetter, err := parseMandateLetterURL(f.mandateLettersURL, mandateIndexHTML)
	if err != nil {
		return domain.CabinetSnapshot{}, err
	}
	if !hasLetter {
		return domain.CabinetSnapshot{PortfolioPeriods: periods, MandateTopics: []domain.CabinetMandateTopic{}}, nil
	}

	mandateHTML, err := f.fetch(ctx, mandateURL)
	if err != nil {
		return domain.CabinetSnapshot{}, fmt.Errorf("fetch mandate letter article: %w", err)
	}
	startDate, bodyText, err := parseMandateLetterHTML(mandateHTML)
	if err != nil {
		return domain.CabinetSnapshot{}, fmt.Errorf("parse mandate letter article: %w", err)
	}
	if startDate != nil {
		for i := range periods {
			periods[i].StartDate = startDate
		}
	}

	topics := inferMandateTopics(bodyText, mandateURL)
	return domain.CabinetSnapshot{
		PortfolioPeriods: periods,
		MandateTopics:    topics,
	}, nil
}

func (f *Fetcher) fetch(ctx context.Context, sourceURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", f.userAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml")

	resp, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("expected HTTP 200 from %s, got %d", sourceURL, resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

func parseCabinetHTML(payload string, sourceURL string) ([]domain.CabinetPortfolioPeriod, error) {
	z := html.NewTokenizer(strings.NewReader(payload))

	var periods []domain.CabinetPortfolioPeriod
	var currentName []string
	var currentRole []string
	var capture string
	captureDepth := 0

	flush := func() {
		name := compactText(strings.Join(currentName, " "))
		role := compactText(strings.Join(currentRole, " "))
		currentName = nil
		currentRole = nil
		if name == "" || role == "" {
			return
		}
		roleLower := strings.ToLower(role)
		if !strings.Contains(roleLower, "minister") && !strings.Contains(roleLower, "prime minister") {
			return
		}
		name = stripHonorifics(name)
		firstName, lastName := splitName(name)
		periods = append(periods, domain.CabinetPortfolioPeriod{
			MinisterName:  name,
			FirstName:     firstName,
			LastName:      lastName,
			PortfolioName: role,
			SourceURL:     sourceURL,
		})
	}

	for {
		switch z.Next() {
		case html.ErrorToken:
			if err := z.Err(); err != io.EOF {
				return nil, fmt.Errorf("parse cabinet html: %w", err)
			}
			flush()
			return periods, nil
		case html.StartTagToken:
			token := z.Token()
			if capture != "" {
				captureDepth++
			}
			if token.Data != "div" {
				continue
			}
			className := attrValue(token, "class")
			switch {
			case capture == "" && hasClass(className, "name"):
				flush()
				capture = "name"
				captureDepth = 1
			case capture == "" && hasClass(className, "role") && len(currentName) > 0:
				capture = "role"
				captureDepth = 1
			}
		case html.EndTagToken:
			if capture == "" {
				continue
			}
			captureDepth--
			if captureDepth > 0 {
				continue
			}
			if capture == "role" {
				flush()
			}
			capture = ""
			captureDepth = 0
		case html.TextToken:
			text := compactText(string(z.Text()))
			if text == "" {
				continue
			}
			switch capture {
			case "name":
				currentName = append(currentName, text)
			case "role":
				currentRole = append(currentRole, text)
			}
		}
	}
}

func parseMandateLetterURL(baseURL, payload string) (string, bool, error) {
	match := mandateLetterHrefPattern.FindStringSubmatch(payload)
	if len(match) == 2 {
		resolved, err := resolveURL(baseURL, match[1])
		if err != nil {
			return "", false, err
		}
		return resolved, true, nil
	}
	if strings.Contains(strings.ToLower(payload), "no mandate letters") {
		return "", false, nil
	}
	return "", false, fmt.Errorf("could not find mandate letter article link on %s", baseURL)
}

func parseMandateLetterHTML(payload string) (*time.Time, string, error) {
	z := html.NewTokenizer(strings.NewReader(payload))

	inArticle := false
	articleDepth := 0
	capture := ""
	captureDepth := 0
	var dateText []string
	var bodyText []string

	for {
		switch z.Next() {
		case html.ErrorToken:
			if err := z.Err(); err != io.EOF {
				return nil, "", err
			}
			publishedAt, err := parsePublishedDate(compactText(strings.Join(dateText, " ")))
			if err != nil {
				return nil, "", err
			}
			return publishedAt, compactText(strings.Join(bodyText, " ")), nil
		case html.StartTagToken:
			token := z.Token()
			if inArticle {
				articleDepth++
			}
			if token.Data == "article" && !inArticle {
				inArticle = true
				articleDepth = 1
				continue
			}
			if !inArticle {
				continue
			}
			if capture != "" {
				captureDepth++
			}
			className := attrValue(token, "class")
			switch {
			case capture == "" && token.Data == "span" && hasClass(className, "inline-date"):
				capture = "date"
				captureDepth = 1
			case capture == "" && token.Data == "div" && hasClass(className, "field--name-body"):
				capture = "body"
				captureDepth = 1
			}
		case html.EndTagToken:
			if inArticle {
				articleDepth--
				if articleDepth == 0 {
					inArticle = false
				}
			}
			if capture == "" {
				continue
			}
			captureDepth--
			if captureDepth > 0 {
				continue
			}
			capture = ""
			captureDepth = 0
		case html.TextToken:
			if capture == "" {
				continue
			}
			text := compactText(string(z.Text()))
			if text == "" {
				continue
			}
			switch capture {
			case "date":
				dateText = append(dateText, text)
			case "body":
				bodyText = append(bodyText, text)
			}
		}
	}
}

func parsePublishedDate(raw string) (*time.Time, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return nil, nil
	}
	for _, layout := range []string{"January 2, 2006", "Mon, 01/02/2006 - 15:04"} {
		parsed, err := time.Parse(layout, value)
		if err == nil {
			date := time.Date(parsed.Year(), parsed.Month(), parsed.Day(), 0, 0, 0, 0, time.UTC)
			return &date, nil
		}
	}
	return nil, fmt.Errorf("parse mandate letter date %q", raw)
}

func inferMandateTopics(bodyText, sourceURL string) []domain.CabinetMandateTopic {
	lower := strings.ToLower(bodyText)
	seen := make(map[string]struct{})
	topics := make([]domain.CabinetMandateTopic, 0, len(mandateKeywords))
	for _, keyword := range mandateKeywords {
		if !strings.Contains(lower, keyword.keyword) {
			continue
		}
		if _, ok := seen[keyword.slug]; ok {
			continue
		}
		seen[keyword.slug] = struct{}{}
		topics = append(topics, domain.CabinetMandateTopic{
			EpacTopicSlug: keyword.slug,
			Confidence:    defaultTopicConfidence,
			SourceURL:     sourceURL,
		})
	}
	sort.Slice(topics, func(i, j int) bool {
		return topics[i].EpacTopicSlug < topics[j].EpacTopicSlug
	})
	return topics
}

func resolveURL(baseURL, href string) (string, error) {
	base, err := url.Parse(baseURL)
	if err != nil {
		return "", err
	}
	rel, err := url.Parse(href)
	if err != nil {
		return "", err
	}
	return base.ResolveReference(rel).String(), nil
}

func splitName(fullName string) (string, string) {
	parts := strings.Fields(strings.TrimSpace(fullName))
	if len(parts) <= 1 {
		return fullName, ""
	}
	return strings.Join(parts[:len(parts)-1], " "), parts[len(parts)-1]
}

func stripHonorifics(name string) string {
	candidates := []string{
		"The Right Honourable ",
		"Right Honourable ",
		"The Rt. Hon. ",
		"Rt. Hon. ",
		"The Honourable ",
		"Honourable ",
		"Hon. ",
	}
	trimmed := strings.TrimSpace(name)
	for _, candidate := range candidates {
		if strings.HasPrefix(trimmed, candidate) {
			return strings.TrimSpace(strings.TrimPrefix(trimmed, candidate))
		}
	}
	return trimmed
}

func compactText(value string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(value)), " ")
}

func hasClass(className, target string) bool {
	for _, part := range strings.Fields(className) {
		if part == target {
			return true
		}
	}
	return false
}

func attrValue(token html.Token, key string) string {
	for _, attr := range token.Attr {
		if attr.Key == key {
			return attr.Val
		}
	}
	return ""
}

var mandateKeywords = []struct {
	keyword string
	slug    string
}{
	{"indigenous", "indigenous"},
	{"first nation", "indigenous"},
	{"aboriginal", "indigenous"},
	{"métis", "indigenous"},
	{"inuit", "indigenous"},
	{"climat", "climate"},
	{"environment", "climate"},
	{"housing", "housing"},
	{"immigra", "immigration"},
	{"agricultur", "agriculture"},
	{"defence", "defence"},
	{"defense", "defence"},
	{"security", "defence"},
	{"armed forces", "defence"},
	{"borders", "defence"},
	{"energy", "energy"},
	{"electricity", "energy"},
	{"nuclear", "energy"},
	{"petroleum", "energy"},
	{"trade", "trade"},
	{"trading", "trade"},
	{"tariff", "trade"},
	{"import", "trade"},
	{"export", "trade"},
	{"foreign", "foreign"},
	{"international", "foreign"},
	{"ally", "foreign"},
	{"allies", "foreign"},
	{"digital", "digital"},
	{"artificial intelligence", "digital"},
	{"cyber", "digital"},
	{"internet", "digital"},
	{"data protection", "digital"},
	{"education", "education"},
	{"school", "education"},
	{"university", "education"},
	{"skill", "education"},
	{"tax", "taxation"},
	{"revenue", "taxation"},
	{"labour", "labour"},
	{"labor", "labour"},
	{"worker", "labour"},
	{"employment", "labour"},
	{"transport", "transport"},
	{"railway", "transport"},
	{"aviation", "transport"},
	{"airport", "transport"},
	{"mineral", "naturalresources"},
	{"mining", "naturalresources"},
	{"forestry", "naturalresources"},
	{"natural resource", "naturalresources"},
}
