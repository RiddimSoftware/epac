// topic-notifier Lambda
//
// Triggered by EventBridge on a daily schedule (recommended: 02:00 UTC / 10 PM Ottawa,
// after Hansard is typically published). Queries today's speeches, matches subject
// titles against the topic keyword taxonomy, and sends APNs push notifications to
// all subscribed devices whose granularity preferences are satisfied.
//
// Schedule the Lambda via:
//   cd backend && make schedule-lambda SERVICE=topic-notifier TIME=0200
//
// Required environment variables:
//   DATABASE_URL     - PostgreSQL connection string
//   APNS_KEY_ID      - 10-char key ID from App Store Connect → Keys
//   APNS_TEAM_ID     - 10-char Apple Developer team ID
//   APNS_PRIVATE_KEY - PEM-encoded ECDSA p8 private key (the .p8 file contents)
//   APNS_BUNDLE_ID   - App bundle ID: net.dinglebox.cabinetdoor
//   APNS_PRODUCTION  - "true" for prod APNs; omit or "false" for sandbox
package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// Accepts an optional EventBridge scheduled event; date overrides are for testing.
type NotifyRequest struct {
	SittingDate string `json:"sitting_date"` // optional override; defaults to yesterday Ottawa time
}

// topic is a named set of keywords mirroring ParliamentaryTopic in iOS.
type topic struct {
	id       string
	name     string
	keywords []string
}

var topics = []topic{
	{id: "housing", name: "Housing", keywords: []string{"housing", "rent", "mortgage", "affordable housing", "logement", "loyer"}},
	{id: "healthcare", name: "Healthcare", keywords: []string{"health", "pharmacare", "mental health", "dental", "pandemic", "santé"}},
	{id: "climate", name: "Climate", keywords: []string{"climate", "carbon", "environment", "clean energy", "net zero", "emission", "énergie", "environnement"}},
	{id: "economy", name: "Economy", keywords: []string{"budget", "fiscal", "inflation", "economic", "gdp", "debt", "déficit", "économie"}},
	{id: "indigenous", name: "Indigenous affairs", keywords: []string{"indigenous", "first nations", "métis", "inuit", "reconciliation", "autochtone"}},
	{id: "immigration", name: "Immigration", keywords: []string{"immigration", "refugee", "asylum", "citizenship", "border", "réfugié"}},
	{id: "defence", name: "Defence", keywords: []string{"defence", "military", "nato", "armed forces", "défense", "armée"}},
	{id: "justice", name: "Justice & Public Safety", keywords: []string{"justice", "crime", "police", "firearms", "gun", "corrections", "sécurité"}},
	{id: "seniors", name: "Seniors", keywords: []string{"senior", "pension", "retirement", "old age", "aîné", "retraite"}},
	{id: "agriculture", name: "Agriculture", keywords: []string{"agriculture", "farming", "food security", "grain", "livestock"}},
	{id: "transport", name: "Transport & Infrastructure", keywords: []string{"transport", "rail", "aviation", "highway", "infrastructure", "transit"}},
	{id: "taxation", name: "Taxation", keywords: []string{"tax", "gst", "hst", "income tax", "corporate tax", "impôt", "taxe"}},
	{id: "foreign", name: "Foreign Affairs", keywords: []string{"foreign affairs", "international", "ukraine", "gaza", "sanctions", "treaty", "affaires étrangères"}},
	{id: "education", name: "Education", keywords: []string{"education", "student", "university", "school", "tuition", "éducation", "étudiant"}},
	{id: "childcare", name: "Child Care", keywords: []string{"child care", "daycare", "family", "children", "services de garde", "enfant"}},
	{id: "energy", name: "Energy", keywords: []string{"energy", "oil", "gas", "pipeline", "electricity", "lng", "pétrole"}},
	{id: "pharma", name: "Pharmaceuticals", keywords: []string{"drug", "pharmaceutical", "medication", "opioid", "naloxone", "médicament"}},
	{id: "digital", name: "Digital & AI", keywords: []string{"digital", "artificial intelligence", "ai", "online harms", "privacy", "cybersecurity", "numérique"}},
	{id: "labour", name: "Labour", keywords: []string{"labour", "labor", "union", "strike", "wage", "employment", "travail", "grève"}},
	{id: "trade", name: "Trade", keywords: []string{"trade", "tariff", "cusma", "ceta", "export", "import", "commerce", "tarif"}},
}

// matchTopics returns IDs of topics whose keywords appear in the subject title.
func matchTopics(subjectTitle string) []string {
	lower := strings.ToLower(subjectTitle)
	var matched []string
	for _, t := range topics {
		for _, kw := range t.keywords {
			if strings.Contains(lower, kw) {
				matched = append(matched, t.id)
				break
			}
		}
	}
	return matched
}

func topicName(id string) string {
	for _, t := range topics {
		if t.id == id {
			return t.name
		}
	}
	return id
}

// ---- database types ----

type subjectSummary struct {
	title        string
	speakerCount int
	bestContent  string // verbatim excerpt from the longest intervention
	speakerName  string
}

