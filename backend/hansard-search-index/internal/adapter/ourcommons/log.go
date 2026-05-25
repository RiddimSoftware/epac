package ourcommons

import (
	"encoding/json"
	"io"
	"os"
	"sync"
	"time"
)

const pipelineName = "hansard-search-index"

type Logger interface {
	Info(event string, fields map[string]any)
	Warn(event string, fields map[string]any)
}

type JSONLogger struct {
	out io.Writer
	mu  sync.Mutex
}

func NewJSONLogger(out io.Writer) *JSONLogger {
	if out == nil {
		out = os.Stdout
	}
	return &JSONLogger{out: out}
}

func (l *JSONLogger) Info(event string, fields map[string]any) {
	l.write("info", event, fields)
}

func (l *JSONLogger) Warn(event string, fields map[string]any) {
	l.write("warn", event, fields)
}

func (l *JSONLogger) write(level, event string, fields map[string]any) {
	record := map[string]any{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"level":     level,
		"pipeline":  pipelineName,
		"event":     event,
	}
	for key, value := range fields {
		record[key] = value
	}
	data, err := json.Marshal(record)
	if err != nil {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	_, _ = l.out.Write(append(data, '\n'))
}

type discardLogger struct{}

func (discardLogger) Info(string, map[string]any) {}
func (discardLogger) Warn(string, map[string]any) {}

func defaultLogger(logger Logger) Logger {
	if logger == nil {
		return discardLogger{}
	}
	return logger
}
