package repository

import (
	"context"
	"encoding/json"
	"time"

	"epac/device-register/application"

	"github.com/jackc/pgx/v5"
)

type PostgresDeviceRepository struct {
	conn *pgx.Conn
}

func NewPostgresDeviceRepository(conn *pgx.Conn) *PostgresDeviceRepository {
	return &PostgresDeviceRepository{conn: conn}
}

func (r *PostgresDeviceRepository) UpsertSubscription(ctx context.Context, sub application.DeviceSubscription) error {
	granJSON, err := json.Marshal(sub.Granularity)
	if err != nil {
		return err
	}

	_, err = r.conn.Exec(ctx, `
		INSERT INTO device_subscriptions (token, topic_ids, bill_ids, granularity, my_mp_member_id, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (token) DO UPDATE SET
			topic_ids       = EXCLUDED.topic_ids,
			bill_ids        = EXCLUDED.bill_ids,
			granularity     = EXCLUDED.granularity,
			my_mp_member_id = EXCLUDED.my_mp_member_id,
			updated_at      = EXCLUDED.updated_at`,
		sub.Token, sub.TopicIds, sub.BillIds, granJSON, sub.MyMPMemberId, time.Now().UTC(),
	)
	return err
}
