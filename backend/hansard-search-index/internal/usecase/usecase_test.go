package usecase

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"

	"epac/hansard-search-index/internal/domain"
)

func TestBuildIndexStopsAtFirstMissingSittingAndWritesManifestAfterUpload(t *testing.T) {
	clockTick = 0
	ctx := context.Background()
	source := &fakeSource{
		bodies: map[int][]byte{
			1: []byte("<one />"),
			2: []byte("<two />"),
		},
	}
	parser := &fakeParser{}
	builder := &fakeBuilder{stats: domain.Stats{
		BuiltAt:           time.Date(2026, 5, 25, 17, 30, 0, 0, time.UTC),
		ParliamentNumber:  45,
		SessionNumber:     1,
		SittingCount:      2,
		InterventionCount: 2,
		MessageCount:      3,
	}}
	uploader := &fakeUploader{sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 1234}
	writer := &fakeWriter{}
	uc, err := NewBuildIndex(source, parser, builder, uploader, writer)
	if err != nil {
		t.Fatalf("NewBuildIndex: %v", err)
	}

	out, err := uc.Execute(ctx, Input{
		Session: domain.Session{ParliamentNumber: 45, SessionNumber: 1},
		Prefix:  "hansard-search/v1",
	})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}

	if !slices.Equal(source.calls, []int{1, 2, 3}) {
		t.Fatalf("source calls = %v, want [1 2 3]", source.calls)
	}
	if uploader.key != "hansard-search/v1/index.sqlite" {
		t.Fatalf("uploaded key = %q", uploader.key)
	}
	if !uploader.calledBefore(writer.calledAt) {
		t.Fatal("manifest was written before SQLite upload")
	}
	if out.Manifest.SQLiteSHA256 != uploader.sha256 {
		t.Fatalf("manifest sha = %q", out.Manifest.SQLiteSHA256)
	}
	if writer.manifest.SQLiteKey != "hansard-search/v1/index.sqlite" {
		t.Fatalf("manifest sqlite key = %q", writer.manifest.SQLiteKey)
	}
	if writer.manifest.MessageCount != 3 {
		t.Fatalf("message count = %d, want 3", writer.manifest.MessageCount)
	}
}

func TestBuildIndexFailsWhenEveryDownloadedSittingFailsToParse(t *testing.T) {
	source := &fakeSource{bodies: map[int][]byte{1: []byte("<bad />")}}
	parser := &fakeParser{err: errors.New("malformed xml")}
	builder := &fakeBuilder{}
	uploader := &fakeUploader{}
	writer := &fakeWriter{}
	uc, err := NewBuildIndex(source, parser, builder, uploader, writer)
	if err != nil {
		t.Fatalf("NewBuildIndex: %v", err)
	}

	_, err = uc.Execute(context.Background(), Input{
		Session: domain.Session{ParliamentNumber: 45, SessionNumber: 1},
	})
	if err == nil {
		t.Fatal("expected parse failure, got nil")
	}
}

type fakeSource struct {
	bodies map[int][]byte
	calls  []int
}

func (s *fakeSource) FetchSitting(_ context.Context, _, _, sitting int) ([]byte, error) {
	s.calls = append(s.calls, sitting)
	if body, ok := s.bodies[sitting]; ok {
		return body, nil
	}
	return nil, ErrSittingNotFound
}

type fakeParser struct {
	err error
}

func (p *fakeParser) Parse(body []byte) ([]domain.Intervention, error) {
	if p.err != nil {
		return nil, p.err
	}
	return []domain.Intervention{{
		InterventionID: string(body),
		Messages:       []domain.Message{{MessageID: string(body) + "-p1", Position: 1, Text: "sample parliament text"}},
	}}, nil
}

type fakeBuilder struct {
	stats domain.Stats
}

func (b *fakeBuilder) Build(context.Context, []domain.Intervention) (string, domain.Stats, error) {
	return "/tmp/index.sqlite", b.stats, nil
}

type fakeUploader struct {
	key        string
	sha256     string
	size       int64
	calledTick int
}

var clockTick int

func (u *fakeUploader) Upload(_ context.Context, _, key string) (string, int64, error) {
	clockTick++
	u.calledTick = clockTick
	u.key = key
	return u.sha256, u.size, nil
}

func (u *fakeUploader) calledBefore(tick int) bool {
	return u.calledTick > 0 && tick > u.calledTick
}

type fakeWriter struct {
	manifest domain.Manifest
	calledAt int
}

func (w *fakeWriter) Write(_ context.Context, manifest domain.Manifest) error {
	clockTick++
	w.calledAt = clockTick
	w.manifest = manifest
	return nil
}
