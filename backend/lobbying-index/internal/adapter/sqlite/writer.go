package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"epac/lobbying-index/internal/domain"

	_ "modernc.org/sqlite"
)

const (
	DefaultDatabasePath = "/tmp/ocl-index.sqlite"
)

type Writer struct{}

func NewWriter() *Writer {
	return &Writer{}
}

func (w *Writer) Write(
	ctx context.Context,
	databasePath string,
	batch domain.OCLIngestionBatch,
	members []domain.Member,
	subjectMatters []domain.OCLSubjectMatterType,
) error {
	if databasePath == "" {
		databasePath = DefaultDatabasePath
	}

	dir := filepath.Dir(databasePath)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create database directory: %w", err)
		}
	}

	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()

	if _, err := db.ExecContext(ctx, "PRAGMA foreign_keys = ON"); err != nil {
		return fmt.Errorf("enable foreign keys: %w", err)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if err := createSchema(ctx, tx); err != nil {
		return err
	}

	if err := insertCommunicationPrimary(ctx, tx, batch.CommunicationsPrimary); err != nil {
		return err
	}
	if err := insertCommunicationDPOHs(ctx, tx, batch.CommunicationsDPOHs); err != nil {
		return err
	}
	if err := insertCommunicationSubjectMatters(ctx, tx, batch.CommunicationsSubjectMatters); err != nil {
		return err
	}
	if err := insertRegistrationPrimary(ctx, tx, batch.RegistrationPrimary); err != nil {
		return err
	}
	if err := insertRegistrationSubjectMatters(ctx, tx, batch.RegistrationSubjectMatters); err != nil {
		return err
	}
	if err := insertRegistrationInHouseLobbyists(ctx, tx, batch.RegistrationInHouseLobbyists); err != nil {
		return err
	}
	if err := insertRegistrationConsultantLobbyists(ctx, tx, batch.RegistrationConsultantLobbyists); err != nil {
		return err
	}
	if err := insertMembers(ctx, tx, members); err != nil {
		return err
	}
	if err := insertSubjectMatterTypes(ctx, tx, subjectMatters); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}
	return nil
}

func createSchema(ctx context.Context, tx *sql.Tx) error {
	if _, err := tx.ExecContext(ctx, schemaSQL); err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	return nil
}

