// config publisher emits the backend-provided app configuration artifact.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type appConfig struct {
	MinimumSupportedVersion string          `json:"minimum_supported_version"`
	Features                map[string]bool `json:"features"`
}

func main() {
	output := flag.String("output", "../../../build/artifacts/config", "artifact output directory")
	minimumVersion := flag.String("minimum-supported-version", envOrDefault("MINIMUM_SUPPORTED_VERSION", "1.0.0"), "minimum supported app version")
	features := flag.String("features", envOrDefault("APP_CONFIG_FEATURES", "search=true,topic_notifications=true"), "comma-separated feature=true|false pairs")
	flag.Parse()

	cfg, err := buildConfig(*minimumVersion, *features)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build config: %v\n", err)
		os.Exit(1)
	}
	if err := writeJSON(filepath.Join(*output, "v1", "app.json"), cfg); err != nil {
		fmt.Fprintf(os.Stderr, "write config artifact: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published app config with %d feature flags\n", len(cfg.Features))
}

func buildConfig(minimumVersion, rawFeatures string) (appConfig, error) {
	cfg := appConfig{
		MinimumSupportedVersion: strings.TrimSpace(minimumVersion),
		Features:                map[string]bool{},
	}
	if cfg.MinimumSupportedVersion == "" {
		return appConfig{}, fmt.Errorf("minimum-supported-version is required")
	}
	for _, pair := range strings.Split(rawFeatures, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		name, rawValue, ok := strings.Cut(pair, "=")
		if !ok {
			return appConfig{}, fmt.Errorf("feature %q must use name=true|false", pair)
		}
		name = strings.TrimSpace(name)
		if name == "" {
			return appConfig{}, fmt.Errorf("feature name is required")
		}
		switch strings.ToLower(strings.TrimSpace(rawValue)) {
		case "true":
			cfg.Features[name] = true
		case "false":
			cfg.Features[name] = false
		default:
			return appConfig{}, fmt.Errorf("feature %q value must be true or false", name)
		}
	}
	return cfg, nil
}

func writeJSON(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
