package sqlite

import (
	"encoding/json"
	"fmt"
	"time"
)

func logProgress(event, phase string, phaseStart time.Time, extra map[string]any) {
	payload := map[string]any{
		"pipeline":   "lobbying-index",
		"event":      event,
		"phase":      phase,
		"elapsed_ms": time.Since(phaseStart).Milliseconds(),
	}
	for k, v := range extra {
		payload[k] = v
	}
	encoded, err := json.Marshal(payload)
	if err == nil {
		fmt.Println(string(encoded))
		return
	}
	fmt.Printf("{\"pipeline\":\"lobbying-index\",\"event\":\"marshaling_error\",\"error\":\"%v\"}\n", err)
}
