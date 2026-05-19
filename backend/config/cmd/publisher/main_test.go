package main

import "testing"

func TestBuildConfigParsesFeatures(t *testing.T) {
	cfg, err := buildConfig("1.2.3", "search=false,topic_notifications=false")
	if err != nil {
		t.Fatalf("buildConfig error: %v", err)
	}
	if cfg.MinimumSupportedVersion != "1.2.3" {
		t.Fatalf("minimum version = %q", cfg.MinimumSupportedVersion)
	}
	if cfg.Features["search"] || cfg.Features["topic_notifications"] {
		t.Fatalf("unexpected features: %#v", cfg.Features)
	}
}

func TestBuildConfigRejectsInvalidFeature(t *testing.T) {
	if _, err := buildConfig("1.0.0", "search=yes"); err == nil {
		t.Fatal("buildConfig accepted invalid feature value")
	}
}
