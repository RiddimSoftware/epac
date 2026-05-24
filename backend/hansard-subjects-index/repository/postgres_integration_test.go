//go:build integration

package repository

import (
	"context"
	"testing"
	"time"

	"epac/_testdb"
	"epac/hansard-subjects-index/application"
	"github.com/jackc/pgx/v5"
)

func TestPostgresSubjectsRepositoryEmptyCorpus(t *testing.T) {
	conn := connectSubjectsDB(t)
	resetSubjects(t, conn)

	repo := NewPostgresSubjectsRepository(conn)
	subjects, err := repo.ListSubjects(context.Background(), application.Window{
		From: mustRepoDate(t, "2020-01-01"),
		To:   mustRepoDate(t, "2026-05-17"),
	})
	if err != nil {
		t.Fatalf("list subjects: %v", err)
	}
	if len(subjects) != 0 {
		t.Fatalf("subjects count = %d, want 0", len(subjects))
	}
}

func TestPostgresSubjectsRepositorySingleSubject(t *testing.T) {
	conn := connectSubjectsDB(t)
	resetSubjects(t, conn)

	seedSubjectSpeech(t, conn, "speech-1", "subject-1", "Question Period", "2026-05-15", 45)
	seedSubjectSpeech(t, conn, "speech-2", "subject-1", "Question Period", "2026-05-15", 45)

	repo := NewPostgresSubjectsRepository(conn)
	subjects, err := repo.ListSubjects(context.Background(), application.Window{
		From: mustRepoDate(t, "2026-01-01"),
		To:   mustRepoDate(t, "2026-05-17"),
	})
	if err != nil {
		t.Fatalf("list subjects: %v", err)
	}
	if len(subjects) != 1 {
		t.Fatalf("subjects count = %d, want 1: %#v", len(subjects), subjects)
	}
	if subjects[0].SubjectID != "subject-1" || subjects[0].SubjectTitle != "Question Period" {
		t.Fatalf("subject = %#v", subjects[0])
	}
}

func TestPostgresSubjectsRepositoryDefaultWindowUsesCurrentAndPreviousTwoParliaments(t *testing.T) {
	conn := connectSubjectsDB(t)
	resetSubjects(t, conn)

	seedSubjectSpeech(t, conn, "speech-42", "subject-42", "Old Parliament", "2020-01-15", 42)
	seedSubjectSpeech(t, conn, "speech-43", "subject-43", "Previous Parliament", "2021-02-15", 43)
	seedSubjectSpeech(t, conn, "speech-45", "subject-45", "Current Parliament", "2026-05-15", 45)

	repo := NewPostgresSubjectsRepository(conn)
	window, err := repo.DefaultWindow(context.Background(), mustRepoDate(t, "2026-05-17"), 3)
	if err != nil {
		t.Fatalf("default window: %v", err)
	}
	subjects, err := repo.ListSubjects(context.Background(), window)
	if err != nil {
		t.Fatalf("list subjects: %v", err)
	}
	if len(subjects) != 2 {
		t.Fatalf("subjects count = %d, want 2: %#v", len(subjects), subjects)
	}
	if subjects[0].SubjectID != "subject-45" || subjects[1].SubjectID != "subject-43" {
		t.Fatalf("unexpected subjects: %#v", subjects)
	}
}

func TestPostgresSubjectsRepositoryDedupesDuplicateSubjectIDsAcrossSittings(t *testing.T) {
	conn := connectSubjectsDB(t)
	resetSubjects(t, conn)

	seedSubjectSpeech(t, conn, "speech-old", "subject-dup", "Older Title", "2026-05-14", 45)
	seedSubjectSpeech(t, conn, "speech-new", "subject-dup", "Newer Title", "2026-05-16", 45)

	repo := NewPostgresSubjectsRepository(conn)
	subjects, err := repo.ListSubjects(context.Background(), application.Window{
		From: mustRepoDate(t, "2026-01-01"),
		To:   mustRepoDate(t, "2026-05-17"),
	})
	if err != nil {
		t.Fatalf("list subjects: %v", err)
	}
	if len(subjects) != 1 {
		t.Fatalf("subjects count = %d, want 1: %#v", len(subjects), subjects)
	}
	if subjects[0].SubjectTitle != "Newer Title" {
		t.Fatalf("dedupe kept %q, want Newer Title", subjects[0].SubjectTitle)
	}
}

func connectSubjectsDB(t *testing.T) *pgx.Conn {
	t.Helper()
	return _testdb.Connect(t)
}

func resetSubjects(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	if _, err := conn.Exec(context.Background(), "DELETE FROM speeches"); err != nil {
		t.Fatalf("reset speeches: %v", err)
	}
}

func seedSubjectSpeech(t *testing.T, conn *pgx.Conn, interventionID string, subjectID string, title string, date string, parliament int) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `
		INSERT INTO speeches (
			intervention_id, filename, speaker_name, content,
			sitting_date, parliament_num, session_num, member_id,
			subject_id, subject_title, intervention_seq, word_count, language
		) VALUES ($1, $2, 'Test Speaker', 'Test content', $3::DATE, $4, 1, 'member-1', $5, $6, 0, 2, 'en')
	`, interventionID, interventionID+".xml", date, parliament, subjectID, title)
	if err != nil {
		t.Fatalf("seed speech %q: %v", interventionID, err)
	}
}

func mustRepoDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return parsed
}
