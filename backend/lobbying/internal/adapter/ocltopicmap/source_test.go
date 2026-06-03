package ocltopicmap

import "testing"

func TestCodesForTopicHitNormalizesAndSortsMappings(t *testing.T) {
	source, err := NewSource([]byte(`[
		{"ocl_code":" smt-44 ","epac_topic_slug":" Housing ","confidence":1.0},
		{"ocl_code":"SMT-1","epac_topic_slug":"digital","confidence":0.72},
		{"ocl_code":"SMT-40","epac_topic_slug":"digital","confidence":0.58}
	]`))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}

	mappings, ok := source.CodesForTopic("DIGITAL")
	if !ok {
		t.Fatal("CodesForTopic returned miss for digital")
	}
	if len(mappings) != 2 {
		t.Fatalf("len(mappings) = %d, want 2", len(mappings))
	}
	if mappings[0].OCLCode != "SMT-1" || mappings[1].OCLCode != "SMT-40" {
		t.Fatalf("mappings not sorted by OCL code: %#v", mappings)
	}
	if mappings[0].EpacTopicSlug != "digital" || mappings[0].Confidence != 0.72 {
		t.Fatalf("unexpected mapping: %#v", mappings[0])
	}
}

func TestCodesForTopicMiss(t *testing.T) {
	source, err := NewSource([]byte(`[
		{"ocl_code":"SMT-44","epac_topic_slug":"housing","confidence":1.0}
	]`))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}

	if mappings, ok := source.CodesForTopic("missing"); ok || mappings != nil {
		t.Fatalf("CodesForTopic returned %#v, %v; want nil, false", mappings, ok)
	}
}

func TestTopicMappingsForOCLCodeReturnsCopy(t *testing.T) {
	source, err := NewSource([]byte(`[
		{"ocl_code":"SMT-18","epac_topic_slug":"healthcare","confidence":1.0},
		{"ocl_code":"SMT-18","epac_topic_slug":"publichealth","confidence":0.83}
	]`))
	if err != nil {
		t.Fatalf("NewSource: %v", err)
	}

	mappings := source.TopicMappingsForOCLCode("18")
	if len(mappings) != 2 {
		t.Fatalf("len(mappings) = %d, want 2", len(mappings))
	}
	if mappings[0].EpacTopicSlug != "healthcare" || mappings[1].EpacTopicSlug != "publichealth" {
		t.Fatalf("unexpected mapping order: %#v", mappings)
	}

	mappings[0].EpacTopicSlug = "mutated"
	again := source.TopicMappingsForOCLCode("SMT-18")
	if again[0].EpacTopicSlug != "healthcare" {
		t.Fatalf("second lookup mutated: %#v", again)
	}
}

func TestNewSourceRejectsInvalidConfidence(t *testing.T) {
	if _, err := NewSource([]byte(`[
		{"ocl_code":"SMT-44","epac_topic_slug":"housing","confidence":1.2}
	]`)); err == nil {
		t.Fatal("NewSource accepted confidence above 1")
	}
}
