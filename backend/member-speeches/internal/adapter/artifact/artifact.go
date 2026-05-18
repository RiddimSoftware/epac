// Package artifact adapts member-content artifacts to the member-speeches
// MemberContentRepository port.
package artifact

import (
	"context"
	"errors"

	membercontent "epac/member-content"
	"epac/member-speeches/internal/usecase"
)

type MemberContentRepository struct {
	store membercontent.Store
}

func NewMemberContentRepository(store membercontent.Store) *MemberContentRepository {
	return &MemberContentRepository{store: store}
}

func NewMemberContentRepositoryFromEnv(ctx context.Context) (*MemberContentRepository, error) {
	store, err := membercontent.NewStoreFromEnv(ctx)
	if err != nil {
		return nil, err
	}
	return NewMemberContentRepository(store), nil
}

func (r *MemberContentRepository) LoadMemberSpeeches(ctx context.Context, memberID string) (usecase.MemberSpeechesArtifact, error) {
	artifact, err := membercontent.LoadMemberSpeechesArtifact(ctx, r.store, memberID)
	if errors.Is(err, membercontent.ErrArtifactNotFound) {
		return usecase.MemberSpeechesArtifact{}, usecase.ErrNotFound
	}
	if err != nil {
		return usecase.MemberSpeechesArtifact{}, err
	}
	return mapArtifact(artifact), nil
}

func mapArtifact(artifact membercontent.MemberSpeechesArtifact) usecase.MemberSpeechesArtifact {
	speeches := make([]usecase.SpeechRecord, 0, len(artifact.Speeches))
	for _, speech := range artifact.Speeches {
		speeches = append(speeches, usecase.SpeechRecord{
			InterventionID:  speech.InterventionID,
			SittingDate:     speech.SittingDate,
			ParliamentNum:   speech.ParliamentNum,
			SessionNum:      speech.SessionNum,
			SubjectTitle:    speech.SubjectTitle,
			Preview:         speech.Preview,
			WordCount:       speech.WordCount,
			Filename:        speech.Filename,
			InterventionSeq: speech.InterventionSeq,
		})
	}
	return usecase.MemberSpeechesArtifact{
		MemberID: artifact.MemberID,
		Stats: usecase.MemberStats{
			TotalSpeeches: artifact.Stats.TotalSpeeches,
			AvgWordCount:  artifact.Stats.AvgWordCount,
			TopTopic:      artifact.Stats.TopTopic,
		},
		Speeches: speeches,
	}
}
