package ocl

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
)

const (
	defaultCommunicationZipURL = "https://lobbycanada.gc.ca/media/mqbbmaqk/communications_ocl_cal.zip"
	defaultRegistrationZipURL  = "https://lobbycanada.gc.ca/media/zwcjycef/registrations_enregistrements_ocl_cal.zip"
	defaultUserAgent           = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

type Fetcher struct {
	client              *http.Client
	communicationZipURL string
	registrationZipURL  string
	userAgent           string
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(fetcher *Fetcher) {
		if client != nil {
			fetcher.client = client
		}
	}
}

func WithCommunicationZipURL(url string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(url) != "" {
			fetcher.communicationZipURL = strings.TrimSpace(url)
		}
	}
}

func WithRegistrationZipURL(url string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(url) != "" {
			fetcher.registrationZipURL = strings.TrimSpace(url)
		}
	}
}

func WithUserAgent(userAgent string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(userAgent) != "" {
			fetcher.userAgent = strings.TrimSpace(userAgent)
		}
	}
}

func NewFetcher(opts ...Option) *Fetcher {
	fetcher := &Fetcher{
		client:              &http.Client{Timeout: 45 * time.Second},
		communicationZipURL: defaultCommunicationZipURL,
		registrationZipURL:  defaultRegistrationZipURL,
		userAgent:           defaultUserAgent,
	}
	for _, opt := range opts {
		opt(fetcher)
	}
	return fetcher
}

func (f *Fetcher) FetchOCLData(ctx context.Context) (domain.OCLIngestionBatch, error) {
	communicationBytes, err := f.download(ctx, f.communicationZipURL)
	if err != nil {
		return domain.OCLIngestionBatch{}, fmt.Errorf("download communication zip: %w", err)
	}
	registrationBytes, err := f.download(ctx, f.registrationZipURL)
	if err != nil {
		return domain.OCLIngestionBatch{}, fmt.Errorf("download registration zip: %w", err)
	}

	batch := domain.OCLIngestionBatch{}
	if err := f.parseOCLZip(communicationBytes, &batch, true); err != nil {
		return domain.OCLIngestionBatch{}, err
	}
	if err := f.parseOCLZip(registrationBytes, &batch, false); err != nil {
		return domain.OCLIngestionBatch{}, err
	}
	return batch, nil
}

func (f *Fetcher) parseOCLZip(data []byte, batch *domain.OCLIngestionBatch, isCommunication bool) error {
	zipReader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("open ocl zip: %w", err)
	}

	for _, file := range zipReader.File {
		name := strings.ToLower(filepath.Base(file.Name))
		if !strings.HasSuffix(name, ".csv") {
			continue
		}

		rc, err := file.Open()
		if err != nil {
			return fmt.Errorf("open zip file %s: %w", file.Name, err)
		}

		err = parseOCLCSV(name, rc, batch, isCommunication)
		closeErr := rc.Close()
		if err != nil {
			return fmt.Errorf("parse %s: %w", file.Name, err)
		}
		if closeErr != nil {
			return fmt.Errorf("close zip file %s: %w", file.Name, closeErr)
		}
	}
	return nil
}

func parseOCLCSV(name string, reader io.Reader, batch *domain.OCLIngestionBatch, isCommunication bool) error {
	switch strings.ToLower(name) {
	case "communication_primaryexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseCommunicationPrimary(rows)
		if err != nil {
			return err
		}
		batch.CommunicationsPrimary = append(batch.CommunicationsPrimary, parsed...)
	case "communication_dpohexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseCommunicationDPOH(rows)
		if err != nil {
			return err
		}
		batch.CommunicationsDPOHs = append(batch.CommunicationsDPOHs, parsed...)
	case "communication_subjectmattersexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseCommunicationSubjectMatter(rows)
		if err != nil {
			return err
		}
		batch.CommunicationsSubjectMatters = append(batch.CommunicationsSubjectMatters, parsed...)
	case "registration_primaryexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseRegistrationPrimary(rows)
		if err != nil {
			return err
		}
		batch.RegistrationPrimary = append(batch.RegistrationPrimary, parsed...)
	case "registration_subjectmattersexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseRegistrationSubjectMatter(rows)
		if err != nil {
			return err
		}
		batch.RegistrationSubjectMatters = append(batch.RegistrationSubjectMatters, parsed...)
	case "registration_inhouselobbyistsexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseRegistrationInHouseLobbyists(rows)
		if err != nil {
			return err
		}
		batch.RegistrationInHouseLobbyists = append(batch.RegistrationInHouseLobbyists, parsed...)
	case "registration_consultantlobbyistsexport.csv":
		rows, err := readCSV(reader)
		if err != nil {
			return err
		}
		parsed, err := parseRegistrationConsultantLobbyists(rows)
		if err != nil {
			return err
		}
		batch.RegistrationConsultantLobbyists = append(batch.RegistrationConsultantLobbyists, parsed...)
	default:
		_ = isCommunication
	}
	return nil
}

