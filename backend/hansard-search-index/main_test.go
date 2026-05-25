package main

import "testing"

func TestSessionFromEnvUsesDefaultsAndAllowsOverrides(t *testing.T) {
	t.Setenv("PARLIAMENT_NUMBER", "")
	t.Setenv("SESSION_NUMBER", "")
	session, err := sessionFromEnv()
	if err != nil {
		t.Fatalf("sessionFromEnv default: %v", err)
	}
	if session.ParliamentNumber != DefaultParliamentNumber || session.SessionNumber != DefaultSessionNumber {
		t.Fatalf("default session = %#v", session)
	}

	t.Setenv("PARLIAMENT_NUMBER", "44")
	t.Setenv("SESSION_NUMBER", "1")
	session, err = sessionFromEnv()
	if err != nil {
		t.Fatalf("sessionFromEnv override: %v", err)
	}
	if session.ParliamentNumber != 44 || session.SessionNumber != 1 {
		t.Fatalf("override session = %#v", session)
	}
}

func TestSessionFromEnvRejectsInvalidOverride(t *testing.T) {
	t.Setenv("PARLIAMENT_NUMBER", "nope")
	t.Setenv("SESSION_NUMBER", "1")
	if _, err := sessionFromEnv(); err == nil {
		t.Fatal("expected invalid parliament error")
	}

	t.Setenv("PARLIAMENT_NUMBER", "45")
	t.Setenv("SESSION_NUMBER", "0")
	if _, err := sessionFromEnv(); err == nil {
		t.Fatal("expected invalid session error")
	}
}
