package main

import (
	"context"
	"strings"
	"testing"
)

func TestDispatchPhaseRejectsEmptyPhase(t *testing.T) {
	err := dispatchPhase(context.Background(), " ", stubPhaseRunners(nil))
	if err == nil {
		t.Fatal("dispatchPhase returned nil error for empty phase")
	}
	if !strings.Contains(err.Error(), "PHASE is required") {
		t.Fatalf("error = %q, want PHASE required message", err.Error())
	}
}

func TestDispatchPhaseRejectsUnknownPhase(t *testing.T) {
	err := dispatchPhase(context.Background(), "unknown", stubPhaseRunners(nil))
	if err == nil {
		t.Fatal("dispatchPhase returned nil error for unknown phase")
	}
	if !strings.Contains(err.Error(), `unknown PHASE "unknown"`) {
		t.Fatalf("error = %q, want unknown PHASE message", err.Error())
	}
}

func TestHandleRequestRequiresPhaseBeforeArtifactBucket(t *testing.T) {
	t.Setenv("PHASE", "")
	t.Setenv("EPAC_ARTIFACT_BUCKET", "")

	err := HandleRequest(context.Background(), PhaseEvent{})
	if err == nil {
		t.Fatal("HandleRequest returned nil error for empty PHASE")
	}
	if !strings.Contains(err.Error(), "PHASE is required") {
		t.Fatalf("error = %q, want PHASE required message", err.Error())
	}
}

func TestHandleRequestRejectsUnknownPhaseBeforeArtifactBucket(t *testing.T) {
	t.Setenv("PHASE", "unknown")
	t.Setenv("EPAC_ARTIFACT_BUCKET", "")

	err := HandleRequest(context.Background(), PhaseEvent{})
	if err == nil {
		t.Fatal("HandleRequest returned nil error for unknown PHASE")
	}
	if !strings.Contains(err.Error(), `unknown PHASE "unknown"`) {
		t.Fatalf("error = %q, want unknown PHASE message", err.Error())
	}
}

func TestHandleRequestReadsPhaseEventBeforeEnv(t *testing.T) {
	t.Setenv("PHASE", "unknown")
	t.Setenv("EPAC_ARTIFACT_BUCKET", "")

	err := HandleRequest(context.Background(), PhaseEvent{Phase: phaseIngestOCLData})
	if err == nil {
		t.Fatal("HandleRequest returned nil error for missing artifact bucket")
	}
	if !strings.Contains(err.Error(), "EPAC_ARTIFACT_BUCKET is required") {
		t.Fatalf("error = %q, want artifact bucket required message", err.Error())
	}
}

func TestHandleRequestFallsBackToEnvPhase(t *testing.T) {
	t.Setenv("PHASE", phaseIngestOCLData)
	t.Setenv("EPAC_ARTIFACT_BUCKET", "")

	err := HandleRequest(context.Background(), PhaseEvent{})
	if err == nil {
		t.Fatal("HandleRequest returned nil error for missing artifact bucket")
	}
	if !strings.Contains(err.Error(), "EPAC_ARTIFACT_BUCKET is required") {
		t.Fatalf("error = %q, want artifact bucket required message", err.Error())
	}
}

func TestDispatchPhaseRunsEachKnownPhase(t *testing.T) {
	for _, selected := range knownPhases {
		t.Run(selected, func(t *testing.T) {
			calls := map[string]int{}
			err := dispatchPhase(context.Background(), selected, stubPhaseRunners(calls))
			if err != nil {
				t.Fatalf("dispatchPhase returned error: %v", err)
			}

			for _, phase := range knownPhases {
				want := 0
				if phase == selected {
					want = 1
				}
				if calls[phase] != want {
					t.Fatalf("phase %q call count = %d, want %d", phase, calls[phase], want)
				}
			}
		})
	}
}

func TestPhaseRunnersExposeKnownPhases(t *testing.T) {
	runners := phaseRunners(&runtimeConfig{})
	if len(runners) != len(knownPhases) {
		t.Fatalf("phaseRunners returned %d runners, want %d", len(runners), len(knownPhases))
	}
	for _, phase := range knownPhases {
		if runners[phase] == nil {
			t.Fatalf("phaseRunners missing phase %q", phase)
		}
	}
}

func stubPhaseRunners(calls map[string]int) map[string]func(context.Context) error {
	runners := make(map[string]func(context.Context) error, len(knownPhases))
	for _, phase := range knownPhases {
		phase := phase
		runners[phase] = func(context.Context) error {
			if calls != nil {
				calls[phase]++
			}
			return nil
		}
	}
	return runners
}