func (f *Fetcher) download(ctx context.Context, sourceURL string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", f.userAgent)
	req.Header.Set("Accept", "application/zip")

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("expected HTTP 200, got %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return body, nil
}

func readCSV(reader io.Reader) (*csv.Reader, error) {
	r := csv.NewReader(reader)
	r.FieldsPerRecord = -1
	r.TrimLeadingSpace = true
	return r, nil
}

func parseCommunicationPrimary(reader *csv.Reader) ([]domain.OCLCommunication, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	comlogIdx, ok := normalized["COMLOG_ID"]
	if !ok {
		return nil, errors.New("missing COMLOG_ID")
	}

	clientOrgIndex := firstColumn(normalized, "CLIENT_ORG_CORP_NUM", "CLIENT_ORG_CRP_NUM")
	if clientOrgIndex < 0 {
		return nil, errors.New("missing CLIENT_ORG_CORP_NUM")
	}
	enOrgIndex := firstColumn(normalized, "EN_CLIENT_ORG_CORP_NM_AN", "EN_CLIENT_ORG_CRP_NM_AN")
	if enOrgIndex < 0 {
		return nil, errors.New("missing EN_CLIENT_ORG_CORP_NM_AN")
	}
	frOrgIndex := firstColumn(normalized, "FR_CLIENT_ORG_CORP_NM", "FR_CLIENT_ORG_CRP_NM")
	if frOrgIndex < 0 {
		return nil, errors.New("missing FR_CLIENT_ORG_CORP_NM")
	}

	registrantFirstIndex := firstColumn(normalized, "RGSTRNT_1ST_NM_PRENOM_DCLRNT")
	registrantLastIndex := firstColumn(normalized, "RGSTRNT_LAST_NM_DCLRNT")
	regTypeIndex := firstColumn(normalized, "REG_TYPE_ENR")
	commDateIndex := firstColumn(normalized, "COMM_DATE")

	var rows []domain.OCLCommunication
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		comlogID := strings.TrimSpace(valueAt(record, comlogIdx))
		if comlogID == "" {
			continue
		}

		commDate := parseNullableTime(valueAt(record, commDateIndex))
		rows = append(rows, domain.OCLCommunication{
			ComlogID:            comlogID,
			ClientOrgCorpNum:    pointerString(valueAt(record, clientOrgIndex)),
			ENClientOrgCorpNmAN: pointerString(valueAt(record, enOrgIndex)),
			FRClientOrgCorpNm:   pointerString(valueAt(record, frOrgIndex)),
			RegistrantFirstName: pointerString(valueAt(record, registrantFirstIndex)),
			RegistrantLastName:  pointerString(valueAt(record, registrantLastIndex)),
			RegTypeENR:          pointerString(valueAt(record, regTypeIndex)),
			CommDate:            commDate,
		})
	}
	return rows, nil
}

func parseCommunicationDPOH(reader *csv.Reader) ([]domain.OCLCommunicationDPOH, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	comlogIdx, ok := normalized["COMLOG_ID"]
	if !ok {
		return nil, errors.New("missing COMLOG_ID")
	}
	firstIdx := firstColumn(normalized, "DPOH_FIRST_NM_PRENOM_TCPD", "DPOH_FIRST_NAME")
	lastIdx := firstColumn(normalized, "DPOH_LAST_NM_TCPD", "DPOH_LAST_NAME")
	institutionIdx := firstColumn(normalized, "INSTITUTION", "INSTITUTION_NAME")
	if firstIdx < 0 || lastIdx < 0 || institutionIdx < 0 {
		return nil, errors.New("missing communication DPOH columns")
	}

	var rows []domain.OCLCommunicationDPOH
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		comlogID := strings.TrimSpace(valueAt(record, comlogIdx))
		if comlogID == "" {
			continue
		}

		rows = append(rows, domain.OCLCommunicationDPOH{
			ComlogID:    comlogID,
			FirstName:   pointerString(valueAt(record, firstIdx)),
			LastName:    pointerString(valueAt(record, lastIdx)),
			Institution: pointerString(valueAt(record, institutionIdx)),
		})
	}
	return rows, nil
}