type subscription struct {
	token        string
	granularity  map[string]string // topic_id → "everyDebate"|"onlyMyMP"|"off"
	myMPMemberID string
}

// ---- main handler ----

var dbConn *pgx.Conn

func getConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	var err error
	dbConn, err = pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	return dbConn, err
}

func HandleRequest(ctx context.Context, req NotifyRequest) error {
	sittingDate := req.SittingDate
	if sittingDate == "" {
		// Default: today in Ottawa time (America/Toronto, UTC-4/UTC-5).
		// Lambda runs at 02:00 UTC = 10 PM Ottawa, so time.Now().In(ottawa) gives
		// the sitting date (e.g. Tuesday 22:00 Ottawa → "2026-04-29").
		ottawa, _ := time.LoadLocation("America/Toronto")
		if ottawa == nil {
			ottawa = time.UTC
		}
		sittingDate = time.Now().In(ottawa).Format("2006-01-02")
	}

	conn, err := getConn(ctx)
	if err != nil {
		return fmt.Errorf("db connect: %w", err)
	}

	// 1. Load all subjects debated on this sitting date.
	subjects, err := loadSubjects(ctx, conn, sittingDate)
	if err != nil {
		return fmt.Errorf("load subjects: %w", err)
	}
	if len(subjects) == 0 {
		fmt.Printf("No subjects found for %s — skipping notifications\n", sittingDate)
		return nil
	}

	// 2. For each subject, find matching topics and notify subscribers.
	apnsJWT, err := buildAPNSToken()
	if err != nil {
		return fmt.Errorf("apns jwt: %w", err)
	}

	sent := 0
	for _, subj := range subjects {
		topicIDs := matchTopics(subj.title)
		if len(topicIDs) == 0 {
			continue
		}

		for _, tid := range topicIDs {
			subs, err := subscribersFor(ctx, conn, tid)
			if err != nil {
				fmt.Printf("subscribers query error for %s: %v\n", tid, err)
				continue
			}

			for _, sub := range subs {
				gran := sub.granularity[tid]
				if gran == "off" {
					continue
				}
				if gran == "onlyMyMP" && sub.myMPMemberID != "" {
					if !subjectContainsMember(ctx, conn, sittingDate, subj.title, sub.myMPMemberID) {
						continue
					}
				}

				if err := sendTopicNotification(ctx, apnsJWT, sub.token, tid, subj, sittingDate); err != nil {
					prefix := sub.token
					if len(prefix) > 8 {
						prefix = prefix[:8]
					}
					fmt.Printf("APNs send error to %s...: %v\n", prefix, err)
				} else {
					sent++
				}
			}
		}
	}

	fmt.Printf("topic-notifier: sent %d notifications for sitting %s\n", sent, sittingDate)
	return nil
}

// loadSubjects returns one summary row per unique subject_title for the given date.
// Best intervention = longest content (most substantive speech).
func loadSubjects(ctx context.Context, conn *pgx.Conn, sittingDate string) ([]subjectSummary, error) {
	rows, err := conn.Query(ctx, `
		WITH ranked AS (
			SELECT
				subject_title,
				speaker_name,
				content,
				word_count,
				ROW_NUMBER() OVER (PARTITION BY subject_title ORDER BY word_count DESC NULLS LAST) AS rn
			FROM speeches
			WHERE sitting_date = $1::date
			  AND subject_title IS NOT NULL
			  AND content != ''
		),
		counts AS (
			SELECT subject_title, COUNT(DISTINCT member_id) AS speaker_count
			FROM speeches
			WHERE sitting_date = $1::date
			  AND subject_title IS NOT NULL
			  AND member_id IS NOT NULL
			GROUP BY subject_title
		)
		SELECT r.subject_title, COALESCE(c.speaker_count, 0), r.speaker_name, r.content
		FROM ranked r
		LEFT JOIN counts c ON c.subject_title = r.subject_title
		WHERE r.rn = 1
		ORDER BY COALESCE(c.speaker_count, 0) DESC`,
		sittingDate,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []subjectSummary
	for rows.Next() {
		var s subjectSummary
		var speakerName *string
		if err := rows.Scan(&s.title, &s.speakerCount, &speakerName, &s.bestContent); err != nil {
			continue
		}
		if speakerName != nil {
			s.speakerName = *speakerName
		}
		result = append(result, s)
	}
	return result, rows.Err()
}

// subscribersFor returns all device subscriptions that include the given topic ID.
func subscribersFor(ctx context.Context, conn *pgx.Conn, topicID string) ([]subscription, error) {
	rows, err := conn.Query(ctx, `
		SELECT token, granularity, COALESCE(my_mp_member_id, '')
		FROM device_subscriptions
		WHERE $1 = ANY(topic_ids)`,
		topicID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subs []subscription
	for rows.Next() {
		var s subscription
		var granJSON []byte
		if err := rows.Scan(&s.token, &granJSON, &s.myMPMemberID); err != nil {
			continue
		}
		if err := json.Unmarshal(granJSON, &s.granularity); err != nil {
			s.granularity = map[string]string{}
		}
		subs = append(subs, s)
	}
	return subs, rows.Err()
}

// subjectContainsMember returns true if the given member spoke in the subject on that date.
func subjectContainsMember(ctx context.Context, conn *pgx.Conn, date, subject, memberID string) bool {
	var count int
	err := conn.QueryRow(ctx, `
		SELECT COUNT(*) FROM speeches
		WHERE sitting_date = $1::date
		  AND subject_title = $2
		  AND member_id = $3`,
		date, subject, memberID,
	).Scan(&count)
	return err == nil && count > 0
}

// sendTopicNotification sends a single APNs push for a matched topic.
func sendTopicNotification(ctx context.Context, jwtToken, deviceToken, topicID string, subj subjectSummary, sittingDate string) error {
	// Build verbatim excerpt: first sentence of best content, ≤140 chars.
	excerpt := firstSentence(subj.bestContent, 140)

	body := buildNotificationBody(topicID, subj, excerpt, sittingDate)
	data, err := json.Marshal(body)
	if err != nil {
		return err
	}

	apnsHost := "api.sandbox.push.apple.com"
	if os.Getenv("APNS_PRODUCTION") == "true" {
		apnsHost = "api.push.apple.com"
	}
	url := fmt.Sprintf("https://%s/3/device/%s", apnsHost, deviceToken)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "bearer "+jwtToken)
	req.Header.Set("apns-topic", os.Getenv("APNS_BUNDLE_ID"))
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "5")
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("APNs returned %d", resp.StatusCode)
	}
	return nil
}

