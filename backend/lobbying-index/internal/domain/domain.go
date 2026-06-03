package domain

import "time"

// OCLCommunication represents one communication row from the OCL communication primary export.
type OCLCommunication struct {
	ComlogID            string
	ENClientOrgCorpNmAN *string
	FRClientOrgCorpNm   *string
	ClientOrgCorpNum    *string
	RegistrantFirstName *string
	RegistrantLastName  *string
	RegTypeENR          *string
	CommDate            *time.Time
}

// OCLCommunicationDPOH represents one designated public office-holder row on a communication.
type OCLCommunicationDPOH struct {
	ComlogID    string
	FirstName   *string
	LastName    *string
	Institution *string
}

// OCLCommunicationSubjectMatter represents one subject-matter link for a communication.
type OCLCommunicationSubjectMatter struct {
	ComlogID             string
	SubjectCodeObjet     string
	CustomSubjObjetPerso *string
}

// OCLRegistrationPrimary represents one registration master row.
type OCLRegistrationPrimary struct {
	RegID                                    string
	RegTypeENR                               *string
	ClientOrgCorpNum                         *string
	ENClientOrgCorpNmAN                      *string
	FRClientOrgCorpNm                        *string
	ClientOrgCorpProfilIDProfilClientOrgCorp *string
	EffectiveDateVigueur                     *time.Time
	EndDateFin                               *time.Time
}

// OCLRegistrationSubjectMatter represents one subject-matter link for a registration.
type OCLRegistrationSubjectMatter struct {
	RegID                string
	SubjectCodeObjet     string
	CustomSubjObjetPerso *string
}

// OCLRegistrationInHouseLobbyist represents one in-house lobbyist row for a registration.
type OCLRegistrationInHouseLobbyist struct {
	ClientOrgCorpProfilIDProfilClientOrgCorp *string
	LbbystID                                 *string
	LbbystFirstNmPrenom                      *string
	LbbystLastNm                             *string
}

// OCLRegistrationConsultantLobbyist represents one consultant lobbyist row for a registration.
type OCLRegistrationConsultantLobbyist struct {
	ClientOrgCorpProfilIDProfilClientOrgCorp *string
	LbbystID                                 *string
	LbbystFirstNmPrenom                      *string
	LbbystLastNm                             *string
}

// OCLSubjectMatterType stores the controlled vocabulary for subject-matter code metadata.
type OCLSubjectMatterType struct {
	SubjectCodeObjet string
	SmtEnDesc        string
}

// Member stores rows for members table.
type Member struct {
	PersonID     string
	Honorific    *string
	FirstName    *string
	LastName     *string
	Constituency *string
	Province     *string
	Caucus       *string
	FromDate     *time.Time
	ToDate       *time.Time
}

// OCLIngestionBatch is the full raw set downloaded from the OCL ZIPs.
type OCLIngestionBatch struct {
	CommunicationsPrimary           []OCLCommunication
	CommunicationsDPOHs             []OCLCommunicationDPOH
	CommunicationsSubjectMatters    []OCLCommunicationSubjectMatter
	RegistrationPrimary             []OCLRegistrationPrimary
	RegistrationSubjectMatters      []OCLRegistrationSubjectMatter
	RegistrationInHouseLobbyists    []OCLRegistrationInHouseLobbyist
	RegistrationConsultantLobbyists []OCLRegistrationConsultantLobbyist
}
