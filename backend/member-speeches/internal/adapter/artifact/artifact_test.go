package artifact

import (
	"testing"

	membercontent "epac/member-content"
)

func TestMapArtifact(t *testing.T) {
	topic := "Budget"
	date := "2026-01-01"
	artifact := mapArtifact(membercontent.MemberSpeechesArtifact{
		MemberID: "m-001",
		Stats:    membercontent.MemberStats{TotalSpeeches: 1, AvgWordCount: 12, TopTopic: "Budget"},
		Speeches: []membercontent.SpeechRecord{
			{
				InterventionID: "sp-001",
				SittingDate:    &date,
				SubjectTitle:   &topic,
				Preview:        "preview",
				Filename:       "HAN001-E.XML",
			},
		},
	})
	if artifact.MemberID != "m-001" || artifact.Stats.TotalSpeeches != 1 {
		t.Fatalf("unexpected artifact mapping: %#v", artifact)
	}
	if len(artifact.Speeches) != 1 || artifact.Speeches[0].SubjectTitle == nil || *artifact.Speeches[0].SubjectTitle != topic {
		t.Fatalf("unexpected speech mapping: %#v", artifact.Speeches)
	}
}