func buildNotificationBody(topicID string, subj subjectSummary, excerpt, sittingDate string) map[string]interface{} {
	title := fmt.Sprintf("%s debated in Parliament today", topicName(topicID))
	body := excerpt
	if subj.speakerName != "" {
		body = fmt.Sprintf("%s said: \"%s\"", subj.speakerName, excerpt)
	}
	if subj.speakerCount > 1 {
		body = fmt.Sprintf("%d MPs spoke. %s", subj.speakerCount, body)
	}

	return map[string]interface{}{
		"aps": map[string]interface{}{
			"alert": map[string]string{
				"title": title,
				"body":  body,
			},
			"sound": "default",
		},
		// Custom keys for iOS deep navigation
		"topic_id":     topicID,
		"hansard_date": sittingDate,
		"date":         sittingDate + "T00:00:00Z",
	}
}

// firstSentence returns the text up to the first sentence break, capped at maxLen runes.
func firstSentence(s string, maxLen int) string {
	s = strings.TrimSpace(s)
	for i, r := range s {
		if r == '.' || r == '!' || r == '?' {
			candidate := strings.TrimSpace(s[:i+1])
			if len([]rune(candidate)) <= maxLen {
				return candidate
			}
		}
	}
	runes := []rune(s)
	if len(runes) > maxLen {
		return string(runes[:maxLen])
	}
	return s
}

// ---- APNs JWT (token-based auth, ES256) ----

// buildAPNSToken generates a fresh ES256 JWT for APNs using the p8 key.
// APNs tokens expire after 1 hour; this Lambda runs once per day so a
// fresh token per invocation is fine.
func buildAPNSToken() (string, error) {
	keyID := os.Getenv("APNS_KEY_ID")
	teamID := os.Getenv("APNS_TEAM_ID")
	privateKeyPEM := os.Getenv("APNS_PRIVATE_KEY")

	if keyID == "" || teamID == "" || privateKeyPEM == "" {
		return "", fmt.Errorf("APNS_KEY_ID, APNS_TEAM_ID, and APNS_PRIVATE_KEY must be set")
	}

	// Parse ECDSA private key from PEM.
	block, _ := pem.Decode([]byte(privateKeyPEM))
	if block == nil {
		return "", fmt.Errorf("failed to decode APNS_PRIVATE_KEY PEM")
	}
	privKey, err := x509.ParseECPrivateKey(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("parse EC key: %w", err)
	}

	// Build JWT header + payload.
	headerJSON, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": keyID})
	payloadJSON, _ := json.Marshal(map[string]interface{}{"iss": teamID, "iat": time.Now().Unix()})

	header := base64.RawURLEncoding.EncodeToString(headerJSON)
	payload := base64.RawURLEncoding.EncodeToString(payloadJSON)
	message := header + "." + payload

	// Sign with ES256.
	hash := sha256.Sum256([]byte(message))
	r, s, err := ecdsa.Sign(rand.Reader, privKey, hash[:])
	if err != nil {
		return "", fmt.Errorf("sign: %w", err)
	}

	// ES256 signature = fixed 64-byte r||s (RFC 7518 §3.4).
	sig := fixedWidthBytes(r, s)
	return message + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

// fixedWidthBytes encodes r and s as a 64-byte (32+32) big-endian pair.
func fixedWidthBytes(r, s *big.Int) []byte {
	b := make([]byte, 64)
	rb := r.Bytes()
	sb := s.Bytes()
	copy(b[32-len(rb):32], rb)
	copy(b[64-len(sb):64], sb)
	return b
}

func main() {
	lambda.Start(HandleRequest)
}