func insertCommunicationPrimary(ctx context.Context, tx *sql.Tx, rows []domain.OCLCommunication) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_communication_primary (
    comlog_id,
    en_client_org_corp_nm_an,
    fr_client_org_corp_nm,
    client_org_corp_num,
    rgstrnt_1st_nm_prenom_dclrnt,
    rgstrnt_last_nm_dclrnt,
    reg_type_enr,
    comm_date
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(comlog_id) DO UPDATE SET
    en_client_org_corp_nm_an = excluded.en_client_org_corp_nm_an,
    fr_client_org_corp_nm = excluded.fr_client_org_corp_nm,
    client_org_corp_num = excluded.client_org_corp_num,
    rgstrnt_1st_nm_prenom_dclrnt = excluded.rgstrnt_1st_nm_prenom_dclrnt,
    rgstrnt_last_nm_dclrnt = excluded.rgstrnt_last_nm_dclrnt,
    reg_type_enr = excluded.reg_type_enr,
    comm_date = excluded.comm_date`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.ComlogID,
			normalizeText(row.ENClientOrgCorpNmAN),
			normalizeText(row.FRClientOrgCorpNm),
			normalizeText(row.ClientOrgCorpNum),
			normalizeText(row.RegistrantFirstName),
			normalizeText(row.RegistrantLastName),
			normalizeText(row.RegTypeENR),
			normalizeTime(row.CommDate),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertCommunicationDPOHs(ctx context.Context, tx *sql.Tx, rows []domain.OCLCommunicationDPOH) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_communication_dpohs (
    comlog_id,
    dpoh_first_nm_prenom_tcpd,
    dpoh_last_nm_tcpd,
    institution
) VALUES (?, ?, ?, ?)
ON CONFLICT(comlog_id, dpoh_first_nm_prenom_tcpd, dpoh_last_nm_tcpd, institution) DO UPDATE SET
    institution = excluded.institution`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.ComlogID,
			normalizeText(row.FirstName),
			normalizeText(row.LastName),
			normalizeText(row.Institution),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertCommunicationSubjectMatters(ctx context.Context, tx *sql.Tx, rows []domain.OCLCommunicationSubjectMatter) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_communication_subject_matters (
    comlog_id,
    subject_code_objet,
    custom_subj_objet_perso
) VALUES (?, ?, ?)
ON CONFLICT(comlog_id, subject_code_objet, custom_subj_objet_perso) DO UPDATE SET
    custom_subj_objet_perso = excluded.custom_subj_objet_perso`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.ComlogID,
			row.SubjectCodeObjet,
			normalizeText(row.CustomSubjObjetPerso),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertRegistrationPrimary(ctx context.Context, tx *sql.Tx, rows []domain.OCLRegistrationPrimary) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_registration_primary (
    reg_id_enr,
    reg_type_enr,
    client_org_corp_num,
    en_client_org_corp_nm_an,
    fr_client_org_corp_nm,
    client_org_corp_profil_id_profil_client_org_corp,
    effective_date_vigueur,
    end_date_fin
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(reg_id_enr) DO UPDATE SET
    reg_type_enr = excluded.reg_type_enr,
    client_org_corp_num = excluded.client_org_corp_num,
    en_client_org_corp_nm_an = excluded.en_client_org_corp_nm_an,
    fr_client_org_corp_nm = excluded.fr_client_org_corp_nm,
    client_org_corp_profil_id_profil_client_org_corp = excluded.client_org_corp_profil_id_profil_client_org_corp,
    effective_date_vigueur = excluded.effective_date_vigueur,
    end_date_fin = excluded.end_date_fin`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.RegID,
			normalizeText(row.RegTypeENR),
			normalizeText(row.ClientOrgCorpNum),
			normalizeText(row.ENClientOrgCorpNmAN),
			normalizeText(row.FRClientOrgCorpNm),
			normalizeText(row.ClientOrgCorpProfilIDProfilClientOrgCorp),
			normalizeTime(row.EffectiveDateVigueur),
			normalizeTime(row.EndDateFin),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertRegistrationSubjectMatters(ctx context.Context, tx *sql.Tx, rows []domain.OCLRegistrationSubjectMatter) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_registration_subject_matters (
    reg_id_enr,
    subject_code_objet,
    custom_subj_objet_perso
) VALUES (?, ?, ?)
ON CONFLICT(reg_id_enr, subject_code_objet, custom_subj_objet_perso) DO UPDATE SET
    custom_subj_objet_perso = excluded.custom_subj_objet_perso`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.RegID,
			row.SubjectCodeObjet,
			normalizeText(row.CustomSubjObjetPerso),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertRegistrationInHouseLobbyists(ctx context.Context, tx *sql.Tx, rows []domain.OCLRegistrationInHouseLobbyist) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_registration_in_house_lobbyists (
    client_org_corp_profil_id_profil_client_org_corp,
    lbbyst_id_lbbyst,
    lbbyst_first_nm_prenom_lbbyst,
    lbbyst_last_nm_lbbyst
) VALUES (?, ?, ?, ?)
ON CONFLICT(client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst) DO UPDATE SET
    lbbyst_first_nm_prenom_lbbyst = excluded.lbbyst_first_nm_prenom_lbbyst,
    lbbyst_last_nm_lbbyst = excluded.lbbyst_last_nm_lbbyst`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			normalizeText(row.ClientOrgCorpProfilIDProfilClientOrgCorp),
			normalizeText(row.LbbystID),
			normalizeText(row.LbbystFirstNmPrenom),
			normalizeText(row.LbbystLastNm),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertRegistrationConsultantLobbyists(ctx context.Context, tx *sql.Tx, rows []domain.OCLRegistrationConsultantLobbyist) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_registration_consultant_lobbyists (
    client_org_corp_profil_id_profil_client_org_corp,
    lbbyst_id_lbbyst,
    lbbyst_first_nm_prenom_lbbyst,
    lbbyst_last_nm_lbbyst
) VALUES (?, ?, ?, ?)
ON CONFLICT(client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst) DO UPDATE SET
    lbbyst_first_nm_prenom_lbbyst = excluded.lbbyst_first_nm_prenom_lbbyst,
    lbbyst_last_nm_lbbyst = excluded.lbbyst_last_nm_lbbyst`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			normalizeText(row.ClientOrgCorpProfilIDProfilClientOrgCorp),
			normalizeText(row.LbbystID),
			normalizeText(row.LbbystFirstNmPrenom),
			normalizeText(row.LbbystLastNm),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertMembers(ctx context.Context, tx *sql.Tx, rows []domain.Member) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO members (
    person_id,
    honorific,
    first_name,
    last_name,
    constituency,
    province,
    caucus,
    from_date,
    to_date
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(person_id) DO UPDATE SET
    honorific = excluded.honorific,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    constituency = excluded.constituency,
    province = excluded.province,
    caucus = excluded.caucus,
    from_date = excluded.from_date,
    to_date = excluded.to_date`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.PersonID,
			normalizeText(row.Honorific),
			normalizeText(row.FirstName),
			normalizeText(row.LastName),
			normalizeText(row.Constituency),
			normalizeText(row.Province),
			normalizeText(row.Caucus),
			normalizeTime(row.FromDate),
			normalizeTime(row.ToDate),
		); err != nil {
			return err
		}
	}
	return nil
}

