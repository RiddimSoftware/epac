package postgres

import (
	"context"
	"errors"
	"strings"

	"epac/push-notification-dispatcher/internal/domain"

	"github.com/jackc/pgx/v5"
)

func Connect(ctx context.Context, connStr string) (*pgx.Conn, error) {
	connStr = strings.TrimSpace(connStr)
	if connStr == "" {
		return nil, errors.New("DATABASE_URL not set")
	}
	return pgx.Connect(ctx, connStr)
}

type DeviceSubscriptionRepository struct {
	conn *pgx.Conn
}

func NewDeviceSubscriptionRepository(conn *pgx.Conn) *DeviceSubscriptionRepository {
	return &DeviceSubscriptionRepository{conn: conn}
}

func (r *DeviceSubscriptionRepository) ListDeviceSubscriptions(ctx context.Context) ([]domain.DeviceSubscription, error) {
	rows, err := r.conn.Query(ctx, `
		SELECT
			token,
			COALESCE(my_mp_member_id, ''),
			COALESCE(topic_ids, '{}'::text[]),
			COALESCE(bill_ids, '{}'::text[])
		FROM device_subscriptions
		ORDER BY token`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subscriptions []domain.DeviceSubscription
	for rows.Next() {
		var (
			token        string
			myMPMemberID string
			topicIDs     []string
			billIDs      []string
		)
		if err := rows.Scan(&token, &myMPMemberID, &topicIDs, &billIDs); err != nil {
			return nil, err
		}
		subscriptions = append(subscriptions, domain.NewDeviceSubscription(token, myMPMemberID, topicIDs, billIDs))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return subscriptions, nil
}
