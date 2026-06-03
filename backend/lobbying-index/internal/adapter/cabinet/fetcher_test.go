package cabinet

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"epac/lobbying-index/internal/domain"
)

func TestFetcher_FetchCabinetParsesMinistersAndMandateDate(t *testing.T) {
	const cabinetHTML = `
<html><body>
<ul>
  <li class="minister-row">
    <div class="teaser">
      <div class="name">The Right Honourable Mark Carney</div>
      <div class="role">Prime Minister of Canada</div>
    </div>
  </li>
  <li class="minister-row">
    <div class="teaser">
      <div class="name">The Honourable Mélanie Joly</div>
      <div class="role">Minister of Industry</div>
    </div>
  </li>
</ul>
</body></html>`
	const mandateIndexHTML = `<html><body><a href="/en/mandate-letters/2025/05/21/mandate-letter">Mandate Letter</a></body></html>`
	const mandateLetterHTML = `
<html><body>
<article>
  <span class="inline-date">May 21, 2025</span>
  <div class="field field--name-body field--type-text-with-summary field--label-hidden field--item">
    <p>We will fight climate change, make housing more affordable, and return immigration rates to sustainable levels.</p>
  </div>
</article>
</body></html>`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/cabinet":
			_, _ = w.Write([]byte(cabinetHTML))
		case "/mandate-letters":
			_, _ = w.Write([]byte(mandateIndexHTML))
		case "/en/mandate-letters/2025/05/21/mandate-letter":
			_, _ = w.Write([]byte(mandateLetterHTML))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	fetcher := NewFetcher(
		WithHTTPClient(srv.Client()),
		WithCabinetURL(srv.URL+"/cabinet"),
		WithMandateLettersURL(srv.URL+"/mandate-letters"),
	)
	snapshot, err := fetcher.FetchCabinet(context.Background())
	if err != nil {
		t.Fatalf("FetchCabinet: %v", err)
	}

	if got, want := len(snapshot.PortfolioPeriods), 2; got != want {
		t.Fatalf("period count = %d, want %d", got, want)
	}
	first := snapshot.PortfolioPeriods[0]
	if first.MinisterName != "Mark Carney" || first.FirstName != "Mark" || first.LastName != "Carney" {
		t.Fatalf("unexpected first minister: %#v", first)
	}
	if first.PortfolioName != "Prime Minister of Canada" {
		t.Fatalf("portfolio = %q", first.PortfolioName)
	}
	if first.StartDate == nil || !first.StartDate.Equal(time.Date(2025, 5, 21, 0, 0, 0, 0, time.UTC)) {
		t.Fatalf("start date = %#v, want 2025-05-21", first.StartDate)
	}

	if !hasTopic(snapshot, "climate") || !hasTopic(snapshot, "housing") || !hasTopic(snapshot, "immigration") {
		t.Fatalf("unexpected mandate topics: %#v", snapshot.MandateTopics)
	}
}

func TestFetcher_FetchCabinetHandlesNoMandateLetters(t *testing.T) {
	const cabinetHTML = `
<html><body><ul><li class="minister-row"><div class="name">The Honourable Gregor Robertson</div><div class="role">Minister of Housing</div></li></ul></body></html>`
	const mandateIndexHTML = `<html><body><p>No mandate letters available.</p></body></html>`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/cabinet":
			_, _ = w.Write([]byte(cabinetHTML))
		case "/mandate-letters":
			_, _ = w.Write([]byte(mandateIndexHTML))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	fetcher := NewFetcher(
		WithHTTPClient(srv.Client()),
		WithCabinetURL(srv.URL+"/cabinet"),
		WithMandateLettersURL(srv.URL+"/mandate-letters"),
	)
	snapshot, err := fetcher.FetchCabinet(context.Background())
	if err != nil {
		t.Fatalf("FetchCabinet: %v", err)
	}

	if got, want := len(snapshot.PortfolioPeriods), 1; got != want {
		t.Fatalf("period count = %d, want %d", got, want)
	}
	if snapshot.PortfolioPeriods[0].StartDate != nil {
		t.Fatalf("expected nil start date, got %#v", snapshot.PortfolioPeriods[0].StartDate)
	}
	if len(snapshot.MandateTopics) != 0 {
		t.Fatalf("expected no mandate topics, got %#v", snapshot.MandateTopics)
	}
}

func hasTopic(snapshot domain.CabinetSnapshot, slug string) bool {
	for _, topic := range snapshot.MandateTopics {
		if topic.EpacTopicSlug == slug {
			return true
		}
	}
	return false
}