func parseCommunicationSubjectMatter(reader *csv.Reader) ([]domain.OCLCommunicationSubjectMatter, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	comlogIdx, ok := normalized["COMLOG_ID"]
	if !ok {
		return nil, errors.New("missing COMLOG_ID")
	}
	subjectCodeIdx := firstColumn(normalized, "SUBJECT_CODE_OBJET", "SUBJECT_CODE")
	customIdx := firstColumn(normalized, "CUSTOM_SUBJ_OBJET_PERSO")
	if subjectCodeIdx < 0 {
		return nil, errors.New("missing communication subject matter columns")
	}

	var rows []domain.OCLCommunicationSubjectMatter
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		comlogID := strings.TrimSpace(valueAt(record, comlogIdx))
		subject := strings.TrimSpace(valueAt(record, subjectCodeIdx))
		if comlogID == "" || subject == "" {
			continue
		}
		rows = append(rows, domain.OCLCommunicationSubjectMatter{
			ComlogID:             comlogID,
			SubjectCodeObjet:     subject,
			CustomSubjObjetPerso: pointerString(valueAt(record, customIdx)),
		})
	}
	return rows, nil
}

func parseRegistrationPrimary(reader *csv.Reader) ([]domain.OCLRegistrationPrimary, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	regIDIdx, ok := normalized["REG_ID_ENR"]
	if !ok {
		return nil, errors.New("missing REG_ID_ENR")
	}
	regTypeIdx := firstColumn(normalized, "REG_TYPE_ENR")
	clientOrgNumIdx := firstColumn(normalized, "CLIENT_ORG_CORP_NUM", "CLIENT_ORG_CRP_NUM")
	enOrgIdx := firstColumn(normalized, "EN_CLIENT_ORG_CORP_NM_AN", "EN_CLIENT_ORG_CRP_NM_AN")
	frOrgIdx := firstColumn(normalized, "FR_CLIENT_ORG_CORP_NM", "FR_CLIENT_ORG_CRP_NM")
	clientProfilIdx := firstColumn(normalized, "CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP", "CLIENT_ORG_CRP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP")
	effectiveDateIdx := firstColumn(normalized, "EFFECTIVE_DATE_VIGUEUR")
	endDateIdx := firstColumn(normalized, "END_DATE_FIN")

	if clientOrgNumIdx < 0 || enOrgIdx < 0 || frOrgIdx < 0 || clientProfilIdx < 0 || effectiveDateIdx < 0 || endDateIdx < 0 {
		return nil, errors.New("missing required registration primary columns")
	}

	var rows []domain.OCLRegistrationPrimary
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		regID := strings.TrimSpace(valueAt(record, regIDIdx))
		if regID == "" {
			continue
		}
		rows = append(rows, domain.OCLRegistrationPrimary{
			RegID:                                    regID,
			ClientOrgCorpNum:                         pointerString(valueAt(record, clientOrgNumIdx)),
			ENClientOrgCorpNmAN:                      pointerString(valueAt(record, enOrgIdx)),
			FRClientOrgCorpNm:                        pointerString(valueAt(record, frOrgIdx)),
			ClientOrgCorpProfilIDProfilClientOrgCorp: pointerString(valueAt(record, clientProfilIdx)),
			RegTypeENR:                               pointerString(valueAt(record, regTypeIdx)),
			EffectiveDateVigueur:                     parseNullableTime(valueAt(record, effectiveDateIdx)),
			EndDateFin:                               parseNullableTime(valueAt(record, endDateIdx)),
		})
	}
	return rows, nil
}

func parseRegistrationSubjectMatter(reader *csv.Reader) ([]domain.OCLRegistrationSubjectMatter, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	regIDIdx, ok := normalized["REG_ID_ENR"]
	if !ok {
		return nil, errors.New("missing REG_ID_ENR")
	}
	subjectCodeIdx := firstColumn(normalized, "SUBJECT_CODE_OBJET", "SUBJECT_CODE")
	customIdx := firstColumn(normalized, "CUSTOM_SUBJ_OBJET_PERSO")
	if subjectCodeIdx < 0 {
		return nil, errors.New("missing registration subject matter columns")
	}

	var rows []domain.OCLRegistrationSubjectMatter
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		regID := strings.TrimSpace(valueAt(record, regIDIdx))
		subject := strings.TrimSpace(valueAt(record, subjectCodeIdx))
		if regID == "" || subject == "" {
			continue
		}
		rows = append(rows, domain.OCLRegistrationSubjectMatter{
			RegID:                regID,
			SubjectCodeObjet:     subject,
			CustomSubjObjetPerso: pointerString(valueAt(record, customIdx)),
		})
	}
	return rows, nil
}