func insertSubjectMatterTypes(ctx context.Context, tx *sql.Tx, rows []domain.OCLSubjectMatterType) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO ocl_subject_matter_types (
    subject_code_objet,
    smt_en_desc
) VALUES (?, ?)
ON CONFLICT(subject_code_objet) DO UPDATE SET
    smt_en_desc = excluded.smt_en_desc`)
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, row := range rows {
		if _, err := stmt.ExecContext(ctx,
			row.SubjectCodeObjet,
			row.SmtEnDesc,
		); err != nil {
			return err
		}
	}
	return nil
}

func normalizeText(value *string) any {
	if value == nil {
		return nil
	}
	return *value
}

func normalizeTime(value *time.Time) any {
	if value == nil {
		return nil
	}
	return value.UTC().Format(time.RFC3339)
}

const schemaSQL = `
DROP TABLE IF EXISTS ocl_communication_subject_matters;
DROP TABLE IF EXISTS ocl_communication_dpohs;
DROP TABLE IF EXISTS ocl_communication_primary;
DROP TABLE IF EXISTS ocl_registration_subject_matters;
DROP TABLE IF EXISTS ocl_registration_in_house_lobbyists;
DROP TABLE IF EXISTS ocl_registration_consultant_lobbyists;
DROP TABLE IF EXISTS ocl_registration_primary;
DROP TABLE IF EXISTS ocl_subject_matter_types;
DROP TABLE IF EXISTS members;

CREATE TABLE members (
    person_id TEXT PRIMARY KEY,
    honorific TEXT,
    first_name TEXT,
    last_name TEXT,
    constituency TEXT,
    province TEXT,
    caucus TEXT,
    from_date TIMESTAMP,
    to_date TIMESTAMP
);

CREATE TABLE ocl_subject_matter_types (
    subject_code_objet TEXT PRIMARY KEY,
    smt_en_desc TEXT
);

CREATE TABLE ocl_communication_primary (
    comlog_id TEXT PRIMARY KEY,
    en_client_org_corp_nm_an TEXT,
    fr_client_org_corp_nm TEXT,
    client_org_corp_num TEXT,
    rgstrnt_1st_nm_prenom_dclrnt TEXT,
    rgstrnt_last_nm_dclrnt TEXT,
    reg_type_enr TEXT,
    comm_date TIMESTAMP
);

CREATE TABLE ocl_communication_dpohs (
    comlog_id TEXT NOT NULL,
    dpoh_first_nm_prenom_tcpd TEXT,
    dpoh_last_nm_tcpd TEXT,
    institution TEXT,
    PRIMARY KEY (comlog_id, dpoh_first_nm_prenom_tcpd, dpoh_last_nm_tcpd, institution)
);

CREATE TABLE ocl_communication_subject_matters (
    comlog_id TEXT NOT NULL,
    subject_code_objet TEXT NOT NULL,
    custom_subj_objet_perso TEXT,
    PRIMARY KEY (comlog_id, subject_code_objet, custom_subj_objet_perso)
);

CREATE TABLE ocl_registration_primary (
    reg_id_enr TEXT PRIMARY KEY,
    reg_type_enr TEXT,
    client_org_corp_num TEXT,
    en_client_org_corp_nm_an TEXT,
    fr_client_org_corp_nm TEXT,
    client_org_corp_profil_id_profil_client_org_corp TEXT,
    effective_date_vigueur TIMESTAMP,
    end_date_fin TIMESTAMP
);

CREATE TABLE ocl_registration_subject_matters (
    reg_id_enr TEXT NOT NULL,
    subject_code_objet TEXT NOT NULL,
    custom_subj_objet_perso TEXT,
    PRIMARY KEY (reg_id_enr, subject_code_objet, custom_subj_objet_perso)
);

CREATE TABLE ocl_registration_in_house_lobbyists (
    client_org_corp_profil_id_profil_client_org_corp TEXT NOT NULL,
    lbbyst_id_lbbyst TEXT,
    lbbyst_first_nm_prenom_lbbyst TEXT,
    lbbyst_last_nm_lbbyst TEXT,
    PRIMARY KEY (client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst)
);

CREATE TABLE ocl_registration_consultant_lobbyists (
    client_org_corp_profil_id_profil_client_org_corp TEXT NOT NULL,
    lbbyst_id_lbbyst TEXT,
    lbbyst_first_nm_prenom_lbbyst TEXT,
    lbbyst_last_nm_lbbyst TEXT,
    PRIMARY KEY (client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst)
);
`
