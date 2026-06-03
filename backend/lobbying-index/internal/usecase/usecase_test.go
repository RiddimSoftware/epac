package usecase

import (
	"context"
	"testing"

	"epac/lobbying-index/internal/domain"
)

type fakeOCLSource struct {
	batch domain.OCLIngestionBatch
	err   error
}

func (f fakeOCLSource) FetchOCLData(context.Context) (domain.OCLIngestionBatch, error) {
	return f.batch, f.err
}

type fakeMembersSource struct {
	members []domain.Member
	err     error
}

func (f fakeMembersSource) FetchMembers(context.Context) ([]domain.Member, error) {
	return f.members, f.err
}

type fakeSubjectMatterSource struct {
	rows []domain.OCLSubjectMatterType
	err  error
}

func (f fakeSubjectMatterSource) FetchSubjectMatters(context.Context) ([]domain.OCLSubjectMatterType, error) {
	return f.rows, f.err
}

type fakeWriter struct {
	called bool
	path   string
}

func (f *fakeWriter) Write(ctx context.Context, path string, batch domain.OCLIngestionBatch, members []domain.Member, subjectMatters []domain.OCLSubjectMatterType) error {
	f.called = true
	f.path = path
	return nil
}

func TestIngestOCLData_Execute(t *testing.T) {
	batch := domain.OCLIngestionBatch{
		CommunicationsPrimary:           []domain.OCLCommunication{{ComlogID: "1"}},
		CommunicationsDPOHs:             []domain.OCLCommunicationDPOH{{ComlogID: "1"}},
		CommunicationsSubjectMatters:    []domain.OCLCommunicationSubjectMatter{{ComlogID: "1", SubjectCodeObjet: "SMT-1"}},
		RegistrationPrimary:             []domain.OCLRegistrationPrimary{{RegID: "10"}},
		RegistrationSubjectMatters:      []domain.OCLRegistrationSubjectMatter{{RegID: "10", SubjectCodeObjet: "SMT-1"}},
		RegistrationInHouseLobbyists:    []domain.OCLRegistrationInHouseLobbyist{{LbbystID: ptr("101")}},
		RegistrationConsultantLobbyists: []domain.OCLRegistrationConsultantLobbyist{{LbbystID: ptr("201")}},
	}
	members := []domain.Member{{PersonID: "person-1"}, {PersonID: "person-2"}}
	subjects := []domain.OCLSubjectMatterType{{SubjectCodeObjet: "SMT-1", SmtEnDesc: "Energy"}}

	writer := &fakeWriter{}
	useCase, err := NewIngestOCLData(
		fakeOCLSource{batch: batch},
		fakeMembersSource{members: members},
		fakeSubjectMatterSource{rows: subjects},
		writer,
	)
	if err != nil {
		t.Fatalf("unexpected constructor error: %v", err)
	}

	result, err := useCase.Execute(context.Background())
	if err != nil {
		t.Fatalf("unexpected execute error: %v", err)
	}
	if !writer.called {
		t.Fatal("expected writer.Write to be called")
	}
	if got, want := result.CommunicationPrimaryRows, 1; got != want {
		t.Fatalf("unexpected communication rows: got %d want %d", got, want)
	}
	if got, want := result.MemberRows, 2; got != want {
		t.Fatalf("unexpected member rows: got %d want %d", got, want)
	}
	if got, want := result.SubjectMatterTypeRows, 1; got != want {
		t.Fatalf("unexpected subject matter type rows: got %d want %d", got, want)
	}
}

func TestIngestOCLData_ConstructorRequiresDependencies(t *testing.T) {
	_, err := NewIngestOCLData(nil, fakeMembersSource{}, fakeSubjectMatterSource{}, &fakeWriter{})
	if err != ErrOCLSourceRequired {
		t.Fatalf("unexpected error: %v", err)
	}
}

func ptr(value string) *string {
	return &value
}