func parseRegistrationInHouseLobbyists(reader *csv.Reader) ([]domain.OCLRegistrationInHouseLobbyist, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	profileIDIdx := firstColumn(normalized, "CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP", "CLIENT_ORG_CRP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP")
	if profileIDIdx < 0 {
		return nil, errors.New("missing registration in-house lobbyists columns")
	}
	idIdx := firstColumn(normalized, "LBBYST_ID_LBBYST")
	firstIdx := firstColumn(normalized, "LBBYST_1ST_NM_PRENOM_LBBYST", "LBBYST_FIRST_NM_PRENOM_LBBYST")
	lastIdx := firstColumn(normalized, "LBBYST_LAST_NM_LBBYST")
	if idIdx < 0 {
		return nil, errors.New("missing registration in-house lobbyists columns")
	}

	var rows []domain.OCLRegistrationInHouseLobbyist
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		rows = append(rows, domain.OCLRegistrationInHouseLobbyist{
			ClientOrgCorpProfilIDProfilClientOrgCorp: pointerString(valueAt(record, profileIDIdx)),
			LbbystID:                                 pointerString(valueAt(record, idIdx)),
			LbbystFirstNmPrenom:                      pointerString(valueAt(record, firstIdx)),
			LbbystLastNm:                             pointerString(valueAt(record, lastIdx)),
		})
	}
	return rows, nil
}

func parseRegistrationConsultantLobbyists(reader *csv.Reader) ([]domain.OCLRegistrationConsultantLobbyist, error) {
	headers, err := reader.Read()
	if err != nil {
		return nil, err
	}
	normalized := normalizeHeaders(headers)

	profileIDIdx := firstColumn(normalized, "CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP", "CLIENT_ORG_CRP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP")
	if profileIDIdx < 0 {
		return nil, errors.New("missing registration consultant lobbyists columns")
	}
	idIdx := firstColumn(normalized, "LBBYST_ID_LBBYST")
	firstIdx := firstColumn(normalized, "LBBYST_1ST_NM_PRENOM_LBBYST", "LBBYST_FIRST_NM_PRENOM_LBBYST")
	lastIdx := firstColumn(normalized, "LBBYST_LAST_NM_LBBYST")
	if idIdx < 0 {
		return nil, errors.New("missing registration consultant lobbyists columns")
	}

	var rows []domain.OCLRegistrationConsultantLobbyist
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		rows = append(rows, domain.OCLRegistrationConsultantLobbyist{
			ClientOrgCorpProfilIDProfilClientOrgCorp: pointerString(valueAt(record, profileIDIdx)),
			LbbystID:                                 pointerString(valueAt(record, idIdx)),
			LbbystFirstNmPrenom:                      pointerString(valueAt(record, firstIdx)),
			LbbystLastNm:                             pointerString(valueAt(record, lastIdx)),
		})
	}
	return rows, nil
}

func normalizeHeaders(headers []string) map[string]int {
	m := map[string]int{}
	for i, header := range headers {
		clean := strings.ToUpper(stripBOM(strings.TrimSpace(header)))
		if _, exists := m[clean]; !exists {
			m[clean] = i
		}
	}
	return m
}

func firstColumn(headers map[string]int, names ...string) int {
	for _, name := range names {
		if idx, ok := headers[name]; ok {
			return idx
		}
	}
	return -1
}

func valueAt(record []string, idx int) string {
	if idx < 0 || idx >= len(record) {
		return ""
	}
	return strings.TrimSpace(stripBOM(record[idx]))
}

func pointerString(raw string) *string {
	value := strings.TrimSpace(raw)
	if value == "" || strings.EqualFold(value, "null") {
		return nil
	}
	return &value
}

func parseNullableTime(raw string) *time.Time {
	s := strings.TrimSpace(raw)
	if s == "" || strings.EqualFold(s, "null") {
		return nil
	}

	for _, layout := range []string{time.RFC3339, "2006-01-02", "2006-01-02T15:04:05"} {
		if value, err := time.Parse(layout, s); err == nil {
			return &value
		}
	}
	return nil
}

func stripBOM(value string) string {
	return strings.TrimPrefix(value, "\ufeff")
}
