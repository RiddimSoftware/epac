package application

import (
	"context"
	"testing"
	"time"
)

type fixedClock struct {
	now time.Time
}

func (c fixedClock) Now() time.Time { return c.now }

type fakeRepo struct {
	window   Window
	subjects []HansardSubject
}

func (r fakeRepo) DefaultWindow(context.Context, time.Time, int) (Window, error) {
	return r.window, nil
}

func (r fakeRepo) ListSubjects(context.Context, Window) ([]HansardSubject, error) {
	return r.subjects, nil
}

func TestExecuteBuildsDeterministicIndex(t *testing.T) {
	from := mustDate(t, "2026-01-01")
	to := mustDate(t, "2026-05-17")
	useCase, err := NewBuildHansardSubjectsIndex(fakeRepo{
		window: Window{From: from, To: to},
		subjects: []HansardSubject{
			{SubjectID: "s-2", SubjectTitle: "Housing", HansardDate: mustDate(t, "2026-05-16")},
			{SubjectID: "s-1", SubjectTitle: "Budget", HansardDate: mustDate(t, "2026-05-16")},
			{SubjectID: "s-2", SubjectTitle: "Older Housing", HansardDate: mustDate(t, "2026-05-10")},
			{SubjectID: " ", SubjectTitle: "ignored", HansardDate: mustDate(t, "2026-05-17")},
		},
	}, fixedClock{now: mustTime(t, "2026-05-17T12:00:00Z")})
	if err != nil {
		t.Fatalf("new use case: %v", err)
	}

	index, err := useCase.Execute(context.Background(), BuildInput{})
	if err != nil {
		t.Fatalf("execute: %v", err)
	}

	if index.SchemaVersion != 1 {
		t.Fatalf("schema version = %d, want 1", index.SchemaVersion)
	}
	if index.GeneratedAt != "2026-05-17T12:00:00Z" {
		t.Fatalf("generated_at = %q", index.GeneratedAt)
	}
	if index.Window.From != "2026-01-01" || index.Window.To != "2026-05-17" {
		t.Fatalf("window = %#v", index.Window)
	}
	if len(index.Subjects) != 2 {
		t.Fatalf("subjects count = %d, want 2", len(index.Subjects))
	}
	if index.Subjects[0].SubjectID != "s-1" || index.Subjects[1].SubjectID != "s-2" {
		t.Fatalf("subjects not sorted by date desc then id asc: %#v", index.Subjects)
	}
	if index.Subjects[1].SubjectTitle != "Housing" {
		t.Fatalf("duplicate id did not keep latest subject: %#v", index.Subjects[1])
	}
}

func mustDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return parsed
}

func mustTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatalf("parse time %q: %v", value, err)
	}
	return parsed
}
