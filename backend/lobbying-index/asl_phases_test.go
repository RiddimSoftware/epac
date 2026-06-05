package main

import (
	"encoding/json"
	"os"
	"testing"
)

type aslDoc struct {
	States map[string]aslState `json:"States"`
}

type aslState struct {
	Parameters *aslParameters `json:"Parameters"`
}

type aslParameters struct {
	Payload *aslPayload `json:"Payload"`
}

type aslPayload struct {
	Phase string `json:"phase"`
}

func TestLobbyingIndexASLPhaseNamesAreValid(t *testing.T) {
	data, err := os.ReadFile("../../infra/lobbying-index.asl.json")
	if err != nil {
		t.Fatalf("read lobbying-index.asl.json: %v", err)
	}

	var asl aslDoc
	if err := json.Unmarshal(data, &asl); err != nil {
		t.Fatalf("parse lobbying-index.asl.json: %v", err)
	}

	valid := make(map[string]bool, len(knownPhases))
	for _, p := range knownPhases {
		valid[p] = true
	}

	for stateName, state := range asl.States {
		if state.Parameters == nil || state.Parameters.Payload == nil {
			continue
		}
		phase := state.Parameters.Payload.Phase
		if phase == "" {
			continue
		}
		if !valid[phase] {
			t.Errorf("state %q has invalid phase %q: not in knownPhases %v", stateName, phase, knownPhases)
		}
	}
}
