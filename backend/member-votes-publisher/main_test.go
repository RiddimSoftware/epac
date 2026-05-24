package main

import "testing"

func TestDefaultVotesSourceURL(t *testing.T) {
	if defaultVotesSourceURL == "" {
		t.Fatal("default votes source URL must be set")
	}
}
